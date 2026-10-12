import AppKit
import ArcCore
import Carbon

@MainActor final class KeyboardShortcutController: ObservableObject {
    enum Action: UInt32, CaseIterable {
        case openPocket = 1
        case toggleIsland = 2

        var keyCode: UInt32 { self == .openPocket ? 35 : 34 }
        var preference: String { self == .openPocket ? "shortcutOpenPocket" : "shortcutToggleIsland" }
    }

    @Published private(set) var openPocketEnabled = false
    @Published private(set) var toggleIslandEnabled = false
    @Published private(set) var errorMessage: String?
    private var hotKeys: [Action: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let coordinator: IslandCoordinator
    private let defaults: UserDefaults
    private static let signature: OSType = 0x41726353 // ArcS

    init(coordinator: IslandCoordinator, defaults: UserDefaults = .standard) {
        self.coordinator = coordinator
        self.defaults = defaults
    }

    func start() {
        for action in Action.allCases where defaults.bool(forKey: action.preference) {
            setEnabled(true, for: action)
        }
    }

    func setEnabled(_ enabled: Bool, for action: Action) {
        errorMessage = nil
        if let hotKey = hotKeys.removeValue(forKey: action) { UnregisterEventHotKey(hotKey) }
        var registered = false
        if enabled {
            var status = installHandler()
            if status == noErr {
                var hotKey: EventHotKeyRef?
                status = RegisterEventHotKey(action.keyCode, UInt32(controlKey | optionKey),
                                            EventHotKeyID(signature: Self.signature, id: action.rawValue),
                                            GetApplicationEventTarget(), 0, &hotKey)
                if status == noErr, let hotKey {
                    hotKeys[action] = hotKey
                    registered = true
                }
            }
            if !registered {
                errorMessage = "Couldn’t enable the shortcut. Another app may already use it (error \(status))."
            }
        }
        defaults.set(registered, forKey: action.preference)
        if action == .openPocket { openPocketEnabled = registered }
        else { toggleIslandEnabled = registered }
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
