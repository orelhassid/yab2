import CoreSpotlight
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Only deliberate, persistent bookmarks are visible outside yab. History,
/// page text, and unsaved open tabs, including private tabs, stay out.
actor BookmarkSpotlight {
    static let shared = BookmarkSpotlight()

    struct Entry: Codable, Equatable {
        let id: String
        let title: String
        let url: String

        var spotlightID: String { "bookmark:" + id }
    }

    private let index = CSSearchableIndex(name: "yab.bookmarks")
    private var known: [String: Entry] = [:]
    private var pending: [String: Entry]?
    private var running = false
    private var latestRevision: UInt64 = 0
    /// The index keeps our last committed fingerprint across app launches.
    private var firstPass = true

    static func entries(in nodes: [Bookmark]) -> [String: Entry] {
        var entries: [String: Entry] = [:]
        func visit(_ nodes: [Bookmark]) {
            for node in nodes {
                if let value = node.url, let url = URL(string: value), Bookmark.keepable(url) {
                    let id = node.id.uuidString
                    entries[id] = Entry(id: id, title: node.title, url: url.absoluteString)
                }
                if let children = node.children { visit(children) }
            }
        }
        visit(nodes)
        return entries
    }

    func submit(_ roots: [Bookmark], revision: UInt64) {
        guard revision >= latestRevision else { return }
        latestRevision = revision
        pending = Self.entries(in: roots)
        guard !running else { return }
        running = true
        Task { await process() }
    }

    private func process() async {
        while let current = pending {
            pending = nil
            guard CSSearchableIndex.isIndexingAvailable() else { break }
            do {
                let fingerprint = try Self.fingerprint(current)
                if firstPass {
                    // A normal launch with unchanged bookmarks needs no index
                    // writes. A missing or stale state calls for a rebuild.
                    if try await index.fetchLastClientState() == fingerprint {
                        known = current
                        firstPass = false
                        continue
                    }
                    try await index.deleteSearchableItems(withDomainIdentifiers: ["bookmarks"])
                }
                let changed = current.values.filter { firstPass || known[$0.id] != $0 }
                let removed = firstPass ? [] : known.keys.filter { current[$0] == nil }.map { "bookmark:" + $0 }
                if !firstPass && changed.isEmpty && removed.isEmpty { continue }
                try await apply(changed: changed, removed: removed, fingerprint: fingerprint)
                known = current
                firstPass = false
            } catch {
                // The bookmark file is authoritative. Try again after the next
                // change or app launch, without recording an incomplete pass.
                break
            }
        }
        running = false
    }

    static func fingerprint(_ entries: [String: Entry]) throws -> Data {
        let sorted = entries.values.sorted { $0.id < $1.id }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(sorted)
        // Change the prefix if the Spotlight item schema changes.
        return Data("yab-bookmarks-v1:".utf8) + Data(SHA256.hash(data: encoded))
    }

    private func apply(changed: [Entry], removed: [String], fingerprint: Data) async throws {
        index.beginBatch()
        do {
            // Keep each request bounded for large imported bookmark folders.
            for start in stride(from: 0, to: changed.count, by: 100) {
                let end = min(start + 100, changed.count)
                try await index.indexSearchableItems(changed[start..<end].map(Self.searchableItem))
            }
            for start in stride(from: 0, to: removed.count, by: 100) {
                let end = min(start + 100, removed.count)
                try await index.deleteSearchableItems(withIdentifiers: Array(removed[start..<end]))
            }
        } catch {
            // An incomplete batch must never claim the current fingerprint.
            try? await index.endBatch(withClientState: Data("retry".utf8))
            throw error
        }
        try await index.endBatch(withClientState: fingerprint)
    }

    private static func searchableItem(_ entry: Entry) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .url)
        attributes.title = entry.title
        attributes.displayName = entry.title
        attributes.url = URL(string: entry.url)
        return CSSearchableItem(uniqueIdentifier: entry.spotlightID,
                                domainIdentifier: "bookmarks", attributeSet: attributes)
    }
}
