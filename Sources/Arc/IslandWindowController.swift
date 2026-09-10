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
        let hosting = NSHostingView(rootView: IslandView(coordinator: coordinator, onSizeChange: { [weak self] size in
            self?.visibleSize = size
            self?.trackPointer()
        }))
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
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.trackPointer()
            return event
        }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.trackPointer()
        }
        panel.acceptsMouseMovedEvents = true
    }

    private func observeModel() {
        guard !closed else { return }
        withObservationTracking {
            _ = coordinator.model.expanded
            _ = coordinator.model.media
            _ = coordinator.model.enabled
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
            return
        }
        // Prefer the built-in notch even when an external monitor owns the menu bar.
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first else { return }
        let notch = IslandLayout.notchSize(safeTop: screen.safeAreaInsets.top,
                                          leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
        coordinator.model.setNotchSize(notch)
        // A stationary canvas avoids competing AppKit and SwiftUI layout animations.
        var canvas = IslandLayout.size(expanded: true, hasMedia: true, notch: notch)
        canvas.width += 24
        canvas.height += 16
        let frame = IslandLayout.frame(screen: screen.frame, visible: screen.visibleFrame, safeTop: notch.height, size: canvas)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.orderFrontRegardless()
        trackPointer()
    }

    private func trackPointer() {
        guard coordinator.model.enabled else { return }
        let point = NSEvent.mouseLocation
        let attached = coordinator.model.notchSize.height > 0
        let rect = CGRect(x: panel.frame.midX - visibleSize.width / 2,
                          y: panel.frame.maxY - visibleSize.height,
                          width: visibleSize.width, height: visibleSize.height)
        let radius: CGFloat = coordinator.model.expanded ? 24 : (attached ? 12 : rect.height / 2)
        let shape = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        // The attached shape has square top corners; the camera housing is reserved space.
        let squareTop = attached && CGRect(x: rect.minX, y: rect.maxY - radius, width: rect.width, height: radius).contains(point)
        let nowInside = shape.contains(point) || squareTop
        // Transparent rounded corners must not swallow clicks intended for the app below.
        panel.ignoresMouseEvents = !nowInside
        if nowInside != inside {
            inside = nowInside
            coordinator.model.hover(nowInside)
        }
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
