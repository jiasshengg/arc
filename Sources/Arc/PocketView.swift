import AppKit
import ArcCore
import SwiftUI

final class PocketHostingView: NSHostingView<IslandView> {
    var model: IslandModel?

    private func fileURLs(_ sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateDrag(sender) }

    private func updateDrag(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let model, model.enabled, !model.draggingFileOut else { return [] }
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return [] }
        let additions = model.pocket.candidates(from: urls)
        let accepted = !additions.isEmpty
        let overflow = max(0, model.pocket.items.count + additions.count - Pocket.islandCapacity)
        model.dropMessage = accepted
            ? (overflow > 0 ? "Drop To Add · \(overflow) more in Pocket" : "Drop To Add")
            : "Already Added Or Missing"
        model.setReceivingFiles(true)
        return accepted ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { model?.setReceivingFiles(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { model?.setReceivingFiles(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        model?.pocket.canHold(fileURLs(sender)) == true
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let model else { return false }
        let held = model.pocket.hold(fileURLs(sender))
        model.setReceivingFiles(false)
        return held
    }
}

struct PocketView: View {
    let model: IslandModel
    let onOpenPocket: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pocket").font(.system(size: 13, weight: .semibold))
                Text(model.pocket.hasOverflow
                     ? "\(Pocket.islandCapacity) of \(model.pocket.items.count)"
                     : "\(model.pocket.items.count)")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
                Spacer()
                if model.pocket.hasOverflow {
                    Button("More") { onOpenPocket() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                }
                Button("Clear") { model.pocket.clear() }
                    .buttonStyle(.plain).font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }.frame(height: 30)
            ForEach(model.pocket.islandItems) { item in
                PocketItemRow(item: item, model: model, showsPath: false)
            }
            Text(model.pocket.hasOverflow
                 ? "\(model.pocket.overflowItems.count) more in Pocket · Originals stay in place."
                 : "Drag a file into another app. Originals stay in place.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4)).frame(height: 24)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .task {
            while !Task.isCancelled {
                model.pocket.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

struct PocketItemRow: View {
    let item: PocketItem
    let model: IslandModel
    let showsPath: Bool

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable().frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if item.isMissing {
                        Text("File Moved Or Deleted").font(.system(size: 10)).foregroundStyle(.orange)
                    } else if showsPath {
                        Text(displayPath)
                            .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: item.isMissing ? "exclamationmark.triangle" : "arrow.up.right")
                    .font(.system(size: 10)).foregroundStyle(item.isMissing ? .orange : .secondary)
            }
            .overlay { PocketDragHandle(url: item.url, model: model) }
            .help(item.isMissing ? "File Moved Or Deleted: \(item.url.path)" : "Drag Into Another App · \(item.url.path)")
            Button { model.pocket.remove(item.url) } label: {
                Image(systemName: "xmark").font(.system(size: 10)).frame(width: 28, height: 30)
            }.buttonStyle(.plain).accessibilityLabel("Remove \(item.url.lastPathComponent) From Pocket")
        }
        .frame(height: showsPath ? 48 : 40)
    }

    private var displayPath: String {
        item.url.deletingLastPathComponent().standardizedFileURL.pathComponents
            .filter { $0 != "/" }.suffix(2).joined(separator: " · ")
    }
}

struct PocketDragHandle: NSViewRepresentable {
    let url: URL
    let model: IslandModel
    func makeNSView(context: Context) -> FileDragView { FileDragView() }
    func updateNSView(_ view: FileDragView, context: Context) {
        view.url = url
        view.model = model
        view.setAccessibilityLabel("Drag \(url.lastPathComponent)")
    }
}

final class FileDragView: NSView, NSDraggingSource {
    var url: URL?
    var model: IslandModel?
    private var start: NSPoint?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow }
    override func mouseUp(with event: NSEvent) { start = nil }
    override func mouseDragged(with event: NSEvent) {
        guard let start, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 3,
              let url, FileManager.default.fileExists(atPath: url.path) else {
            model?.pocket.refresh()
            return
        }
        self.start = nil
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: point.x - 16, y: point.y - 16, width: 32, height: 32),
                              contents: NSWorkspace.shared.icon(forFile: url.path))
        model?.draggingFileOut = true
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        model?.draggingFileOut = false
        model?.pocket.refresh()
        model?.hover(false)
    }
}
