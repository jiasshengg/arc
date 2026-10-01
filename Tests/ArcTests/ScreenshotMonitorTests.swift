import AppKit
import XCTest
@testable import Arc

final class ScreenshotMonitorTests: XCTestCase {
    @MainActor func testDelayedOlderCaptureCannotOverwriteNewerCapture() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try capture(in: directory, name: "old", date: Date(timeIntervalSince1970: 100))
        let new = try capture(in: directory, name: "new", date: Date(timeIntervalSince1970: 200))
        let oldImage = NSImage(size: NSSize(width: 1, height: 1))
        let newImage = NSImage(size: NSSize(width: 2, height: 2))
        let waiting = expectation(description: "Older capture waiting for metadata")
        var oldAttempts = 0
        var copied: [NSImage] = []
        let monitor = ScreenshotMonitor(loadImage: { url in
            if url == old {
                oldAttempts += 1
                if oldAttempts == 1 { waiting.fulfill(); return nil }
                return oldImage
            }
            return newImage
        }, copyImage: { copied.append($0); return true })
        let pending = Task { await monitor.process(old) }
        await fulfillment(of: [waiting], timeout: 1)
        await monitor.process(new)
        await pending.value
        XCTAssertEqual(copied.count, 1)
        XCTAssertTrue(copied.last === newImage)
    }

    @MainActor func testNewestCaptureWinsRegardlessOfDiscoveryOrder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try capture(in: directory, name: "old", date: Date(timeIntervalSince1970: 100))
        let new = try capture(in: directory, name: "new", date: Date(timeIntervalSince1970: 200))
        for urls in [[old, new], [new, old]] {
            var copied: [URL] = []
            var loading: URL?
            let monitor = ScreenshotMonitor(loadImage: { url in
                loading = url
                return NSImage(size: NSSize(width: 1, height: 1))
            }, copyImage: { _ in copied.append(loading!); return true })
            for url in urls { await monitor.process(url) }
            XCTAssertEqual(copied.last, new)
        }
    }

    @MainActor func testFailedCopyDoesNotSuppressOlderValidCapture() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = try capture(in: directory, name: "old", date: Date(timeIntervalSince1970: 100))
        let new = try capture(in: directory, name: "new", date: Date(timeIntervalSince1970: 200))
        var attempts = 0
        var confirmations = 0
        let monitor = ScreenshotMonitor(loadImage: { _ in NSImage(size: NSSize(width: 1, height: 1)) },
                                        copyImage: { _ in attempts += 1; return attempts > 1 })
        monitor.onScreenshot = { _ in confirmations += 1 }
        await monitor.process(new)
        await monitor.process(old)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(confirmations, 1)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func capture(in directory: URL, name: String, date: Date) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data().write(to: url)
        try FileManager.default.setAttributes([.creationDate: date], ofItemAtPath: url.path)
        return url
    }
}
