import AppKit
import Testing
@testable import Fast

@MainActor @Suite(.serialized)
struct FieldRankTests {
    private func withBrowser(_ body: (Browser, Tab) throws -> Void) rethrows {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let tab = Tab(later: .nonPersistent())
        tab.restore(url: URL(string: "https://fixture.example/")!, title: "Fixture")
        browser.lay([tab])
        browser.activeID = nil
        let suggest = browser.prefs.searchSuggest
        let requests = browser.prefs.fieldRequests
        let menu = browser.prefs.menuCommands
        let live = browser.prefs.usesLiveFolders
        let under = FieldUnder.shared
        let matches = (under.tabs, under.pages, under.commands)
        browser.prefs.searchSuggest = false
        browser.prefs.fieldRequests = false
        browser.prefs.menuCommands = true
        browser.prefs.usesLiveFolders = true
        under.tabs = true; under.pages = true; under.commands = true
        browser.history = History([])
        browser.openFresh()
        defer {
            tab.close(); browser.dismiss(); browser.letGo()
            browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
            browser.prefs.searchSuggest = suggest
            browser.prefs.fieldRequests = requests
            browser.prefs.menuCommands = menu
            browser.prefs.usesLiveFolders = live
            under.tabs = matches.0; under.pages = matches.1; under.commands = matches.2
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            }
        }
        try body(browser, tab)
    }

    private func merged(_ browser: Browser, _ words: String) -> (list: [Suggestion], lead: Int?) {
        SearchSuggestions.merge([Suggestion(key: words + " news", title: "", url: nil, kind: .suggested)],
                                into: browser.offers, lead: browser.query.lead)
    }

    @Test func profileLibraryCommandsLeadHistoryAndWebSuggestions() throws {
        try withBrowser { browser, _ in
            browser.prefs.menuCommands = false
            for (command, page) in MenuCommands.profileLibraries {
                let url = URL(string: "https://fixture.example/" + page.rawValue)!
                for words in [command.title, page.title + " Library"] {
                    browser.history = History([Visit(url: url.absoluteString, key: Address.pretty(url),
                                                     title: words, count: 100, last: Date(), typed: 50)])
                    browser.replaceTyped(words)
                    #expect(browser.offers.first?.kind == .command(command), "\(words)")
                    #expect(browser.offers.contains { $0.url == url })
                    let result = merged(browser, words)
                    #expect(result.list.first?.kind == .command(command))
                    #expect(result.list.contains { $0.kind == .suggested })
                    #expect(result.lead == 0)
                }
            }
        }
    }

    @Test func sitePrefixesLeadLiveFolderCreationInEveryProvider() throws {
        try withBrowser { browser, tab in
            for (words, host) in [("you", "youtube.com"), ("git", "github.com"), ("x", "x.com")] {
                let url = URL(string: "https://" + host + "/")!
                for source in ["history", "open", "bookmark"] {
                    browser.history = History([Visit(url: url.absoluteString, key: host, title: host,
                                                     count: 100, last: Date(), typed: 50)])
                    tab.restore(url: source == "open" ? url : URL(string: "https://fixture.example/")!,
                                title: source == "open" ? host : "Fixture")
                    let bookmark = source == "bookmark" ? browser.bookmarks.add(url, title: host) : nil
                    defer { if let bookmark { browser.bookmarks.remove(bookmark) } }
                    browser.replaceTyped(words)
                    let result = merged(browser, words)
                    #expect(result.list.first?.url == url, "\(words): \(source)")
                    #expect(result.lead == 0)
                    let site = try #require(result.list.firstIndex { $0.url == url })
                    for i in result.list.indices where result.list[i].menuTargetID != nil {
                        #expect(site < i)
                    }
                }
            }
        }
    }

    @Test func titleMatchesStayBelowSearchDespiteFrecency() throws {
        try withBrowser { browser, tab in
            browser.prefs.usesLiveFolders = false
            let url = URL(string: "https://play.google.com/console")!
            tab.restore(url: url, title: "Google Play Console")
            tab.name = "Google work folder"
            tab.kept = true
            browser.history = History([Visit(url: url.absoluteString, key: Address.pretty(url),
                                             title: "Google Play Console", count: 10000, last: Date(), typed: 100)])
            for words in ["google", "work folder", "play console"] {
                browser.replaceTyped(words)
                let result = merged(browser, words)
                let search = try #require(result.list.firstIndex { $0.kind == .search })
                let opened = try #require(result.list.firstIndex { $0.tab == tab.id })
                #expect(search < opened, "\(words)")
                // A known site's own name may still navigate to that site;
                // a title-only match must never steal Return from it.
                #expect(result.list[result.lead ?? 0].tab != tab.id)
                if words != "google" { #expect(result.list.first?.kind == .search) }
                let web = try #require(result.list.firstIndex { $0.kind == .suggested })
                #expect(opened < web)
            }
            // Exact addresses still switch to the existing tab.
            browser.replaceTyped("play.google.com/console")
            #expect(browser.offers.first?.tab == tab.id)
            #expect(browser.query.lead == 0)
        }
    }

    @Test func aTitleMatchCannotBypassSingleLetterVisitRules() throws {
        try withBrowser { browser, tab in
            tab.restore(url: URL(string: "https://frequency.example/")!, title: "Unrelated")
            for (path, count, typed, navigates) in [("/deep", 1000, 0, false), ("/deep", 2, 2, true),
                                                    ("/", 1, 0, false), ("/", 3, 0, true)] {
                let url = URL(string: "https://q-rare-unit.invalid" + path)!
                browser.history = History([Visit(url: url.absoluteString, key: Address.pretty(url), title: "Quiet page",
                                                 count: count, last: Date(), typed: typed)])
                browser.replaceTyped("q")
                if navigates { #expect(browser.offers.first?.url == url) }
                else { #expect(browser.offers.first?.kind == .search) }
            }
            // Removing an inline ending is still a request to search.
            browser.replaceTyped("q", completing: false)
            #expect(browser.offers.first?.kind == .search)
        }
    }

    @Test func titleMatchesRespectTheConfiguredRowsUnderWords() throws {
        try withBrowser { browser, tab in
            let under = FieldUnder.shared
            let rows = under.rows
            let firstRow = under.firstRow
            defer { under.rows = rows; under.firstRow = firstRow }
            under.rows = [FieldUnder.place(.history), FieldUnder.search, FieldUnder.ask, FieldUnder.task]
            under.firstRow = true
            tab.restore(url: URL(string: "https://console.example.test/project")!, title: "Project control panel")
            browser.replaceTyped("project control")
            let result = merged(browser, "project control")
            let search = try #require(result.list.firstIndex { $0.kind == .search })
            let history = try #require(result.list.firstIndex { $0.kind == .within(.history) })
            let opened = try #require(result.list.firstIndex { $0.tab == tab.id })
            #expect(history < search)
            #expect(search < opened)
        }
    }

    @Test func bookmarkTitleDoesNotReplaceTheQuery() throws {
        try withBrowser { browser, _ in
            browser.prefs.usesLiveFolders = false
            let url = URL(string: "https://console.example.test/project")!
            let bookmark = browser.bookmarks.add(url, title: "Google Play Console")
            defer { if let bookmark { browser.bookmarks.remove(bookmark) } }
            browser.replaceTyped("google")
            let result = merged(browser, "google")
            let search = try #require(result.list.firstIndex { $0.kind == .search })
            let saved = try #require(result.list.firstIndex { $0.url == url })
            #expect(search < saved)
            #expect(result.list[result.lead ?? 0].url != url)
        }
    }

    @Test func creationRemainsDiscoverableWithItsOwnShortcutAndAvailability() throws {
        try withBrowser { browser, _ in
            browser.replaceTyped("new folder")
            #expect(browser.offers.contains { $0.kind == .command(.newFolder) })
            let targets = MenuCommands.targets(.newLiveFolder, in: browser)
            let indexed = Set(MenuCommands.targets(in: browser).map(\.id))
            #expect(!targets.isEmpty)
            for target in targets {
                #expect(!target.opens)
                #expect(target.offer.title.isEmpty)
                #expect(target.score("new folder") != nil)
                // Pull Requests intentionally uses its existing typed Command
                // in the field, rather than a duplicate dynamic target.
                if !indexed.contains(target.id) {
                    #expect(target.id == "newLiveFolder:github.pulls")
                    continue
                }
                browser.replaceTyped(target.title)
                #expect(browser.offers.first?.menuTargetID == target.id)
                #expect(browser.query.lead == 0)
            }
            browser.replaceTyped(Command.pullRequestsFolder.title)
            #expect(browser.offers.contains { $0.kind == .command(.pullRequestsFolder) })
            browser.prefs.usesLiveFolders = false
            #expect(MenuCommands.targets(.newLiveFolder, in: browser).isEmpty)
        }
    }
}
