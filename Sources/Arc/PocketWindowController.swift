import AppKit
import ArcCore
import SwiftUI

@MainActor final class PocketWindowController: NSWindowController, NSWindowDelegate {
    init(model: IslandModel) {
        let view = PocketWindowView(model: model)
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pocket"
        window.contentMinSize = NSSize(width: 460, height: 320)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("PocketWindow")
        window.contentView = hosting
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct PocketWindowView: View {
    let model: IslandModel
    @State private var receivingDrop = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if model.pocket.items.isEmpty {
                ContentUnavailableView(
                    "Pocket is empty",
                    systemImage: "tray",
                    description: Text("Drop files or folders above to keep them nearby.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(model.pocket.islandItems) { item in
                                PocketItemRow(item: item, model: model, showsPath: true)
                                    .padding(.horizontal, 18)
                                Divider().padding(.leading, 54)
                            }
                        } header: {
                            sectionHeader("IN THE ISLAND", detail: "\(model.pocket.islandItems.count) of \(Pocket.islandCapacity)")
                        }

                        if model.pocket.hasOverflow {
                            Section {
                                ForEach(model.pocket.overflowItems) { item in
                                    PocketItemRow(item: item, model: model, showsPath: true)
                                        .padding(.horizontal, 18)
                                    Divider().padding(.leading, 54)
                                }
                            } header: {
                                sectionHeader("MORE IN POCKET", detail: "Not shown in island")
                            }
                        }
                    }
                }
            }

            Divider()
            HStack {
                Text("Temporary · Originals stay in place · Clears when Arc quits")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Clear") { model.pocket.clear() }
                    .disabled(model.pocket.items.isEmpty)
            }
            .padding(.horizontal, 18)
            .frame(height: 48)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            receivingDrop = false
            return model.pocket.hold(urls)
        } isTargeted: { receivingDrop = $0 }
        .task {
            while !Task.isCancelled {
                model.pocket.refresh()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private var dropZone: some View {
        HStack(spacing: 9) {
            Image(systemName: "tray.and.arrow.down")
            Text(receivingDrop ? "Drop to hold" : "Drop files and folders to hold them")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(receivingDrop ? .primary : .secondary)
        .frame(maxWidth: .infinity, minHeight: 62)
        .background(receivingDrop ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(receivingDrop ? Color.accentColor.opacity(0.7) : Color.secondary.opacity(0.25),
                              style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(detail)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .frame(height: 30)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
