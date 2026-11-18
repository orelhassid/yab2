import AppKit
import Combine

// Bookmarks: folders and sites, kept in a small file.
//
// Found and kept in order in the box's Bookmarks (Places.swift, ⌥⌘B), a
// folder at a time, rather than as a system menu: a menu can't be searched,
// renamed in, or asked a second thing by ⌘K. The bar and the column's
// folders take drags.

struct Bookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    /// Nil for a folder.
    var url: String?
    var children: [Bookmark]?
    /// When it was kept: here, or in the browser it was brought from. Nil
    /// when nobody said, as for those kept before Yab noted it, and for
    /// Safari's, whose files have no dates.
    var added: Date?
    /// Imported profile collection: shown in this Space by the bookmark bar.
    var space: UUID?
    var importKey: String?
    var folderIcon: String?
    var folderColor: String?

    var isFolder: Bool { url == nil }

    var host: String? {
        url.flatMap { URL(string: $0)?.host()?.lowercased() }
    }

    /// The name its site's icon is kept under (Favicons.site): the host,
    /// with the port where the address names one of its own.
    var iconSite: String? {
        url.flatMap(URL.init(string:)).flatMap(Favicons.site)
    }

    /// The icon its page wore when last open, its site's otherwise
    /// (Favicons.cached(page:)): a slideshow's bookmark, not the Docs icon.
    @MainActor var savedIcon: NSImage? {
        url.flatMap(URL.init(string:)).flatMap(Favicons.shared.cached(page:))
    }

    /// Its site's icon fetched, if none is kept yet: from its own front
    /// page, on its own scheme and port.
    @MainActor func fetchIcon() {
        guard let site = iconSite, Favicons.shared.cached(site) == nil,
              let page = url.flatMap(URL.init(string:)) else { return }
        Favicons.shared.fetch(page: page)
    }

    static func site(_ title: String, _ url: URL, added: Date? = Date()) -> Bookmark {
        Bookmark(title: title.isEmpty ? Address.pretty(url) : title, url: url.absoluteString, children: nil, added: added)
    }

    static func folder(_ title: String, _ children: [Bookmark], added: Date? = Date()) -> Bookmark {
        Bookmark(title: title, url: nil, children: children, added: added)
    }

    /// A page on the web. The app's own pages aren't places to keep.
    static func keepable(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}

@MainActor
final class Bookmarks: ObservableObject {
    static let shared = Bookmarks()
    private static let writes = DispatchQueue(label: "yab.bookmarks", qos: .utility)
    @Published private(set) var roots: [Bookmark] = [] {
        didSet { revision &+= 1 }
    }
    /// Bumped with every change, for a list made from the tree to know
    /// it is stale without comparing the tree.
    private(set) var revision = 0
    private var spotlightRevision: UInt64 = 0

    init() {
        load()
        if Self.shouldIndex { Task { await BookmarkSpotlight.shared.submit(roots, revision: 0) } }
    }

    var isEmpty: Bool { roots.isEmpty }

    /// Global bookmarks plus this Space's imported collection, without a
    /// wrapper folder in the bar. The library retains every collection.
    func barRoots(in space: UUID, profile: String? = nil) -> [Bookmark] {
        roots.flatMap { node in
            guard let owner = node.space else { return [node] }
            let sameProfile = node.importKey.map { key in
                profile == key || profile?.hasPrefix(key + ":") == true
            } ?? false
            return owner == space || sameProfile ? (node.children ?? []) : []
        }
    }

    @discardableResult
    func takeProfile(_ nodes: [Bookmark], key: String, name: String, space: UUID) -> Int {
        guard !nodes.isEmpty else { return 0 }
        let at = roots.firstIndex { $0.importKey == key }
        let old = at.map { roots[$0].children ?? [] } ?? []
        let plan = Self.plan(nodes, into: old, from: key, brought: Self.brought(from: key) ?? Brought(urls: Self.addresses(old), top: true))
        Self.remember(plan.brought, from: key)
        var collection = at.map { roots[$0] } ?? Bookmark.folder(name, [])
        collection.space = space
        collection.importKey = key
        collection.children = plan.roots
        if let at { roots[at] = collection } else { roots.append(collection) }
        save()
        return plan.added
    }

    /// How many sites, folders included.
    var count: Int { Bookmarks.count(roots) }

    nonisolated static func count(_ nodes: [Bookmark]) -> Int {
        nodes.reduce(0) { $0 + ($1.isFolder ? count($1.children ?? []) : 1) }
    }

    /// Every site in the list, in order, folders opened.
    nonisolated static func urls(_ nodes: [Bookmark]) -> [URL] {
        nodes.flatMap { node -> [URL] in
            if node.isFolder { return urls(node.children ?? []) }
            return node.url.flatMap(URL.init(string:)).map { [$0] } ?? []
        }
    }

    /// Every site whose day is known, newest first, each with the folder
    /// it sits in (nil at the top level): Recently Added.
    nonisolated static func recent(_ nodes: [Bookmark]) -> [(node: Bookmark, folder: Bookmark?)] {
        var out: [(node: Bookmark, folder: Bookmark?, at: Date, order: Int)] = []
        func walk(_ nodes: [Bookmark], in folder: Bookmark?) {
            for node in nodes {
                if node.isFolder {
                    walk(node.children ?? [], in: node)
                } else if let at = node.added {
                    out.append((node, folder, at, out.count))
                }
            }
        }
        walk(nodes, in: nil)
        // Kept at the same moment, as a folder of tabs is: the one further
        // down the list first, as it came last.
        return out.sorted { $0.at != $1.at ? $0.at > $1.at : $0.order > $1.order }.map { ($0.node, $0.folder) }
    }

    /// Every folder in the tree, each with how deep it sits, for "move to
    /// folder" lists, where a folder three deep should look like it.
    static func folders(_ nodes: [Bookmark], depth: Int = 0) -> [(node: Bookmark, depth: Int)] {
        nodes.flatMap { node -> [(Bookmark, Int)] in
            guard node.isFolder else { return [] }
            return [(node, depth)] + folders(node.children ?? [], depth: depth + 1)
        }
    }

    // MARK: - changing

    /// The page, at the end of the list. Nothing is asked: the title is the
    /// page's, and filing it into a folder is the corner's Move To, a drag
    /// or a right-click away. Hands back the new one, nil if it was kept already.
    @discardableResult
    func add(_ url: URL, title: String) -> Bookmark.ID? {
        guard !contains(url) else { return nil }
        let site = Bookmark.site(title, url)
        fresh = (site.id, Date())
        roots.append(site)
        save()
        return site.id
    }

    /// The one just added, and when: the bookmarks bar draws it arriving,
    /// out of the place it offered for it when the row was empty.
    private var fresh: (id: Bookmark.ID, at: Date)?
    /// When another browser's bookmarks last came in, for the bar to bring
    /// them in one after another.
    private var arrived = Date.distantPast

    func isFresh(_ id: Bookmark.ID) -> Bool {
        guard let fresh, fresh.id == id else { return false }
        return Date().timeIntervalSince(fresh.at) < 1
    }

    var arriving: Bool { Date().timeIntervalSince(arrived) < 1 }

    func contains(_ url: URL) -> Bool {
        func walk(_ nodes: [Bookmark]) -> Bool {
            nodes.contains { $0.url == url.absoluteString || walk($0.children ?? []) }
        }
        return walk(roots)
    }

    /// The bookmark kept for this address, the first one found.
    func id(for url: URL) -> Bookmark.ID? {
        func find(_ nodes: [Bookmark]) -> Bookmark.ID? {
            for node in nodes {
                if node.url == url.absoluteString { return node.id }
                if let children = node.children, let id = find(children) { return id }
            }
            return nil
        }
        return find(roots)
    }

    func url(for id: Bookmark.ID) -> URL? {
        func find(_ nodes: [Bookmark]) -> URL? {
            for node in nodes {
                if node.id == id { return node.url.flatMap(URL.init(string:)) }
                if let children = node.children, let url = find(children) { return url }
            }
            return nil
        }
        return find(roots)
    }

    /// Whether any site kept here is on `host`.
    func contains(host: String) -> Bool {
        func walk(_ nodes: [Bookmark]) -> Bool {
            nodes.contains { $0.iconSite == host || walk($0.children ?? []) }
        }
        return walk(roots)
    }

    func remove(_ id: Bookmark.ID) {
        // A browser's folder deleted whole: what it was brought with goes too.
        if let folder = roots.first(where: { $0.id == id && $0.isFolder }) { Bookmarks.remember(nil, from: folder.title) }
        roots = Bookmarks.prune(id, from: roots)
        if roots.isEmpty { Bookmarks.forgetBrought() }
        save()
    }

    /// Remove, and the way back for ⌘Z: the same bookmark or folder, where
    /// it stood, whatever was added since.
    func removeUndoably(_ id: Bookmark.ID) -> () -> Void {
        let spot = Bookmarks.spot(of: id, in: roots, parent: nil)
        remove(id)
        return { [weak self] in
            guard let self, let spot else { return }
            var all = roots
            var filed = false
            if let parent = spot.parent { filed = Bookmarks.insert(spot.node, into: parent, before: spot.before, nodes: &all) }
            if !filed { all.insert(spot.node, at: spot.before.flatMap { b in all.firstIndex { $0.id == b } } ?? min(spot.index, all.count)) }
            roots = all
            save()
        }
    }

    private static func spot(of id: Bookmark.ID, in nodes: [Bookmark], parent: Bookmark.ID?)
        -> (node: Bookmark, parent: Bookmark.ID?, before: Bookmark.ID?, index: Int)? {
        for (index, node) in nodes.enumerated() {
            if node.id == id { return (node, parent, nodes.indices.contains(index + 1) ? nodes[index + 1].id : nil, index) }
            if let found = spot(of: id, in: node.children ?? [], parent: node.id) { return found }
        }
        return nil
    }

    private static func prune(_ id: Bookmark.ID, from nodes: [Bookmark]) -> [Bookmark] {
        nodes.compactMap { node in
            if node.id == id { return nil }
            var copy = node
            if let kids = node.children { copy.children = prune(id, from: kids) }
            return copy
        }
    }

    /// Takes a bookmark or a whole folder out of wherever it currently sits
    /// and puts it in another folder's children, or at the top level when
    /// `folderID` is nil, in front of `before`, or at the end without one.
    /// Moving a folder into its own children is refused rather than allowed
    /// to erase it by looping it inside itself; moving it onto itself is
    /// simply nothing to do.
    func move(_ id: Bookmark.ID, into folderID: Bookmark.ID?, before: Bookmark.ID? = nil) {
        guard id != folderID, id != before else { return }
        var working = roots
        guard let node = Bookmarks.detach(id, from: &working) else { return }
        if let folderID {
            guard !Bookmarks.holds(folderID, node) else { return }
            guard Bookmarks.insert(node, into: folderID, before: before, nodes: &working) else { return }
        } else {
            let at = before.flatMap { b in working.firstIndex { $0.id == b } } ?? working.count
            working.insert(node, at: at)
        }
        roots = working
        save()
    }

    private static func detach(_ id: Bookmark.ID, from nodes: inout [Bookmark]) -> Bookmark? {
        for i in nodes.indices {
            if nodes[i].id == id { return nodes.remove(at: i) }
            guard nodes[i].children != nil else { continue }
            var kids = nodes[i].children!
            if let found = detach(id, from: &kids) {
                nodes[i].children = kids
                return found
            }
        }
        return nil
    }

    @discardableResult
    private static func insert(_ node: Bookmark, into id: Bookmark.ID, before: Bookmark.ID? = nil, nodes: inout [Bookmark]) -> Bool {
        for i in nodes.indices {
            if nodes[i].id == id, nodes[i].isFolder {
                var kids = nodes[i].children ?? []
                let at = before.flatMap { b in kids.firstIndex { $0.id == b } } ?? kids.count
                kids.insert(node, at: at)
                nodes[i].children = kids
                return true
            }
            guard nodes[i].children != nil else { continue }
            var kids = nodes[i].children!
            if insert(node, into: id, before: before, nodes: &kids) {
                nodes[i].children = kids
                return true
            }
        }
        return false
    }

    /// `id` is `node` itself, or somewhere inside it.
    private static func holds(_ id: Bookmark.ID, _ node: Bookmark) -> Bool {
        node.id == id || (node.children ?? []).contains { holds(id, $0) }
    }

    /// Another browser's, or a file's, kept apart in a folder of that name
    /// unless there was nothing here yet. Taken again, they are merged, not
    /// put back: only a page that is kept nowhere here comes in, into the
    /// folder it sits in there, so what was renamed, moved or filed since
    /// stays as it was left. A page brought before and deleted since stays
    /// deleted, while what it was brought into is still here (see `plan`).
    /// Returns how many pages are new, and how many were left out as ones
    /// deleted here.
    @discardableResult
    func take(_ nodes: [Bookmark], from name: String, brought: Brought? = nil, apart: Bool = false) -> (added: Int, held: Int) {
        guard !nodes.isEmpty else { return (0, 0) }
        arrived = Date()
        let plan = Bookmarks.plan(nodes, into: roots, from: name, brought: brought, apart: apart)
        Bookmarks.remember(plan.brought, from: name)
        guard plan.added > 0 else { return (0, plan.held) }
        roots = plan.roots
        save()
        return (plan.added, plan.held)
    }

    /// What was brought in from a browser or a file, by its name: every page
    /// it had, whether or not it is still kept here, and whether it went in
    /// at the top level, as a first import into no bookmarks does, rather
    /// than into a folder of its name.
    struct Brought: Codable, Equatable {
        var urls: Set<String>
        var top: Bool
    }

    struct Plan {
        var roots: [Bookmark]
        var added: Int
        var held: Int
        var brought: Brought
    }

    /// Where `incoming` goes and what of it, with no file touched.
    /// - Nothing here yet: all of it, at the top level, unless it is to be
    ///   kept `apart` in its folder whatever else there is, as one of
    ///   Arc's spaces is.
    /// - A folder of this name: into it, leaving out what is kept anywhere
    ///   here and what was brought before and has been deleted since.
    /// - No such folder, but it went in at the top level before: into the
    ///   top level, by the same rules.
    /// - No such folder, and it had one: the folder was deleted, so what
    ///   was brought before says nothing now, and a new folder takes all
    ///   that isn't kept somewhere else.
    nonisolated static func plan(_ incoming: [Bookmark], into roots: [Bookmark], from name: String, brought: Brought?, apart: Bool = false) -> Plan {
        let kept = addresses(roots)
        let coming = addresses(incoming)
        var working = roots
        var added = 0
        var deleted = Set<String>()
        var top = false
        var carried = false
        if roots.isEmpty, !apart {
            added = merge(incoming, into: &working, skipping: [], fresh: true)
            top = true
        } else if let at = working.firstIndex(where: { $0.isFolder && $0.title == name }) {
            deleted = (brought?.urls ?? []).subtracting(kept)
            carried = true
            var kids = working[at].children ?? []
            added = merge(incoming, into: &kids, skipping: kept.union(deleted), fresh: false)
            working[at].children = kids
        } else if let brought, brought.top {
            deleted = brought.urls.subtracting(kept)
            added = merge(incoming, into: &working, skipping: kept.union(deleted), fresh: false)
            top = true
            carried = true
        } else {
            var kids: [Bookmark] = []
            added = merge(incoming, into: &kids, skipping: kept, fresh: true)
            if !kids.isEmpty { working.append(.folder(name, kids)) }
        }
        // Once the folder is gone, what it once had is forgotten with it.
        let remembered = carried ? coming.union(brought?.urls ?? []) : coming
        return Plan(roots: working, added: added, held: coming.intersection(deleted).count, brought: Brought(urls: remembered, top: top))
    }

    /// `incoming` filed into `target`: a folder into the folder of the same
    /// name at the same level, if there was one before this call, or as a
    /// new one; a page at the end of its folder, unless its address is in
    /// `skipping`. A folder that brings nothing new is left out; an empty
    /// one only comes into a `fresh` place, one this import is making, so
    /// an empty folder deleted here isn't put back. Returns how many pages
    /// went in.
    @discardableResult
    nonisolated static func merge(_ incoming: [Bookmark], into target: inout [Bookmark], skipping: Set<String>, fresh: Bool) -> Int {
        let before = target.count
        var added = 0
        for node in incoming {
            if node.isFolder {
                let kids = node.children ?? []
                if let at = target[..<before].firstIndex(where: { $0.isFolder && $0.title == node.title }) {
                    var into = target[at].children ?? []
                    added += merge(kids, into: &into, skipping: skipping, fresh: false)
                    target[at].children = into
                } else {
                    var into: [Bookmark] = []
                    added += merge(kids, into: &into, skipping: skipping, fresh: true)
                    if !into.isEmpty || (kids.isEmpty && fresh) { target.append(.folder(node.title, into, added: node.added)) }
                }
            } else if let url = node.url, !skipping.contains(url) {
                target.append(node)
                added += 1
            }
        }
        return added
    }

    /// Every address in the tree, as written.
    nonisolated static func addresses(_ nodes: [Bookmark]) -> Set<String> {
        var out = Set<String>()
        func walk(_ nodes: [Bookmark]) {
            for node in nodes {
                if let url = node.url { out.insert(url) } else { walk(node.children ?? []) }
            }
        }
        walk(nodes)
        return out
    }

    /// Read off the main thread, by whoever gathers the import.
    nonisolated static func brought(from name: String) -> Brought? {
        broughtAll()[name]
    }

    nonisolated static func broughtAll() -> [String: Brought] {
        (try? Data(contentsOf: broughtFile)).flatMap { try? JSONDecoder().decode([String: Brought].self, from: $0) } ?? [:]
    }

    /// Nil forgets the name.
    private static func remember(_ brought: Brought?, from name: String) {
        let file = broughtFile
        // One after another: two imports close together each read, change
        // and write the whole file.
        remembering.async {
            var all = broughtAll()
            all[name] = brought
            if all.isEmpty {
                try? FileManager.default.removeItem(at: file)
                return
            }
            guard let data = try? JSONEncoder().encode(all) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
        }
    }

    /// Everything once brought in, forgotten: it names pages deleted here,
    /// and goes with the history, and when no bookmarks are left.
    static func forgetBrought() {
        let file = broughtFile
        remembering.async { try? FileManager.default.removeItem(at: file) }
    }

    private static let remembering = DispatchQueue(label: "bookmarks.brought", qos: .utility)
    nonisolated private static var broughtFile: URL { Store.file("bookmarks-brought.json") }


    // MARK: - the file

    private static var file: URL { Store.file("bookmarks.json") }

    // MARK: - for extensions

    /// A page or a folder filed under `parent`, or at the top level for nil
    /// or a folder that isn't there. What chrome.bookmarks.create does.
    @discardableResult
    func insert(_ node: Bookmark, into parent: Bookmark.ID?) -> Bookmark {
        if let parent {
            var nodes = roots
            if Bookmarks.insert(node, into: parent, nodes: &nodes) {
                roots = nodes
                save()
                return node
            }
        }
        roots.append(node)
        save()
        return node
    }

    /// Several at once, one write: tabs let go of over a folder.
    func insert(contentsOf nodes: [Bookmark], into parent: Bookmark.ID?) {
        guard !nodes.isEmpty else { return }
        var all = roots
        if let parent, Bookmarks.insert(nodes[0], into: parent, nodes: &all) {
            for node in nodes.dropFirst() { _ = Bookmarks.insert(node, into: parent, nodes: &all) }
        } else {
            all.append(contentsOf: nodes)
        }
        roots = all
        save()
    }

    /// A new title or address for one that is kept. chrome.bookmarks.update.
    func update(_ id: Bookmark.ID, title: String?, url: String?) {
        edit(id) { node in
            if let title { node.title = title }
            if let url, !node.isFolder { node.url = url }
        }
    }

    func setFolderIcon(_ icon: String?, for id: Bookmark.ID) {
        edit(id) { if $0.isFolder { $0.folderIcon = icon } }
    }

    func setFolderColor(_ tint: FolderTint, for id: Bookmark.ID) {
        edit(id) { if $0.isFolder { $0.folderColor = tint.stored } }
    }

    private func edit(_ id: Bookmark.ID, change: (inout Bookmark) -> Void) {
        func walk(_ nodes: inout [Bookmark]) -> Bool {
            for i in nodes.indices {
                if nodes[i].id == id {
                    change(&nodes[i])
                    return true
                }
                guard var kids = nodes[i].children else { continue }
                if walk(&kids) {
                    nodes[i].children = kids
                    return true
                }
            }
            return false
        }
        var nodes = roots
        if walk(&nodes) {
            roots = nodes
            save()
        }
    }

    /// Every bookmark at once, as another Mac has them (SyncCenter).
    func replaceAll(with tree: [Bookmark]) {
        roots = tree
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Bookmarks.file) else { return }
        guard let list = try? JSONDecoder().decode([Bookmark].self, from: data) else {
            Store.quarantine(Bookmarks.file)
            return
        }
        roots = list
    }

    private func save() {
        let snapshot = roots
        let file = Bookmarks.file
        spotlightRevision &+= 1
        let revision = spotlightRevision
        let shouldIndex = Self.shouldIndex
        Bookmarks.writes.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard (try? data.write(to: file, options: .atomic)) != nil else { return }
            if shouldIndex { Task { await BookmarkSpotlight.shared.submit(snapshot, revision: revision) } }
        }
    }

    private static var shouldIndex: Bool {
        !Store.testing || ProcessInfo.processInfo.environment["YAB_SPOTLIGHT_TEST"] == "1"
    }
}
