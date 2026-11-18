import Foundation
import Testing
@testable import Fast

// The AppKit column's rows (ColumnLayout) stand where the SwiftUI column
// draws them: each tab's and each folder's row at the slot Folders.slots
// gives it, the slot a drag reads the rows by, a row's step apart.
@MainActor
@Suite(.serialized)
struct ColumnLayoutTests {
    private func world(_ build: (Browser) -> Void) -> (Browser, Folders) {
        let browser = Browser(windowID: UUID())
        build(browser)
        let folders = Folders(emptiesFile: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        folders.browser = browser
        folders.refresh()
        return (browser, folders)
    }

    private func close(_ browser: Browser) {
        browser.tabs.forEach { $0.close() }
        if let id = browser.windowID { try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json")) }
    }

    /// Every row ColumnLayout lays is at the slot Folders.slots says, the
    /// rows past the line as much higher as it is shorter than a row, and
    /// nothing else takes room.
    private func agrees(_ browser: Browser, _ folders: Folders) {
        let loose = browser.tabs.filter { $0.pin == nil }
        let slots = folders.slots(loose, joined: !browser.pairs.isEmpty)
        let items = ColumnLayout.live(browser, folders: folders)
        let line = slots.folders[Folders.line]
        let y = { (slot: Int?) in slot.map { ColumnLayout.y(Double($0), line: line) } }
        for item in items where item.height > 0 {
            switch item.kind {
            case .tab(let tab), .pair(let tab, _):
                #expect(y(slots.tabs[tab.id]) == item.y, "tab \(tab.title)")
            case .nest(let nest, _, _):
                #expect(y(slots.folders[nest.key]) == item.y, "folder \(nest.name)")
            case .task(let folder, _):
                #expect(y(slots.folders[folder.id]) == item.y)
            case .line:
                #expect(y(line) == item.y)
                #expect(item.height == SideBar.line)
            case .newTab:
                #expect(y(slots.folders[Folders.newTab]) == item.y)
            default:
                break
            }
            // A drag reads the slot back from where the row stands.
            if let slot = item.tab.flatMap({ slots.tabs[$0.id] }) {
                #expect(abs(ColumnLayout.slot(item.y, line: line) - Double(slot)) < 0.001)
            }
        }
        // As tall as the slots run, the last row's gap left out.
        let rows = items.filter { $0.height > 0 }.count
        let short = items.contains { if case .line = $0.kind { $0.height > 0 } else { false } } ? SideBar.lineShort : 0
        #expect(ColumnLayout.height(items) == (rows > 0 ? CGFloat(rows) * ColumnLayout.step - SideBar.gap - short : 0))
    }

    @Test func libraryPagesStayAccessibleWithoutSidebarRows() {
        let (browser, folders) = world { browser in
            _ = browser.open(URL(string: "https://example.test/history")!, foreground: true)
            for page: LibraryPage in [.tabs, .bookmarks, .history, .downloads, .extensions] {
                browser.showLibrary(page)
            }
        }
        defer { close(browser) }
        let documents = browser.tabs.filter { $0.libraryPage == nil }.map(\.id)
        #expect(documents.count == 1)
        #expect(ColumnLayout.live(browser, folders: folders).compactMap { $0.tab?.id } == documents)
        let row = Parked(tabs: browser.tabs, active: browser.activeID, pairs: [])
        #expect(ColumnLayout.parked(browser, row: row, travelling: [], space: browser.space).items.compactMap { $0.tab?.id } == documents)
        let count = browser.tabs.count
        browser.showLibrary(.bookmarks)
        #expect(browser.active?.libraryPage == .bookmarks)
        #expect(browser.tabs.count == count)
    }

    @Test func spaceSwitcherPrecedesAppTabsAndNamedPinnedRows() throws {
        let (browser, _) = world { browser in
            browser.prefs.sidebar = true
            browser.prefs.showLeftTrail = false
            browser.prefs.usesSpaces = true
            browser.prefs.spaceNames = true
            let tab = browser.open(URL(string: "https://example.test/favorite")!, foreground: true)
            _ = browser.pin(tab)
            let app = browser.open(URL(string: "https://example.test/shared-app")!, foreground: false, rowNow: true)
            TrailApps.shared.pin(app)
        }
        defer {
            TrailApps.shared.remove(URL(string: "https://example.test/shared-app")!, in: browser)
            close(browser)
        }
        let parked = Parked(tabs: browser.tabs, active: browser.activeID, pairs: [])
        for head in [ColumnLayout.head(browser),
                     ColumnLayout.parked(browser, row: parked, travelling: [], space: browser.space).head] {
            let heading = try #require(head.first { if case .name = $0.kind { true } else { false } })
            #expect(!head.contains { $0.isPin })
            #expect(browser.sidebarAppsHeight > 0)
            #expect(ColumnLayout.lead(browser, pins: 0) == heading.y + heading.height + SideBar.gap + browser.sidebarAppsHeight)
        }
        #expect(browser.sidebarLooseTabs.contains { $0.kept && $0.pin == nil })
    }

    @Test func todaysTabsAloneAreNewTabThenTheRows() {
        let (browser, folders) = world { browser in
            for n in 0..<4 { _ = browser.open(URL(string: "https://example.test/\(n)")!, foreground: n == 0) }
        }
        defer { close(browser) }
        let items = ColumnLayout.live(browser, folders: folders)
        #expect(items.map(\.id).prefix(2) == ["line", "new-tab"])
        agrees(browser, folders)
    }

    @Test func keptTabsAndFoldersStandAboveTheLine() {
        let (browser, folders) = world { browser in
            let tabs = (0..<6).map { browser.open(URL(string: "https://example.test/\($0)")!, foreground: $0 == 0) }
            let work = Nest(name: "Work", open: true)
            let inner = Nest(name: "Inner", open: true)
            inner.parent = work
            for tab in tabs.prefix(4) { tab.kept = true }
            tabs[0].nest = work
            tabs[1].nest = inner
            tabs[2].nest = inner
        }
        defer { close(browser) }
        let items = ColumnLayout.live(browser, folders: folders)
        let line = items.firstIndex { $0.id == "line" } ?? -1
        #expect(line > 0)
        #expect(items.prefix(line).allSatisfy { $0.tab.map(\.kept) ?? true })
        // A folder in a folder is a step further in, its tabs a step past it.
        let inner = items.first { if case .nest(let nest, _, _) = $0.kind { return nest.name == "Inner" } else { return false } }
        #expect(inner?.indent == Folders.indent)
        agrees(browser, folders)
    }

    @Test func aShutFolderTucksItsTabsAway() {
        let (browser, folders) = world { browser in
            let tabs = (0..<5).map { browser.open(URL(string: "https://example.test/\($0)")!, foreground: $0 == 4) }
            let shut = Nest(name: "Shut", open: false)
            for tab in tabs.prefix(3) {
                tab.kept = true
                tab.nest = shut
                // Put down: a kept link, not an open tab, which would stay
                // out under the shut folder as Arc's does (register #1022).
                tab.rest()
            }
        }
        defer { close(browser) }
        let items = ColumnLayout.live(browser, folders: folders)
        #expect(items.filter { if case .tab = $0.kind { return true } else { return false } }.count == 2)
        agrees(browser, folders)
    }

    /// An empty folder of yours put among the kept (feedback #384) is drawn
    /// just above the run it stands over, at the slot Folders.slots gives
    /// it, and stays under the row above when the one under it moves away.
    @Test func anEmptyFolderStandsWhereItWasPut() throws {
        var tabs: [Tab] = []
        let work = Nest(name: "Work", open: true)
        let (browser, _) = world { browser in
            browser.prefs.sidebar = true
            tabs = (0..<6).map { browser.open(URL(string: "https://example.test/\($0)")!, foreground: $0 == 5) }
            for tab in tabs.prefix(4) { tab.kept = true }
            tabs[2].nest = work
            tabs[3].nest = work
            browser.lay(tabs)
        }
        // The browser's own folders, which its moves and Move to Folder ask.
        let folders = Folders.shared
        let previous = folders.browser
        folders.browser = browser
        defer {
            folders.browser = previous
            close(browser)
        }
        let empty = try #require(folders.makeEmpty(named: "Empty"))
        func names() -> [String] {
            ColumnLayout.live(browser, folders: folders).compactMap { item -> String? in
                switch item.kind {
                case .tab(let tab): return tabs.firstIndex { $0 === tab }.map(String.init)
                case .nest(let nest, _, _): return nest.name
                case .line: return "line"
                default: return nil
                }
            }
        }
        // Made, at the kept's end.
        #expect(names() == ["0", "1", "Work", "2", "3", "Empty", "line", "4", "5"])
        agrees(browser, folders)

        folders.stand(empty, before: tabs[1].id)
        #expect(names() == ["0", "Empty", "1", "Work", "2", "3", "line", "4", "5"])
        agrees(browser, folders)

        // Over a folder's run: above the folder's own row.
        folders.stand(empty, before: tabs[2].id)
        #expect(names() == ["0", "1", "Empty", "Work", "2", "3", "line", "4", "5"])
        agrees(browser, folders)

        // The row above it dragged to the kept's end: it goes with nothing,
        // standing over the folder still.
        browser.move(tabs[1], to: 3)
        folders.refresh()
        #expect(names() == ["0", "Empty", "Work", "2", "3", "1", "line", "4", "5"])
        // The folder under it dragged away: it stays under the row above.
        browser.move(work, to: 2, in: nil)
        folders.refresh()
        #expect(names() == ["0", "Empty", "1", "Work", "2", "3", "line", "4", "5"])
        agrees(browser, folders)

        // A tab put in it goes in where it stands.
        browser.keepTabs([tabs[4]], in: empty)
        folders.refresh()
        #expect(tabs[4].nest === empty)
        #expect(names() == ["0", "Empty", "4", "1", "Work", "2", "3", "line", "5"])
        #expect(empty.stand == nil)
    }

    /// Where an empty folder stands once the row changed under it: the tab
    /// it stood over still there between the same two, or with only one of
    /// them changed, keeps it; moved away or gone, the head under the one
    /// above takes it.
    @Test func anEmptyFoldersPlaceFollowsTheRowAboveIt() {
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        func at(_ heads: [UUID]) -> [UUID: Int] { Dictionary(uniqueKeysWithValues: heads.enumerated().map { ($1, $0) }) }
        let stand = Nest.Stand(before: b, after: a, next: c)
        // As it was.
        #expect(Folders.resolve(stand, heads: [a, b, c, d], at: at([a, b, c, d])) == b)
        // A row put in above b: b didn't move.
        #expect(Folders.resolve(stand, heads: [a, d, b, c], at: at([a, d, b, c])) == b)
        // b moved to the end: the one now under a.
        #expect(Folders.resolve(stand, heads: [a, c, d, b], at: at([a, c, d, b])) == c)
        #expect(Folders.resolve(stand, heads: [a, c, d, b], at: at([a, c, d, b]), moved: [b]) == c)
        // a moved past b, which the move says: b stays.
        #expect(Folders.resolve(stand, heads: [b, a, c, d], at: at([b, a, c, d]), moved: [a]) == b)
        // b gone: under a still.
        #expect(Folders.resolve(stand, heads: [a, c, d], at: at([a, c, d])) == c)
        // b gone, a last: the kept's end.
        #expect(Folders.resolve(stand, heads: [d, a], at: at([d, a])) == nil)
        // At the top, the first gone: at the top still.
        let top = Nest.Stand(before: a, after: nil, next: b)
        #expect(Folders.resolve(top, heads: [b, c], at: at([b, c])) == b)
    }
}
