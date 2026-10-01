import AppKit
import ApplicationServices

/// Temporarily moves just the selected status item across Arc's divider.
@MainActor final class MenuPocketItemAccess {
    private struct Placement {
        let window: Int
        let owner: pid_t
        let original: CGRect
    }
    private var placement: Placement?
    private let windows: () -> [[String: Any]]
    private let move: ((Int, pid_t, CGPoint, CGPoint, Int?) -> Bool)?
    var hasPendingItem: Bool { placement != nil }

    init(windows: @escaping () -> [[String: Any]] = {
        CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
    }, move: ((Int, pid_t, CGPoint, CGPoint, Int?) -> Bool)? = nil) {
        self.windows = windows
        self.move = move
    }

    func show(_ frame: CGRect, beside control: CGRect) -> Bool {
        _ = restore()
        guard !hasPendingItem, let window = statusWindow(at: frame),
              let number = window[kCGWindowNumber as String] as? Int,
              let owner = window[kCGWindowOwnerPID as String] as? Int32 else { return false }
        let original = CGPoint(x: frame.midX, y: frame.midY)
        // Drop on the arrow's left edge, on the visible side of the spacer.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let destination = CGPoint(x: control.minX + 1, y: top - control.midY)
        let destinationFrame = CGRect(x: control.minX, y: top - control.maxY,
                                      width: control.width, height: control.height)
        guard let target = statusWindow(at: destinationFrame)?[kCGWindowNumber as String] as? Int,
              drag(window: number, owner: owner, from: original, to: destination, targetWindow: target) else { return false }
        placement = Placement(window: number, owner: owner, original: frame)
        return true
    }

    @discardableResult func restore() -> Bool {
        guard let placement else { return false }
        guard let window = windows().first(where: {
            ($0[kCGWindowNumber as String] as? Int) == placement.window
                && ($0[kCGWindowOwnerPID as String] as? Int32) == placement.owner
        }) else {
            // The original item has gone away; never move a reused window ID.
            self.placement = nil
            return false
        }
        guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
        if Self.matches(frame, placement.original) {
            self.placement = nil
            return false
        }
        // Retain the original placement until a later observation confirms it.
        // Posting events can succeed even if macOS ignores the move.
        return drag(window: placement.window, owner: placement.owner,
                    from: CGPoint(x: frame.midX, y: frame.midY),
                    to: CGPoint(x: placement.original.midX, y: placement.original.midY))
    }

    private func statusWindow(at frame: CGRect) -> [String: Any]? {
        return windows().first { window in
            guard (window[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return Self.matches(windowFrame, frame)
        }
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 2 && abs(lhs.minY - rhs.minY) < 2
            && abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    private func drag(window: Int, owner: pid_t, from: CGPoint, to: CGPoint, targetWindow: Int? = nil) -> Bool {
        if let move { return move(window, owner, from, to, targetWindow) }
        guard AXIsProcessTrusted(),
              let down = Self.event(.leftMouseDown, window: window, at: from, command: true),
              let up = Self.event(.leftMouseUp, window: targetWindow ?? window, at: to, command: false) else { return false }
        let pointer = CGEvent(source: nil)?.location
        down.postToPid(owner)
        up.post(tap: .cgSessionEventTap)
        if let pointer { CGWarpMouseCursorPosition(pointer) }
        return true
    }

    static func event(_ type: NSEvent.EventType, window: Int, at point: CGPoint, command: Bool) -> CGEvent? {
        // AppKit supplies the native window number through its public event API.
        guard let event = NSEvent.mouseEvent(with: type, location: .zero,
                                             modifierFlags: command ? .command : [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1)?.cgEvent else { return nil }
        event.location = point
        return event
    }
}
