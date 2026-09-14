import AppKit
import ArcCore
import ImageIO
import Observation
import SwiftUI

@MainActor @Observable final class IslandCoordinator {
    let model: IslandModel
    private(set) var artwork: NSImage?
    private(set) var screenshot: NSImage?
    private(set) var battery: BatteryReading?
    @ObservationIgnored private let systemMonitor = SystemActivityMonitor()
    @ObservationIgnored private let screenshotMonitor = ScreenshotMonitor()
    @ObservationIgnored private var sleeping = false
    @ObservationIgnored private let provider: NowPlayingProviding
    @ObservationIgnored private var updates: Task<Void, Never>?
    @ObservationIgnored private var window: IslandWindowController?
    @ObservationIgnored private var pocketWindow: PocketWindowController?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(provider: NowPlayingProviding, enabled: Bool) {
        self.provider = provider
        model = IslandModel(enabled: enabled)
    }

    func start() {
        window = IslandWindowController(coordinator: self)
        pocketWindow = PocketWindowController(model: model)
        systemMonitor.onActivity = { [weak self] activity in
            self?.model.showActivity(activity)
        }
        systemMonitor.onBattery = { [weak self] reading in self?.battery = reading }
        screenshotMonitor.onScreenshot = { [weak self] image in self?.showScreenshot(image) }
        screenshotMonitor.start()
        if model.enabled { systemMonitor.start() }
        updates = Task { [weak self, provider] in
            for await state in provider.updates {
                guard let self, !Task.isCancelled else { break }
                let image = await Self.decodeArtwork(state.snapshot?.artworkData)
                guard !Task.isCancelled else { break }
                self.artwork = image
                self.model.receive(state)
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = true
                self?.provider.stop()
                self?.systemMonitor.stop()
                self?.model.clearActivity()
                self?.model.clearScreenshotFeedback()
                self?.screenshotMonitor.stop()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.sleeping = false
                if self?.model.enabled == true { self?.systemMonitor.start() }
                self?.screenshotMonitor.start()
                self?.model.receive(.idle)
                self?.provider.start()
            }
        })
        provider.start()
    }

    func stop() {
        systemMonitor.stop()
        screenshotMonitor.stop()
        model.clearActivity()
        model.clearScreenshotFeedback()
        provider.stop()
        updates?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        window?.close()
        pocketWindow?.close()
    }

    func setEnabled(_ enabled: Bool) {
        model.setEnabled(enabled)
        if enabled && !sleeping { systemMonitor.start() }
        else { systemMonitor.stop() }
    }

    func send(_ command: MediaCommand) {
        guard model.media.snapshot != nil else { return }
        provider.send(command)
    }

    func retry() {
        provider.stop()
        model.receive(.idle)
        provider.start()
    }

    func showPocket() {
        pocketWindow?.show()
    }

    func showScreenshot(_ image: NSImage) {
        screenshot = image
        model.showScreenshotCopied()
    }

    private static func decodeArtwork(_ data: Data?) async -> NSImage? {
        guard let data else { return nil }
        let cgImage = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil as CGImage? }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 160,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
        return cgImage.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }
}
