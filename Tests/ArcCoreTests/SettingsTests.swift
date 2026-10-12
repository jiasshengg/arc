import XCTest
@testable import ArcCore

final class SettingsTests: XCTestCase {
    @MainActor func testArrangementSuppressesContentInteractionsAndPlaybackWithoutChangingPreference() async throws {
        let model = IslandModel(enterDelay: 0)
        model.receive(.media(NowPlayingSnapshot(title: "Song", isPlaying: true)))
        model.expand()
        XCTAssertTrue(model.shouldTick)
        model.hover(true)
        model.setArrangingMenuPocket(true)
        XCTAssertTrue(model.enabled)
        XCTAssertFalse(model.expanded)
        XCTAssertFalse(model.shouldShowIsland)
        XCTAssertFalse(model.shouldTick)
        XCTAssertFalse(model.shouldAnimatePlayback)
        model.expand()
        model.hover(true)
        model.setReceivingFiles(true)
        model.showActivity(SystemActivity(kind: .charging, level: 0.5))
        model.showScreenshotCopied()
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.expanded)
        XCTAssertFalse(model.receivingFiles)
        XCTAssertFalse(model.shouldShowIsland)
        XCTAssertEqual(model.media.snapshot?.title, "Song")
        model.clearActivity()
        model.clearScreenshotFeedback()
        model.setArrangingMenuPocket(false)
        XCTAssertTrue(model.shouldShowIsland)
        XCTAssertTrue(model.shouldAnimatePlayback)
        model.setArrangingMenuPocket(true)
        model.setEnabled(false)
        model.setArrangingMenuPocket(false)
        XCTAssertFalse(model.enabled)
        XCTAssertFalse(model.shouldShowIsland)
    }

    func testDisplaySelectionUsesPreferenceAndFallsBackWhenDisconnected() {
        let ids = ["external", "built-in"]
        XCTAssertEqual(IslandLayout.screenIndex(ids: ids, notchedIndex: 1, preferredID: ""), 1)
        XCTAssertEqual(IslandLayout.screenIndex(ids: ids, notchedIndex: 1, preferredID: "external"), 0)
        XCTAssertEqual(IslandLayout.screenIndex(ids: ids, notchedIndex: 1, preferredID: "missing"), 1)
        XCTAssertEqual(IslandLayout.screenIndex(ids: ["external"], notchedIndex: nil, preferredID: "built-in"), 0)
        XCTAssertEqual(IslandLayout.screenIndex(ids: ["external", "built-in"], notchedIndex: 1, preferredID: "built-in"), 1)
        XCTAssertNil(IslandLayout.screenIndex(ids: [], notchedIndex: nil, preferredID: "missing"))
    }

    @MainActor func testHoverOffAllowsExplicitExpansionAndDragEntry() async throws {
        let model = IslandModel(enterDelay: 0, exitDelay: 0)
        model.setExpandsOnHover(false)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.expanded)
        model.expand()
        XCTAssertTrue(model.expanded)
        model.hover(false)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(model.expanded)
        model.setReceivingFiles(true)
        XCTAssertTrue(model.expanded)
        model.setExpandsOnHover(true)
        XCTAssertTrue(model.expanded)
        model.setReceivingFiles(false)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.expanded)
    }

    @MainActor func testChangingHoverPreferencesRestartsPendingExpansion() async throws {
        let model = IslandModel(enterDelay: 30_000_000)
        model.hover(true)
        model.setExpandsOnHover(false)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(model.expanded)
        model.setExpandsOnHover(true)
        model.setHoverDelay(0.08)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(model.expanded)
        model.setHoverDelay(0)
        try await Task.sleep(for: .milliseconds(70))
        XCTAssertTrue(model.expanded)
    }

    @MainActor func testReenablingHoverExpandsWithoutAnotherPointerEvent() async throws {
        let model = IslandModel(enterDelay: 0)
        model.setExpandsOnHover(false)
        model.hover(true)
        model.setExpandsOnHover(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.expanded)
    }

    @MainActor func testChangingEnterDelayDoesNotCancelPointerExit() async throws {
        let model = IslandModel(enterDelay: 0, exitDelay: 30_000_000)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(model.expanded)
        model.hover(false)
        model.setHoverDelay(0.3)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(model.expanded)
    }

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

    @MainActor func testPausedTracksWithSameTitleFromDifferentAlbumsGetNewDeadline() async throws {
        let model = IslandModel()
        model.setPausedMusicDelay(0.03)
        model.receive(.media(NowPlayingSnapshot(title: "Intro", artist: "Artist", album: "First", duration: 60)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.pausedMediaHidden)
        model.receive(.media(NowPlayingSnapshot(title: "Intro", artist: "Artist", album: "Second", duration: 90)))
        XCTAssertFalse(model.pausedMediaHidden)
        XCTAssertTrue(model.shouldShowIsland)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.pausedMediaHidden)
        model.receive(.media(NowPlayingSnapshot(title: "Intro", artist: "Artist", album: "Second", duration: 120)))
        XCTAssertFalse(model.pausedMediaHidden)
        model.receive(.idle)
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
