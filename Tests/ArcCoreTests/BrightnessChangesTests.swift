import XCTest
@testable import ArcCore

final class BrightnessChangesTests: XCTestCase {
    func testWakeRampDoesNotShowHUD() {
        var changes = BrightnessChanges()
        changes.reset(at: 100)
        for (time, value) in [(100.0, 0), (100.25, 15), (100.5, 40), (101.0, 65), (102.0, 70), (102.75, 70)] {
            XCTAssertFalse(changes.receive(value, at: time))
        }
        XCTAssertTrue(changes.receive(75, at: 103))
        XCTAssertFalse(changes.receive(75, at: 103.25))
    }

    func testSlowRestorationWaitsForStableBaseline() {
        var changes = BrightnessChanges()
        changes.reset(at: 0)
        for step in 0...16 {
            XCTAssertFalse(changes.receive(step * 5, at: Double(step) / 4))
        }
        XCTAssertFalse(changes.receive(80, at: 4.75))
        XCTAssertTrue(changes.receive(85, at: 5))
    }

    func testDisplayWakeResetsAnAlreadyActiveMonitor() {
        var changes = BrightnessChanges()
        changes.reset(at: 0)
        XCTAssertFalse(changes.receive(60, at: 0))
        XCTAssertFalse(changes.receive(60, at: 2))
        XCTAssertTrue(changes.receive(65, at: 3))
        changes.reset(at: 10)
        XCTAssertFalse(changes.receive(0, at: 10))
        XCTAssertFalse(changes.receive(65, at: 11))
        XCTAssertFalse(changes.receive(65, at: 12))
        XCTAssertTrue(changes.receive(70, at: 13))
    }

    func testRapidAdjustmentsAfterSettlingAreNotDebounced() {
        var changes = BrightnessChanges()
        changes.reset(at: 0)
        XCTAssertFalse(changes.receive(50, at: 0))
        XCTAssertFalse(changes.receive(50, at: 2))
        for step in 1...5 {
            XCTAssertTrue(changes.receive(50 + step, at: 2 + Double(step) / 4))
        }
    }
}
