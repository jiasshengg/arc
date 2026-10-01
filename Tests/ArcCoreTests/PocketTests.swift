import XCTest
@testable import ArcCore

final class PocketTests: XCTestCase {
    @MainActor func testIslandCapacityOverflowDeduplicationAndRemoval() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = try (0..<6).map { index in
            let url = directory.appendingPathComponent("file-\(index)")
            try Data("original".utf8).write(to: url)
            return url
        }
        let pocket = Pocket()
        XCTAssertTrue(pocket.hold([files[0], files[0]]))
        XCTAssertEqual(pocket.items.count, 1)
        XCTAssertTrue(pocket.hold(files))
        XCTAssertEqual(pocket.items.count, 6)
        XCTAssertEqual(pocket.islandItems.count, Pocket.islandCapacity)
        XCTAssertEqual(pocket.overflowItems.map(\.url), [files[5]])
        XCTAssertTrue(pocket.hasOverflow)
        pocket.remove(files[0])
        XCTAssertEqual(pocket.islandItems.map(\.url), Array(files[1...5]))
        XCTAssertTrue(pocket.overflowItems.isEmpty)
        pocket.clear()
        XCTAssertTrue(pocket.items.isEmpty)
        for file in files { XCTAssertEqual(try String(contentsOf: file), "original") }
    }

    @MainActor func testFoldersInvalidURLsAndMissingOriginals() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pocket = Pocket()
        XCTAssertFalse(pocket.hold([URL(string: "https://example.com/file")!, directory.appendingPathComponent("absent")]))
        XCTAssertTrue(pocket.hold([directory]))
        try FileManager.default.removeItem(at: directory)
        pocket.refresh()
        XCTAssertTrue(pocket.items[0].isMissing)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pocket.refresh()
        XCTAssertFalse(pocket.items[0].isMissing)
    }

    @MainActor func testIncomingDragOverridesActivityAndHoverThenCollapses() async throws {
        let model = IslandModel(enterDelay: 0, exitDelay: 0)
        model.showActivity(SystemActivity(kind: .charging, level: 0.5))
        model.setReceivingFiles(true)
        model.hover(false)
        try await Task.sleep(for: .milliseconds(10))
        XCTAssertTrue(model.expanded)
        XCTAssertTrue(model.showsPocket)
        XCTAssertFalse(model.shouldTick)
        model.setReceivingFiles(false)
        XCTAssertFalse(model.expanded)
        XCTAssertFalse(model.showsPocket)
        XCTAssertNotNil(model.activity)
        model.setReceivingFiles(true)
        model.setEnabled(false)
        XCTAssertFalse(model.receivingFiles)
        XCTAssertFalse(model.expanded)
    }
}
