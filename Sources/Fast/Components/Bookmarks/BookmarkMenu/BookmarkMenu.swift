import AppKit
import SwiftUI

/// The bookmarks in the menu bar's Bookmarks menu, made by AppKit rather
/// than SwiftUI. SwiftUI makes a menu bar's items all at once, folders and
/// all, before the app has finished launching: 1,500 bookmarks, as a Chrome
/// import brings, held the window back by a quarter of a second at every
/// launch. Here the top of the list is made as the menu opens, and a
/// folder's items as that folder opens.
///
/// SwiftUI keeps its own items, and its own delegate, which lays the menu
/// out afresh each time it opens: anything added beside them was gone by
/// then. So its delegate is wrapped: SwiftUI does its update, then the
/// bookmarks go in after it. SwiftUI puts its delegate back on every update,
/// so the wrapping is put back too (see `start`).
@MainActor
final class BookmarkMenu: NSObject, NSMenuDelegate {
    static let shared = BookmarkMenu()

    private weak var browser: Browser?
    private var watch: [Any] = []
    private let relay = Relay()
    /// What each folder's submenu holds, until it opens.
    private var folders: [ObjectIdentifier: [Bookmark]] = [:]
    /// The items put in here, among SwiftUI's own.
    fileprivate static let mark = 0x5EAC

    func start(for browser: Browser) {
        guard self.browser == nil else { return }
        self.browser = browser
        relay.after = { [weak self] menu in self?.fill(menu) }
        // SwiftUI puts its own delegate back whenever it updates the menu
        // bar. What matters is that it is wrapped when the menu bar is used,
        // so it is wrapped then, as the menu bar starts tracking, before any
        // of its menus opens. The bookmarks go in only while it is: AppKit
        // also asks a menu to update itself to look for a key's equivalent,
        // and every ⌘ key a page left unused would have rebuilt them.
        let center = NotificationCenter.default
        watch = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { [weak self] note in
                MainActor.assumeIsolated {
                    guard (note.object as? NSMenu) === NSApp.mainMenu else { return }
                    self?.relay.tracking = true
                    self?.wrap()
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: nil) { [weak self] note in
                MainActor.assumeIsolated {
                    guard (note.object as? NSMenu) === NSApp.mainMenu else { return }
                    self?.relay.tracking = false
                }
            },
        ]
        wrap()
    }

    private func wrap() {
        guard let menu = NSApp.mainMenu?.items.first(where: { $0.title == "Bookmarks" })?.submenu,
              menu.delegate !== relay
        else { return }
        relay.inner = menu.delegate
        menu.delegate = relay
    }

    /// How many items this has put in the menu, for the bench.
    var count: Int {
        NSApp.mainMenu?.items.first(where: { $0.title == "Bookmarks" })?.submenu?.items.filter { $0.tag == Self.mark }.count ?? 0
    }

    /// The top of the list, after SwiftUI's items, in place of any left
    /// from the last time.
    func fill(_ menu: NSMenu) {
        for item in menu.items where item.tag == Self.mark { menu.removeItem(item) }
        folders = [:]
        guard let roots = browser?.bookmarks.roots, !roots.isEmpty else { return }
        let line = NSMenuItem.separator()
        line.tag = Self.mark
        menu.addItem(line)
        for item in items(for: roots) { menu.addItem(item) }
    }

    /// Each line of the Bookmarks menu with its mark: a
    /// page's favicon at 16 points (the one it last wore, its site's
    /// otherwise), a folder's glyph, the site's letter until its icon is
    /// fetched. The bookmarks' row's own menus draw the same
    /// (BookmarkBar.image).
    private func items(for nodes: [Bookmark]) -> [NSMenuItem] {
        let scheme: ColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        return nodes.compactMap { node in
            let item: NSMenuItem
            if node.isFolder {
                item = NSMenuItem(title: node.title, action: nil, keyEquivalent: "")
                let sub = NSMenu(title: node.title)
                sub.delegate = self
                folders[ObjectIdentifier(sub)] = node.children ?? []
                item.submenu = sub
            } else if let text = node.url, let url = URL(string: text) {
                item = NSMenuItem(title: node.title, action: #selector(open(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = url
            } else {
                return nil
            }
            item.image = BookmarkBar.image(node, scheme: scheme)
            if !node.isFolder { node.fetchIcon() }
            item.tag = Self.mark
            return item
        }
    }

    /// A folder, opening.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let kids = folders[ObjectIdentifier(menu)] else { return }
        menu.removeAllItems()
        let made = items(for: kids)
        if made.isEmpty {
            let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for item in made { menu.addItem(item) }
    }

    @objc private func open(_ item: NSMenuItem) {
        guard let url = item.representedObject as? URL else { return }
        browser?.visit(url)
    }

    /// SwiftUI's delegate, with the bookmarks put in after its update.
    /// Everything else it answers goes straight to it.
    private final class Relay: NSObject, NSMenuDelegate {
        weak var inner: NSMenuDelegate?
        var after: ((NSMenu) -> Void)?
        /// The menu bar is open, not merely asked for a key's equivalent.
        var tracking = false

        func menuNeedsUpdate(_ menu: NSMenu) {
            inner?.menuNeedsUpdate?(menu)
            if tracking { MainActor.assumeIsolated { after?(menu) } }
        }

        func menuDidClose(_ menu: NSMenu) { inner?.menuDidClose?(menu) }

        /// Only for its own items: the bookmarks aren't SwiftUI's to know.
        func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
            guard item?.tag != BookmarkMenu.mark else { return }
            inner?.menu?(menu, willHighlight: item)
        }

        override func responds(to selector: Selector!) -> Bool {
            super.responds(to: selector) || (inner?.responds(to: selector) ?? false)
        }

        override func forwardingTarget(for selector: Selector!) -> Any? { inner }
    }
}
