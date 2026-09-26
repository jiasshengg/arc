import AppKit
import XCTest
import ArcCore
@testable import Arc

final class PerformanceTests: XCTestCase {
    @MainActor func testPlaybackAnimationsStopAndResume() throws {
        let view = PlaybackBarsView()
        let bars = try XCTUnwrap(view.layer?.sublayers)
        XCTAssertEqual(bars.count, 4)
        view.update(playing: true, animating: true)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "playback") != nil })
        view.update(playing: true, animating: false)
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
        view.update(playing: true, animating: true)
        XCTAssertTrue(bars.allSatisfy { $0.animation(forKey: "playback") != nil })
        view.update(playing: false, animating: true)
        XCTAssertTrue(bars.allSatisfy { $0.animationKeys()?.isEmpty != false })
    }

    @MainActor func testArtworkReusedUntilBytesChangeOrDisappear() async throws {
        let coordinator = IslandCoordinator(provider: PerformanceProvider(), enabled: true)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.setColor(.red, atX: 0, y: 0)
        let firstData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        await coordinator.receive(.media(NowPlayingSnapshot(title: "First", artworkData: firstData)))
        let firstImage = try XCTUnwrap(coordinator.artwork)
        await coordinator.receive(.media(NowPlayingSnapshot(title: "Updated", artworkData: firstData)))
        XCTAssertTrue(coordinator.artwork === firstImage)
        XCTAssertEqual(coordinator.model.media.snapshot?.title, "Updated")
        let secondBitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 3, pixelsHigh: 3,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        secondBitmap.setColor(.blue, atX: 0, y: 0)
        let secondData = try XCTUnwrap(secondBitmap.representation(using: .png, properties: [:]))
        XCTAssertNotEqual(firstData, secondData)
        await coordinator.receive(.media(NowPlayingSnapshot(title: "Second", artworkData: secondData)))
        XCTAssertNotNil(coordinator.artwork)
        XCTAssertFalse(coordinator.artwork === firstImage)
        await coordinator.receive(.idle)
        XCTAssertNil(coordinator.artwork)
    }
}

@MainActor private final class PerformanceProvider: NowPlayingProviding {
    let updates = AsyncStream<MediaState> { $0.finish() }
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) {}
    func seek(to position: TimeInterval) {}
}
