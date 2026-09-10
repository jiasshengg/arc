import XCTest
@testable import ArcCore

final class BrightnessKeyTests: XCTestCase {
    func testBrightnessKeyPressAndRepeat() {
        XCTAssertTrue(BrightnessKey.isAdjustment(subtype: 8, data: (2 << 16) | 0x0a00))
        XCTAssertTrue(BrightnessKey.isAdjustment(subtype: 8, data: (3 << 16) | 0x0a00))
        XCTAssertTrue(BrightnessKey.isAdjustment(subtype: 8, data: (2 << 16) | 0x0a01))
    }

    func testKeyReleaseDoesNotTriggerHUD() {
        XCTAssertFalse(BrightnessKey.isAdjustment(subtype: 8, data: (2 << 16) | 0x0b00))
    }

    func testOtherSystemKeysAndEventTypesDoNotTriggerHUD() {
        for key in [0, 1, 7, 16, 21, 22] {
            XCTAssertFalse(BrightnessKey.isAdjustment(subtype: 8, data: (key << 16) | 0x0a00))
        }
        XCTAssertFalse(BrightnessKey.isAdjustment(subtype: 0, data: (2 << 16) | 0x0a00))
    }
}
