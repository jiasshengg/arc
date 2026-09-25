import XCTest
import CoreGraphics
@testable import ArcCore

final class ArcCoreTests: XCTestCase {
    let epoch = Date(timeIntervalSince1970: 100)

    func testProgressExtrapolatesAndClamps() {
        let track = NowPlayingSnapshot(title: "Track", duration: 120, elapsed: 30, observedAt: epoch, isPlaying: true, playbackRate: 2)
        XCTAssertEqual(track.position(at: epoch.addingTimeInterval(10)), 50)
        XCTAssertEqual(track.progress(at: epoch.addingTimeInterval(100)), 1)
        XCTAssertEqual(track.position(at: epoch.addingTimeInterval(-10)), 30)
    }

    func testPausedDoesNotAdvance() {
        let track = NowPlayingSnapshot(title: "Track", duration: 120, elapsed: 30, observedAt: epoch)
        XCTAssertEqual(track.position(at: epoch.addingTimeInterval(60)), 30)
    }

    func testSeekingClampsAndResetsObservationTime() {
        let track = NowPlayingSnapshot(title: "Track", duration: 120, elapsed: 30,
                                       observedAt: epoch, isPlaying: true)
        let seekDate = epoch.addingTimeInterval(10)
        XCTAssertEqual(track.seeking(to: 75, at: seekDate).position(at: seekDate), 75)
        XCTAssertEqual(track.seeking(to: -5, at: seekDate).position(at: seekDate), 0)
        XCTAssertEqual(track.seeking(to: 150, at: seekDate).position(at: seekDate), 120)
    }

    func testMalformedNumbersAreNormalized() {
        for invalid in [Double.nan, .infinity, -.infinity, -1, 0] {
            let track = NowPlayingSnapshot(title: " ", duration: invalid, elapsed: invalid, observedAt: epoch, isPlaying: true, playbackRate: .nan)
            XCTAssertNil(track.duration)
            XCTAssertEqual(track.title, "Unknown title")
            XCTAssertEqual(track.progress(at: epoch), 0)
            XCTAssertEqual(track.position(at: epoch), 0)
        }
    }

    func testCompletePayloadAndTrackReplacement() throws {
        let first = try MediaDecoder.decode(Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"test.player","title":"First","artist":"Artist","artworkData":"aGVsbG8=","playing":true,"durationMicros":120000000,"elapsedTimeMicros":30000000,"timestampEpochMicros":100000000}}"#.utf8), now: epoch)
        XCTAssertEqual(first.snapshot?.artworkData, Data("hello".utf8))
        XCTAssertEqual(first.snapshot?.position(at: epoch), 30)
        let second = try MediaDecoder.decode(Data(#"{"type":"data","diff":false,"payload":{"bundleIdentifier":"test.player","title":"Second","playing":false}}"#.utf8), now: epoch)
        XCTAssertNil(second.snapshot?.artworkData)
        XCTAssertEqual(second.snapshot?.artist, "")
        XCTAssertEqual(second.snapshot?.title, "Second")
        XCTAssertEqual(second.snapshot?.isPlaying, false)
    }

    func testIdleAndMissingMetadata() throws {
        for value in ["null", "{}", #"{"type":"data","diff":false,"payload":{}}"#] {
            XCTAssertEqual(try MediaDecoder.decode(Data(value.utf8)), .idle)
        }
        let missing = try MediaDecoder.decode(Data(#"{"bundleIdentifier":"player","artworkData":"!bad!"}"#.utf8))
        XCTAssertEqual(missing.snapshot?.title, "Unknown title")
        XCTAssertNil(missing.snapshot?.artworkData)
        XCTAssertThrowsError(try MediaDecoder.decode(Data(#"{"diff":true,"payload":{"title":"partial"}}"#.utf8)))
        XCTAssertThrowsError(try MediaDecoder.decode(Data("garbage".utf8)))
    }

    func testFramesRespectMenuBarNotchAndScaledCoordinates() {
        let size = CGSize(width: 380, height: 176)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 40, width: 1512, height: 918)
        let normal = IslandLayout.frame(screen: screen, visible: visible, safeTop: 0, size: size)
        XCTAssertEqual(normal.midX, screen.midX)
        XCTAssertEqual(normal.maxY, 950)
        let notch = IslandLayout.frame(screen: screen, visible: screen, safeTop: 38, size: size)
        XCTAssertEqual(notch.maxY, screen.maxY)
        let autoHidden = IslandLayout.frame(screen: screen, visible: screen, safeTop: 0, size: size)
        XCTAssertEqual(autoHidden.maxY, 974)
        let external = screen.offsetBy(dx: -1920, dy: 200)
        let moved = IslandLayout.frame(screen: external, visible: external, safeTop: 0, size: size)
        XCTAssertEqual(moved.midX, external.midX)
        XCTAssertEqual(moved.maxY, external.maxY - 8)
    }

    func testMirroredNotchlessDisplayAttachesToTop() {
        let screen = CGRect(x: -2560, y: 200, width: 2560, height: 1080)
        let visible = CGRect(x: -2560, y: 260, width: 2560, height: 996)
        for expanded in [false, true] {
            let size = IslandLayout.size(expanded: expanded, hasMedia: true)
            let mirrored = IslandLayout.frame(screen: screen, visible: visible, safeTop: 0, size: size, mirrored: true)
            XCTAssertEqual(mirrored.maxY, screen.maxY)
            XCTAssertEqual(mirrored.midX, screen.midX)
            let unmirrored = IslandLayout.frame(screen: screen, visible: visible, safeTop: 0, size: size, mirrored: false)
            XCTAssertEqual(unmirrored.maxY, visible.maxY - 8)
        }
    }

    func testExpansionKeepsTopCenterFixed() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let compact = IslandLayout.frame(screen: screen, visible: screen, safeTop: 0, size: IslandLayout.size(expanded: false, hasMedia: true))
        let expanded = IslandLayout.frame(screen: screen, visible: screen, safeTop: 0, size: IslandLayout.size(expanded: true, hasMedia: true))
        XCTAssertEqual(compact.midX, expanded.midX)
        XCTAssertEqual(compact.maxY, expanded.maxY)
    }

    func testNotchGeometryReservesCameraAndAttachesAtTop() {
        let notch = IslandLayout.notchSize(safeTop: 32,
            leftArea: CGRect(x: 0, y: 950, width: 660, height: 32),
            rightArea: CGRect(x: 852, y: 950, width: 660, height: 32))
        XCTAssertEqual(notch, CGSize(width: 192, height: 32))
        XCTAssertEqual(IslandLayout.notchSize(safeTop: 0, leftArea: nil, rightArea: nil), .zero)
        XCTAssertEqual(IslandLayout.notchSize(safeTop: 32, leftArea: nil, rightArea: nil), .zero)
        let compact = IslandLayout.size(expanded: false, hasMedia: true, notch: notch)
        let expanded = IslandLayout.size(expanded: true, hasMedia: true, notch: notch)
        XCTAssertEqual(compact.width - notch.width, 88)
        XCTAssertEqual(expanded.height - notch.height, 164)
        let screen = CGRect(x: -1512, y: 200, width: 1512, height: 982)
        for size in [compact, expanded, IslandLayout.size(expanded: false, hasMedia: false, notch: notch)] {
            let frame = IslandLayout.frame(screen: screen, visible: screen.insetBy(dx: 0, dy: 32), safeTop: notch.height, size: size)
            XCTAssertEqual(frame.maxY, screen.maxY)
            XCTAssertEqual(frame.midX, screen.midX)
        }
    }

    func testActivityLayoutOnlyExpandsWithIsland() {
        let notch = CGSize(width: 192, height: 32)
        XCTAssertEqual(IslandLayout.activitySize(expanded: false, notch: notch), CGSize(width: 280, height: 34))
        XCTAssertEqual(IslandLayout.activitySize(expanded: true, notch: notch), CGSize(width: 280, height: 96))
        XCTAssertEqual(IslandLayout.activitySize(expanded: false), CGSize(width: 240, height: 40))
    }

    @MainActor func testHoverCancellationAndVisibility() async throws {
        let model = IslandModel(enterDelay: 10_000_000, exitDelay: 30_000_000)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(model.expanded)
        model.hover(false)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(model.expanded)
        model.setEnabled(false)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertFalse(model.expanded)
        model.setEnabled(true)
        model.hover(true)
        model.hover(false)
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertFalse(model.expanded)
    }

    @MainActor func testPlaybackAndUnavailableStatesStopTicks() async throws {
        let model = IslandModel(enterDelay: 0, exitDelay: 0)
        model.receive(.media(NowPlayingSnapshot(title: "Playing", isPlaying: true)))
        XCTAssertFalse(model.shouldTick)
        model.hover(true)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(model.shouldTick)
        model.receive(.media(NowPlayingSnapshot(title: "Playing", isPlaying: false)))
        XCTAssertFalse(model.shouldTick)
        XCTAssertEqual(model.media.snapshot?.title, "Playing")
        model.receive(.unavailable)
        XCTAssertFalse(model.shouldTick)
        XCTAssertNil(model.media.snapshot)
        model.receive(.idle)
        XCTAssertEqual(model.media, .idle)
    }
}
