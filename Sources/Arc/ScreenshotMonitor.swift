import AppKit
import Darwin
import Foundation

@MainActor final class ScreenshotMonitor {
    var onScreenshot: ((NSImage) -> Void)?

    private var source: DispatchSourceFileSystemObject?
    private var knownURLs: Set<URL> = []
    private var scanTask: Task<Void, Never>?
    private var processingTasks: [URL: Task<Void, Never>] = [:]
    private var latestCopied: (date: Date, path: String)?
    private let loadImage: (URL) -> NSImage?
    private let copyImage: (NSImage) -> Bool

    init(loadImage: ((URL) -> NSImage?)? = nil, copyImage: ((NSImage) -> Bool)? = nil) {
        self.loadImage = loadImage ?? { url in
            Self.isScreenshot(url) ? NSImage(contentsOf: url) : nil
        }
        self.copyImage = copyImage ?? { image in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            return pasteboard.writeObjects([image])
        }
    }

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
        latestCopied = nil
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

    func process(_ url: URL) async {
        let createdAt = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        let order = (createdAt, url.path)
        for attempt in 0..<6 {
            guard !Task.isCancelled else { return }
            // Metadata can arrive out of order. Never replace a newer capture
            // that has already reached the clipboard with an older one.
            if let latestCopied, order <= latestCopied { return }
            if let image = loadImage(url) {
                guard copyImage(image) else { return }
                latestCopied = order
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
