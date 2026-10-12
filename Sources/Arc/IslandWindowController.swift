import AppKit
import ArcCore
import SwiftUI

private final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor final class IslandWindowController {
    private let panel: IslandPanel
    private let coordinator: IslandCoordinator
    private var observers: [NSObjectProtocol] = []
    private var localMouse: Any?
    private var globalMouse: Any?
    private var inside = false
    private var fileDragInProgress = false
    private var dragPasteboardBaseline = NSPasteboard(name: .drag).changeCount
    private var closed = false
    private var visibleSize = CGSize.zero

    init(coordinator: IslandCoordinator) {
        self.coordinator = coordinator
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let hosting = PocketHostingView(rootView: IslandView(coordinator: coordinator, onSizeChange: { [weak self] size in
            self?.visibleSize = size
            self?.trackPointer()
        }))
        hosting.model = coordinator.model
        hosting.registerForDraggedTypes([.fileURL])
        hosting.sizingOptions = []
        panel.contentView = hosting
        observeModel()
        present()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.present() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.present() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.present() }
        })
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.trackPointer(event)
            return event
        }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.trackPointer(event)
        }
        panel.acceptsMouseMovedEvents = true
    }

    private func observeModel() {
        guard !closed else { return }
        withObservationTracking {
            _ = coordinator.model.enabled
            _ = coordinator.model.shouldShowIsland
            _ = coordinator.model.preferredDisplayID
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.present()
                self?.observeModel()
            }
        }
    }

    private func present() {
        guard !closed else { return }
        guard coordinator.model.enabled else {
            panel.orderOut(nil)
            inside = false
            fileDragInProgress = false
            return
        }
        // Automatic prefers the built-in notch; disconnected choices fall back to Automatic.
        let screens = NSScreen.screens
        guard let index = IslandLayout.screenIndex(ids: screens.map(Self.displayIdentifier),
                                                   notchedIndex: screens.firstIndex(where: { $0.safeAreaInsets.top > 0 }),
                                                   preferredID: coordinator.model.preferredDisplayID) else { return }
        let screen = screens[index]
        let notch = IslandLayout.notchSize(safeTop: screen.safeAreaInsets.top,
                                          leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        coordinator.model.setNotchSize(notch)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let mirrored = displayID.map { CGDisplayIsInMirrorSet($0) != 0 } ?? false
        coordinator.model.displayIsMirrored = mirrored
        let external = displayID.map { CGDisplayIsBuiltin($0) == 0 } ?? false
        coordinator.model.displayIsExternal = external
        // A closed-lid desktop has no built-in screen; keep the island at the monitor's top edge.
        let externalOnly = !screens.contains { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return true }
            return CGDisplayIsBuiltin(id) != 0
        }
        coordinator.model.displayIsExternalOnly = externalOnly
        // A stationary canvas avoids competing AppKit and SwiftUI layout animations.
        var canvas = IslandLayout.pocketSize(expanded: true, count: Pocket.islandCapacity, receiving: false, notch: notch)
        canvas.width += 24
        canvas.height += 16
        let frame = IslandLayout.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: notch.height, size: canvas, mirrored: mirrored, externalOnly: externalOnly, external: external)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
        trackPointer()
    }

    private func trackPointer(_ event: NSEvent? = nil) {
        guard coordinator.model.enabled, coordinator.model.displayAwake else { return }
        if event?.type == .leftMouseDown { dragPasteboardBaseline = NSPasteboard(name: .drag).changeCount }
        // Read the drag pasteboard only when a new drag is being detected.
        let pasteboard = event?.type == .leftMouseDragged && !fileDragInProgress ? NSPasteboard(name: .drag) : nil
        fileDragInProgress = Self.isFileDrag(previous: fileDragInProgress, eventType: event?.type,
                                             leftButtonDown: NSEvent.pressedMouseButtons & 1 != 0,
                                             pasteboardChanged: pasteboard.map { $0.changeCount != dragPasteboardBaseline } ?? false,
                                             pasteboardTypes: pasteboard?.types ?? [])
        if !coordinator.model.shouldShowIsland {
            coordinator.model.hover(false)
            coordinator.model.collapse()
            inside = false
            // Keep the transparent destination available only during a drag.
            if !fileDragInProgress {
                panel.ignoresMouseEvents = true
                return
            }
        }
        let point = NSEvent.mouseLocation
        let attached = coordinator.model.attachesToTop
        let rect = CGRect(x: panel.frame.midX - visibleSize.width / 2,
                          y: panel.frame.maxY - visibleSize.height,
                          width: visibleSize.width, height: visibleSize.height)
        let radius: CGFloat = coordinator.model.expanded ? 24 : (attached ? 12 : rect.height / 2)
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // The attached shape has square top corners; the camera housing is reserved space.
        let squareTop = attached && CGRect(x: rect.minX, y: rect.maxY - radius, width: rect.width, height: radius).contains(point)
        let overMenuControl = coordinator.menuPocketControlFrame?()?.contains(point) == true
        let nowInside = !overMenuControl && (shape.contains(point) || squareTop)
        // Transparent rounded corners must not swallow clicks intended for the app below.
        panel.ignoresMouseEvents = overMenuControl || (!nowInside && !coordinator.model.receivingFiles && !coordinator.model.draggingFileOut)
        if nowInside != inside {
            inside = nowInside
            coordinator.model.hover(nowInside)
        }
    }

    static func isFileDrag(previous: Bool, eventType: NSEvent.EventType?, leftButtonDown: Bool,
                           pasteboardChanged: Bool, pasteboardTypes: [NSPasteboard.PasteboardType]) -> Bool {
        guard leftButtonDown, eventType != .leftMouseDown, eventType != .leftMouseUp else { return false }
        if previous { return true }
        return eventType == .leftMouseDragged && pasteboardChanged && pasteboardTypes.contains(.fileURL)
    }

    static func displayIdentifier(_ screen: NSScreen) -> String {
        guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "" }
        return CFUUIDCreateString(nil, uuid) as String
    }

    func close() {
        closed = true
        if let localMouse { NSEvent.removeMonitor(localMouse) }
        if let globalMouse { NSEvent.removeMonitor(globalMouse) }
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        panel.close()
    }
}
