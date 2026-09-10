import AppKit
import ArcCore
import ServiceManagement
import SwiftUI

@main struct ArcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Arc", systemImage: "capsule.lefthalf.filled") {
            ArcMenu(coordinator: delegate.coordinator)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = IslandCoordinator(
        provider: MediaRemoteProvider(),
        enabled: UserDefaults.standard.object(forKey: "showIsland") as? Bool ?? true
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if PrototypeChecks.runIfRequested() { return }
        #endif
        coordinator.start()
    }
    func applicationWillTerminate(_ notification: Notification) { coordinator.stop() }
}

private struct ArcMenu: View {
    let coordinator: IslandCoordinator
    @AppStorage("showIsland") private var showIsland = true
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @State private var brightnessKeyAccess = CGPreflightListenEventAccess()

    var body: some View {
        Text("Arc · Music, within reach")
            .onAppear {
                brightnessKeyAccess = CGPreflightListenEventAccess()
                coordinator.refreshBrightnessKeyAccess()
            }
        Divider()
        Toggle("Show island", isOn: $showIsland)
            .onChange(of: showIsland) { _, enabled in coordinator.setEnabled(enabled) }
        if !brightnessKeyAccess {
            Button("Enable brightness key indicator…") { coordinator.enableBrightnessKeys() }
            Text("Requires Input Monitoring; other indicators work without it.")
        }
        Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
        if let loginMessage { Text(loginMessage) }
        if SMAppService.mainApp.status == .requiresApproval {
            Button("Allow Arc in Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
        Divider()
        if coordinator.model.media == .unavailable {
            Text("Media integration unavailable")
            Button("Retry media connection") { coordinator.retry() }
        } else if let track = coordinator.model.media.snapshot {
            Text(track.isPlaying ? "Playing: \(track.title)" : "Paused: \(track.title)")
            Button(track.isPlaying ? "Pause" : "Play") { coordinator.send(.togglePlayback) }
            Button("Next track") { coordinator.send(.next) }
        } else { Text("No media playing") }
        Divider()
        if let battery = coordinator.battery {
            Text("Battery: \(battery.percent)% · \(battery.charging ? "Charging" : (battery.pluggedIn ? "Plugged in" : "On battery"))")
            Divider()
        }
        Button("Quit Arc") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Approval needed in System Settings" : nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = "Couldn’t update login item: \(error.localizedDescription)"
        }
    }
}
