import AppKit
import XCTest
@testable import Arc

final class IslandPointerTests: XCTestCase {
    @MainActor func testOrdinaryClicksAndStalePasteboardAreNotFileDrags() {
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: false, eventType: .leftMouseDown,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: false, eventType: .mouseMoved,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: false, eventType: .leftMouseDragged,
            leftButtonDown: true, pasteboardChanged: false, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: false, eventType: .leftMouseDragged,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.string]))
    }

    @MainActor func testFileDragSurvivesLayoutAndResetsOnMouseReleaseOrNewClick() {
        XCTAssertTrue(IslandWindowController.isFileDrag(previous: false, eventType: .leftMouseDragged,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertTrue(IslandWindowController.isFileDrag(previous: true, eventType: nil,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: true, eventType: .leftMouseUp,
            leftButtonDown: true, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: true, eventType: nil,
            leftButtonDown: false, pasteboardChanged: true, pasteboardTypes: [.fileURL]))
        XCTAssertFalse(IslandWindowController.isFileDrag(previous: true, eventType: .leftMouseDown,
            leftButtonDown: true, pasteboardChanged: false, pasteboardTypes: [.fileURL]))
    }
}
