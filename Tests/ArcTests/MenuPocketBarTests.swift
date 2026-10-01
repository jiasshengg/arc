import AppKit
import ApplicationServices
import XCTest
@testable import Arc

final class MenuPocketBarTests: XCTestCase {
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
