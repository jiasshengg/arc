import Foundation

public struct SystemActivity: Equatable, Sendable {
    public enum Kind: Sendable { case charging, unplugged, lowBattery, charged }
    public let kind: Kind
    public let level: Double
    public init(kind: Kind, level: Double) {
        self.kind = kind
        self.level = level.isFinite ? min(1, max(0, level)) : 0
    }
    public var title: String {
        switch kind {
        case .charging: return "Power connected"
        case .unplugged: return "On battery"
        case .lowBattery: return "Low battery"
        case .charged: return "Fully charged"
        }
    }
    public var symbol: String {
        switch kind {
        case .charging: return "bolt.fill"
        case .unplugged: return "battery.75percent"
        case .lowBattery: return "battery.25percent"
        case .charged: return "battery.100percent"
        }
    }
}

public struct BatteryReading: Equatable, Sendable {
    public let percent: Int
    public let pluggedIn: Bool
    public let charging: Bool
    public init(percent: Int, pluggedIn: Bool, charging: Bool) {
        self.percent = min(100, max(0, percent))
        self.pluggedIn = pluggedIn
        self.charging = charging
    }
}

/// Baseline silently at startup; warn once per discharge threshold, not every update.
public struct BatteryTransitions {
    private var previous: BatteryReading?
    private var warnedAt: Int = 100
    public init() {}
    public mutating func receive(_ reading: BatteryReading) -> SystemActivity? {
        defer { previous = reading }
        if reading.pluggedIn || reading.percent > 25 { warnedAt = 100 }
        guard let previous else { return nil }
        let level = Double(reading.percent) / 100
        if reading.pluggedIn != previous.pluggedIn {
            return SystemActivity(kind: reading.pluggedIn ? .charging : .unplugged, level: level)
        }
        if reading.pluggedIn && reading.percent == 100 && previous.percent < 100 {
            return SystemActivity(kind: .charged, level: level)
        }
        if !reading.pluggedIn {
            let threshold = reading.percent <= 10 ? 10 : (reading.percent <= 20 ? 20 : 100)
            if threshold < warnedAt {
                warnedAt = threshold
                return SystemActivity(kind: .lowBattery, level: level)
            }
        }
        return nil
    }
}
