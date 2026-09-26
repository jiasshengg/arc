import AppKit
import ArcCore
import ServiceManagement
import SwiftUI

@main struct ArcApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            ArcMenu(coordinator: delegate.coordinator, menuPocket: delegate.menuPocket)
        } label: {
            Image(nsImage: Self.menuBarIcon)
                .accessibilityLabel("Arc")
        }
    }

    private static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let orbit = NSBezierPath()
            orbit.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 6.2,
                            startAngle: 65, endAngle: 355, clockwise: false)
            orbit.lineWidth = 1.8
            orbit.lineCapStyle = .round
            NSColor.black.setStroke()
            orbit.stroke()
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: 12.8, y: 11.3, width: 3.2, height: 3.2)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let menuPocket = MenuPocketController()
    let coordinator = IslandCoordinator(
        provider: MediaRemoteProvider(),
        enabled: UserDefaults.standard.object(forKey: "showIsland") as? Bool ?? true
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if PrototypeChecks.runIfRequested() { return }
        #endif
        coordinator.menuPocketControlFrame = { [weak menuPocket] in menuPocket?.chevronFrame }
        coordinator.start()
        menuPocket.start()
    }
    func applicationWillTerminate(_ notification: Notification) {
        menuPocket.stop()
        coordinator.stop()
    }
}

private struct ArcMenu: View {
    let coordinator: IslandCoordinator
    @ObservedObject var menuPocket: MenuPocketController
    @AppStorage("showIsland") private var showIsland = true
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?

    var body: some View {
        Text("Arc · Music Within Reach")
        Divider()
        Toggle("Show Island", isOn: $showIsland)
            .onChange(of: showIsland) { _, enabled in coordinator.setEnabled(enabled) }
        Toggle("Launch At Login", isOn: Binding(get: { loginEnabled }, set: setLogin))
        if let loginMessage { Text(loginMessage) }
        if SMAppService.mainApp.status == .requiresApproval {
            Button("Allow Arc In Login Items…") { SMAppService.openSystemSettingsLoginItems() }
        }
        Divider()
        if coordinator.model.media == .unavailable {
            Text("Can’t Connect To Your Music")
            Button("Try Connecting Again") { coordinator.retry() }
        } else if let track = coordinator.model.media.snapshot {
            Text(track.isPlaying ? "Playing: \(track.title)" : "Paused: \(track.title)")
            Button(track.isPlaying ? "Pause" : "Play") { coordinator.send(.togglePlayback) }
            Button("Next Track") { coordinator.send(.next) }
        } else { Text("Nothing Playing") }
        Divider()
        if let battery = coordinator.battery {
            Text("Battery: \(battery.percent)% · \(battery.charging ? "Charging" : (battery.pluggedIn ? "Plugged In" : "On Battery"))")
            Divider()
        }
        Toggle("Menu Pocket", isOn: Binding(get: { menuPocket.isEnabled }, set: menuPocket.setEnabled))
        if menuPocket.isEnabled {
            Button(menuPocket.isExpanded ? "Hide Menu Icons" : "Show Menu Icons") { menuPocket.toggle() }
            Button("Arrange Menu Pocket…") { menuPocket.showSetup() }
        }
        Divider()
        Text("Pocket: \(coordinator.model.pocket.items.count) items")
        Button("Open Pocket…") { coordinator.showPocket() }
        Button("Clear") { coordinator.model.pocket.clear() }
            .disabled(coordinator.model.pocket.items.isEmpty)
        Divider()
        Button("Quit Arc") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }

    private func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = SMAppService.mainApp.status == .requiresApproval ? "Allow Arc in System Settings to start it when you log in." : nil
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = "Couldn’t change Launch At Login: \(error.localizedDescription)"
        }
    }
}
