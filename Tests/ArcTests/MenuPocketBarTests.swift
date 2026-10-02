import AppKit
import ApplicationServices
import XCTest
@testable import Arc

final class MenuPocketBarTests: XCTestCase {
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
