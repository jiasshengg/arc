import Foundation

public struct NowPlayingSnapshot: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let album: String
    public let sourceBundleIdentifier: String
    public let parentBundleIdentifier: String
    public let artworkData: Data?
    public let duration: TimeInterval?
    public let elapsed: TimeInterval
    public let observedAt: Date
    public let isPlaying: Bool
    public let playbackRate: Double

    public init(title: String, artist: String = "", album: String = "",
                sourceBundleIdentifier: String = "", parentBundleIdentifier: String = "",
                artworkData: Data? = nil, duration: TimeInterval? = nil, elapsed: TimeInterval = 0,
                observedAt: Date = Date(), isPlaying: Bool = false, playbackRate: Double = 1) {
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown title" : title
        self.artist = artist
        self.album = album
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.parentBundleIdentifier = parentBundleIdentifier
        self.artworkData = artworkData
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.elapsed = elapsed.isFinite ? max(0, elapsed) : 0
        self.observedAt = observedAt.timeIntervalSince1970.isFinite ? observedAt : Date()
        self.isPlaying = isPlaying
        self.playbackRate = playbackRate.isFinite && playbackRate >= 0 ? playbackRate : 1
    }

    public func position(at date: Date) -> TimeInterval {
        let delta = max(0, date.timeIntervalSince(observedAt))
        let position = elapsed + (isPlaying ? delta * playbackRate : 0)
        return min(duration ?? .greatestFiniteMagnitude, position)
    }

    public func progress(at date: Date) -> Double {
        guard let duration else { return 0 }
        return min(1, max(0, position(at: date) / duration))
    }

    public func seeking(to position: TimeInterval, at date: Date = Date()) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            title: title, artist: artist, album: album,
            sourceBundleIdentifier: sourceBundleIdentifier, parentBundleIdentifier: parentBundleIdentifier,
            artworkData: artworkData,
            duration: duration, elapsed: min(duration ?? .greatestFiniteMagnitude, max(0, position)),
            observedAt: date, isPlaying: isPlaying, playbackRate: playbackRate
        )
    }

    /// The app to open for this media: the parent app when a helper process is playing.
    public var appBundleIdentifier: String {
        parentBundleIdentifier.isEmpty ? sourceBundleIdentifier : parentBundleIdentifier
    }

    /// Some browsers play media in a helper process, so the parent app is checked too.
    public var isFromBrowser: Bool {
        [sourceBundleIdentifier, parentBundleIdentifier].contains { identifier in
            let identifier = identifier.lowercased()
            return Self.browserBundleIdentifiers.contains { identifier == $0 || identifier.hasPrefix($0 + ".") }
        }
    }

    /// Lowercased; a prefix match also covers beta channels and helper processes.
    private static let browserBundleIdentifiers = [
        "com.apple.safari", "com.apple.safaritechnologypreview",
        "com.google.chrome", "org.chromium.chromium",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
        "com.microsoft.edgemac", "com.brave.browser",
        "company.thebrowser.browser", "company.thebrowser.dia",
        "com.operasoftware.opera", "com.operasoftware.operagx",
        "com.vivaldi.vivaldi", "app.zen-browser.zen",
        "com.kagi.kagimacos", "com.duckduckgo.macos.browser"
    ]
}

public enum MediaState: Equatable, Sendable {
    case idle
    case media(NowPlayingSnapshot)
    case unavailable

    public var snapshot: NowPlayingSnapshot? {
        if case .media(let snapshot) = self { return snapshot }
        return nil
    }
}

public enum MediaCommand: String, Sendable {
    case previous = "5", togglePlayback = "2", next = "4"
}

@MainActor public protocol NowPlayingProviding: AnyObject {
    var updates: AsyncStream<MediaState> { get }
    func start()
    func stop()
    func send(_ command: MediaCommand)
    func seek(to position: TimeInterval)
}

/// The adapter is asked for complete payloads, so tracks never inherit old fields.
public enum MediaDecoder {
    public static func decode(_ data: Data, now: Date = Date()) throws -> MediaState {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let envelope = object as? [String: Any] else { return .idle }
        guard envelope["diff"] as? Bool != true else { throw DecodeError.partialPayload }
        let payload = envelope["payload"] as? [String: Any] ?? envelope
        guard !payload.isEmpty,
              let source = payload["bundleIdentifier"] as? String, !source.isEmpty else { return .idle }
        func seconds(_ key: String) -> Double? {
            (payload[key] as? NSNumber).map { $0.doubleValue / 1_000_000 }
        }
        let timestamp = seconds("timestampEpochMicros").flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil } ?? now
        let artwork = (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) }
        return .media(NowPlayingSnapshot(
            title: payload["title"] as? String ?? "Unknown title",
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            sourceBundleIdentifier: source,
            parentBundleIdentifier: payload["parentApplicationBundleIdentifier"] as? String ?? "",
            artworkData: artwork,
            duration: seconds("durationMicros"), elapsed: seconds("elapsedTimeMicros") ?? 0,
            observedAt: timestamp, isPlaying: payload["playing"] as? Bool ?? false,
            playbackRate: (payload["playbackRate"] as? NSNumber)?.doubleValue ?? 1
        ))
    }
    public enum DecodeError: Error { case partialPayload }
}
