import AppKit
import ApplicationServices
import XCTest
import SwiftUI
@testable import Arc

final class MenuPocketBarTests: XCTestCase {
    @MainActor func testFailedPressTriesShowMenuBeforeMouseFallback() async {
        for failure in [AXError.failure, .cannotComplete, .actionUnsupported] {
            var actions: [String] = []
            let result = await MenuPocketBar.openAccessibilityMenu(perform: { action in
                actions.append(action)
                return action == kAXPressAction ? failure : .success
            }, menuOpened: { false })
            XCTAssertEqual(result, .success)
            XCTAssertEqual(actions, [kAXPressAction, kAXShowMenuAction])
        }
    }

    @MainActor func testFailedAccessibilityActionsAllowNativeClick() async {
        for failure in [AXError.failure, .cannotComplete, .actionUnsupported] {
            var actions: [String] = []
            let result = await MenuPocketBar.openAccessibilityMenu(perform: {
                actions.append($0)
                return failure
            }, menuOpened: { false })
            XCTAssertEqual(actions, [kAXPressAction, kAXShowMenuAction])
            XCTAssertTrue(MenuPocketBar.canRetryMenuAction(result))
        }
    }

    @MainActor func testDelayedMenuAfterFailedReplyIsNotPressedAgain() async {
        var actions: [String] = []
        var observations = 0
        let result = await MenuPocketBar.openAccessibilityMenu(perform: {
            actions.append($0)
            return .cannotComplete
        }, menuOpened: {
            observations += 1
            return observations == 3
        })
        XCTAssertEqual(result, .success)
        XCTAssertEqual(actions, [kAXPressAction])
    }

    @MainActor func testInvalidOrDisabledAccessibilityControlIsNotClicked() async {
        for failure in [AXError.invalidUIElement, .apiDisabled] {
            var actions: [String] = []
            let result = await MenuPocketBar.openAccessibilityMenu(perform: {
                actions.append($0)
                return failure
            }, menuOpened: { false })
            XCTAssertEqual(result, failure)
            XCTAssertEqual(actions, [kAXPressAction])
            XCTAssertFalse(MenuPocketBar.canRetryMenuAction(result))
        }
    }

    @MainActor func testOverflowRowNeverShowsNativeScrollbars() async throws {
        let hosting = NSHostingView(rootView: MenuPocketBar.scrollbarPreview().frame(width: 320, height: 72))
        hosting.frame = CGRect(x: 0, y: 0, width: 320, height: 72)
        let window = NSWindow(contentRect: hosting.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        hosting.layoutSubtreeIfNeeded()
        func findScrollView(_ view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView { return scrollView }
            return view.subviews.lazy.compactMap(findScrollView).first
        }
        let scrollView = try XCTUnwrap(findScrollView(hosting))
        XCTAssertFalse(scrollView.hasHorizontalScroller)
        XCTAssertFalse(scrollView.hasVerticalScroller)
        let document = try XCTUnwrap(scrollView.documentView)
        XCTAssertGreaterThan(document.frame.width, scrollView.contentView.bounds.width)
        let offset = document.frame.width - scrollView.contentView.bounds.width
        scrollView.contentView.scroll(to: NSPoint(x: offset, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        XCTAssertGreaterThan(scrollView.contentView.bounds.origin.x, 0)
    }

    @MainActor func testGroupingUsesLiveDividerAfterAnotherIconReturns() {
        let bar = MenuPocketBar()
        let beforeRestore = CGRect(x: -4100, y: 0, width: 5000, height: 33)
        var liveDivider = beforeRestore
        bar.currentDividerFrame = { liveDivider }
        // Returning Teams shifts the boundary right past the unchanged Glide
        // frame. The pre-restoration boundary would incorrectly omit Glide.
        let glide = CGRect(x: -4084, y: 4.5, width: 24, height: 24)
        liveDivider.origin.x += 37
        XCTAssertLessThan(glide.minX, bar.groupingBoundary(before: beforeRestore))
        XCTAssertGreaterThan(glide.minX, beforeRestore.minX)
        liveDivider.origin.x -= 50
        XCTAssertEqual(bar.groupingBoundary(before: beforeRestore), liveDivider.minX)
        bar.currentDividerFrame = { nil }
        XCTAssertEqual(bar.groupingBoundary(before: beforeRestore), beforeRestore.minX)
    }

    func testPointerRestorationPreservesPhysicalDeltasDespiteScreenEdgeClamping() throws {
        var snapshot = MenuPocketPointerSnapshot(point: CGPoint(x: 800, y: 300))
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                         mouseCursorPosition: .zero, mouseButton: .left))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventSourceStateID, value: Int64(CGEventSourceStateID.hidSystemState.rawValue))
        event.setDoubleValueField(.mouseEventDeltaX, value: 12)
        event.setDoubleValueField(.mouseEventDeltaY, value: -6)
        snapshot.record(event)
        XCTAssertEqual(snapshot.point, CGPoint(x: 812, y: 294))
        event.type = .leftMouseDragged
        snapshot.record(event)
        XCTAssertEqual(snapshot.point, CGPoint(x: 824, y: 288))
    }

    func testPointerRestorationIgnoresSyntheticMotionClicksAndScrolling() throws {
        let point = CGPoint(x: 800, y: 300)
        let event = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                         mouseCursorPosition: .zero, mouseButton: .left))
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventSourceStateID, value: Int64(CGEventSourceStateID.hidSystemState.rawValue))
        event.setDoubleValueField(.mouseEventDeltaX, value: -800)
        event.setDoubleValueField(.mouseEventDeltaY, value: -300)
        var snapshot = MenuPocketPointerSnapshot(point: point)
        event.setIntegerValueField(.eventSourceUserData, value: 123)
        snapshot.record(event)
        XCTAssertEqual(snapshot.point, point)
        event.setIntegerValueField(.eventSourceUserData, value: 0)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(getpid()))
        snapshot.record(event)
        XCTAssertEqual(snapshot.point, point)
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.eventSourceStateID, value: Int64(CGEventSourceStateID.privateState.rawValue))
        snapshot.record(event)
        XCTAssertEqual(snapshot.point, point)
        event.setIntegerValueField(.eventSourceStateID, value: Int64(CGEventSourceStateID.hidSystemState.rawValue))
        for type in [CGEventType.leftMouseUp, .leftMouseDown, .scrollWheel] {
            event.type = type
            snapshot.record(event)
            XCTAssertEqual(snapshot.point, point)
        }
    }

    @MainActor func testMenuTimeoutRequiresANewMenuFromTheSelectedApp() {
        let menu = [kCGWindowNumber as String: 10, kCGWindowOwnerPID as String: Int32(20),
                    kCGWindowLayer as String: Int(CGWindowLevelForKey(.popUpMenuWindow)),
                    kCGWindowBounds as String: CGRect(x: 900, y: 24, width: 200, height: 150).dictionaryRepresentation] as [String: Any]
        XCTAssertTrue(MenuPocketBar.hasOpenedMenu(owner: 20, before: [], after: [menu]))
        XCTAssertFalse(MenuPocketBar.hasOpenedMenu(owner: 21, before: [], after: [menu]))
        XCTAssertFalse(MenuPocketBar.hasOpenedMenu(owner: 20, before: [menu], after: [menu]))
        XCTAssertFalse(MenuPocketBar.hasOpenedMenu(owner: 20, before: [], after: []))
        var ordinaryWindow = menu
        ordinaryWindow[kCGWindowLayer as String] = 0
        XCTAssertFalse(MenuPocketBar.hasOpenedMenu(owner: 20, before: [], after: [ordinaryWindow]))
    }

    @MainActor func testRestorationTargetsOriginalNeighborAfterGroupRelayout() {
        let original = CGRect(x: -3000, y: 0, width: 24, height: 24)
        let control = CGRect(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 24,
                             width: 18, height: 24)
        var itemFrame = original
        var neighborFrame = CGRect(x: -2976, y: 0, width: 24, height: 24)
        var destination: CGPoint?
        var target: Int?
        let access = MenuPocketItemAccess(windows: {
            [self.window(1, owner: 20, frame: itemFrame),
             self.window(3, owner: 20, frame: neighborFrame),
             self.window(2, owner: 20, frame: CGRect(x: 900, y: 0, width: 18, height: 24))]
        }, move: { _, _, _, point, window in destination = point; target = window; return true })
        XCTAssertTrue(access.show(original, beside: control))
        itemFrame = CGRect(x: 876, y: 0, width: 24, height: 24)
        neighborFrame.origin.x -= 37
        XCTAssertTrue(access.restore())
        XCTAssertEqual(target, 3)
        XCTAssertEqual(destination, CGPoint(x: neighborFrame.minX + 1, y: neighborFrame.midY))
        XCTAssertTrue(access.hasPendingItem)
        itemFrame.origin.x = neighborFrame.minX - itemFrame.width
        XCTAssertFalse(access.restore())
        XCTAssertFalse(access.hasPendingItem)
    }

    @MainActor func testArrowProxyMatchesInsetHostingWindow() {
        let original = CGRect(x: -3000, y: 0, width: 34, height: 33)
        let control = CGRect(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 33,
                             width: 34, height: 33)
        var targetWindow: Int?
        let access = MenuPocketItemAccess(windows: {
            [self.window(1, owner: 20, frame: original),
             // Native smoke check: proxy 34x33, host inset 3 points per side.
             self.window(2, owner: 20, frame: CGRect(x: 903, y: 3, width: 28, height: 27))]
        }, move: { _, _, _, _, target in targetWindow = target; return true })
        XCTAssertTrue(access.show(original, beside: control))
        XCTAssertEqual(targetWindow, 2)
        XCTAssertNil(access.failureReason)
    }

    @MainActor func testAccessibilityContentMatchesPaddedStatusWindow() {
        // Observed locally: AX is 36x24 at (954, 4.5), hosting window is
        // 34x33 at (955, 0). They share a center, not a size or origin.
        let content = CGRect(x: -2046, y: 4.5, width: 36, height: 24)
        let original = CGRect(x: -2045, y: 0, width: 34, height: 33)
        let control = CGRect(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 33,
                             width: 34, height: 33)
        var itemFrame = original
        var selectedWindow: Int?
        let access = MenuPocketItemAccess(windows: {
            [self.window(99, owner: 20, frame: CGRect(x: -3000, y: 0, width: 4000, height: 33)),
             self.window(1, owner: 20, frame: itemFrame),
             self.window(2, owner: 20, frame: CGRect(x: 900, y: 0, width: 34, height: 33))]
        }, move: { window, _, _, _, _ in selectedWindow = window; return true })
        XCTAssertTrue(access.show(content, beside: control))
        XCTAssertEqual(selectedWindow, 1, "Match the icon window, not the large spacer")
        itemFrame = CGRect(x: 866, y: 0, width: 34, height: 33)
        XCTAssertTrue(access.restore())
        itemFrame = original
        XCTAssertFalse(access.restore())
        XCTAssertFalse(access.hasPendingItem, "Compare restored window geometry with the original window")
    }

    @MainActor func testFailedRestorationKeepsOriginalPlacementAndBlocksAnotherMove() throws {
        let original = CGRect(x: -3000, y: 0, width: 24, height: 24)
        let visible = CGRect(x: 876, y: 0, width: 24, height: 24)
        let control = CGRect(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 24,
                             width: 18, height: 24)
        var itemFrame = original
        var permitMove = true
        var destinations: [CGPoint] = []
        let access = MenuPocketItemAccess(windows: {
            [self.window(1, owner: 20, frame: itemFrame),
             self.window(2, owner: 20, frame: CGRect(x: 900, y: 0, width: 18, height: 24))]
        }, move: { _, _, _, to, _ in
            destinations.append(to)
            return permitMove
        })
        XCTAssertTrue(access.show(original, beside: control))
        itemFrame = visible
        permitMove = false
        XCTAssertFalse(access.restore())
        XCTAssertTrue(access.hasPendingItem)
        XCTAssertFalse(access.show(visible, beside: control))
        XCTAssertTrue(access.hasPendingItem)
        XCTAssertEqual(destinations.last, CGPoint(x: original.midX, y: original.midY))

        permitMove = true
        XCTAssertTrue(access.restore())
        XCTAssertTrue(access.hasPendingItem, "Posting events does not confirm restoration")
        itemFrame = original
        XCTAssertFalse(access.restore())
        XCTAssertFalse(access.hasPendingItem)
    }

    @MainActor func testRestorationNeverMovesReusedWindowFromAnotherProcess() {
        let original = CGRect(x: -3000, y: 0, width: 24, height: 24)
        let control = CGRect(x: 900, y: (NSScreen.screens.first?.frame.maxY ?? 0) - 24,
                             width: 18, height: 24)
        var owner: Int32 = 20
        var moves = 0
        let access = MenuPocketItemAccess(windows: {
            [self.window(1, owner: owner, frame: original),
             self.window(2, owner: 20, frame: CGRect(x: 900, y: 0, width: 18, height: 24))]
        }, move: { _, _, _, _, _ in moves += 1; return true })
        XCTAssertTrue(access.show(original, beside: control))
        owner = 21
        XCTAssertFalse(access.restore())
        XCTAssertFalse(access.hasPendingItem)
        XCTAssertEqual(moves, 1)
    }

    private func window(_ number: Int, owner: Int32, frame: CGRect) -> [String: Any] {
        [kCGWindowNumber as String: number, kCGWindowOwnerPID as String: owner,
         kCGWindowLayer as String: Int(CGWindowLevelForKey(.statusWindow)),
         kCGWindowBounds as String: frame.dictionaryRepresentation]
    }

    @MainActor func testNativeMoveIncludesCommandDragBeforeRelease() throws {
        let from = CGPoint(x: -3000, y: 16)
        let to = CGPoint(x: 900, y: 16)
        let events = try XCTUnwrap(MenuPocketItemAccess.dragEvents(window: 42, owner: 20,
                                                                 from: from, to: to, targetWindow: 99))
        XCTAssertEqual(events.map(\.type), [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        XCTAssertEqual(events.map(\.location), [from, to, to])
        XCTAssertTrue(events[1].flags.contains(.maskCommand))
        XCTAssertEqual(NSEvent(cgEvent: events[1])?.windowNumber, 42)
        XCTAssertEqual(NSEvent(cgEvent: events[2])?.windowNumber, 99)
        XCTAssertFalse(events[2].flags.contains(.maskCommand))
        let sourceID = try XCTUnwrap(CGEventSource(event: events[0])).sourceStateID
        for event in events {
            let source = try XCTUnwrap(CGEventSource(event: event))
            XCTAssertEqual(source.sourceStateID, sourceID)
            XCTAssertNotEqual(source.sourceStateID, .hidSystemState)
            XCTAssertNotEqual(source.sourceStateID, .combinedSessionState)
            XCTAssertEqual(source.localEventsSuppressionInterval, 0)
            XCTAssertEqual(source.getLocalEventsFilterDuringSuppressionState(.eventSuppressionStateRemoteMouseDrag), [.permitLocalMouseEvents, .permitLocalKeyboardEvents, .permitSystemDefinedEvents])
        }
    }

    @MainActor func testStatusItemEventsTargetOneWindow() throws {
        let point = CGPoint(x: 1000, y: 15)
        let down = try XCTUnwrap(MenuPocketItemAccess.event(.leftMouseDown, window: 42, at: point, command: true, owner: 20))
        XCTAssertEqual(NSEvent(cgEvent: down)?.windowNumber, 42)
        XCTAssertEqual(down.type, .leftMouseDown)
        XCTAssertEqual(down.location, point)
        XCTAssertEqual(down.getIntegerValueField(.eventTargetUnixProcessID), 20)
        XCTAssertEqual(down.getIntegerValueField(.mouseEventWindowUnderMousePointer), 42)
        XCTAssertEqual(down.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent), 42)
        XCTAssertTrue(down.flags.contains(.maskCommand))
        let up = try XCTUnwrap(MenuPocketItemAccess.event(.leftMouseUp, window: 42, at: point, command: false, owner: 20))
        XCTAssertEqual(up.getIntegerValueField(.eventTargetUnixProcessID), 20)
        XCTAssertEqual(up.getIntegerValueField(.mouseEventWindowUnderMousePointer), 42)
        XCTAssertEqual(up.type, .leftMouseUp)
        XCTAssertFalse(up.flags.contains(.maskCommand))
    }

    @MainActor func testHiddenAndPartiallyOffscreenIconsAreNotClicked() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
        XCTAssertTrue(MenuPocketBar.isOnScreen(CGRect(x: 1200, y: 0, width: 24, height: 24), screens: screens))
        XCTAssertFalse(MenuPocketBar.isOnScreen(CGRect(x: -3000, y: 0, width: 24, height: 24), screens: screens))
        XCTAssertFalse(MenuPocketBar.isOnScreen(CGRect(x: -12, y: 0, width: 24, height: 24), screens: screens))
        XCTAssertFalse(MenuPocketBar.isOnScreen(CGRect(x: 1200, y: 0, width: 0, height: 24), screens: screens))
    }

    @MainActor func testAccessibilityCoordinatesOnOffsetSecondaryDisplays() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 300, width: 1920, height: 1080)]
        XCTAssertTrue(MenuPocketBar.isOnScreen(CGRect(x: -500, y: -480, width: 24, height: 24), screens: screens))
        XCTAssertFalse(MenuPocketBar.isOnScreen(CGRect(x: -500, y: 700, width: 24, height: 24), screens: screens))
    }
}
