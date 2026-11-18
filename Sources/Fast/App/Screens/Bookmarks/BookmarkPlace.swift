import AppKit
import SwiftUI

// Bookmarks, a place in the box beside History (Places.swift), where the
// page yab://bookmarks was: ⌥⌘B, the menu, the bar's Show Bookmarks, or
// "bookmarks" and Tab. One folder at a time, its folders first, then its
// sites; words find anything under it, each under the folder it is in.
//
//   ↩   open the site, or go into the folder    ⌥↩  in a background tab
//   ⌘↩  copy the link                           ⇧⌘C a Markdown link
//   ⌘E  rename it, and a site's address         ⌘N  a new folder here
//   ⌃X  remove it (a folder with sites in it is asked about)
//   ⌘K  Move To any folder, Move Up and Down, Open All, Bring In More…
//
// Esc, or ⌫ in the empty field, goes up a folder before it leaves. The
// folder menu at the field's end goes anywhere in the tree at once, or to
// Recently Added: every site whose day is known, newest first, under its
// day, whatever folder it is in.

extension Bookmarks {
    /// The one with this id, anywhere in the tree.
    func node(_ id: Bookmark.ID) -> Bookmark? {
        trail(to: id)?.last
    }

    /// The folders down to it, outermost first, and it last; nil if it
    /// isn't kept.
    func trail(to id: Bookmark.ID) -> [Bookmark]? {
        func walk(_ nodes: [Bookmark], _ above: [Bookmark]) -> [Bookmark]? {
            for node in nodes {
                if node.id == id { return above + [node] }
                if let kids = node.children, let found = walk(kids, above + [node]) { return found }
            }
            return nil
        }
        return walk(roots, [])
    }

    /// The folders it sits in, as a heading says them: "Bookmarks › Work".
    func path(of folder: Bookmark.ID?) -> String {
        let names = folder.flatMap { trail(to: $0) }?.map(\.title) ?? []
        return (["Bookmarks"] + names).joined(separator: " › ")
    }

    /// What a folder holds, said: "3 folders, 12 bookmarks", "Empty".
    nonisolated static func holding(_ folder: Bookmark) -> String {
        let kids = folder.children ?? []
        let folders = kids.filter(\.isFolder).count
        let sites = count(kids)
        var parts: [String] = []
        if folders > 0 { parts.append(folders == 1 ? "1 folder" : "\(folders) folders") }
        if sites > 0 || folders > 0 { parts.append(sites == 1 ? "1 bookmark" : "\(sites.formatted()) bookmarks") }
        return parts.isEmpty ? "Empty" : parts.joined(separator: ", ")
    }
}

extension Browser {
    /// ⌥⌘B, the menu's Show Bookmarks, the bar's: the place, the same key
    /// again putting it away.
    func showBookmarks() {
        openPlace(.bookmarks)
    }

    // MARK: the rows

    /// The folder open now: its folders, then its sites. With words, all
    /// that answers to them under it, a heading for each folder they are in.
    func bookmarkItems() -> [PlaceItem] {
        let words = typed.lowercased().split(separator: " ").map(String.init)
        let here = query.stock.folder
        let kids = here.flatMap { bookmarks.node($0)?.children } ?? bookmarks.roots
        var out: [PlaceItem] = []
        if query.stock.recent {
            for (node, folder) in Bookmarks.recent(bookmarks.roots) {
                let hay = (node.title + " " + (node.url ?? "")).lowercased()
                guard words.allSatisfy({ hay.contains($0) }), let added = node.added else { continue }
                var item = bookmarkItem(node, section: Browser.day(added))
                if let folder { item.source += " · in " + folder.title }
                out.append(item)
            }
        } else if words.isEmpty {
            let section = bookmarks.path(of: here)
            for node in kids.filter(\.isFolder) + kids.filter({ !$0.isFolder }) {
                out.append(bookmarkItem(node, section: section))
            }
        } else {
            // Kept together by the folder they are in, in the tree's order.
            var order: [String] = []
            var found: [String: [PlaceItem]] = [:]
            func walk(_ nodes: [Bookmark], _ path: String) {
                for node in nodes {
                    let hay = (node.title + " " + (node.url ?? "")).lowercased()
                    if words.allSatisfy({ hay.contains($0) }) {
                        if found[path] == nil { order.append(path) }
                        found[path, default: []].append(bookmarkItem(node, section: path))
                    }
                    if let children = node.children { walk(children, path + " › " + node.title) }
                }
            }
            walk(kids, bookmarks.path(of: here))
            out = order.flatMap { found[$0] ?? [] }
        }
        // A folder being made stands first, as a new card does.
        if let edit = query.edit, edit.new, case .folder = edit.kind {
            let name = edit.value("title")
            out.insert(PlaceItem(id: "draft", section: bookmarks.path(of: here), title: name.isEmpty ? "New Folder" : name,
                                 tile: .symbol("folder.badge.plus"), what: .draft), at: 0)
        }
        return out
    }

    private func bookmarkItem(_ node: Bookmark, section: String) -> PlaceItem {
        if node.isFolder {
            return PlaceItem(id: "bookmark." + node.id.uuidString, section: section, title: node.title,
                             source: Bookmarks.holding(node), tile: .symbol("folder"), what: .bookmark(node))
        }
        let url = node.url.flatMap(URL.init(string:))
        let pretty = url.map(Address.pretty) ?? node.url ?? ""
        // The page's own icon, as History's pull-down list draws its rows,
        // not only its host's: a slideshow's bookmark wears Slides.
        return PlaceItem(id: "bookmark." + node.id.uuidString, section: section, title: node.title.isEmpty ? pretty : node.title,
                         source: pretty, tile: url.map(PlaceTile.page) ?? .site(""), search: node.url ?? "", what: .bookmark(node))
    }

    // MARK: going in and out

    /// Into a folder, its first row chosen.
    func openFolder(_ id: Bookmark.ID?) {
        query.stock.folder = id
        query.stock.recent = false
        query.spot = 0
        query.unpick()
        query.stock.version += 1
        if !typed.isEmpty { typed = "" }
    }

    /// Esc, or ⌫ in the empty field: up to the folder around this one,
    /// the one just left chosen. False at the top.
    func upFolder() -> Bool {
        guard query.place == .bookmarks else { return false }
        if query.stock.recent {
            openFolder(nil)
            return true
        }
        guard let here = query.stock.folder else { return false }
        let above = bookmarks.trail(to: here)?.dropLast().last?.id
        query.stock.folder = above
        query.stock.version += 1
        query.spot = placeItems.firstIndex { $0.id == "bookmark." + here.uuidString } ?? 0
        return true
    }

    /// Recently Added, from the folder menu: its newest first chosen.
    func openRecent() {
        query.stock.folder = nil
        query.stock.recent = true
        query.spot = 0
        query.stock.version += 1
        if !typed.isEmpty { typed = "" }
    }

    /// ⌘N: a folder in the one open, or at the top from Recently Added,
    /// the list turning to where it will be.
    func newBookmarkFolder() {
        if query.stock.recent { openFolder(nil) }
        beginEdit(.folder(in: query.stock.folder))
    }

    // MARK: what a row can have done to it

    func bookmarkActions(_ node: Bookmark) -> [FieldAction] {
        var out: [FieldAction] = []
        if node.isFolder {
            let urls = Bookmarks.urls(node.children ?? [])
            out.append(FieldAction(id: "open", title: "Open Folder", symbol: "yab.folder.right") { self.openFolder(node.id) })
            if !urls.isEmpty {
                out.append(FieldAction(id: "all", title: urls.count == 1 ? "Open Its Bookmark in a Tab" : "Open All \(urls.count) in Tabs",
                                       symbol: urls.count == 1 ? "plus.tab" : "yab.tabs.out", group: 1) {
                    self.close()
                    for (index, url) in urls.enumerated() { self.open(url, foreground: index == 0) }
                })
            }
            out.append(FieldAction(id: "edit", title: "Rename Folder", keys: Keymap.shared.text(.fieldEdit), symbol: "pencil", group: 2) {
                self.beginEdit(.bookmark(node.id))
            })
        } else if let url = node.url.flatMap(URL.init(string:)) {
            let asking = self.asking
            out.append(FieldAction(id: "open", title: self.openWords(asking), symbol: self.openSymbol(asking), image: ActionIcons.site(url)) {
                self.close()
                self.place(url, asking, from: self.active)
            })
            out.append(FieldAction(id: "copy", title: "Copy URL", keys: Keymap.shared.text(.fieldCopy), symbol: "link", group: 1) {
                self.copyPlain(url.absoluteString)
            })
            out.append(FieldAction(id: "second", title: "Copy Markdown Link", keys: Keymap.shared.text(.fieldSecond), symbol: "markdown", group: 1) {
                self.copyPlain("[\(node.title)](\(url.absoluteString))")
            })
            out.append(FieldAction(id: "plain", title: "Open in Background Tab", keys: Keymap.shared.text(.fieldAlternate), symbol: "yab.tab.down", group: 1) {
                self.close()
                self.open(url, foreground: false, from: self.active)
            })
            out.append(FieldAction(id: "edit", title: "Edit Bookmark", keys: Keymap.shared.text(.fieldEdit), symbol: "pencil", group: 2) {
                self.beginEdit(.bookmark(node.id))
            })
        }
        out.append(contentsOf: moveActions(node))
        out.append(removeAction(node))
        out.append(contentsOf: bookmarksKit())
        return out
    }

    /// Move To each folder it can go into, the top of the list among them,
    /// and a step up or down among its neighbors while a folder is listed.
    private func moveActions(_ node: Bookmark) -> [FieldAction] {
        var out: [FieldAction] = []
        let trail = bookmarks.trail(to: node.id) ?? []
        let parent = trail.dropLast().last
        if typed.isEmpty, !query.stock.recent {
            let siblings = parent?.children ?? bookmarks.roots
            // Among the rows as they are listed: folders first, then sites.
            let listed = siblings.filter { $0.isFolder == node.isFolder }
            if let at = listed.firstIndex(where: { $0.id == node.id }) {
                if at > 0 {
                    out.append(FieldAction(id: "up", title: "Move Up", symbol: "yab.up", group: 3) {
                        self.bookmarks.move(node.id, into: parent?.id, before: listed[at - 1].id)
                        self.query.spot = max(0, self.query.spot - 1)
                    })
                }
                if at < listed.count - 1 {
                    out.append(FieldAction(id: "down", title: "Move Down", symbol: "yab.down", group: 3) {
                        // Just after the next one: in front of whatever
                        // follows it, or at the end.
                        let next = siblings.firstIndex { $0.id == listed[at + 1].id } ?? siblings.count - 1
                        let after = next + 1 < siblings.count ? siblings[next + 1].id : nil
                        self.bookmarks.move(node.id, into: parent?.id, before: after)
                        self.query.spot += 1
                    })
                }
            }
        }
        if parent != nil {
            out.append(FieldAction(id: "move.top", title: "Move to Bookmarks", symbol: "yab.bookmark.right", group: 3) {
                self.bookmarks.move(node.id, into: nil)
            })
        }
        // Never into itself, nor into a folder inside it.
        let inside = Set(Bookmarks.folders([node]).map(\.node.id))
        for (folder, _) in Bookmarks.folders(bookmarks.roots) where folder.id != parent?.id && !inside.contains(folder.id) {
            out.append(FieldAction(id: "move." + folder.id.uuidString, title: "Move to \(folder.title)", symbol: "yab.bookmark.right", group: 3) {
                self.bookmarks.move(node.id, into: folder.id)
            })
        }
        return out
    }

    /// A site goes at once, as it went on the page; a folder with sites in
    /// it is asked about first.
    private func removeAction(_ node: Bookmark) -> FieldAction {
        let inside = node.isFolder ? Bookmarks.count(node.children ?? []) : 0
        let title = node.isFolder ? (inside > 0 ? "Remove Folder…" : "Remove Folder") : "Remove Bookmark"
        return FieldAction(id: "delete", title: title, keys: Keymap.shared.text(.fieldDelete), symbol: "trash", group: 3) {
            guard inside > 0 else {
                self.did(self.bookmarks.removeUndoably(node.id))
                self.query.spot = min(self.query.spot, max(0, self.placeItems.count - 1))
                return
            }
            self.close()
            Task { @MainActor in
                let yes = await Questions.shared.ask(Question(
                    title: "Remove \(node.title) and \(inside == 1 ? "its bookmark" : "its \(inside.formatted()) bookmarks")?",
                    detail: "Everything in the folder goes with it.",
                    glyph: "trash", yes: "Remove", danger: true
                ))
                if yes { self.did(self.bookmarks.removeUndoably(node.id)) }
            }
        }
    }

    /// The whole list's own: a new folder here, and more brought in.
    private func bookmarksKit() -> [FieldAction] {
        [FieldAction(id: "new", title: "New Folder", keys: Keymap.shared.text(.fieldNew), symbol: "yab.folder.plus", group: 4) { self.newBookmarkFolder() },
         FieldAction(id: "more", title: "Bring In More…", symbol: "tray.and.arrow.down", group: 4) { self.bringMore() }]
    }

    // MARK: writing

    /// ⌘E's fields: a name, and a site's address.
    func bookmarkLines(_ id: Bookmark.ID) -> (String, [PlaceEdit.Line]) {
        let node = bookmarks.node(id)
        var lines = [PlaceEdit.Line(key: "title", label: "Name", value: node?.title ?? "", hint: node?.isFolder == true ? "The folder’s name" : "As the list shows it")]
        if let node, !node.isFolder {
            lines.append(PlaceEdit.Line(key: "url", label: "Address", value: node.url ?? "", hint: "https://…"))
        }
        return (node?.title ?? "Bookmark", lines)
    }

    /// ↩ on a bookmark or a folder being written: kept, or why not.
    func saveBookmark(_ edit: PlaceEdit, wrong: (String, String) -> Void) {
        let title = edit.value("title")
        switch edit.kind {
        case .bookmark(let id):
            guard let node = bookmarks.node(id) else { return wrong("title", "It isn’t kept any more.") }
            var url: String?
            if !node.isFolder {
                guard let typed = Address.url(from: edit.value("url"), names: false), Bookmark.keepable(typed) else {
                    return wrong("url", "Write the address as a page has it: https://example.com.")
                }
                url = typed.absoluteString
            }
            guard !title.isEmpty || !node.isFolder else { return wrong("title", "A folder needs a name.") }
            bookmarks.update(id, title: title.isEmpty ? url.flatMap(URL.init(string:)).map(Address.pretty) ?? node.title : title, url: url)
            finishEdit(select: "bookmark." + id.uuidString)
        case .folder(let parent):
            guard !title.isEmpty else { return wrong("title", "A folder needs a name.") }
            let made = bookmarks.insert(.folder(title, []), into: parent)
            finishEdit(select: "bookmark." + made.id.uuidString)
        default:
            break
        }
    }

    // MARK: empty

    func bookmarksEmpty(words: String) -> PlaceEmpty {
        let place = FieldPlace.bookmarks
        let add = Keymap.shared.text(.bookmark)
        let keep = add.isEmpty ? "Keep a page" : "Keep a page with \(add)"
        let kept = add.isEmpty ? "Pages you keep" : "Pages you keep with \(add)"
        let actions = Keymap.shared.text(.fieldActions)
        let move = actions.isEmpty ? "choose Move" : "\(actions) › Move"
        let newFolder = FieldAction(id: "new", title: "New Folder", keys: Keymap.shared.text(.fieldNew), symbol: "yab.folder.plus") { self.newBookmarkFolder() }
        let here = query.stock.folder.flatMap { bookmarks.node($0) }
        if query.stock.recent {
            let back = FieldAction(id: "back", title: "Back", symbol: "yab.chevleft") { _ = self.upFolder() }
            if !words.isEmpty {
                return PlaceEmpty(place: place, searching: true, title: "Nothing for “\(words)” in Recently Added",
                                  detail: "Bookmarks with no date are only in their folders.",
                                  actions: [FieldAction(id: "all", title: "Search All Bookmarks", symbol: "yab.bookmark.search") {
                                      self.query.stock.recent = false
                                      self.query.spot = 0
                                      self.query.stock.version += 1
                                  }])
            }
            return PlaceEmpty(place: place, searching: false, title: "Nothing added lately",
                              detail: "\(kept) come here, newest first. Bookmarks with no date are only in their folders.",
                              actions: [back])
        }
        if !words.isEmpty {
            if let here {
                return PlaceEmpty(place: place, searching: true, title: "Nothing for “\(words)” in \(here.title)",
                                  detail: "It may be in another folder.",
                                  actions: [FieldAction(id: "all", title: "Search All Bookmarks", symbol: "yab.bookmark.search") {
                                      self.query.stock.folder = nil
                                      self.query.spot = 0
                                      self.query.stock.version += 1
                                  }])
            }
            return PlaceEmpty(place: place, searching: true, title: "Nothing for “\(words)”",
                              detail: "Bookmarks are found by their name and their address.")
        }
        if let here {
            return PlaceEmpty(place: place, searching: false, title: "Nothing in \(here.title)",
                              detail: "\(keep), then \(move) to \(here.title). Esc goes back.",
                              actions: [newFolder, FieldAction(id: "back", title: "Back", symbol: "yab.chevleft") { _ = self.upFolder() }])
        }
        // Nothing kept at all: the browsers to bring them from, as
        // Passwords has it, and a folder to start with.
        let sources = placeSources(place)
        let chosen = sources[min(query.spot, sources.count - 1)]
        return PlaceEmpty(place: place, searching: false, title: "Your bookmarks, kept by Yab",
                          detail: "Press \(add) on a page to keep it. Folders to file them in, and every one found here by its name or its site.",
                          footnote: chosen.icon != nil && chosen.name != "Safari" ? "Folders come as they are. Nothing changes in \(chosen.name)." : nil,
                          sources: sources, actions: [chosen.take, newFolder])
    }

    /// Every browser on this Mac with bookmarks, counted off the main thread.
    func countBookmarkSources() {
        query.stock.sources = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let found: [(Chromium.Source, Int)] = Chromium.installed().compactMap { source in
                let count = Bookmarks.count(Chromium.bookmarks(in: source))
                return count > 0 ? (source, count) : nil
            }.sorted { $0.1 > $1.1 }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.query.place == .bookmarks else { return }
                self.query.stock.sources = found.map { source, count in
                    PlaceSource(name: source.name, icon: source.icon, detail: "\(count)",
                                take: FieldAction(id: "bring", title: "Bring In from \(source.name)", symbol: "yab.bookmark.dl") {
                                    self.bringBookmarks(source)
                                })
                }
            }
        }
    }

    /// A browser's bookmarks, folders as they are, merged with any brought
    /// from it before; the count is said as the bar's import says it.
    private func bringBookmarks(_ source: Chromium.Source) {
        query.stock.bringing = source.name
        takeBookmarks(from: source.authorizingImport()) { [weak self] _ in
            guard let self, self.query.place == .bookmarks else { return }
            self.query.stock.bringing = nil
            _ = self.leaveMore()
            self.restock()
        }
    }
}
