import AppKit
import SwiftUI
import Testing
import WebKit
@testable import Fast

/// Actual TabMenu -> NSHostingMenu -> ActionMenuList, plus the composed
/// command-field offers. No menu opening, page materialization or account.
@MainActor @Suite(.serialized)
struct KeptPageMenuTests {
    init() throws {
        try #require(Store.testing && Store.world != nil && Store.settings !== UserDefaults.standard)
        _ = NSApplication.shared
    }

    private func withBrowser(_ body: (Browser, (String) -> Fast.Tab) throws -> Void) rethrows {
        let keys = ["mail", "search.suggest", FieldRequest.key, "field.compact", MenuCommands.key, "shortcuts"]
        let saved = keys.map { Store.settings.object(forKey: $0) }
        let commands = FieldUnder.shared.commands
        let foldersBrowser = Folders.shared.browser
        defer {
            FieldUnder.shared.commands = commands
            Folders.shared.browser = foldersBrowser
            for (key, value) in zip(keys, saved) {
                if let value { Store.settings.set(value, forKey: key) }
                else { Store.settings.removeObject(forKey: key) }
            }
            Keymap.shared.adoptStored()
        }
        Store.settings.set(false, forKey: "mail")
        Store.settings.set(false, forKey: "search.suggest")
        Store.settings.set(false, forKey: FieldRequest.key)
        Store.settings.set(true, forKey: "field.compact")
        Store.settings.set(true, forKey: MenuCommands.key)
        Store.settings.set([String: String](), forKey: "shortcuts")
        Keymap.shared.adoptStored()
        FieldUnder.shared.commands = true
        let id = UUID(), browser = Browser(windowID: id)
        browser.lookForMailSignInLink = {}
        browser.dropSpare()
        browser.history = History([])
        var made: [Fast.Tab] = []
        func page(_ path: String) -> Fast.Tab {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let tab = Fast.Tab(bench: true, configuration: configuration)
            tab.restore(url: URL(string: "https://kept-menu.fixture.invalid/" + path)!, title: "Owned menu page")
            browser.prepare(tab)
            made.append(tab)
            return tab
        }
        defer {
            browser.cancelTabEdit()
            for tab in made where !tab.gone { tab.close() }
            browser.letGo()
            browser.dropSpare()
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
            for prefix in ["session", "spaces"] {
                try? FileManager.default.removeItem(at: Store.file("\(prefix)-window-\(id.uuidString).json"))
            }
        }
        try body(browser, page)
        #expect(made.allSatisfy { $0.builtPage == nil && !$0.store.isPersistent })
    }

    @Test func leftTrailPinCommandsLeadHistoryAndPersist() throws {
        try withBrowser { browser, page in
            let path = UUID().uuidString
            let tab = page(path), independent = page(path)
            let url = try #require(tab.address)
            let sidebar = browser.prefs.sidebar, spaces = browser.prefs.usesSpaces
            defer {
                TrailApps.shared.remove(url)
                browser.prefs.sidebar = sidebar
                browser.prefs.usesSpaces = spaces
            }
            browser.prefs.sidebar = true
            browser.prefs.usesSpaces = true
            browser.lay([tab])
            browser.activeID = tab.id
            for command in [Command.pinTrailApp, .unpinTrailApp] {
                browser.history = History([Visit(url: "https://history.fixture.invalid/menu", key: "history.fixture.invalid/menu",
                                                 title: command.title, count: 5, last: Date())])
                let menu = NSHostingMenu(rootView: TabMenu(browser: browser, tab: tab, close: {}))
                menu.update()
                #expect(menu.items.contains { $0.title == command.title })
                browser.replaceTyped(command.title)
                #expect(browser.offers.first?.kind == .command(command))
                command.run(in: browser)
                if command == .pinTrailApp {
                    TrailApps.shared.pin(tab)
                    #expect(TrailApps.shared.apps.filter { $0.id == url }.count == 1)
                }
                #expect(TrailApps(defaults: Store.settings).contains(url) == (command == .pinTrailApp))
                let restored = TrailApps(defaults: Store.settings)
                let visible = restored.sidebarTabs([tab, independent])
                #expect(visible.contains { $0 === tab } == (command == .unpinTrailApp))
                #expect(visible.contains { $0 === independent })
                #expect(browser.tabs.contains { $0 === tab })
            }
        }
    }

    @Test func legacyRailPinAdoptsOneMatchingTab() throws {
        try withBrowser { browser, page in
            let path = UUID().uuidString, suite = UUID().uuidString
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let original = page(path), duplicate = page(path)
            let url = try #require(original.address)
            defaults.set(try JSONEncoder().encode([["id": url.absoluteString, "title": "App"]]), forKey: "sidebar.pinnedApps")
            let pins = TrailApps(defaults: defaults)
            browser.lay([original, duplicate])
            #expect(pins.sidebarTabs(browser.tabs).map(\.id) == [duplicate.id])
            pins.pin(original)
            #expect(browser.tabs.count == 2)
            #expect(TrailApps(defaults: defaults).sidebarTabs([duplicate, original]).map(\.id) == [duplicate.id])
        }
    }

    @Test func tabOverviewLeadsExactCommandSearch() throws {
        try withBrowser { browser, _ in
            let command = Command.tabOverview
            _ = try #require(LibraryPage(url: URL(string: "yab://tabs")) == .tabs)
            for query in [command.title, "All Tabs"] {
                browser.history = History([Visit(url: "https://history.fixture.invalid/tabs", key: "history.fixture.invalid/tabs",
                                                 title: query, count: 5, last: Date())])
                browser.replaceTyped(query)
                #expect(browser.offers.first?.kind == .command(command))
            }
        }
    }

    private func list(_ tab: Fast.Tab, in browser: Browser) -> ActionMenuList {
        ActionMenuList(menu: NSHostingMenu(rootView: TabMenu(browser: browser, tab: tab, close: {})), falls: true)
    }

    private func editMenu(_ tab: Fast.Tab, in browser: Browser) throws -> NSMenu {
        let menu = list(tab, in: browser)
        return try #require(menu.lines.first { $0.title == (tab.pin == nil ? "Edit Kept Page" : "Edit Pinned Page") }?.submenu)
    }

    @Test(arguments: [false, true])
    func theExistingHomeSubmenuIsVisibleImmediatelyAfterRename(pinned: Bool) throws {
        try withBrowser { browser, page in
            let tab = page("home"), current = page("current")
            if pinned { tab.pin = "K" } else { tab.kept = true }
            browser.lay([tab, current])
            browser.activeID = current.id
            let menu = list(tab, in: browser)
            let title = pinned ? "Edit Pinned Page" : "Edit Kept Page"
            let rename = try #require(menu.lines.firstIndex { $0.title == "Rename…" })
            let home = try #require(menu.lines.firstIndex { $0.title == title })
            #expect(home == rename + 1)
            #expect(menu.lines.filter { $0.title == title }.count == 1)
            #expect(menu.lines[home].image === MenuMark.image("yab.page.pen"))
            let submenu = try #require(menu.lines[home].submenu)
            submenu.update()
            let replacement = pinned ? "Replace Pinned Address with Current" : "Replace Kept Address with Current"
            #expect(submenu.items.map(\.title) == [replacement, "Edit…"])
            #expect(submenu.items.first?.isEnabled == false)
            #expect(browser.activeID == current.id && tab.asleep && tab.builtPage == nil)
            menu.modifiers(.option)
            #expect(menu.lines.filter { $0.title == title }.count == 1)
            menu.query = title
            #expect(menu.lines.filter { $0.title == title }.count == 1)
            #expect(browser.activeID == current.id && tab.builtPage == nil)
        }
    }

    @Test func normalMultipleAndSplitMenusDoNotGainASinglePageEditor() throws {
        try withBrowser { browser, page in
            let a = page("a"), b = page("b")
            browser.lay([a, b]); browser.activeID = a.id
            @MainActor func noEditor(_ menu: ActionMenuList) {
                #expect(!menu.lines.contains { $0.title == "Edit Kept Page" || $0.title == "Edit Pinned Page" })
            }
            noEditor(list(a, in: browser))
            a.kept = true; b.kept = true
            browser.pickAll()
            try #require(browser.several)
            noEditor(list(a, in: browser))
            browser.pairs = [Pair(first: a.id, second: b.id)]
            noEditor(list(a, in: browser))
        }
    }

    @Test(arguments: [false, true])
    func actualEditHandlerKeepsCancelAndReturnHomeSemantics(pinned: Bool) throws {
        try withBrowser { browser, page in
            let tab = page("away")
            if pinned { tab.pin = "K" } else { tab.kept = true }
            let home = URL(string: "https://kept-menu.fixture.invalid/home")!
            tab.home = home
            browser.lay([tab]); browser.activeID = tab.id
            let submenu = try editMenu(tab, in: browser)
            submenu.update()
            #expect(submenu.items.first?.isEnabled == true)
            let edit = try #require(submenu.items.firstIndex { $0.title == "Edit…" })
            submenu.performActionForItem(at: edit)
            #expect(browser.editingTab == tab.id && browser.editingHome && browser.tabDraft == home.absoluteString)
            browser.tabDraft = "https://kept-menu.fixture.invalid/cancelled"
            browser.cancelTabEdit()
            #expect(tab.home == home && browser.editingTab == nil && !browser.editingHome)
            submenu.performActionForItem(at: edit)
            let newHome = URL(string: "https://kept-menu.fixture.invalid/new-home")!
            browser.tabDraft = newHome.absoluteString
            browser.commitTabEdit()
            #expect(tab.home == newHome && browser.editingTab == nil && !browser.editingHome)
            #expect(tab.address?.path == "/away" && browser.activeID == tab.id)
            #expect(tab.pin == (pinned ? "K" : nil) && tab.kept == !pinned)
        }
    }

    @Test(arguments: [false, true])
    func exactVisibleMenuNameLeadsComposedHistoryAndSuggestionsAndActions(pinned: Bool) throws {
        try withBrowser { browser, page in
            let tab = page("home")
            if pinned { tab.pin = "K" } else { tab.kept = true }
            browser.lay([tab]); browser.activeID = tab.id
            let words = pinned ? "Edit Pinned Page" : "Edit Kept Page"
            browser.history = History([Visit(url: "https://history.fixture.invalid/menu", key: "history.fixture.invalid/menu",
                                             title: words + " tutorial", count: 5, last: Date())])
            browser.replaceTyped(words)
            try #require(browser.offers.contains { $0.kind == .visited })
            #expect(browser.offers.first?.kind == .command(.editPinnedURL))
            #expect(browser.ending == nil)
            let suggested = Suggestion(key: words + " tutorial", title: "", url: URL(string: "https://search.fixture.invalid/"), kind: .suggested)
            let merged = SearchSuggestions.merge([suggested], into: browser.offers, lead: 0)
            #expect(merged.list.contains { $0.kind == .suggested })
            #expect(merged.list.first?.kind == .command(.editPinnedURL))
            browser.replaceTyped("")
            try #require(browser.enterActions())
            #expect(browser.offers.contains { $0.kind == .command(.editPinnedURL) })
            browser.replaceTyped(words)
            #expect(browser.offers.first?.kind == .command(.editPinnedURL))
            Command.editPinnedURL.run(in: browser)
            #expect(browser.editingTab == tab.id && browser.editingHome)
            browser.cancelTabEdit()
            tab.pin = nil; tab.kept = false
            browser.guessAgain()
            #expect(!Command.editPinnedURL.available(in: browser))
            #expect(!browser.offers.contains { $0.kind == .command(.editPinnedURL) })
        }
    }

    @Test func neighboringRenameKeepsItsRemappedKeyInNativeMenuAndCommandField() throws {
        try withBrowser { browser, page in
            let tab = page("home")
            tab.kept = true
            browser.lay([tab]); browser.activeID = tab.id
            let key = Hotkey("y", [.control, .option, .command])
            Keymap.shared.set(key, for: .rename)
            let menu = list(tab, in: browser)
            let rename = try #require(menu.lines.first { $0.title == "Rename…" })
            #expect(rename.keys == key.text)
            #expect(Command.renameTab.keys == key.text)
            browser.replaceTyped("Rename Tab")
            let offer = try #require(browser.offers.first { $0.kind == .command(.renameTab) })
            #expect(offer.title == key.text)
            // Address editing already has no catalog shortcut; exposing its
            // existing submenu must not borrow Rename's or create one.
            #expect(Command.editPinnedURL.keys.isEmpty)
            #expect(menu.lines.first { $0.title == "Edit Kept Page" }?.keys.isEmpty == true)
        }
    }
}
