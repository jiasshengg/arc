import AppKit
import Carbon

@MainActor final class KeyboardShortcutController: ObservableObject {
    enum Action: UInt32, CaseIterable {
        case openPocket = 1
        case toggleIsland = 2

        var keyCode: UInt32 { self == .openPocket ? 35 : 34 }
        var title: String { self == .openPocket ? "Open Pocket" : "Show Or Hide Island" }
        var defaultShortcut: Shortcut { Shortcut(keyCode: keyCode, modifiers: UInt32(controlKey | optionKey), key: self == .openPocket ? "P" : "I") }
        var preference: String { self == .openPocket ? "shortcutOpenPocket" : "shortcutToggleIsland" }
    }

    struct Shortcut: Codable, Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let key: String

        var isValid: Bool {
            let allowed = UInt32(cmdKey | controlKey | optionKey | shiftKey)
            return keyCode < 128 && modifiers & ~allowed == 0
                && modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
                && key.count == 1 && !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var label: String {
            var result = ""
            if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
            if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
            if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
            if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
            return result + key
        }

        init(keyCode: UInt32, modifiers: UInt32, key: String) {
            self.keyCode = keyCode
            self.modifiers = modifiers
            self.key = key
        }

        init?(event: NSEvent) {
            guard let key = event.charactersIgnoringModifiers?.uppercased(), key.count == 1,
                  key.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }) else { return nil }
            var modifiers: UInt32 = 0
            if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
            if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
            if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
            if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
            self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key)
            guard isValid else { return nil }
        }
    }

    @Published private(set) var bindings: [Action: Shortcut] = [:]
    @Published private(set) var openPocketEnabled = false
    @Published private(set) var toggleIslandEnabled = false
    @Published private(set) var errorMessage: String?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private var isRecording = false
    private var handler: EventHandlerRef?
    private let coordinator: IslandCoordinator
    private let defaults: UserDefaults
    private static let signature: OSType = 0x41726353 // ArcS

    init(coordinator: IslandCoordinator, defaults: UserDefaults = .standard) {
        self.coordinator = coordinator
        self.defaults = defaults
        for action in Action.allCases {
            let stored = defaults.data(forKey: action.preference + "Binding")
                .flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
            bindings[action] = stored?.isValid == true ? stored : action.defaultShortcut
        }
        if let pocket = bindings[.openPocket], let island = bindings[.toggleIsland],
           pocket.keyCode == island.keyCode && pocket.modifiers == island.modifiers {
            bindings[.openPocket] = Action.openPocket.defaultShortcut
            bindings[.toggleIsland] = Action.toggleIsland.defaultShortcut
        }
    }

    func start() {
        var errors: [String] = []
        for action in Action.allCases where defaults.bool(forKey: action.preference) {
            setEnabled(true, for: action)
            if let errorMessage { errors.append(errorMessage) }
        }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func setEnabled(_ enabled: Bool, for action: Action) {
        errorMessage = nil
        if let hotKey = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(hotKey) }
        var registered = false
        if enabled {
            var status = installHandler()
            if status == noErr {
                var hotKey: EventHotKeyRef?
                let shortcut = binding(for: action)
                status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                                            EventHotKeyID(signature: Self.signature, id: action.rawValue),
                                            GetApplicationEventTarget(), 0, &hotKey)
                if status == noErr, let hotKey {
                    hotKeys[action] = hotKey
                    registered = true
                }
            }
            if !registered {
                let name = action.title
                errorMessage = "Couldn’t enable \(name). Another app may already use it (error \(status))."
            }
        }
        defaults.set(registered, forKey: action.preference)
        if action == .openPocket { openPocketEnabled = registered }
        else { toggleIslandEnabled = registered }
    }

    func binding(for action: Action) -> Shortcut { bindings[action] ?? action.defaultShortcut }

    func setShortcut(_ shortcut: Shortcut, for action: Action) {
        errorMessage = nil
        guard shortcut.isValid else {
            errorMessage = "Use a letter, number, or punctuation key with Command, Control, or Option."
            return
        }
        guard !Action.allCases.contains(where: {
            $0 != action && binding(for: $0).keyCode == shortcut.keyCode && binding(for: $0).modifiers == shortcut.modifiers
        }) else {
            errorMessage = "Arc’s other shortcut already uses this combination."
            return
        }
        let old = binding(for: action)
        guard old.keyCode != shortcut.keyCode || old.modifiers != shortcut.modifiers else { return }
        if hotKeys[action] != nil {
            var replacement: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
                EventHotKeyID(signature: Self.signature, id: action.rawValue),
                GetApplicationEventTarget(), 0, &replacement)
            guard status == noErr, let replacement else {
                errorMessage = "Couldn’t change \(action.title). Another app may already use it (error \(status))."
                return
            }
            if let oldKey = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(oldKey) }
            hotKeys[action] = replacement
        }
        bindings[action] = shortcut
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: action.preference + "Binding")
    }

    // Release Arc's hot keys while the recorder is first responder.
    func beginRecording() {
        isRecording = true
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
    }

    func endRecording() {
        guard isRecording else { return }
        isRecording = false
        let pocket = openPocketEnabled
        let island = toggleIslandEnabled
        var errors: [String] = []
        for (action, enabled) in [(Action.openPocket, pocket), (.toggleIsland, island)] where enabled {
            setEnabled(true, for: action)
            if let errorMessage { errors.append(errorMessage) }
        }
        errorMessage = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func reset() {
        isRecording = false
        for action in Action.allCases {
            setEnabled(false, for: action)
            defaults.removeObject(forKey: action.preference + "Binding")
            bindings[action] = action.defaultShortcut
        }
    }

    private func installHandler() -> OSStatus {
        guard handler == nil else { return noErr }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        return InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr, id.signature == 0x41726353,
                  let action = Action(rawValue: id.id) else { return OSStatus(eventNotHandledErr) }
            let controller = Unmanaged<KeyboardShortcutController>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor [weak controller] in controller?.perform(action) }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func perform(_ action: Action) {
        guard hotKeys[action] != nil else { return }
        switch action {
        case .openPocket: coordinator.showPocket()
        case .toggleIsland:
            let enabled = !coordinator.model.enabled
            defaults.set(enabled, forKey: "showIsland")
            coordinator.setEnabled(enabled)
        }
    }

    func stop() {
        hotKeys.values.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
        openPocketEnabled = false
        toggleIslandEnabled = false
    }
}
