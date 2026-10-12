import XCTest
@testable import ArcCore

final class SettingsTests: XCTestCase {
    @MainActor func testPausedMusicDeadlineSurvivesMetadataAndResumesOnPlayback() async throws {
        let model = IslandModel()
        model.setPausedMusicDelay(0.06)
        let paused = NowPlayingSnapshot(title: "Song", isPlaying: false)
        model.receive(.media(paused))
        try await Task.sleep(for: .milliseconds(40))
        model.receive(.media(paused))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertTrue(model.pausedMediaHidden)
        XCTAssertFalse(model.shouldShowIsland)
        XCTAssertEqual(model.media, .media(paused))
        XCTAssertEqual(model.visibleMedia, .idle)
        model.showScreenshotCopied()
        XCTAssertTrue(model.shouldShowIsland)
        model.clearScreenshotFeedback()
        model.receive(.media(NowPlayingSnapshot(title: "Song", isPlaying: true)))
        XCTAssertFalse(model.pausedMediaHidden)
        XCTAssertTrue(model.shouldShowIsland)
        model.receive(.media(paused))
        try await Task.sleep(for: .milliseconds(80))
        model.setPausedMusicDelay(0)
        XCTAssertTrue(model.shouldShowIsland)
        XCTAssertEqual(model.visibleMedia, .media(paused))
    }

    @MainActor func testPausedMusicTimerCancelsForNewTrackAndIdle() async throws {
        let model = IslandModel()
        model.setPausedMusicDelay(0.06)
        model.receive(.media(NowPlayingSnapshot(title: "First")))
        try await Task.sleep(for: .milliseconds(40))
        model.receive(.media(NowPlayingSnapshot(title: "Second")))
        try await Task.sleep(for: .milliseconds(40))
        XCTAssertFalse(model.pausedMediaHidden)
        model.receive(.idle)
        try await Task.sleep(for: .milliseconds(80))
        XCTAssertFalse(model.pausedMediaHidden)
        XCTAssertTrue(model.shouldShowIsland)
    }

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
