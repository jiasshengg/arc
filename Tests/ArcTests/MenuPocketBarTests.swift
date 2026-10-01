import AppKit
import ApplicationServices
import XCTest
@testable import Arc

final class MenuPocketBarTests: XCTestCase {
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
        let down = try XCTUnwrap(MenuPocketItemAccess.event(.leftMouseDown, window: 42, at: point, command: true))
        XCTAssertEqual(NSEvent(cgEvent: down)?.windowNumber, 42)
        XCTAssertEqual(down.type, .leftMouseDown)
        XCTAssertEqual(down.location, point)
        XCTAssertTrue(down.flags.contains(.maskCommand))
        let up = try XCTUnwrap(MenuPocketItemAccess.event(.leftMouseUp, window: 42, at: point, command: false))
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
