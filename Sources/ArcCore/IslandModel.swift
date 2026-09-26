import Foundation
import CoreGraphics
import Observation

@MainActor @Observable public final class IslandModel {
    public let pocket = Pocket()
    public private(set) var receivingFiles = false
    public var dropMessage = "Drop To Add"
    public var draggingFileOut = false {
        didSet { if draggingFileOut { hoverTask?.cancel() } }
    }
    public var showsPocket: Bool {
        receivingFiles || (!pocket.items.isEmpty && (expanded || (activity == nil && !screenshotCopied)))
    }

    public func setReceivingFiles(_ receiving: Bool) {
        guard receivingFiles != receiving, !receiving || enabled else { return }
        receivingFiles = receiving
        if receiving { hoverTask?.cancel(); expanded = true }
        else { collapse() }
    }

    public private(set) var media: MediaState = .idle
    public private(set) var expanded = false
    public private(set) var activity: SystemActivity?
    @ObservationIgnored private var activityTask: Task<Void, Never>?
    public private(set) var screenshotCopied = false
    @ObservationIgnored private var screenshotTask: Task<Void, Never>?

    public func showActivity(_ activity: SystemActivity, duration: UInt64 = 1_500_000_000) {
        guard enabled else { return }
        activityTask?.cancel()
        self.activity = activity
        activityTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: duration) } catch { return }
            self?.activity = nil
        }
    }

    public func clearActivity() {
        activityTask?.cancel()
        activity = nil
    }

    public func showScreenshotCopied(duration: UInt64 = 1_500_000_000) {
        guard enabled else { return }
        screenshotTask?.cancel()
        screenshotCopied = true
        screenshotTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: duration) } catch { return }
            self?.screenshotCopied = false
        }
    }

    public func clearScreenshotFeedback() {
        screenshotTask?.cancel()
        screenshotCopied = false
    }
    public private(set) var notchSize: CGSize = .zero
    public func setNotchSize(_ size: CGSize) { notchSize = size }
    public var displayIsMirrored = false
    public var attachesToTop: Bool { notchSize.height > 0 || displayIsMirrored }
    public private(set) var enabled: Bool
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private let enterDelay: UInt64
    @ObservationIgnored private let exitDelay: UInt64
    public var displayAwake = true
    public var lowPowerMode = false
    public var shouldAnimatePlayback: Bool {
        enabled && displayAwake && !lowPowerMode && !showsPocket && activity == nil && !screenshotCopied && media.snapshot?.isPlaying == true
    }
    public var shouldTick: Bool { enabled && displayAwake && expanded && !showsPocket && activity == nil && !screenshotCopied && media.snapshot?.isPlaying == true }

    public init(enabled: Bool = true, enterDelay: UInt64 = 100_000_000, exitDelay: UInt64 = 100_000_000) {
        self.enabled = enabled
        self.enterDelay = enterDelay
        self.exitDelay = exitDelay
    }

    public func receive(_ state: MediaState) { media = state }
    public func seek(to position: TimeInterval, at date: Date = Date()) {
        guard let snapshot = media.snapshot, snapshot.duration != nil else { return }
        media = .media(snapshot.seeking(to: position, at: date))
    }
    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { receivingFiles = false; collapse(); clearActivity(); clearScreenshotFeedback() }
    }
    public func collapse() {
        hoverTask?.cancel()
        expanded = false
    }
    public func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard enabled, !receivingFiles, !draggingFileOut else { return }
        if inside { pocket.refresh() }
        let delay = inside ? enterDelay : exitDelay
        hoverTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) } catch { return }
            guard let self, self.enabled else { return }
            self.expanded = inside
        }
    }
}

public enum IslandLayout {
    public static func notchSize(safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?) -> CGSize {
        guard safeTop > 0, let leftArea, let rightArea,
              rightArea.minX > leftArea.maxX else { return .zero }
        return CGSize(width: rightArea.minX - leftArea.maxX, height: safeTop)
    }

    public static func size(expanded: Bool, hasMedia: Bool, notch: CGSize = .zero) -> CGSize {
        if notch.height > 0 {
            return expanded
                ? CGSize(width: max(380, notch.width + 88), height: notch.height + (hasMedia ? 164 : 100))
                : CGSize(width: notch.width + (hasMedia ? 88 : 12), height: notch.height + 2)
        }
        return expanded ? CGSize(width: 380, height: hasMedia ? 164 : 100)
            : (hasMedia ? CGSize(width: 240, height: 40) : CGSize(width: 72, height: 12))
    }

    public static func pocketSize(expanded: Bool, count: Int, receiving: Bool, notch: CGSize = .zero) -> CGSize {
        guard expanded else { return size(expanded: false, hasMedia: true, notch: notch) }
        return CGSize(width: max(380, notch.width + 88),
                      height: notch.height + (receiving ? 100 : CGFloat(70 + max(1, count) * 40)))
    }

    public static func activitySize(expanded: Bool, notch: CGSize = .zero) -> CGSize {
        guard expanded else { return size(expanded: false, hasMedia: true, notch: notch) }
        return CGSize(width: max(280, notch.width + 88), height: notch.height + 64)
    }

    public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, size: CGSize, mirrored: Bool = false) -> CGRect {
        let top = safeTop > 0 || mirrored ? screen.maxY : visible.maxY - 8
        let width = min(size.width, screen.width)
        return CGRect(x: screen.midX - width / 2, y: top - size.height, width: width, height: size.height)
    }
}
