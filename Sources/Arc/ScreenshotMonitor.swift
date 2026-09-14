import AppKit
import Darwin
import Foundation

@MainActor final class ScreenshotMonitor {
    var onScreenshot: ((NSImage) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var knownURLs: Set<URL> = []
    private var scanTask: Task<Void, Never>?
    private var processingTasks: [URL: Task<Void, Never>] = [:]

    func start() {
        guard source == nil, let directory = Self.captureDirectory() else { return }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        knownURLs = Self.contents(of: directory)
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .link, .rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleScan(directory) }
        source.setCancelHandler { close(descriptor) }
        self.source = source
        source.resume()
    }

    func stop() {
        scanTask?.cancel()
        scanTask = nil
        processingTasks.values.forEach { $0.cancel() }
        processingTasks.removeAll()
        source?.cancel()
        source = nil
        knownURLs.removeAll()
    }

    private func scheduleScan(_ directory: URL) {
        scanTask?.cancel()
        scanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.scan(directory)
        }
    }

    private func scan(_ directory: URL) {
        let current = Self.contents(of: directory)
        let additions = current.subtracting(knownURLs)
        knownURLs = current
        for url in additions {
            guard processingTasks[url] == nil else { continue }
            processingTasks[url] = Task { [weak self] in
                await self?.process(url)
                self?.processingTasks[url] = nil
            }
        }
    }

    private func process(_ url: URL) async {
        for attempt in 0..<6 {
            guard !Task.isCancelled else { return }
            if Self.isScreenshot(url), let image = NSImage(contentsOf: url) {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                guard pasteboard.writeObjects([image]) else { return }
                onScreenshot?(image)
                return
            }
            if attempt < 5 { try? await Task.sleep(for: .milliseconds(300)) }
        }
    }

    private static func captureDirectory() -> URL? {
        let raw = CFPreferencesCopyAppValue(
            "location" as CFString,
            "com.apple.screencapture" as CFString
        ) as? String
        let path = NSString(string: raw ?? "~/Desktop").expandingTildeInPath
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
    }

    private static func contents(of directory: URL) -> Set<URL> {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        return Set(urls.filter { (try? $0.resourceValues(forKeys: Set(keys)).isRegularFile) == true }
            .map(\.standardizedFileURL))
    }

    private static func isScreenshot(_ url: URL) -> Bool {
        guard let item = NSMetadataItem(url: url),
              let value = item.value(forAttribute: "kMDItemIsScreenCapture") as? NSNumber else { return false }
        return value.boolValue
    }
}
