#if DEBUG
import AppKit
import ArcCore
import SwiftUI

/// Development-only fixtures: never replace real media in a normal launch.
@MainActor enum PrototypeChecks {
    static func runIfRequested() -> Bool {
        let args = ProcessInfo.processInfo.arguments
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
                        ("notch-charging", .idle, false),
                        ("notch-low-battery", .idle, false),
                        ("notch-charged", .idle, false)
                    ]
                    for (name, state, expanded) in fixtures {
                        let coordinator = IslandCoordinator(provider: FixtureProvider(), enabled: true)
                        let notch = name.hasPrefix("notch-") ? CGSize(width: 192, height: 32) : .zero
                        coordinator.model.setNotchSize(notch)
                        coordinator.model.receive(state)
                        if expanded {
                            coordinator.model.hover(true)
                            try await Task.sleep(for: .milliseconds(120))
                        }
                        let activity: SystemActivity?
                        switch name {
                        case "notch-charging": activity = SystemActivity(kind: .charging, level: 0.42)
                        case "notch-low-battery": activity = SystemActivity(kind: .lowBattery, level: 0.2)
                        case "notch-charged": activity = SystemActivity(kind: .charged, level: 1)
                        default: activity = nil
                        }
                        if let activity { coordinator.model.showActivity(activity) }
                        let size = activity == nil
                            ? IslandLayout.size(expanded: expanded, hasMedia: state.snapshot != nil, notch: notch)
                            : CGSize(width: max(280, notch.width + 88), height: notch.height + 64)
                        let view = IslandView(coordinator: coordinator).frame(width: size.width, height: size.height)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        guard let image = renderer.cgImage,
                              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                            throw CocoaError(.fileWriteUnknown)
                        }
                        try png.write(to: directory.appendingPathComponent(name + ".png"))
                    }
                    print("Rendered \(fixtures.count) prototype states to \(directory.path)")
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
}

@MainActor private final class FixtureProvider: NowPlayingProviding {
    let updates = AsyncStream<MediaState> { $0.finish() }
    func start() {}
    func stop() {}
    func send(_ command: MediaCommand) {}
}
#endif
