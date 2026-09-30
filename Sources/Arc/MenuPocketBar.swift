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
    var onVisibilityChanged: (() -> Void)?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle(beside controlFrame: CGRect, before dividerFrame: CGRect) {
        if isVisible {
            close()
            return
        }
        show(beside: controlFrame, before: dividerFrame)
    }

    func close() {
        guard panel != nil else { return }
        panel?.close()
        panel = nil
        onVisibilityChanged?()
    }

    private func show(beside controlFrame: CGRect, before dividerFrame: CGRect) {
        let trusted = AXIsProcessTrusted()
        let items = trusted ? groupedItems(before: dividerFrame.minX) : []
        let screen = NSScreen.screens.first { $0.frame.intersects(controlFrame) } ?? NSScreen.main
        guard let screen else { return }

        let width = min(max(220, CGFloat(items.count) * 60 + 32), screen.frame.width - 40)
        let height: CGFloat = 100
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
                                                         open: open, close: close))
        panel = bar
        bar.orderFrontRegardless()
        onVisibilityChanged?()
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
                let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: name) ?? NSImage()
                result.append(Item(id: "\(app.processIdentifier)-\(index)", element: element,
                                   name: name, icon: icon, x: frame.minX))
            }
        }
        return result.sorted { $0.x > $1.x }
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

    private func open(_ element: AXUIElement) -> Bool {
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
        if error == .success { close() }
        return error == .success
    }

    private struct BarView: View {
        let items: [Item]
        let trusted: Bool
        let requestAccess: () -> Void
        let open: (AXUIElement) -> Bool
        let close: () -> Void
        @State private var failedName: String?

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
                                    if !open(item.element) { failedName = item.name }
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
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .bottom) {
                if let failedName {
                    Text("Couldn’t Open \(failedName)")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}
