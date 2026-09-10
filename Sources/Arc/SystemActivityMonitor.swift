import AppKit
import ArcCore
import CoreAudio
import IOKit.ps

@MainActor final class SystemActivityMonitor {
    var onActivity: ((SystemActivity) -> Void)?
    var onBattery: ((BatteryReading?) -> Void)?
    private var batteryTransitions = BatteryTransitions()
    private var powerSource: CFRunLoopSource?
    private var brightnessTimer: Timer?
    private var brightnessChanges = BrightnessChanges()
    private var displaySleeping = false
    private var screenObservers: [NSObjectProtocol] = []
    private var displayID: CGDirectDisplayID?
    private var device = AudioDeviceID(kAudioObjectUnknown)
    private var lastVolume: SystemActivity?
    private var volumeListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var enabled = false
    private var displayObserver: NSObjectProtocol?

    private typealias ReadBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private let brightnessLibrary: UnsafeMutableRawPointer?
    private let readBrightness: ReadBrightness?

    init() {
        let library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        brightnessLibrary = library
        readBrightness = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: ReadBrightness.self) }
    }

    deinit {
        if let brightnessLibrary { dlclose(brightnessLibrary) }
    }

    #if DEBUG
    func diagnostics() -> String {
        "Volume readable: \(sampleVolume() != nil); brightness readable: \(sampleBrightness() != nil)"
    }
    #endif

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
        configureVolume()
        displaySleeping = false
        selectDisplay(forceReset: true)
        let workspace = NSWorkspace.shared.notificationCenter
        screenObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.displaySleeping = true
                self?.brightnessTimer?.invalidate()
                self?.brightnessTimer = nil
            }
        })
        screenObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.displaySleeping = false
                self?.selectDisplay(forceReset: true)
            }
        })
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.selectDisplay() }
        }
    }

    func stop() {
        enabled = false
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        if let powerSource { CFRunLoopSourceInvalidate(powerSource) }
        powerSource = nil
        for (object, var address, listener) in volumeListeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
        }
        volumeListeners.removeAll()
        if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }
        displayObserver = nil
        screenObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        screenObservers.removeAll()
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

    private func selectDisplay(forceReset: Bool = false) {
        guard enabled && !displaySleeping else { return }
        let screen = NSScreen.screens.first(where: { screen in
            let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return CGDisplayIsBuiltin(id) != 0
        }) ?? NSScreen.screens.first
        let id = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard forceReset || displayID != id || brightnessTimer == nil else { return }
        displayID = id
        brightnessChanges.reset(at: ProcessInfo.processInfo.systemUptime)
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        guard sampleBrightness() != nil else { return }
        if let value = sampleBrightness() {
            _ = brightnessChanges.receive(value, at: ProcessInfo.processInfo.systemUptime)
        }
        // Read-only SPI has no public change subscription. Poll only while visible and awake.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshBrightness() }
        }
        timer.tolerance = 0.05
        brightnessTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func sampleBrightness() -> Int? {
        guard let displayID, let readBrightness else { return nil }
        var value: Float = 0
        guard readBrightness(displayID, &value) == 0, value.isFinite, value >= 0 else { return nil }
        return Int((min(1, value) * 100).rounded())
    }

    private func refreshBrightness() {
        guard enabled else { return }
        guard let value = sampleBrightness() else {
            brightnessTimer?.invalidate()
            brightnessTimer = nil
            brightnessChanges.reset(at: ProcessInfo.processInfo.systemUptime)
            return
        }
        if brightnessChanges.receive(value, at: ProcessInfo.processInfo.systemUptime) {
            onActivity?(SystemActivity(kind: .brightness, level: Double(value) / 100))
        }
    }

    private func configureVolume() {
        guard enabled else { return }
        for (object, var address, listener) in volumeListeners {
            AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
        }
        volumeListeners.removeAll()
        lastVolume = nil
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var count = UInt32(MemoryLayout<AudioDeviceID>.size)
        device = AudioDeviceID(kAudioObjectUnknown)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &count, &device)
        listen(object: AudioObjectID(kAudioObjectSystemObject), address: address, deviceChange: true)
        guard device != kAudioObjectUnknown else { return }
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element in UInt32(0)...UInt32(2) {
                listen(object: device, address: AudioObjectPropertyAddress(mSelector: selector,
                    mScope: kAudioDevicePropertyScopeOutput, mElement: element), deviceChange: false)
            }
        }
        lastVolume = sampleVolume()
    }

    private func listen(object: AudioObjectID, address: AudioObjectPropertyAddress, deviceChange: Bool) {
        var address = address
        guard AudioObjectHasProperty(object, &address) else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                if deviceChange { self.configureVolume() }
                else { self.refreshVolume() }
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) == noErr {
            volumeListeners.append((object, address, listener))
        }
    }

    private func sampleVolume() -> SystemActivity? {
        func scalar(_ element: UInt32) -> Float32? {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var result: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &result) == noErr,
                  result.isFinite else { return nil }
            return result
        }
        let channels = [scalar(1), scalar(2)].compactMap { $0 }
        guard let volume = scalar(0) ?? (channels.isEmpty ? nil : channels.reduce(0, +) / Float(channels.count)) else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
        return SystemActivity(kind: .volume, level: Double(volume), muted: muted != 0)
    }

    private func refreshVolume() {
        let value = sampleVolume()
        defer { lastVolume = value }
        guard let value, value != lastVolume else { return }
        onActivity?(value)
    }
}
