import Foundation
import CoreGraphics
import Observation

@MainActor @Observable public final class IslandModel {
    public private(set) var media: MediaState = .idle
    public private(set) var expanded = false
    public private(set) var activity: SystemActivity?
    @ObservationIgnored private var activityTask: Task<Void, Never>?

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
    public private(set) var notchSize: CGSize = .zero
    public func setNotchSize(_ size: CGSize) { notchSize = size }
    public private(set) var enabled: Bool
    @ObservationIgnored private var hoverTask: Task<Void, Never>?
    @ObservationIgnored private let enterDelay: UInt64
    @ObservationIgnored private let exitDelay: UInt64
    public var shouldTick: Bool { enabled && expanded && activity == nil && media.snapshot?.isPlaying == true }

    public init(enabled: Bool = true, enterDelay: UInt64 = 100_000_000, exitDelay: UInt64 = 100_000_000) {
        self.enabled = enabled
        self.enterDelay = enterDelay
        self.exitDelay = exitDelay
    }

    public func receive(_ state: MediaState) { media = state }
    public func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        if !enabled { collapse(); clearActivity() }
    }
    public func collapse() {
        hoverTask?.cancel()
        expanded = false
    }
    public func hover(_ inside: Bool) {
        hoverTask?.cancel()
        guard enabled else { return }
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
                ? CGSize(width: max(380, notch.width + 88), height: notch.height + (hasMedia ? 148 : 100))
                : CGSize(width: notch.width + (hasMedia ? 88 : 12), height: notch.height + 2)
        }
        return expanded ? CGSize(width: 380, height: hasMedia ? 148 : 100)
            : (hasMedia ? CGSize(width: 240, height: 40) : CGSize(width: 72, height: 12))
    }

    public static func frame(screen: CGRect, visible: CGRect, safeTop: CGFloat, size: CGSize) -> CGRect {
        let top = safeTop > 0 ? screen.maxY : visible.maxY - 8
        let width = min(size.width, screen.width)
        return CGRect(x: screen.midX - width / 2, y: top - size.height, width: width, height: size.height)
    }
}
