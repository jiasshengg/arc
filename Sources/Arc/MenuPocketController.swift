import AppKit
import Combine

/// Uses Arc's own spacer to push status items on its left out of view.
@MainActor final class MenuPocketController: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isExpanded = true

    private var chevron: NSStatusItem?
    private var spacer: NSStatusItem?
    private let defaults: UserDefaults
    private let itemPrefix: String
    private var spacerPadding: NSLayoutConstraint?
    private let expandedLength: CGFloat = 0
    private var isArranging = false
    private let dividerImage: NSImage = {
        // Draw the separator directly; "line.vertical" is not an SF Symbol.
        let image = NSImage(size: NSSize(width: 2, height: 14), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: rect.midX - 0.5, y: 0, width: 1, height: rect.height)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Menu Pocket divider"
        return image
    }()

    init(defaults: UserDefaults = .standard, itemPrefix: String = "MenuPocket") {
        self.defaults = defaults
        self.itemPrefix = itemPrefix
        super.init()
    }

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        if defaults.bool(forKey: "menuPocketEnabled") { setEnabled(true) }
    }

    func stop() {
        removeItems()
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: "menuPocketEnabled")
        if !enabled {
            removeItems()
            return
        }

        // New status items appear on the left: create the chevron first.
        let control = NSStatusBar.system.statusItem(withLength: 18)
        control.autosaveName = NSStatusItem.AutosaveName(itemPrefix + "Chevron")
        control.behavior = []
        control.button?.target = self
        control.button?.action = #selector(toggle)
        chevron = control

        let divider = NSStatusBar.system.statusItem(withLength: expandedLength)
        divider.autosaveName = NSStatusItem.AutosaveName(itemPrefix + "Spacer")
        divider.behavior = []
        spacer = divider
        // AppKit adds padding even at length zero. Only relax the width relation
        // on our own content view; restore it before arranging or collapsing.
        if let content = divider.button?.window?.contentView {
            spacerPadding = content.constraintsAffectingLayout(for: .horizontal).first {
                ($0.firstItem as? NSView) === content && $0.firstAttribute == .width
                    && $0.secondAttribute == .width && $0.relation == .equal
                    && $0.constant > 0
            }
        }

        // Start revealed so newly added icons and changed arrangements are visible.
        isExpanded = true
        updateAppearance()
    }

    @objc func toggle() {
        guard isEnabled else { return }
        if isExpanded {
            // Never enlarge a divider placed to the right of our reveal control.
            guard let dividerFrame = spacer?.button?.window?.frame,
                  let controlFrame = chevron?.button?.window?.frame,
                  dividerFrame.maxX <= controlFrame.minX + 1 else {
                showSetup()
                return
            }
        }
        isArranging = false
        isExpanded.toggle()
        updateAppearance()
    }

    func showSetup() {
        if isEnabled {
            isArranging = true
            isExpanded = true
            updateAppearance()
        }
        let alert = NSAlert()
        alert.messageText = "Arrange your Menu Pocket"
        alert.informativeText = "Hold Command and drag lower-priority icons to the LEFT of Arc’s vertical divider. Keep the divider to the LEFT of Arc’s chevron.\n\nKeep Arc’s capsule, battery, Wi-Fi, Search, and Control Centre to the RIGHT of the divider.\n\nClick the chevron when you’re done arranging to hide the divider and collapse the section. Click again to reveal the real icons. Click it again when you’re done; apps keep running normally. Menu Pocket starts revealed when Arc launches.\n\nIf revealed icons don’t fit beside the notch, reduce the number of menu-bar icons."
        alert.addButton(withTitle: "Got it")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func screenParametersChanged() {
        // Reopen after a display change so a new layout cannot strand the control.
        isArranging = false
        isExpanded = true
        updateAppearance()
    }

    private func updateAppearance() {
        let widestScreen = NSScreen.screens.map(\.frame.width).max() ?? 1000
        let showsDivider = isExpanded && isArranging
        spacerPadding?.isActive = !isExpanded || showsDivider
        spacer?.length = isExpanded ? (showsDivider ? 8 : expandedLength) : min(10_000, max(500, widestScreen * 2))
        spacer?.button?.image = showsDivider ? dividerImage : nil
        if isExpanded && !showsDivider, let window = spacer?.button?.window {
            // Keep a measurable boundary without the standard 16-point padding.
            window.setContentSize(NSSize(width: 1, height: window.frame.height))
        }
        spacer?.button?.window?.ignoresMouseEvents = !showsDivider
        spacer?.button?.toolTip = showsDivider
            ? "Command-drag icons to the left of this divider to hide them in Menu Pocket." : nil
        let title = isExpanded ? "Hide Menu Pocket" : "Reveal Menu Pocket"
        chevron?.button?.image = NSImage(systemSymbolName: isExpanded ? "chevron.right" : "chevron.left",
                                       accessibilityDescription: title)
        chevron?.button?.toolTip = title
        chevron?.button?.setAccessibilityLabel(title)
    }

    private func removeItems() {
        // Release the wide spacer first, restoring all other apps' icons.
        if let spacer {
            spacer.length = expandedLength
            NSStatusBar.system.removeStatusItem(spacer)
        }
        if let chevron { NSStatusBar.system.removeStatusItem(chevron) }
        spacerPadding = nil
        spacer = nil
        chevron = nil
        isArranging = false
        isExpanded = true
    }
}
