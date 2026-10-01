import AppKit
import Combine

/// Uses Arc's own spacer to push status items on its left out of view.
@MainActor final class MenuPocketController: NSObject, ObservableObject {
    @Published private(set) var isEnabled = false
    @Published private(set) var isExpanded = true
    @Published private(set) var isBarOpen = false

    private var chevron: NSStatusItem?
    private var spacer: NSStatusItem?
    private let bar = MenuPocketBar()
    private let defaults: UserDefaults
    private let itemPrefix: String
    private var spacerPadding: NSLayoutConstraint?
    private var spacerWidth: NSLayoutConstraint?
    private var screenFrames: [CGRect] = []
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
        image.accessibilityDescription = "Menu Pocket Setup Line"
        return image
    }()

    init(defaults: UserDefaults = .standard, itemPrefix: String = "MenuPocket") {
        self.defaults = defaults
        self.itemPrefix = itemPrefix
        super.init()
        bar.onVisibilityChanged = { [weak self] in
            guard let self else { return }
            self.isBarOpen = self.bar.isVisible
            self.updateAppearance()
        }
    }

    var chevronFrame: CGRect? { chevron?.button?.window?.frame }

    func start() {
        screenFrames = NSScreen.screens.map(\.frame)
        NotificationCenter.default.addObserver(self, selector: #selector(screenParametersChanged),
                                               name: NSApplication.didChangeScreenParametersNotification,
                                               object: nil)
        if defaults.bool(forKey: "menuPocketEnabled") { setEnabled(true, startExpanded: false) }
    }

    func stop() {
        removeItems()
        NotificationCenter.default.removeObserver(self)
    }

    func setEnabled(_ enabled: Bool) {
        setEnabled(enabled, startExpanded: true)
    }

    private func setEnabled(_ enabled: Bool, startExpanded: Bool) {
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
            // Hold the revealed width with our own constraint. An imperative
            // resize is discarded whenever AppKit re-lays the item out, such as
            // when the menu bar moves to a display with different geometry.
            spacerWidth = content.widthAnchor.constraint(equalToConstant: 1)
        }

        // First-time setup is visible; relaunch keeps configured icons hidden.
        isExpanded = startExpanded
        updateAppearance()
    }

    @objc func toggle() {
        guard isEnabled else { return }
        if !isExpanded {
            guard let controlFrame = chevron?.button?.window?.frame,
                  let dividerFrame = spacer?.button?.window?.frame else { return }
            bar.toggle(beside: controlFrame, before: dividerFrame)
            return
        }
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
        bar.close()
        if isEnabled {
            isArranging = true
            isExpanded = true
            updateAppearance()
        }
        let alert = NSAlert()
        alert.messageText = "Arrange Menu Pocket"
        alert.informativeText = "Hold Command and drag the icons you want to hide to the left of the vertical line. Keep the line to the left of Arc’s arrow.\n\nKeep Arc’s main icon, battery, Wi-Fi, Search, and Control Centre to the right of the line.\n\nClick the arrow when you’re done. Click it again to open the icons in a row below the menu bar. Arc needs Accessibility permission to find and open those icons. Your apps keep running."
        alert.addButton(withTitle: "Got It")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func screenParametersChanged() {
        // Display sleep, wake, and resolution changes post this notification too,
        // so react only to an actual arrangement change and keep the current state.
        let frames = NSScreen.screens.map(\.frame)
        guard frames != screenFrames else { return }
        bar.close()
        screenFrames = frames
        // A new arrangement can strand the control off-screen; reveal only then.
        if !isExpanded && !isControlReachable {
            isArranging = false
            isExpanded = true
        }
        updateAppearance()
    }

    private var isControlReachable: Bool {
        guard let frame = chevron?.button?.window?.frame else { return false }
        return NSScreen.screens.contains { $0.frame.intersects(frame) }
    }

    private func updateAppearance() {
        let widestScreen = NSScreen.screens.map(\.frame.width).max() ?? 1000
        let showsDivider = isExpanded && isArranging
        // Keep a measurable boundary without the standard 16-point padding.
        let narrow = isExpanded && !showsDivider
        spacerPadding?.isActive = !narrow
        spacerWidth?.isActive = narrow
        spacer?.length = isExpanded ? (showsDivider ? 8 : expandedLength) : min(10_000, max(500, widestScreen * 2))
        spacer?.button?.image = showsDivider ? dividerImage : nil
        spacer?.button?.window?.ignoresMouseEvents = !showsDivider
        spacer?.button?.toolTip = showsDivider
            ? "Hold Command and drag icons to the left of this line to hide them." : nil
        let title = isExpanded ? "Hide Menu Pocket" : (isBarOpen ? "Close Menu Pocket" : "Open Menu Pocket")
        chevron?.button?.image = NSImage(systemSymbolName: isExpanded || isBarOpen ? "chevron.up" : "chevron.down",
                                       accessibilityDescription: title)
        chevron?.button?.toolTip = title
        chevron?.button?.setAccessibilityLabel(title)
    }

    private func removeItems() {
        bar.close()
        // Release the wide spacer first, restoring all other apps' icons.
        if let spacer {
            spacer.length = expandedLength
            NSStatusBar.system.removeStatusItem(spacer)
        }
        if let chevron { NSStatusBar.system.removeStatusItem(chevron) }
        spacerWidth?.isActive = false
        spacerWidth = nil
        spacerPadding = nil
        spacer = nil
        chevron = nil
        isArranging = false
        isExpanded = true
    }
}

#if DEBUG
extension MenuPocketController {
    /// Exercises native status-item layout and target/action without user preferences.
    static func smokeCheck() async -> Bool {
        let name = "Arc.MenuPocketCheck." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: name) else { return false }
        let controller = MenuPocketController(defaults: defaults, itemPrefix: name)
        defer {
            controller.stop()
            defaults.removePersistentDomain(forName: name)
        }
        // start() registers the screen-parameters observer the checks below exercise.
        controller.start()
        controller.setEnabled(true)
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(200))
            if let frame = controller.chevronFrame, frame.minY > 0 { break }
        }
        guard let button = controller.chevron?.button,
              let control = controller.chevronFrame,
              let divider = controller.spacer?.button?.window?.frame,
              divider.maxX <= control.minX + 1,
              divider.minY > 0, divider.width <= 1 else {
            print("Menu Pocket initial layout failed:", controller.chevronFrame as Any,
                  controller.spacer?.button?.window?.frame as Any)
            return false
        }
        for _ in 0..<3 {
            button.performClick(nil)
            try? await Task.sleep(for: .milliseconds(300))
            guard !controller.isExpanded, (controller.spacer?.length ?? 0) >= 500 else {
                print("Menu Pocket click did not collapse")
                return false
            }
            // Display sleep and wake post this with an unchanged arrangement; it
            // must not reveal the section behind the user's back.
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification,
                                            object: NSApp)
            try? await Task.sleep(for: .milliseconds(200))
            guard !controller.isExpanded else {
                print("Menu Pocket reopened on an unchanged screen arrangement")
                return false
            }
            button.performClick(nil)
            try? await Task.sleep(for: .milliseconds(300))
            guard !controller.isExpanded, controller.isBarOpen,
                  controller.bar.isVisible,
                  button.toolTip == "Close Menu Pocket" else {
                print("Menu Pocket click did not open the separate bar")
                return false
            }
            button.performClick(nil)
            guard !controller.bar.isVisible, !controller.isBarOpen,
                  button.toolTip == "Open Menu Pocket" else {
                print("Menu Pocket click did not close the separate bar")
                return false
            }
            controller.isExpanded = true
            controller.updateAppearance()
            try? await Task.sleep(for: .milliseconds(300))
            guard controller.isExpanded,
                  let frame = controller.spacer?.button?.window?.frame,
                  frame.width <= 1, frame.minY > 0 else {
                print("Menu Pocket did not restore narrow boundary")
                return false
            }
        }
        controller.setEnabled(false)
        guard controller.spacer == nil, controller.chevron == nil else { return false }
        controller.stop()
        defaults.set(true, forKey: "menuPocketEnabled")
        let relaunched = MenuPocketController(defaults: defaults, itemPrefix: name)
        defer { relaunched.stop() }
        relaunched.start()
        guard !relaunched.isExpanded,
              (relaunched.spacer?.length ?? 0) >= 500,
              relaunched.chevron?.button?.toolTip == "Open Menu Pocket" else {
            print("Menu Pocket did not start collapsed after relaunch")
            return false
        }
        print("Menu Pocket native check passed: three collapse/bar cycles, collapsed relaunch, cleanup")
        return true
    }
}
#endif
