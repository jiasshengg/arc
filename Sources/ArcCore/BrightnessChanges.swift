import Foundation

/// A wake ramp is system restoration, not a brightness adjustment to announce.
/// Use monotonic uptime so wall-clock changes cannot affect the settling window.
public struct BrightnessChanges {
    private var previous: Int?
    private var settleAfter: TimeInterval = 0
    private var lastChangeAt: TimeInterval = 0
    private var settled = false

    public init() {}

    public mutating func reset(at uptime: TimeInterval) {
        previous = nil
        settleAfter = uptime + 2
        lastChangeAt = uptime
        settled = false
    }

    public mutating func receive(_ value: Int, at uptime: TimeInterval) -> Bool {
        let changed = previous != nil && previous != value
        if previous == nil || changed { lastChangeAt = uptime }
        previous = value
        guard settled else {
            // Keep absorbing the restore ramp until it has actually stopped.
            if uptime >= settleAfter && uptime - lastChangeAt >= 0.75 { settled = true }
            return false
        }
        return changed
    }
}
