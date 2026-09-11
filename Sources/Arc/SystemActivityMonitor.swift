import Foundation
import ArcCore
import IOKit.ps

@MainActor final class SystemActivityMonitor {
    var onActivity: ((SystemActivity) -> Void)?
    var onBattery: ((BatteryReading?) -> Void)?
    private var batteryTransitions = BatteryTransitions()
    private var powerSource: CFRunLoopSource?
    private var enabled = false

    func start() {
        guard !enabled else { return }
        enabled = true
        batteryTransitions = BatteryTransitions()
        refreshBattery()
        powerSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<SystemActivityMonitor>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { monitor.refreshBattery() }
        }, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let powerSource { CFRunLoopAddSource(CFRunLoopGetMain(), powerSource, .commonModes) }
    }

    func stop() {
        enabled = false
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
    }

    private func refreshBattery() {
        guard enabled, let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let data = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  data[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = data[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = data[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            let reading = BatteryReading(percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                pluggedIn: data[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: data[kIOPSIsChargingKey] as? Bool ?? false)
            onBattery?(reading)
            if let activity = batteryTransitions.receive(reading) { onActivity?(activity) }
            return
        }
        onBattery?(nil)
    }

}
