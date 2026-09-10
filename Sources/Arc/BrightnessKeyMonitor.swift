import AppKit
import ArcCore

/// Listen-only: the original hardware event always continues to macOS.
@MainActor final class BrightnessKeyMonitor {
    var onAdjustment: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    var isRunning: Bool { tap != nil }

    func start() {
        guard tap == nil, CGPreflightListenEventAccess() else { return }
        let mask = CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<BrightnessKeyMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated {
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    } else if let key = NSEvent(cgEvent: event),
                              BrightnessKey.isAdjustment(subtype: key.subtype.rawValue, data: key.data1) {
                        monitor.onAdjustment?()
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopSourceInvalidate(source) }
        tap = nil
        source = nil
    }
}
