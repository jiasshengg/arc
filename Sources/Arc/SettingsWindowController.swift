import AppKit
import ServiceManagement
import SwiftUI

@MainActor final class SettingsWindowController: NSWindowController {
    static let contentSize = NSSize(width: 440, height: 540)

    init(coordinator: IslandCoordinator, menuPocket: MenuPocketController) {
        let view = SettingsView(coordinator: coordinator, menuPocket: menuPocket)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Arc Settings"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        super.init(window: window)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let coordinator: IslandCoordinator
    @ObservedObject var menuPocket: MenuPocketController
    @AppStorage("showBatteryAlerts") private var showBatteryAlerts = true
    @AppStorage("hideWhenIdle") private var hideWhenIdle = false
    @AppStorage("pausedMusicDelay") private var pausedMusicDelay = 0.0
    @AppStorage("expandOnHover") private var expandOnHover = true
    @AppStorage("hoverDelay") private var hoverDelay = 0.1
    @AppStorage("showScreenshotPreview") private var showScreenshotPreview = true
    @AppStorage("islandDisplayID") private var islandDisplayID = ""
    @State private var screens = NSScreen.screens
    @AppStorage("showIsland") private var showIsland = true
    @AppStorage("copyScreenshots") private var copyScreenshots = true
    @AppStorage("showBrowserMedia") private var showBrowserMedia = true
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage: String?
    @State private var showsBrowserMediaInfo = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Show Island", isOn: $showIsland)
                    .onChange(of: showIsland) { _, enabled in coordinator.setEnabled(enabled) }
                Picker("Display", selection: $islandDisplayID) {
                    Text("Automatic").tag("")
                    ForEach(screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(IslandWindowController.displayIdentifier(screen))
                    }
                    if !islandDisplayID.isEmpty && !screens.contains(where: { IslandWindowController.displayIdentifier($0) == islandDisplayID }) {
                        Text("Disconnected Display").tag(islandDisplayID)
                    }
                }
                .onChange(of: islandDisplayID) { _, id in coordinator.model.preferredDisplayID = id }
                Toggle("Hide When Idle", isOn: $hideWhenIdle)
                    .onChange(of: hideWhenIdle) { _, hide in coordinator.model.hideWhenIdle = hide }
                Toggle("Expand On Hover", isOn: $expandOnHover)
                    .onChange(of: expandOnHover) { _, expands in coordinator.model.setExpandsOnHover(expands) }
                Picker("Hover Delay", selection: $hoverDelay) {
                    Text("Fast").tag(0.1)
                    Text("Normal").tag(0.3)
                    Text("Slow").tag(0.6)
                }
                .disabled(!expandOnHover)
                .onChange(of: hoverDelay) { _, delay in coordinator.model.setHoverDelay(delay) }
                if !expandOnHover { Text("Click the island to expand it.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Show Battery Alerts", isOn: $showBatteryAlerts)
                    .onChange(of: showBatteryAlerts) { _, shows in coordinator.model.setShowsBatteryAlerts(shows) }
                Toggle("Launch At Login", isOn: Binding(get: { loginEnabled }, set: setLogin))
                if let loginMessage { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                if SMAppService.mainApp.status == .requiresApproval {
                    Button("Allow Arc In Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                }
            }
            Section {
                Toggle(isOn: $showBrowserMedia) {
                    HStack(spacing: 6) {
                        Text("Show Media From Browsers")
                        Button { showsBrowserMediaInfo = true } label: { Image(systemName: "info.circle") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("About Show Media From Browsers")
                            .popover(isPresented: $showsBrowserMediaInfo, arrowEdge: .bottom) {
                                Text("While a browser is playing, Arc can’t show a paused music app such as Spotify or Apple Music instead, so the island stays empty until you play your music again.")
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(width: 260)
                                    .padding()
                            }
                    }
                }
                    .onChange(of: showBrowserMedia) { _, enabled in
                        Task { await coordinator.setShowsBrowserMedia(enabled) }
                    }
                Picker("Hide Paused Music After", selection: $pausedMusicDelay) {
                    Text("Keep Visible").tag(0.0)
                    Text("30 Seconds").tag(30.0)
                    Text("1 Minute").tag(60.0)
                    Text("5 Minutes").tag(300.0)
                }
                .onChange(of: pausedMusicDelay) { _, delay in coordinator.model.setPausedMusicDelay(delay) }
            } header: {
                Text("Music")
            } footer: {
                Text("Turn off to ignore music and videos playing in browsers such as Safari or Chrome.")
            }
            Section {
                Toggle("Copy Screenshots To Clipboard", isOn: $copyScreenshots)
                    .onChange(of: copyScreenshots) { _, enabled in coordinator.setCopiesScreenshots(enabled) }
                Toggle("Show Screenshot Preview", isOn: $showScreenshotPreview)
                    .onChange(of: showScreenshotPreview) { _, shows in coordinator.setShowsScreenshotPreview(shows) }
            } header: {
                Text("Screenshots")
            } footer: {
                Text("Copy saved screenshots, show a brief island preview, or use both.")
            }
            Section {
                Toggle("Menu Pocket", isOn: Binding(get: { menuPocket.isEnabled }, set: menuPocket.setEnabled))
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("Keep less important menu bar icons behind an arrow.")
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindowController.contentSize.width,
               height: SettingsWindowController.contentSize.height)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screens = NSScreen.screens
        }
        // Login approval is granted in System Settings; refresh when the user returns.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginEnabled = SMAppService.mainApp.status == .enabled
        }
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
