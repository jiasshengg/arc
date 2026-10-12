import XCTest
import AppKit
import ArcCore
import Carbon
@testable import Arc

final class KeyboardShortcutTests: XCTestCase {
    @MainActor func testCustomBindingPersistenceValidationAndReset() throws {
        let suite = "ArcShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = IslandCoordinator(provider: ShortcutProvider(), enabled: true)
        let shortcuts = KeyboardShortcutController(coordinator: coordinator, defaults: defaults)
        defer { shortcuts.stop() }
        let custom = KeyboardShortcutController.Shortcut(keyCode: 40, modifiers: UInt32(controlKey | optionKey | shiftKey), key: "K")
        shortcuts.setShortcut(custom, for: .openPocket)
        XCTAssertEqual(shortcuts.binding(for: .openPocket).label, "⌃⌥⇧K")
        let restored = KeyboardShortcutController(coordinator: coordinator, defaults: defaults)
        XCTAssertEqual(restored.binding(for: .openPocket), custom)
        shortcuts.setShortcut(custom, for: .toggleIsland)
        XCTAssertNotNil(shortcuts.errorMessage)
        XCTAssertEqual(shortcuts.binding(for: .toggleIsland), KeyboardShortcutController.Action.toggleIsland.defaultShortcut)
        shortcuts.setShortcut(.init(keyCode: 0, modifiers: UInt32(shiftKey), key: "A"), for: .openPocket)
        XCTAssertNotNil(shortcuts.errorMessage)
        XCTAssertEqual(shortcuts.binding(for: .openPocket), custom)
        defaults.set("untouched", forKey: "unrelatedPreference")
        shortcuts.reset()
        XCTAssertEqual(shortcuts.binding(for: .openPocket), KeyboardShortcutController.Action.openPocket.defaultShortcut)
        XCTAssertNil(defaults.data(forKey: "shortcutOpenPocketBinding"))
        XCTAssertFalse(defaults.bool(forKey: "shortcutOpenPocket"))
        XCTAssertFalse(shortcuts.openPocketEnabled)
        XCTAssertFalse(shortcuts.toggleIslandEnabled)
        XCTAssertNil(shortcuts.errorMessage)
        XCTAssertEqual(defaults.string(forKey: "unrelatedPreference"), "untouched")
    }

    @MainActor func testChangingEnabledShortcutPreservesOldBindingOnConflict() throws {
        let suite = "ArcShortcutTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let coordinator = IslandCoordinator(provider: ShortcutProvider(), enabled: true)
        let shortcuts = KeyboardShortcutController(coordinator: coordinator, defaults: defaults)
        defer { shortcuts.stop() }
        let modifiers = UInt32(controlKey | optionKey | shiftKey)
        let custom = KeyboardShortcutController.Shortcut(keyCode: 40, modifiers: modifiers, key: "K")
        shortcuts.setShortcut(custom, for: .toggleIsland)
        shortcuts.setEnabled(true, for: .toggleIsland)
        guard shortcuts.toggleIslandEnabled else { throw XCTSkip("Custom shortcut already in use") }
        var reserved: EventHotKeyRef?
        let status = RegisterEventHotKey(38, modifiers, EventHotKeyID(signature: 0x54657374, id: 2),
                                         GetApplicationEventTarget(), 0, &reserved)
        guard status == noErr, let reserved else { throw XCTSkip("Conflict test shortcut already in use") }
        defer { UnregisterEventHotKey(reserved) }
        shortcuts.setShortcut(.init(keyCode: 38, modifiers: modifiers, key: "J"), for: .toggleIsland)
        XCTAssertNotNil(shortcuts.errorMessage)
        XCTAssertEqual(shortcuts.binding(for: .toggleIsland), custom)
        XCTAssertTrue(shortcuts.toggleIslandEnabled)
        shortcuts.perform(.toggleIsland)
        XCTAssertFalse(coordinator.model.enabled)
        shortcuts.beginRecording()
        shortcuts.perform(.toggleIsland)
        XCTAssertFalse(coordinator.model.enabled)
        shortcuts.endRecording()
        XCTAssertTrue(shortcuts.toggleIslandEnabled)
        shortcuts.perform(.toggleIsland)
        XCTAssertTrue(coordinator.model.enabled)
        let replacement = KeyboardShortcutController.Shortcut(keyCode: 37, modifiers: modifiers, key: "L")
        shortcuts.setShortcut(replacement, for: .toggleIsland)
        XCTAssertNil(shortcuts.errorMessage)
        XCTAssertEqual(shortcuts.binding(for: .toggleIsland), replacement)
        shortcuts.perform(.toggleIsland)
        XCTAssertFalse(coordinator.model.enabled)
    }

    @MainActor func testRecorderCapturesCommandKeysAndRejectsBareKeys() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.command, .shift],
            timestamp: 0, windowNumber: 0, context: nil, characters: "K", charactersIgnoringModifiers: "K",
            isARepeat: false, keyCode: 40))
        XCTAssertEqual(KeyboardShortcutController.Shortcut(event: event)?.label, "⇧⌘K")
        let bare = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
            isARepeat: false, keyCode: 40))
        XCTAssertNil(KeyboardShortcutController.Shortcut(event: bare))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ShortcutRecorder.CaptureView()
        window.contentView = view
        window.makeFirstResponder(view)
        var captured: UInt16?
        view.record = { captured = $0.keyCode }
        XCTAssertTrue(view.performKeyEquivalent(with: event))
        XCTAssertEqual(captured, 40)
        var cancelled = false
        view.cancel = { cancelled = true }
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false, keyCode: 53))
        view.keyDown(with: escape)
        XCTAssertTrue(cancelled)
    }

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
