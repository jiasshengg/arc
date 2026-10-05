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
            } header: {
                Text("Music")
            } footer: {
                Text("Turn off to ignore music and videos playing in browsers such as Safari or Chrome.")
            }
            Section {
                Toggle("Copy Screenshots To Clipboard", isOn: $copyScreenshots)
                    .onChange(of: copyScreenshots) { _, enabled in coordinator.setCopiesScreenshots(enabled) }
            } header: {
                Text("Screenshots")
            } footer: {
                Text("New screenshots saved as files are copied so you can paste them right away.")
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
