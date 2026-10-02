import AppKit
import ApplicationServices

/// Temporarily moves just the selected status item across Arc's divider.
@MainActor final class MenuPocketItemAccess {
    private struct Placement {
        let window: Int
        let owner: pid_t
        let original: CGRect
        let neighbor: Int?
        let gap: CGFloat
    }
    private var placement: Placement?
    private let delivery = MenuPocketEventDelivery()
    private(set) var failureReason: String?

    private func fail(_ reason: String) -> Bool {
        failureReason = reason
        NSLog("Menu Pocket: %@", reason)
        return false
    }
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
        failureReason = nil
        guard AXIsProcessTrusted() || move != nil else { return fail("Allow Accessibility To Open Menu Icons") }
        _ = restore()
        guard !hasPendingItem else { return fail("Previous Menu Icon Has Not Returned") }
        guard let window = statusWindow(at: frame) else {
            NSLog("Menu Pocket missing source window for AX frame %@", NSStringFromRect(frame))
            return fail("Couldn’t Find The Original Menu Icon")
        }
        guard
            let number = window[kCGWindowNumber as String] as? Int,
              let owner = window[kCGWindowOwnerPID as String] as? Int32,
              let bounds = window[kCGWindowBounds as String] as? [String: Any],
              let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return fail("Couldn’t Read The Original Menu Icon") }
        let original = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
        // Native ordering is relative to another status window. Absolute hidden
        // coordinates change when other items enter or leave the group.
        let neighbor = windows().first { candidate in
            guard (candidate[kCGWindowOwnerPID as String] as? Int32) == owner,
                  (candidate[kCGWindowLayer as String] as? Int) == Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = candidate[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return abs(frame.midY - windowFrame.midY) < 2
                && frame.minX >= windowFrame.maxX - 2 && frame.minX <= windowFrame.maxX + 8
        }
        let neighborFrame = (neighbor?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        // Drop on the arrow's left edge, on the visible side of the spacer.
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let destination = CGPoint(x: control.minX + 1, y: top - control.midY)
        let destinationFrame = CGRect(x: control.minX, y: top - control.maxY,
                                      width: control.width, height: control.height)
        guard let target = statusWindow(at: destinationFrame)?[kCGWindowNumber as String] as? Int else {
            NSLog("Menu Pocket missing arrow window for frame %@", NSStringFromRect(destinationFrame))
            return fail("Couldn’t Find The Menu Pocket Arrow")
        }
        guard drag(window: number, owner: owner, from: original, to: destination, targetWindow: target) else {
            return fail("Couldn’t Send The Menu Icon Move")
        }
        NSLog("Menu Pocket move posted: window %d owner %d from %@ to %@", number, owner,
              NSStringFromPoint(original), NSStringFromPoint(destination))
        placement = Placement(window: number, owner: owner, original: windowFrame,
                              neighbor: neighbor?[kCGWindowNumber as String] as? Int,
                              gap: (neighborFrame?.minX ?? windowFrame.maxX) - windowFrame.maxX)
        return true
    }

    @discardableResult func restore() -> Bool {
        guard let placement else { return false }
        if delivery.isBusy { delivery.cancel() }
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
        let neighbor = windows().first {
            ($0[kCGWindowNumber as String] as? Int) == placement.neighbor
                && ($0[kCGWindowOwnerPID as String] as? Int32) == placement.owner
        }
        let neighborFrame = (neighbor?[kCGWindowBounds as String] as? [String: Any])
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
        let returned = neighborFrame.map {
            abs(frame.maxX + placement.gap - $0.minX) < 2 && abs(frame.midY - $0.midY) < 2
        } ?? Self.matches(frame, placement.original)
        if returned {
            self.placement = nil
            return false
        }
        // Retain the original placement until a later observation confirms it.
        // Posting events can succeed even if macOS ignores the move.
        return drag(window: placement.window, owner: placement.owner,
                    from: CGPoint(x: frame.midX, y: frame.midY),
                    to: neighborFrame.map { CGPoint(x: $0.minX + 1, y: $0.midY) }
                        ?? CGPoint(x: placement.original.midX, y: placement.original.midY),
                    targetWindow: neighbor?[kCGWindowNumber as String] as? Int)
    }

    func statusWindow(at frame: CGRect) -> [String: Any]? {
        return windows().first { window in
            guard (window[kCGWindowLayer as String] as? Int ?? 0) >= Int(CGWindowLevelForKey(.statusWindow)),
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let windowFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            // AX describes the clickable content, not the whole hosting window.
            // macOS can add vertical padding and expand the AX hit area sideways.
            return abs(windowFrame.midX - frame.midX) < 2
                && abs(windowFrame.midY - frame.midY) < 2
                && frame.width <= windowFrame.width + 8
                && frame.height <= windowFrame.height + 8
                && windowFrame.width <= frame.width + 16
                && windowFrame.height <= frame.height + 16
        }
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 2 && abs(lhs.minY - rhs.minY) < 2
            && abs(lhs.width - rhs.width) < 2 && abs(lhs.height - rhs.height) < 2
    }

    private func drag(window: Int, owner: pid_t, from: CGPoint, to: CGPoint, targetWindow: Int? = nil) -> Bool {
        if let move { return move(window, owner, from, to, targetWindow) }
        guard AXIsProcessTrusted(),
              let down = Self.event(.leftMouseDown, window: window, at: from, command: true, owner: owner),
              let up = Self.event(.leftMouseUp, window: targetWindow ?? window, at: to, command: false, owner: owner) else { return false }
        guard let release = Self.event(.leftMouseUp, window: window, at: from,
                                       command: false, owner: owner) else { return false }
        return delivery.send([down, up], owner: owner, release: release)
    }

    static func event(_ type: NSEvent.EventType, window: Int, at point: CGPoint, command: Bool, owner: pid_t = 0) -> CGEvent? {
        // AppKit supplies the native window number through its public event API.
        guard let event = NSEvent.mouseEvent(with: type, location: .zero,
                                             modifierFlags: command ? .command : [],
                                             timestamp: ProcessInfo.processInfo.systemUptime,
                                             windowNumber: window, context: nil,
                                             eventNumber: 0, clickCount: 1, pressure: 1)?.cgEvent else { return nil }
        event.location = point
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(owner))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(window))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(window))
        return event
    }
}
