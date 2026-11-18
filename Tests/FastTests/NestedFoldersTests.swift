import Foundation
import Testing
import SyncKit
@testable import Fast

// Folders of yours in folders (Kept.swift, AgentFolders.swift): a tab is
// drawn under every folder it is in, each a step further in; a shut folder
// hides what is in it but the tab on screen, which comes out a step in from
// it; the session and sync carry the folders above a folder on each tab.
@MainActor
struct NestedFoldersTests {
    init() { SyncShapes.register() }

    /// Analitycs › SEO with two tabs, Analitycs' own tab, and one of today's.
    static func tree(analytics: Bool = true, seo: Bool = true) -> (an: Nest, seo: Nest, tabs: [Tab]) {
        let an = Nest(name: "Analitycs", open: analytics)
        let seo = Nest(name: "SEO", open: seo)
        seo.parent = an
        let a = Tab(), b = Tab(), c = Tab(), d = Tab()
        for tab in [a, b, c] { tab.kept = true }
        a.nest = seo
        b.nest = seo
        c.nest = an
        return (an, seo, [a, b, c, d])
    }

    static func lay(_ tabs: [Tab], active: Tab.ID? = nil) -> [Tab.ID: Folders.Place] {
        Folders.lay(Folders.nests(in: tabs), isOpen: { $0.nest?.open ?? false }, whole: [], folding: [], active: active).places
    }

    @Test func aFolderInAFolderHoldsItsTabsAndItsParentHoldsThemToo() {
        let (an, seo, tabs) = Self.tree()
        let made = Folders.nests(in: tabs)
        #expect(made.map(\.id) == [an.key, seo.key])
        #expect(made[0].members == tabs.prefix(3).map(\.id))
        #expect(made[1].members == tabs.prefix(2).map(\.id))
        #expect(seo.chain.map(\.id) == [an.id, seo.id] && seo.depth == 2 && seo.within(an) && !an.within(seo))
    }

    @Test func aLoopEndsTheChain() {
        let a = Nest(name: "A"), b = Nest(name: "B")
        a.parent = b
        b.parent = a
        #expect(a.chain.count == 2)
    }

    @Test func openRowsStepInAFolderAtATime() {
        let (an, seo, tabs) = Self.tree()
        let placed = Self.lay(tabs)
        #expect(placed[tabs[0].id]?.heads == [an.key, seo.key])
        #expect(placed[tabs[0].id]?.depth == 2)
        #expect(placed[tabs[1].id]?.heads == [])
        #expect(placed[tabs[2].id]?.depth == 1 && placed[tabs[2].id]?.folder == an.key)
        #expect(placed[tabs[3].id] == nil)
        #expect(tabs.prefix(3).allSatisfy { placed[$0.id]?.shown == true })
    }

    @Test func aShutFolderInsideHidesItsTabsButNotItsRow() {
        let (an, seo, tabs) = Self.tree(seo: false)
        let placed = Self.lay(tabs, active: tabs[1].id)
        #expect(placed[tabs[0].id]?.shown == false)
        #expect(placed[tabs[0].id]?.heads == [an.key, seo.key])
        // The tab on screen is out under its shut folder, a step in from it.
        #expect(placed[tabs[1].id]?.shown == true && placed[tabs[1].id]?.depth == 2)
        #expect(placed[tabs[2].id]?.shown == true)
    }

    @Test func aShutFolderHidesTheFoldersInItAndTheTabOnScreenPeeksOneStepIn() {
        let (an, _, tabs) = Self.tree(analytics: false)
        let placed = Self.lay(tabs, active: tabs[1].id)
        // Only the outer folder's row: SEO's is inside a shut one.
        #expect(placed[tabs[0].id]?.heads == [an.key])
        #expect(placed[tabs[0].id]?.chain == [an.key])
        #expect(placed[tabs[1].id]?.shown == true && placed[tabs[1].id]?.depth == 1)
        #expect(placed[tabs[2].id]?.shown == false)
    }

    /// Register 1451: opened tabs stay reachable under a shut ancestor,
    /// including after selecting a tab outside the folder.
    @Test func aShutFolderKeepsItsOpenedTabsAfterFocusMovesAway() {
        let (an, _, tabs) = Self.tree(analytics: false)
        let placed = Folders.lay(Folders.nests(in: tabs), isOpen: { $0.nest?.open ?? false }, whole: [], folding: [],
                                 active: tabs[1].id, awake: [tabs[0].id, tabs[1].id]).places
        #expect(placed[tabs[0].id]?.shown == true)
        #expect(placed[tabs[1].id]?.shown == true && placed[tabs[1].id]?.depth == 1 && placed[tabs[1].id]?.chain == [an.key])
        #expect(placed[tabs[0].id]?.order == 0 && placed[tabs[1].id]?.order == 1)
        #expect(placed[tabs[2].id]?.shown == false)
        // Only links that have not been opened stay inside.
        let later = Folders.lay(Folders.nests(in: tabs), isOpen: { $0.nest?.open ?? false }, whole: [], folding: [],
                                active: tabs[3].id, awake: [tabs[0].id, tabs[1].id]).places
        #expect(later[tabs[0].id]?.shown == true && later[tabs[1].id]?.shown == true)
        #expect(later[tabs[2].id]?.shown == false)
    }

    /// Open is Arc's pinned tab's: a kept tab brought back from the last
    /// session or put down, not opened since, is a link in the folder and
    /// stays in; so is a tab of today's.
    @Test func aTabBroughtBackOrPutDownIsNotOpen() {
        let (_, _, tabs) = Self.tree(analytics: false)
        tabs[0].restore(url: URL(string: "about:blank#nested-1022-a")!, title: "A")
        #expect(tabs[0].unopened && tabs[0].asleep)
        #expect(!Folders.awake(in: tabs).contains(tabs[0].id))
        // Never loaded and naming nothing: not open either.
        #expect(Folders.awake(in: tabs).isEmpty)
    }

    @Test func theComingRowLaysThemAsTheColumnDoes() {
        let (an, seo, tabs) = Self.tree()
        let items = PagedSpace.Coming.items(tabs, active: nil)
        #expect(items.map(\.id) == [an.key, seo.key] + tabs.prefix(3).map(\.id.uuidString) + ["line", tabs[3].id.uuidString])
    }

    /// #503: a kept row hidden by a folded folder has no numbered key.
    /// A visible pin is still eligible even before its page has been woken.
    @Test func numberedKeysSkipHiddenKeptRowsInVisibleOrder() {
        let (parent, child, tabs) = Self.tree(seo: false)
        let browser = Browser(windowID: UUID())
        browser.takeOwnFolders()
        let pin = Tab()
        pin.pin = "P"
        pin.restore(url: URL(string: "about:blank#numbered-pin")!, title: "Pin")
        for (index, tab) in tabs.enumerated() {
            tab.restore(url: URL(string: "about:blank#numbered-\(index)")!, title: "Tab \(index)")
        }
        browser.lay([pin] + tabs)
        browser.activeID = tabs[3].id
        defer {
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            browser.tabs.forEach { $0.close() }
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
                Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
            }
        }
        func pick(_ index: Int, from active: Tab? = nil) -> Tab.ID? {
            browser.activeID = active?.id ?? tabs[3].id
            browser.folderBook.refresh()
            browser.select(number: index + 1)
            return browser.activeID
        }
        browser.folderBook.refresh()
        #expect(pin.asleep)
        #expect(pick(0) == pin.id)
        #expect(pick(1) == tabs[2].id)
        #expect(pick(2) == tabs[3].id)
        #expect(pick(3) == tabs[3].id) // No fourth visible tab: keep the current one.
        #expect(pick(browser.tabs.count - 1) == tabs[3].id) // Cmd-9.
        browser.lay([pin, tabs[2], tabs[3], tabs[0], tabs[1]])
        #expect(pick(browser.tabs.count - 1) == tabs[3].id) // Cmd-9 still follows visible order after regrouping.
        browser.lay([pin] + tabs)
        child.open = true
        #expect(pick(1) == tabs[0].id)
        #expect(pick(2) == tabs[1].id)
        parent.open = false
        // Keyboard navigation still skips shut folders, independently of
        // the opened rows retained for pointer access (register 1448).
        #expect(pick(1) == tabs[3].id)
        #expect(pick(3) == tabs[3].id)
        #expect(browser.numberable() == [0, 4])
        browser.activeID = pin.id
        browser.folderBook.refresh()
        browser.step(1)
        #expect(browser.activeID == tabs[3].id)
        browser.step(-1)
        #expect(browser.activeID == pin.id)
        // Put down, they go in.
        for tab in tabs.prefix(3) { tab.rest() }
        #expect(pick(1) == tabs[3].id)
        // Peeking out of a shut folder does not give the current tab a number.
        #expect(pick(1, from: tabs[1]) == tabs[3].id)
        #expect(pick(2, from: tabs[1]) == tabs[1].id)
        #expect(!parent.open)
    }

    // MARK: - empty folders in folders

    @Test func anEmptyFolderInAFolderStandsAtTheEndOfItsRun() {
        let (an, _, _) = Self.tree()
        let inside = Nest(name: "Later", open: true)
        inside.parent = an
        let deeper = Nest(name: "Deeper", open: true)
        deeper.parent = inside
        let top = Nest(name: "Top", open: false)
        let empty = [inside, deeper, top]
        #expect(Folders.flat(empty, under: nil).map(\.name) == ["Top"])
        #expect(Folders.trails(empty, living: [an.id])[an.key]?.map(\.name) == ["Later", "Deeper"])
        inside.open = false
        #expect(Folders.trails(empty, living: [an.id])[an.key]?.map(\.name) == ["Later"])
    }

    // MARK: - written and read

    @Test func aPathNamesTheFoldersAboveAndMakesThemAgain() {
        let (an, seo, _) = Self.tree()
        an.customMark = "emoji:📊"
        #expect(seo.path == [Session.Step(id: an.id.uuidString, name: "Analitycs", open: true, mark: "emoji:📊")])
        #expect(an.path == nil)
        var nests: [String: Nest] = [:]
        let again = Nest(id: seo.id, name: "SEO")
        again.file(in: seo.path, nests: &nests)
        #expect(again.parent?.id == an.id && again.parent?.name == "Analitycs" && again.parent?.customMark == "emoji:📊")
        // A second tab under it finds the same one.
        let other = Nest(name: "Other")
        other.file(in: seo.path, nests: &nests)
        #expect(other.parent === again.parent)
    }

    @Test func syncCarriesTheFolderAFolderIsIn() throws {
        let space = UUID()
        let an = Session.Step(id: "F-an", name: "Analitycs", open: false)
        // Two tabs right in SEO, none right in Analitycs: it has a record
        // all the same.
        let entries = (0..<2).map { n in
            Session.Entry(url: "https://nest.test/\(n)", title: "T\(n)", pin: nil, seen: 100, kept: true,
                          folder: "F-seo", folderName: "SEO", folderOpen: true, folderPath: [an], id: "tab-\(n)")
        }
        let shape = Session.Shape(tabs: entries, active: 0)
        let out = SyncShapes.rows([space: shape], orders: [:])
        #expect(out.folders.count == 2)
        #expect(out.folders["F-seo"]?["folder"]?.string == "F-an")
        #expect(out.folders["F-an"]?["folder"] == .null && out.folders["F-an"]?["name"]?.string == "Analitycs")
        let j = try Journal(path: nil, device: "a")
        try j.reconcile(SyncShapes.tab, out.tabs)
        try j.reconcile(SyncShapes.folder, out.folders)
        let back = SyncShapes.row(space, tabs: j.all(SyncShapes.tab), folders: j.all(SyncShapes.folder), pairs: [], here: shape)
        #expect(back.tabs.map(\.folder) == ["F-seo", "F-seo"])
        #expect(back.tabs[0].folderPath == [an])
    }

    @Test func folderRecordsFromAnOlderMacReadFlat() throws {
        let space = UUID()
        let entry = Session.Entry(url: "https://nest.test/0", title: "T0", pin: nil, seen: 100, kept: true,
                                  folder: "F-seo", folderName: "SEO", folderOpen: true, id: "tab-0")
        let shape = Session.Shape(tabs: [entry], active: 0)
        let out = SyncShapes.rows([space: shape], orders: [:])
        let j = try Journal(path: nil, device: "a")
        try j.reconcile(SyncShapes.tab, out.tabs)
        try j.reconcile(SyncShapes.folder, out.folders)
        let back = SyncShapes.row(space, tabs: j.all(SyncShapes.tab), folders: j.all(SyncShapes.folder), pairs: [], here: shape)
        #expect(back.tabs[0].folder == "F-seo" && back.tabs[0].folderPath == nil)
    }

    // MARK: - Arc's folders brought in before

    @Test func aPathInANameBecomesFoldersInFolders() {
        let an = Nest(name: "Analitycs", open: true)
        let flat = Nest(name: "Analitycs \u{203A} SEO", open: false)
        let deep = Nest(name: "Work \u{203A} Clients \u{203A} Acme", open: true)
        let mine = Nest(name: "Ideas", open: true)
        let tabs = [an, flat, deep, mine].map { nest -> Tab in
            let tab = Tab()
            tab.kept = true
            tab.nest = nest
            return tab
        }
        #expect(Nest.unflatten(tabs))
        #expect(flat.name == "SEO" && flat.parent === an)
        #expect(deep.name == "Acme" && deep.parent?.name == "Clients" && deep.parent?.parent?.name == "Work")
        #expect(mine.parent == nil && mine.name == "Ideas")
        // Once done, nothing more to do.
        #expect(!Nest.unflatten(tabs))
    }
}

// The browser's own moves on folders in folders (Kept.swift), a row of
// Analitycs › SEO › Competitors worked on as the menus and drags do, with a
// Folders of its own putting the row in order after each (`refresh`); the
// session written and read back; Arc's sidebar and a space's file brought
// in with folders in folders.
@MainActor
struct NestedFoldersBrowserTests {
    @MainActor
    struct World {
        let browser: Browser
        let folders: Folders
        let an: Nest, seo: Nest, comp: Nest
        let tabs: [String: Tab]
        let window: UUID
        let file: URL

        func order() -> [String] {
            browser.tabs.map { tab in tabs.first { $0.value === tab }?.key ?? "?" }
        }

        func done() {
            folders.browser = nil
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            for tab in browser.tabs { tab.close() }
            try? FileManager.default.removeItem(at: Store.file("session-window-\(window.uuidString).json"))
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// brex; Analitycs { SEO { gsc, ywm, Competitors { sem, sim } }, ga, amp }; hn today's.
    static func world() -> World {
        let window = UUID(), browser = Browser(windowID: window)
        let names = ["brex", "gsc", "ywm", "sem", "sim", "ga", "amp", "hn"]
        var tabs: [String: Tab] = [:]
        let row = names.map { name -> Tab in
            let tab = Tab()
            tab.restore(url: URL(string: "https://nest.test/\(name)")!, title: name)
            browser.prepare(tab)
            tabs[name] = tab
            return tab
        }
        let an = Nest(name: "Analitycs"), seo = Nest(name: "SEO"), comp = Nest(name: "Competitors")
        seo.parent = an
        comp.parent = seo
        for name in names where name != "hn" { tabs[name]?.kept = true }
        tabs["gsc"]?.nest = seo
        tabs["ywm"]?.nest = seo
        tabs["sem"]?.nest = comp
        tabs["sim"]?.nest = comp
        tabs["ga"]?.nest = an
        tabs["amp"]?.nest = an
        browser.lay(row)
        browser.activeID = tabs["brex"]!.id
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let folders = Folders(emptiesFile: file)
        folders.browser = browser
        return World(browser: browser, folders: folders, an: an, seo: seo, comp: comp, tabs: tabs, window: window, file: file)
    }

    @Test func aFolderInAFolderStaysOneRunWhereverItsTabsWere() {
        let world = Self.world()
        defer { world.done() }
        // A tab of Competitors left at the end of the kept: back in its run.
        var row = world.browser.tabs.filter { $0 !== world.tabs["sem"] }
        row.insert(world.tabs["sem"]!, at: 6)
        world.browser.lay(row)
        world.folders.refresh()
        #expect(world.order() == ["brex", "gsc", "ywm", "sim", "sem", "ga", "amp", "hn"])
    }

    @Test func removeFolderKeepTabsLiftsWhatWasInItIntoTheFolderItWasIn() {
        let world = Self.world()
        defer { world.done() }
        world.browser.ungroup(world.seo)
        world.folders.refresh()
        #expect(world.tabs["gsc"]?.nest === world.an && world.tabs["ywm"]?.nest === world.an)
        #expect(world.comp.parent === world.an)
        #expect(!world.browser.nests.contains { $0 === world.seo })
        #expect(world.order() == ["brex", "gsc", "ywm", "sem", "sim", "ga", "amp", "hn"])
    }

    @Test func removeFromFolderTakesATabOneStepOut() {
        let world = Self.world()
        defer { world.done() }
        world.browser.unfile(world.tabs["sem"]!)
        world.folders.refresh()
        #expect(world.tabs["sem"]?.nest === world.seo)
        #expect(world.order() == ["brex", "gsc", "ywm", "sim", "sem", "ga", "amp", "hn"])
    }

    @Test func aFolderMovedOutCarriesItsRunAndLandsAfterTheOneItLeft() {
        let world = Self.world()
        defer { world.done() }
        world.browser.file(world.comp, in: nil)
        world.folders.refresh()
        #expect(world.comp.parent == nil && world.comp.depth == 1)
        #expect(world.order() == ["brex", "gsc", "ywm", "ga", "amp", "sem", "sim", "hn"])
        // And back in, at the end of SEO's run.
        world.browser.file(world.comp, in: world.seo)
        world.folders.refresh()
        #expect(world.comp.parent === world.seo)
        #expect(world.order() == ["brex", "gsc", "ywm", "sem", "sim", "ga", "amp", "hn"])
    }

    @Test func aFolderNeverGoesIntoItselfOrPastFiveDeep() {
        let world = Self.world()
        defer { world.done() }
        #expect(!world.browser.canPut(world.an, in: world.comp))
        #expect(!world.browser.canPut(world.seo, in: world.seo))
        #expect(world.browser.canPut(world.comp, in: nil))
        // Two more under Competitors make five; Analitycs' whole tree can't go
        // into anything else then.
        let four = Nest(name: "Four"), five = Nest(name: "Five")
        four.parent = world.comp
        five.parent = four
        world.tabs["sim"]?.nest = five
        world.folders.refresh()
        #expect(five.depth == 5)
        let other = Nest(name: "Other")
        world.tabs["brex"]?.nest = other
        world.folders.refresh()
        #expect(!world.browser.canPut(world.an, in: other))
        #expect(world.browser.canPut(five, in: other))
    }

    @Test func closingTheLastTabsOfAFolderInsideTakesOnlyThatOne() {
        let world = Self.world()
        defer { world.done() }
        world.browser.discard(world.browser.tabs(in: world.comp))
        world.folders.refresh()
        #expect(!world.browser.nests.contains { $0 === world.comp })
        #expect(world.browser.nests.contains { $0 === world.seo })
        #expect(world.order() == ["brex", "gsc", "ywm", "ga", "amp", "hn"])
    }

    @Test func newFolderWithTabsPickedInAFolderIsMadeInThatFolder() {
        let world = Self.world()
        defer { world.done() }
        world.browser.newFolder(with: [world.tabs["ga"]!, world.tabs["amp"]!])
        world.folders.refresh()
        let made = world.tabs["ga"]?.nest
        #expect(made !== world.an && made?.parent === world.an && world.tabs["amp"]?.nest === made)
        #expect(world.order() == ["brex", "gsc", "ywm", "sem", "sim", "ga", "amp", "hn"])
    }

    @Test func theSessionWritesTheTreeAndReadsItBack() {
        let world = Self.world()
        defer { world.done() }
        world.seo.open = false
        world.browser.writeRow(world.browser.tabs, active: world.browser.activeID, space: Space.firstID, pairs: [], now: true)
        let saved = Session.read(space: Space.firstID, window: world.window)
        let sem = saved.tabs.first { $0.url.hasSuffix("/sem") }
        #expect(sem?.folderName == "Competitors" && sem?.folderPath?.map(\.name) == ["Analitycs", "SEO"])
        #expect(sem?.folderPath?.last?.open == false)
        #expect(saved.tabs.first { $0.url.hasSuffix("/ga") }?.folderPath == nil)
        let back = world.browser.loadRow(Space.firstID)
        defer { for tab in back.tabs { tab.close() } }
        let found = { (name: String) in back.tabs.first { $0.pending?.absoluteString.hasSuffix("/" + name) ?? false } }
        #expect(found("sem")?.nest?.chain.map(\.name) == ["Analitycs", "SEO", "Competitors"])
        #expect(found("gsc")?.nest === found("ywm")?.nest)
        #expect(found("gsc")?.nest?.parent === found("ga")?.nest)
        #expect(found("gsc")?.nest?.open == false)
    }

    @Test func arcsFoldersInFoldersComeAsAPath() throws {
        let item = ArcSidebarTests.item
        let items: [[String: Any]] = [
            item("pinned", nil, ["an"], nil, nil, nil, "itemContainer", nil),
            item("an", "pinned", ["seo", "ga"], nil, "Analitycs", nil, "list", nil),
            item("seo", "an", ["gsc"], nil, "SEO", nil, "list", nil),
            item("gsc", "seo", [], "https://search.google.com/", nil, "Overview", "itemContainer", nil),
            item("ga", "an", [], "https://analytics.google.com/", nil, "GA", "itemContainer", nil),
            item("unpinned", nil, [], nil, nil, nil, "itemContainer", nil),
        ]
        var list: [Any] = []
        for each in items { list += [each["id"]!, each] }
        let json: [String: Any] = ["sidebar": ["containers": [
            ["global": [String: Any]()],
            ["items": list, "spaces": ["s", ["id": "s", "title": "Work", "profile": ["default": [String: Any]()],
                                              "containerIDs": ["pinned", "pinned", "unpinned", "unpinned"]]]],
        ]]]
        let place = try #require(ArcSidebar.places(in: JSONSerialization.data(withJSONObject: json)).first)
        #expect(place.kept.map(\.folder) == ["Analitycs \u{203A} SEO", "Analitycs"])
        #expect(place.kept.map(\.path) == [["Analitycs", "SEO"], nil])
    }

    @Test func bringingInWritesTheTreeIntoASpacesFile() throws {
        let window = UUID(), browser = Browser(windowID: window)
        let space = Space(id: UUID(), name: "Work", icon: "", ownSignIns: false,
                          paint: SpacePaint(swatch: .custom, color: browser.prefs.backdropColor, grain: 0))
        browser.spaces.append(space)
        defer { Session.erase(space: space.id) }
        var gsc = try #require(TabImport.entry("https://search.google.com/", "Overview"))
        gsc.folder = "Analitycs \u{203A} SEO"
        gsc.path = ["Analitycs", "SEO"]
        var ga = try #require(TabImport.entry("https://analytics.google.com/", "GA"))
        ga.folder = "Analitycs"
        _ = browser.lay([], kept: [gsc, ga], open: [], into: space.id)
        let saved = Session.read(space: space.id, window: window)
        let first = try #require(saved.tabs.first { $0.url.contains("search.google") })
        let second = try #require(saved.tabs.first { $0.url.contains("analytics.google") })
        #expect(first.folderName == "SEO" && first.folderPath?.map(\.name) == ["Analitycs"])
        // Analitycs is the same folder for both: GA right in it, SEO in it.
        #expect(first.folderPath?.first?.id == second.folder)
        #expect(second.folderPath == nil)
    }
}
