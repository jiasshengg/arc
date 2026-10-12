import XCTest
@testable import ArcCore

final class SettingsTests: XCTestCase {
    @MainActor func testIdleHidingRestoresForMediaAlertsAndFileDrops() throws {
        let model = IslandModel()
        XCTAssertTrue(model.shouldShowIsland)
        model.hideWhenIdle = true
        XCTAssertFalse(model.shouldShowIsland)
        model.receive(.unavailable)
        XCTAssertFalse(model.shouldShowIsland)
        model.receive(.media(NowPlayingSnapshot(title: "Paused")))
        XCTAssertTrue(model.shouldShowIsland)
        model.receive(.idle)
        model.showActivity(SystemActivity(kind: .charging, level: 0.5))
        XCTAssertTrue(model.shouldShowIsland)
        model.clearActivity()
        XCTAssertFalse(model.shouldShowIsland)
        model.showScreenshotCopied()
        XCTAssertTrue(model.shouldShowIsland)
        model.clearScreenshotFeedback()
        model.setReceivingFiles(true)
        XCTAssertTrue(model.shouldShowIsland)
        model.setReceivingFiles(false)
        XCTAssertFalse(model.shouldShowIsland)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        model.pocket.hold([file])
        XCTAssertTrue(model.shouldShowIsland)
        model.pocket.clear()
        XCTAssertFalse(model.shouldShowIsland)
        model.hideWhenIdle = false
        XCTAssertTrue(model.shouldShowIsland)
        model.setEnabled(false)
        XCTAssertFalse(model.shouldShowIsland)
    }
}
