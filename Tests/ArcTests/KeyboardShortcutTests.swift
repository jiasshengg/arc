import XCTest
import ArcCore
import Carbon
@testable import Arc

final class KeyboardShortcutTests: XCTestCase {
    @MainActor func testStartupKeepsConflictErrorWhenOtherShortcutSucceeds() throws {
        var reserved: EventHotKeyRef?
        let status = RegisterEventHotKey(35, UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x54657374, id: 1), GetApplicationEventTarget(), 0, &reserved)
        guard status == noErr, let reserved else { throw XCTSkip("Pocket shortcut already in use") }
        defer { UnregisterEventHotKey(reserved) }
        let suite = "ArcShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "shortcutOpenPocket")
        defaults.set(true, forKey: "shortcutToggleIsland")
        let coordinator = IslandCoordinator(provider: ShortcutProvider(), enabled: true)
        let shortcuts = KeyboardShortcutController(coordinator: coordinator, defaults: defaults)
        defer { shortcuts.stop() }
        shortcuts.start()
        guard shortcuts.toggleIslandEnabled else { throw XCTSkip("Island shortcut already in use") }
        XCTAssertFalse(shortcuts.openPocketEnabled)
        XCTAssertTrue(shortcuts.errorMessage?.contains("Open Pocket") == true)
    }

    @MainActor func testGlobalShortcutRegistrationPersistenceAndToggle() async throws {
        let suite = "ArcShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = IslandCoordinator(provider: ShortcutProvider(), enabled: true)
        let shortcuts = KeyboardShortcutController(coordinator: coordinator, defaults: defaults)
        defer { shortcuts.stop() }
        shortcuts.start()
        XCTAssertFalse(shortcuts.toggleIslandEnabled)
        shortcuts.perform(.toggleIsland)
        XCTAssertTrue(coordinator.model.enabled)
        shortcuts.setEnabled(true, for: .toggleIsland)
        guard shortcuts.toggleIslandEnabled else {
            XCTAssertNotNil(shortcuts.errorMessage)
            XCTAssertFalse(defaults.bool(forKey: "shortcutToggleIsland"))
            throw XCTSkip("Global shortcut is unavailable in this desktop session")
        }
        XCTAssertNil(shortcuts.errorMessage)
        XCTAssertTrue(defaults.bool(forKey: "shortcutToggleIsland"))
        var event: EventRef?
        XCTAssertEqual(CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed),
                                   GetCurrentEventTime(), 0, &event), noErr)
        let hotKeyEvent = try XCTUnwrap(event)
        defer { ReleaseEvent(hotKeyEvent) }
        var id = EventHotKeyID(signature: 0x41726353, id: KeyboardShortcutController.Action.toggleIsland.rawValue)
        XCTAssertEqual(SetEventParameter(hotKeyEvent, EventParamName(kEventParamDirectObject),
                                         EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id), noErr)
        XCTAssertEqual(SendEventToEventTarget(hotKeyEvent, GetApplicationEventTarget()), noErr)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertFalse(coordinator.model.enabled)
        XCTAssertFalse(defaults.bool(forKey: "showIsland"))
        shortcuts.perform(.toggleIsland)
        XCTAssertTrue(coordinator.model.enabled)
        XCTAssertTrue(defaults.bool(forKey: "showIsland"))
        shortcuts.stop()
        XCTAssertFalse(shortcuts.toggleIslandEnabled)
        XCTAssertTrue(defaults.bool(forKey: "shortcutToggleIsland"))
        shortcuts.start()
        XCTAssertTrue(shortcuts.toggleIslandEnabled)
        shortcuts.setEnabled(false, for: .toggleIsland)
        XCTAssertFalse(defaults.bool(forKey: "shortcutToggleIsland"))
        shortcuts.perform(.toggleIsland)
        XCTAssertTrue(coordinator.model.enabled)
    }
}

@MainActor private final class ShortcutProvider: NowPlayingProviding {
    let updates = AsyncStream<MediaState> { $0.finish() }
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) {}
    func seek(to position: TimeInterval) {}
}
