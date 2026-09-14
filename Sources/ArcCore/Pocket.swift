import Foundation
import Observation

public struct PocketItem: Identifiable, Equatable {
    public var id: URL { url }
    public let url: URL
    public var isMissing: Bool
}

@MainActor @Observable public final class Pocket {
    public static let islandCapacity = 5
    public private(set) var items: [PocketItem] = []
    public var islandItems: ArraySlice<PocketItem> { items.prefix(Self.islandCapacity) }
    public var overflowItems: ArraySlice<PocketItem> { items.dropFirst(Self.islandCapacity) }
    public var hasOverflow: Bool { items.count > Self.islandCapacity }

    public init() {}

    public func candidates(from urls: [URL]) -> [URL] {
        var result: [URL] = []
        for url in urls where url.isFileURL {
            let url = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: url.path),
                  !items.contains(where: { $0.url == url }), !result.contains(url) else { continue }
            result.append(url)
        }
        return result
    }

    public func canHold(_ urls: [URL]) -> Bool {
        !candidates(from: urls).isEmpty
    }

    @discardableResult public func hold(_ urls: [URL]) -> Bool {
        let additions = candidates(from: urls)
        guard !additions.isEmpty else { return false }
        items += additions.map { PocketItem(url: $0, isMissing: false) }
        return true
    }

    public func refresh() {
        items = items.map { PocketItem(url: $0.url, isMissing: !FileManager.default.fileExists(atPath: $0.url.path)) }
    }

    public func remove(_ url: URL) { items.removeAll { $0.url == url } }
    public func clear() { items.removeAll() }
}
