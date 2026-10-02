import AppKit
import ApplicationServices
import SwiftUI

/// A separate, scrollable place for status items that cannot fit beside the notch.
@MainActor final class MenuPocketBar {
    private struct Item: Identifiable {
        let id: String
        let element: AXUIElement
        let name: String
        let icon: NSImage
        let x: CGFloat
    }

    private var panel: NSPanel?
    private var accessTask: Task<Void, Never>?
    private var presentationTask: Task<Void, Never>?
    var onVisibilityChanged: (() -> Void)?
    private let itemAccess = MenuPocketItemAccess()
    private var controlFrame = CGRect.zero
    private var failureReason: String?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle(beside controlFrame: CGRect, before dividerFrame: CGRect) {
        if panel != nil || presentationTask != nil {
            close()
            return
        }
        let restoring = itemAccess.restore()
        if !restoring {
            show(beside: controlFrame, before: dividerFrame)
            return
        }
        presentationTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self else { return }
            self.presentationTask = nil
            self.show(beside: controlFrame, before: dividerFrame)
        }
    }

    func close() {
        _ = itemAccess.restore()
        dismissRow()
    }

    private func dismissRow() {
        presentationTask?.cancel()
        presentationTask = nil
        guard panel != nil else { return }
        accessTask?.cancel()
        accessTask = nil
        panel?.close()
        panel = nil
        onVisibilityChanged?()
    }

    private func show(beside controlFrame: CGRect, before dividerFrame: CGRect) {
        self.controlFrame = controlFrame
        let trusted = AXIsProcessTrusted()
        let items = trusted ? groupedItems(before: dividerFrame.minX) : []
        let screen = NSScreen.screens.first { $0.frame.intersects(controlFrame) } ?? NSScreen.main
        guard let screen else { return }

        let width = min(max(220, CGFloat(items.count) * 60 + 24), screen.frame.width - 40)
        let height: CGFloat = 72
        let x = min(max(screen.frame.minX + 20, controlFrame.midX - width / 2), screen.frame.maxX - width - 20)
        let menuHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let y = screen.frame.maxY - max(menuHeight, 24) - height - 6

        let bar = NSPanel(contentRect: CGRect(x: x, y: y, width: width, height: height),
                          styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        bar.level = .mainMenu + 1
        bar.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace, .ignoresCycle]
        bar.backgroundColor = .clear
        bar.hasShadow = true
        bar.isFloatingPanel = true
        bar.contentView = NSHostingView(rootView: BarView(items: items, trusted: trusted,
                                                         requestAccess: requestAccess,
                                                         open: open, failureReason: { [weak self] in self?.failureReason },
                                                         close: close))
        panel = bar
        bar.orderFrontRegardless()
        onVisibilityChanged?()
        if !trusted { watchForAccess(beside: controlFrame, before: dividerFrame) }
    }

    private func watchForAccess(beside controlFrame: CGRect, before dividerFrame: CGRect) {
        accessTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                guard let self, self.isVisible else { return }
                guard AXIsProcessTrusted() else { continue }
                self.panel?.close()
                self.panel = nil
                self.accessTask = nil
                self.show(beside: controlFrame, before: dividerFrame)
                return
            }
        }
    }

    private func groupedItems(before boundaryX: CGFloat) -> [Item] {
        var result: [Item] = []
        for app in NSWorkspace.shared.runningApplications {
            let application = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(application, 0.2)
            var menu: CFTypeRef?
            guard AXUIElementCopyAttributeValue(application, kAXExtrasMenuBarAttribute as CFString, &menu) == .success,
                  let menu, CFGetTypeID(menu) == AXUIElementGetTypeID() else { continue }
            var children: CFTypeRef?
            guard AXUIElementCopyAttributeValue(menu as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
                  let children = children as? [AXUIElement] else { continue }
            for (index, element) in children.enumerated() {
                guard let frame = frame(of: element), frame.width > 4,
                      frame.minX < boundaryX else { continue }
                let name = label(of: element) ?? app.localizedName ?? "Menu Bar Item"
                let icon = icon(for: app, name: name)
                result.append(Item(id: "\(app.processIdentifier)-\(index)", element: element,
                                   name: name, icon: icon, x: frame.minX))
            }
        }
        return result.sorted { $0.x > $1.x }
    }

    private func icon(for app: NSRunningApplication, name: String) -> NSImage {
        let source = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage()
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48,
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                           isPlanar: false, colorSpaceName: .deviceRGB,
                                           bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return source }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        source.draw(in: CGRect(x: 0, y: 0, width: 48, height: 48))
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        bitmap.size = NSSize(width: 24, height: 24)
        let image = NSImage(size: bitmap.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
              let position, let size,
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point),
              AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    private func label(of element: AXUIElement) -> String? {
        for attribute in [kAXDescriptionAttribute, kAXTitleAttribute] {
            var value: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
               let text = value as? String, !text.isEmpty { return text }
        }
        return nil
    }

    private func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func open(_ element: AXUIElement) async -> Bool {
        // A hidden status item can accept AXPress without presenting a usable
        // menu. Move only this item into view before opening its control.
        failureReason = nil
        guard AXIsProcessTrusted() else {
            failureReason = "Allow Accessibility To Open Menu Icons"
            NSLog("Menu Pocket: Accessibility access missing at click")
            return false
        }
        guard let openingPanel = panel else { return false }
        openingPanel.orderOut(nil)
        onVisibilityChanged?()
        defer {
            // Keep failures visible, but never revive a closed or replaced row.
            if panel === openingPanel {
                _ = itemAccess.restore()
                openingPanel.orderFrontRegardless()
                onVisibilityChanged?()
            }
        }
        guard let original = frame(of: element) else {
            failureReason = "Couldn’t Read The Original Menu Icon"
            NSLog("Menu Pocket: AX frame read failed")
            return false
        }
        guard itemAccess.show(original, beside: controlFrame) else {
            failureReason = itemAccess.failureReason
            return false
        }
        var visibleFrame: CGRect?
        var settledFrame: CGRect?
        for _ in 0..<10 {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
            guard !Task.isCancelled, panel === openingPanel else { return false }
            guard let current = frame(of: element), Self.isOnScreen(current, screens: NSScreen.screens.map(\.frame)) else { continue }
            if current == visibleFrame {
                settledFrame = current
                break
            }
            visibleFrame = current
        }
        guard !Task.isCancelled, panel === openingPanel, let settledFrame,
              let current = frame(of: element), current == settledFrame,
              Self.isOnScreen(current, screens: NSScreen.screens.map(\.frame)) else {
            failureReason = "Menu Icon Didn’t Move Into View"
            NSLog("Menu Pocket: settling failed; original %@ final %@", NSStringFromRect(original),
                  frame(of: element).map { NSStringFromRect($0) } ?? "unavailable")
            return false
        }

        var error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error == .actionUnsupported {
            error = AXUIElementPerformAction(element, kAXShowMenuAction as CFString)
        }
        if error == .success {
            dismissRow()
            return true
        }
        failureReason = "Couldn’t Open The Original Menu"
        NSLog("Menu Pocket AX action result: %d", error.rawValue)
        guard error == .actionUnsupported,
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown,
                                 mouseCursorPosition: CGPoint(x: current.midX, y: current.midY), mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp,
                               mouseCursorPosition: CGPoint(x: current.midX, y: current.midY), mouseButton: .left) else { return false }
        // Close our panel before delivering a normal click to the original icon.
        dismissRow()
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    static func isOnScreen(_ frame: CGRect, screens: [CGRect]) -> Bool {
        // Accessibility uses a top-left origin; AppKit uses a bottom-left origin.
        let top = screens.first?.maxY ?? 0
        let cocoaFrame = CGRect(x: frame.minX, y: top - frame.maxY,
                                width: frame.width, height: frame.height)
        return frame.width > 4 && frame.height > 0 && screens.contains { $0.contains(cocoaFrame) }
    }

    private struct BarView: View {
        let items: [Item]
        let trusted: Bool
        let requestAccess: () -> Void
        let open: (AXUIElement) async -> Bool
        let failureReason: () -> String?
        let close: () -> Void
        @State private var failedName: String?
        @State private var isOpening = false

        var body: some View {
            HStack(spacing: 8) {
                if !trusted {
                    Text("Allow Accessibility To Show Menu Icons")
                        .font(.system(size: 12))
                    Button("Allow…", action: requestAccess)
                } else if items.isEmpty {
                    Text("No Menu Icons Found. Arrange Menu Pocket To Choose Icons.")
                        .font(.system(size: 12))
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 4) {
                            ForEach(items) { item in
                                Button {
                                    isOpening = true
                                    failedName = nil
                                    Task {
                                        let opened = await open(item.element)
                                        if !opened { failedName = failureReason() ?? "Couldn’t Open \(item.name)" }
                                        isOpening = false
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(nsImage: item.icon)
                                            .resizable()
                                            .interpolation(.high)
                                            .frame(width: 24, height: 24)
                                        Text(item.name)
                                            .font(.system(size: 9))
                                            .lineLimit(1)
                                            .frame(width: 52)
                                    }
                                    .frame(width: 56, height: 56)
                                }
                                .buttonStyle(.plain)
                                .disabled(isOpening)
                                .help(item.name)
                                .accessibilityLabel(item.name)
                            }
                        }
                    }
                    .scrollIndicators(.visible)
                }
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .help("Close Menu Pocket")
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) {
                if let failedName {
                    Text(failedName)
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}

#if DEBUG
extension MenuPocketBar {
    static func diagnose() {
        print("Menu Pocket Accessibility:", AXIsProcessTrusted())
        let bar = MenuPocketBar()
        let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
        for window in windows where (window[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)) {
            print("Menu Pocket status window:", window[kCGWindowNumber as String] as Any,
                  window[kCGWindowBounds as String] as Any)
        }
        for item in bar.groupedItems(before: .infinity) {
            var actions: CFArray?
            let result = AXUIElementCopyActionNames(item.element, &actions)
            let itemFrame = bar.frame(of: item.element)
            let match = itemFrame.flatMap { MenuPocketItemAccess().statusWindow(at: $0) }
            print("Menu Pocket item:", item.name, "frame:", itemFrame as Any,
                  "matched window:", match?[kCGWindowNumber as String] as Any,
                  "actions:", actions as Any, "result:", result.rawValue)
        }
    }
}
#endif
