#if DEBUG
import AppKit
import ArcCore
import SwiftUI

/// Development-only fixtures: never replace real media in a normal launch.
@MainActor enum PrototypeChecks {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--menu-pocket-smoke-test") {
            Task { exit(await MenuPocketController.smokeCheck() ? 0 : 1) }
            return true
        }
        if args.contains("--system-smoke-test") {
            Task {
                let monitor = SystemActivityMonitor()
                var hasBattery = false
                monitor.onBattery = { hasBattery = $0 != nil }
                monitor.start()
                try? await Task.sleep(for: .seconds(1))
                print("Battery readable: \(hasBattery)")
                monitor.stop()
                exit(0)
            }
            return true
        }
        if args.contains("--smoke-test") {
            Task {
                let provider = MediaRemoteProvider()
                let started = Date()
                var received: MediaState?
                let reader = Task {
                    for await state in provider.updates {
                        received = state
                        if state.snapshot != nil {
                            print("Active media received in \(Date().timeIntervalSince(started)) seconds")
                        }
                    }
                }
                provider.start()
                try? await Task.sleep(for: .seconds(2))
                reader.cancel()
                provider.stop()
                guard let state = received else {
                    fputs("Media stream timed out\n", stderr)
                    exit(1)
                }
                print("Available: \(state != .unavailable); active session: \(state.snapshot != nil); artwork: \(state.snapshot?.artworkData != nil)")
                exit(state == .unavailable ? 1 : 0)
            }
            return true
        }
        if let index = args.firstIndex(of: "--render-previews"), args.indices.contains(index + 1) {
            let directory = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            Task {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let fixtures: [(String, MediaState, Bool)] = [
                        ("pocket-compact", .idle, false),
                        ("pocket-expanded", .idle, true),
                        ("notch-pocket-expanded", .idle, true),
                        ("notch-pocket-drop", .idle, true),
                        ("notch-pocket-missing", .idle, true),
                        ("idle", .idle, false),
                        ("idle-expanded", .idle, true),
                        ("playing-compact", .media(track()), false),
                        ("playing-expanded", .media(track()), true),
                        ("paused-expanded", .media(track(playing: false)), true),
                        ("long-title", .media(track(title: "A very long song title that should truncate gracefully without displacing playback controls")), true),
                        ("unavailable", .unavailable, true),
                        ("notch-idle", .idle, false),
                        ("notch-compact", .media(track()), false),
                        ("notch-expanded", .media(track()), true),
                        ("notch-paused", .media(track(playing: false)), true),
                        ("screenshot-expanded", .idle, true),
                        ("notch-screenshot", .idle, false),
                        ("notch-charging", .idle, false),
                        ("notch-charging-expanded", .media(track()), true),
                        ("notch-low-battery", .idle, false),
                        ("notch-charged", .idle, false)
                    ]
                    let pocketDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: pocketDirectory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: pocketDirectory) }
                    let pocketFiles = ["Project brief.pdf", "Landscape.png", "Notes.txt", "Archive.zip",
                                       "A very long filename that should truncate gracefully.pdf", "Invoices", "Demo recording.mov"].map {
                        pocketDirectory.appendingPathComponent($0)
                    }
                    for file in pocketFiles { try Data().write(to: file) }
                    for (name, state, expanded) in fixtures {
                        let coordinator = IslandCoordinator(provider: FixtureProvider(), enabled: true)
                        let notch = name.hasPrefix("notch-") ? CGSize(width: 192, height: 32) : .zero
                        coordinator.model.setNotchSize(notch)
                        coordinator.model.receive(state)
                        if expanded {
                            coordinator.model.hover(true)
                            try await Task.sleep(for: .milliseconds(120))
                        }
                        if name.contains("pocket") {
                            coordinator.model.pocket.hold(pocketFiles)
                            if name.hasSuffix("drop") { coordinator.model.setReceivingFiles(true) }
                            if name.hasSuffix("missing") {
                                try FileManager.default.removeItem(at: pocketFiles[0])
                                coordinator.model.pocket.refresh()
                            }
                        }
                        if name.contains("screenshot"),
                           let image = NSImage(systemSymbolName: "rectangle.dashed", accessibilityDescription: nil) {
                            coordinator.showScreenshot(image)
                        }
                        let activity: SystemActivity?
                        switch name {
                        case "notch-charging", "notch-charging-expanded": activity = SystemActivity(kind: .charging, level: 0.42)
                        case "notch-low-battery": activity = SystemActivity(kind: .lowBattery, level: 0.2)
                        case "notch-charged": activity = SystemActivity(kind: .charged, level: 1)
                        default: activity = nil
                        }
                        if let activity { coordinator.model.showActivity(activity) }
                        let size = coordinator.model.showsPocket
                            ? IslandLayout.pocketSize(expanded: expanded, count: coordinator.model.pocket.islandItems.count,
                                                      receiving: coordinator.model.receivingFiles, notch: notch)
                            : coordinator.model.screenshotCopied
                            ? IslandLayout.activitySize(expanded: expanded, notch: notch)
                            : activity == nil
                            ? IslandLayout.size(expanded: expanded, hasMedia: state.snapshot != nil, notch: notch)
                            : IslandLayout.activitySize(expanded: expanded, notch: notch)
                        let view = IslandView(coordinator: coordinator).frame(width: size.width, height: size.height)
                        try snapshot(view, size: size, to: directory.appendingPathComponent(name + ".png"))
                    }
                    try Data().write(to: pocketFiles[0])
                    let pocketModel = IslandModel()
                    pocketModel.pocket.hold(pocketFiles)
                    let pocketWindowSize = CGSize(width: 620, height: 560)
                    let pocketWindow = PocketWindowView(model: pocketModel)
                        .frame(width: pocketWindowSize.width, height: pocketWindowSize.height)
                    try snapshot(pocketWindow, size: pocketWindowSize,
                                 to: directory.appendingPathComponent("pocket-window.png"))
                    print("Rendered \(fixtures.count + 1) prototype states to \(directory.path)")
                    exit(0)
                } catch {
                    fputs("Preview rendering failed: \(error)\n", stderr)
                    exit(1)
                }
            }
            return true
        }
        return false
    }

    private static func track(title: String = "Weightless", playing: Bool = true) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: title, artist: "Arc Studio", album: "After Hours", duration: 243,
                           elapsed: 87, isPlaying: playing)
    }

    private static func snapshot<Content: View>(_ view: Content, size: CGSize, to url: URL) throws {
        // AppKit snapshots include native drag handles that ImageRenderer cannot render.
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: url)
    }
}

@MainActor private final class FixtureProvider: NowPlayingProviding {
    let updates = AsyncStream<MediaState> { $0.finish() }
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) {}
    func seek(to position: TimeInterval) {}
}
#endif
