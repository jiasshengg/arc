import AppKit
import ArcCore
import XCTest
@testable import Arc

final class MenuPocketArrangementTests: XCTestCase {
    @MainActor func testArrangementHidesNativeIslandAndDisableRestoresIt() throws {
        let suite = "ArcArrangementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "showIsland")
        let coordinator = IslandCoordinator(provider: ArrangementProvider(), enabled: true,
                                            copiesScreenshots: false, showsScreenshotPreview: false)
        coordinator.start()
        defer { coordinator.stop() }
        let panel = try XCTUnwrap(NSApp.windows.first { $0.contentView is PocketHostingView })
        XCTAssertTrue(panel.isVisible)
        let menuPocket = MenuPocketController(defaults: defaults, itemPrefix: suite)
        defer { menuPocket.stop() }
        menuPocket.onArrangementChanged = { coordinator.setArrangingMenuPocket($0) }
        menuPocket.setEnabled(true)
        menuPocket.beginArrangement()
        XCTAssertTrue(menuPocket.isArranging)
        XCTAssertFalse(panel.isVisible, "Hide synchronously before the setup alert opens")
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(coordinator.model.enabled)
        XCTAssertTrue(defaults.bool(forKey: "showIsland"))
        // A display/Space refresh must not reopen the panel during arrangement.
        coordinator.setArrangingMenuPocket(true)
        XCTAssertFalse(panel.isVisible)
        menuPocket.setEnabled(false)
        XCTAssertFalse(menuPocket.isArranging)
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(coordinator.model.enabled)
    }

    @MainActor func testStoppingArrangementKeepsDisabledIslandAndPocketFiles() throws {
        let suite = "ArcArrangementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = IslandCoordinator(provider: ArrangementProvider(), enabled: false)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        coordinator.model.pocket.hold([file])
        let menuPocket = MenuPocketController(defaults: defaults, itemPrefix: suite)
        defer { menuPocket.stop() }
        menuPocket.onArrangementChanged = { coordinator.setArrangingMenuPocket($0) }
        menuPocket.beginArrangement()
        XCTAssertFalse(coordinator.model.isArrangingMenuPocket, "Disabled Menu Pocket cannot enter arrangement")
        menuPocket.setEnabled(true)
        menuPocket.beginArrangement()
        XCTAssertTrue(coordinator.model.isArrangingMenuPocket)
        menuPocket.stop()
        XCTAssertFalse(coordinator.model.isArrangingMenuPocket)
        XCTAssertFalse(coordinator.model.enabled)
        XCTAssertFalse(coordinator.model.shouldShowIsland)
        XCTAssertEqual(coordinator.model.pocket.items.count, 1)
    }
}

@MainActor private final class ArrangementProvider: NowPlayingProviding {
    let updates = AsyncStream<MediaState> { $0.finish() }
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) {}
    func seek(to position: TimeInterval) {}
}
