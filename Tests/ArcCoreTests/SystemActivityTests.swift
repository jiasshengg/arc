import XCTest
@testable import ArcCore

final class SystemActivityTests: XCTestCase {
    func testInvalidBatteryLevels() {
        XCTAssertEqual(SystemActivity(kind: .unplugged, level: .nan).level, 0)
        XCTAssertEqual(SystemActivity(kind: .charging, level: 2).level, 1)
        XCTAssertEqual(SystemActivity(kind: .charging, level: -1).level, 0)
    }

    func testPowerTransitionsAndFullCharge() {
        var tracker = BatteryTransitions()
        XCTAssertNil(tracker.receive(BatteryReading(percent: 60, pluggedIn: false, charging: false)))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 60, pluggedIn: true, charging: true))?.kind, .charging)
        XCTAssertNil(tracker.receive(BatteryReading(percent: 61, pluggedIn: true, charging: true)))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 100, pluggedIn: true, charging: false))?.kind, .charged)
        XCTAssertNil(tracker.receive(BatteryReading(percent: 100, pluggedIn: true, charging: false)))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 100, pluggedIn: false, charging: false))?.kind, .unplugged)
    }

    func testLowBatteryDoesNotRepeatAndRearmsAfterCharge() {
        var tracker = BatteryTransitions()
        XCTAssertNil(tracker.receive(BatteryReading(percent: 21, pluggedIn: false, charging: false)))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 20, pluggedIn: false, charging: false))?.kind, .lowBattery)
        XCTAssertNil(tracker.receive(BatteryReading(percent: 19, pluggedIn: false, charging: false)))
        XCTAssertNil(tracker.receive(BatteryReading(percent: 21, pluggedIn: false, charging: false)))
        XCTAssertNil(tracker.receive(BatteryReading(percent: 20, pluggedIn: false, charging: false)))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 10, pluggedIn: false, charging: false))?.kind, .lowBattery)
        XCTAssertNil(tracker.receive(BatteryReading(percent: 9, pluggedIn: false, charging: false)))
        _ = tracker.receive(BatteryReading(percent: 26, pluggedIn: false, charging: false))
        XCTAssertEqual(tracker.receive(BatteryReading(percent: 20, pluggedIn: false, charging: false))?.kind, .lowBattery)
    }

    @MainActor func testNewActivityExtendsDeadlineAndRestoresMusic() async throws {
        let model = IslandModel(enterDelay: 0)
        let track = NowPlayingSnapshot(title: "Test", isPlaying: true)
        model.receive(.media(track))
        model.hover(true)
        try await Task.sleep(for: .milliseconds(10))
        model.showActivity(SystemActivity(kind: .charging, level: 0.5), duration: 30_000_000)
        XCTAssertFalse(model.shouldTick)
        model.showActivity(SystemActivity(kind: .unplugged, level: 0.8), duration: 120_000_000)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(model.activity?.kind, .unplugged)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(model.activity)
        XCTAssertEqual(model.media, .media(track))
        XCTAssertTrue(model.expanded)
        XCTAssertTrue(model.shouldTick)
    }

    @MainActor func testHiddenIslandDropsActivity() {
        let model = IslandModel()
        model.showActivity(SystemActivity(kind: .charging, level: 0.6))
        model.setEnabled(false)
        XCTAssertNil(model.activity)
        model.showActivity(SystemActivity(kind: .charging, level: 1))
        XCTAssertNil(model.activity)
        model.setEnabled(true)
        XCTAssertNil(model.activity)
    }

    @MainActor func testScreenshotFeedbackPausesMediaAndExpires() async throws {
        let model = IslandModel(enterDelay: 0)
        model.receive(.media(NowPlayingSnapshot(title: "Test", isPlaying: true)))
        model.hover(true)
        try await Task.sleep(for: .milliseconds(10))
        model.showScreenshotCopied(duration: 30_000_000)
        XCTAssertTrue(model.screenshotCopied)
        XCTAssertFalse(model.shouldTick)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.screenshotCopied)
        XCTAssertTrue(model.shouldTick)
    }

    @MainActor func testExpandedPocketKeepsPriorityOverScreenshot() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = IslandModel(enterDelay: 0)
        XCTAssertTrue(model.pocket.hold([directory]))
        model.showScreenshotCopied()
        XCTAssertFalse(model.showsPocket)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(model.showsPocket)
    }
}
