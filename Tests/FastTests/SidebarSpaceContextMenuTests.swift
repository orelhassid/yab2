import AppKit
import SwiftUI
import Testing
@testable import Fast

/// Actual ColumnView -> SideBar -> native page/background hit testing and
/// NSApp event dispatch. No HID events, live profile or added menu observer.
/// This file uses only pre-existing APIs so the same checks can run on base.
@MainActor @Suite(.serialized)
struct SidebarSpaceContextMenuTests {
    @Test(arguments: Density.allCases, [false, true])
    func expandedScrolledTailOpensTheExistingSpaceMenu(_ density: Density, _ control: Bool) async throws {
        try await world(density, count: 60) { f in
            let page = try await f.page()
            try #require(!f.browser.folderBook.shut)
            try #require(page.items.contains { $0.tab?.kept == true })
            try #require(page.headItems.contains { if case .name = $0.kind { return true }; return false })
            try #require(page.items.contains { if case .newTab = $0.kind { return true }; return false })
            // More rows than the full host: the old, unscrolled backdrop
            // reservation cannot admit any point in this window.
            try #require(ColumnLayout.height(page.items) > f.column.bounds.height)
            let point = try f.tail(page, atEnd: true)
            try f.context(point, in: page, control: control)
            try f.expectSpaceMenu(first: false)
            #expect(f.browser.tabs.allSatisfy { $0.built == nil && !$0.gone })
        }
    }

    @Test(arguments: Density.allCases, [false, true])
    func shortAndCollapsedListsKeepTheirSpaceMenu(_ density: Density, _ collapsed: Bool) async throws {
        try await world(density, count: collapsed ? 60 : 2, collapsed: collapsed) { f in
            let page = try await f.page()
            try #require(f.browser.folderBook.shut == collapsed)
            if collapsed { #expect(!page.items.contains { $0.tab?.kept == true && $0.height > 0 }) }
            let point = try f.tail(page, atEnd: false)
            try f.context(point, in: page)
            try f.expectSpaceMenu(first: false)
        }
    }

    @Test(arguments: Density.allCases)
    func theNextSpaceUsesItsOwnExistingMenu(_ density: Density) async throws {
        try await world(density, count: 60) { f in
            let old = try await f.page()
            try f.context(try f.tail(old, atEnd: true), in: old)
            try f.expectSpaceMenu(first: false)
            ActionMenu.close()
            f.browser.switchSpace(to: Space.firstID)
            let current = try await f.page()
            try #require(current.space == Space.firstID && current !== old)
            try #require(f.browser.tabs.isEmpty && current.items.allSatisfy {
                if case .newTab = $0.kind { return true }
                if case .line = $0.kind { return true }
                return false
            }, "Switching must use only the fixture's empty parked row, never retained session tabs")
            let point = try f.tail(current, atEnd: false)
            // The switch slides the spaces (SpacePager); while that runs the
            // column hands its presses to no one. A right click comes after
            // the slide, so the press waits for the column to answer again.
            let root = try #require(f.window.contentView)
            for _ in 0..<40 where root.hitTest(root.convert(point, from: current)) == nil {
                try await Task.sleep(for: .milliseconds(50))
            }
            try f.context(point, in: current)
            // Sign-Ins is present only on a non-first Space. This asserts
            // the real menu was rebuilt for the new target, not captured.
            try f.expectSpaceMenu(first: true)
        }
    }

    @Test(arguments: Density.allCases)
    func rowsHeaderScrollerAndFootKeepTheirOwnTargets(_ density: Density) async throws {
        try await world(density, count: 60) { f in
            let page = try await f.page()
            let tail = try f.tail(page, atEnd: true)
            let row = try #require(page.items.last { $0.height > 0 })
            let document = try #require(page.scrollView.documentView)
            let rowPoint = page.convert(NSPoint(x: page.bounds.midX, y: row.y + row.height / 2), from: document)
            try #require(page.item(at: rowPoint)?.id == row.id && page.holds(rowPoint))
            try #require(!page.holds(tail))
            // Rows remain native; the stationary switcher owns header hits.
            let pages = try #require(ColumnPages.of(f.browser))
            let root = try #require(f.window.contentView)
            let name = try #require(page.headItems.first { if case .name = $0.kind { return true }; return false })
            let namePoint = NSPoint(x: SideBar.margin + (name.x ?? 0) + (name.width ?? 0) / 2,
                                   y: name.y + name.height / 2)
            #expect(page.cellAt(try f.event(.rightMouseDown, namePoint, in: page))?.itemID != name.id,
                    "The moving native page must not expose its hidden header cell")
            let headerHit = try #require(root.hitTest(root.convert(namePoint, from: page)))
            #expect(!headerHit.isDescendant(of: pages), "The fixed switcher must receive header input outside the sliding pages")
            for point in [rowPoint] {
                let native = pages.convert(point, from: page)
                #expect(pages.hitTest(pages.convert(native, to: pages.superview)) != nil)
            }
            let foot = NSPoint(x: page.bounds.midX, y: page.rowsClip.maxY + 2)
            // The foot keeps its own targets (its space icons have their own
            // menus, SteadyMenu): the press there never qualifies as the
            // background tail, and never reaches the background's strip.
            try #require(!pages.spaceMenuTail(at: pages.convert(foot, from: page), from: pages,
                                              event: try f.event(.rightMouseDown, foot, in: page)))
            SidebarSpaceContextMenuTests.current(try f.event(.rightMouseDown, foot, in: page))
            let footHit = root.hitTest(root.convert(foot, from: page))
            #expect(!Self.chain(footHit).contains("DragStrip"), "The footer became the background: \(Self.chain(footHit))")
            try f.context(foot, in: page)
            // What opened there, if anything, is the foot's own (a space
            // icon's menu, with Show Spaces as Dots), not the background's.
            if ActionMenu.isOpen(in: f.window) {
                let lines = (ActionMenu.state()["lines"] as? [[String: Any]]) ?? []
                #expect(lines.contains { $0["title"] as? String == "Show Spaces as Dots" },
                        "The footer opened the background Space menu")
            }
            ActionMenu.close()
            if let scroller = page.scrollView.verticalScroller, !scroller.isHidden, scroller.alphaValue > 0.01 {
                let at = page.convert(NSPoint(x: scroller.bounds.midX, y: scroller.bounds.midY), from: scroller)
                #expect(page.holds(at))
                let hit = root.hitTest(root.convert(at, from: page))
                // The column's overlay scroller is its last 10 pt, and since
                // 0fc461fa5 the column's one native resize handle (SideEdge,
                // Metrics.edgeReach 20 pt centered on the column's edge)
                // covers those same 10 pt, docked as well as floating: a
                // press there resizes the column, the rows still scroll
                // under fingers and wheels. What this test guards is that
                // the Space menu's tail (1fa5381b3) never takes that strip,
                // so either owner may answer, never the background.
                let owner = hit.map { view -> Bool in
                    view === scroller || view.isDescendant(of: scroller) || view is EdgeHandle.Handle
                } ?? false
                #expect(owner, "The scroller's strip went to \(Self.chain(hit))")
            }
            // The untouched non-context branch does not admit the stale
            // backdrop reservation as a window handle in the blank tail.
            try f.send(.leftMouseDown, tail, in: page)
            try f.send(.leftMouseDragged, NSPoint(x: tail.x + 20, y: tail.y), in: page)
            try f.send(.leftMouseUp, tail, in: page)
            #expect(!ActionMenu.isOpen(in: f.window))
            #expect(f.window.frame == f.frame)
            #expect(f.browser.tabs.count == 60 && !page.hand.holding)
        }
    }

    @Test(arguments: Density.allCases)
    func theBlankTailStillHandsWheelEventsToTheNativeRows(_ density: Density) async throws {
        try await world(density, count: 60) { f in
            let page = try await f.page()
            let point = try f.tail(page, atEnd: true)
            let before = columnScrollsHeard.values.reduce(0, +)
            let wheel = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .line,
                wheelCount: 2, wheel1: 1, wheel2: 0, wheel3: 0))
            wheel.flags = []
            wheel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
            wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
            wheel.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
            let local = page.convert(point, to: nil)
            let screen = f.window.convertPoint(toScreen: local)
            wheel.location = CGPoint(x: screen.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.y)
            wheel.setIntegerValueField(CGEventField(rawValue: 51)!, value: Int64(f.window.windowNumber))
            // Same existing in-process binding as WheelLatchTests. Never
            // post a CGEvent or move the global pointer.
            typealias Place = @convention(c) (CGEvent, CGPoint) -> Void
            let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGEventSetWindowLocation"))
            unsafeBitCast(symbol, to: Place.self)(wheel, CGPoint(x: local.x, y: f.window.contentView!.bounds.height - local.y))
            let event = try #require(NSEvent(cgEvent: wheel))
            try #require(event.window === f.window && event.type == .scrollWheel)
            Self.deliver(event)
            #expect(columnScrollsHeard.values.reduce(0, +) > before)
            #expect(!ActionMenu.isOpen(in: f.window))
        }
    }

    @Test func aPutAwayColumnCannotOpenTheBackgroundMenu() async throws {
        try await world(.compact, count: 60) { f in
            let page = try await f.page()
            let point = try f.tail(page, atEnd: true)
            f.column.slide(out: false, animated: false)
            try #require(!f.column.shown)
            try f.context(point, in: page)
            #expect(!ActionMenu.isOpen(in: f.window))
        }
    }

    @Test func aStaleOrdinaryHostCannotShowItsMenuDuringTheMailTransition() async throws {
        try await world(.compact, count: 60) { f in
            let page = try await f.page()
            let point = try f.tail(page, atEnd: true)
            let ordinary = f.browser.spaceID
            // The old representable still exists until SwiftUI's next
            // pass. Its native qualification must use current Mail state,
            // not the ordinary menu closure retained by that old host.
            f.browser.spaceID = Space.mailID
            defer { f.browser.spaceID = ordinary }
            try f.context(point, in: page)
            #expect(!ActionMenu.isOpen(in: f.window))
        }
    }

    /// AppKit makes an event NSApp.currentEvent while it dispatches it,
    /// and the column's hit testing reads that (DragStrip's context tail,
    /// ColumnPages' wheel route). NSApp.sendEvent alone leaves it as it
    /// was, nil in a test, so the tail never qualified.
    static func current(_ event: NSEvent) {
        let set = NSSelectorFromString("_setCurrentEvent:")
        if NSApp.responds(to: set) { NSApp.perform(set, with: event) }
    }

    /// As AppKit hands a real event over: current while dispatched.
    static func deliver(_ event: NSEvent) {
        current(event)
        NSApp.sendEvent(event)
    }

    static func chain(_ view: NSView?) -> String {
        var names: [String] = []
        var at = view
        while let v = at { names.append(String(describing: type(of: v))); at = v.superview }
        return names.joined(separator: " < ")
    }

    @MainActor private final class Fixture {
        let browser: Browser
        let window: NSWindow
        let column: ColumnView
        let frame: NSRect

        init(browser: Browser) {
            let room = NSRect(x: -30_000, y: -30_000, width: 800, height: 650)
            let nativeWindow = NSWindow(contentRect: room, styleMask: [.borderless], backing: .buffered, defer: false)
            let nativeColumn = ColumnView(browser: browser)
            self.browser = browser
            frame = room; window = nativeWindow; column = nativeColumn
            window.isReleasedWhenClosed = false
            let root = NSView(frame: NSRect(origin: .zero, size: frame.size))
            root.wantsLayer = true
            window.contentView = root
            column.frame = root.bounds
            root.addSubview(column)
            column.slide(out: true, animated: false)
            // On screen, if far off it: a window that isn't is handed no
            // mouse events, and the presses below must arrive as real ones.
            window.orderFrontRegardless()
        }

        func page() async throws -> ColumnPage {
            // Let the actual SwiftUI representables and native row cells
            // attach. No direct page.live or mirrored layout is substituted.
            window.layoutIfNeeded(); window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(80))
            window.contentView?.layoutSubtreeIfNeeded()
            let pages = try #require(ColumnPages.of(browser))
            let page = try #require(pages.shown)
            try #require(column.shown && pages.window === window && page.window === window && !page.away)
            try #require(page.space == browser.spaceID && page.rowsClip.height > SideBar.rowsTail)
            try #require(page.items.contains { $0.height > 0 })
            try #require(browser.tabs.allSatisfy { $0.built == nil }, "Fixture pages must stay asleep")
            return page
        }

        func tail(_ page: ColumnPage, atEnd: Bool) throws -> NSPoint {
            let document = try #require(page.scrollView.documentView)
            if atEnd {
                page.scroll(to: document.frame.height - page.scrollView.contentView.bounds.height
                            + page.scrollView.contentInsets.top + page.scrollView.contentInsets.bottom)
                try #require(abs(page.offset + page.rowsClip.height - ColumnLayout.height(page.items) - SideBar.rowsTail) < 1)
            } else { page.scroll(to: 0) }
            page.layoutSubtreeIfNeeded()
            let end = ColumnLayout.height(page.items)
            let documentY = atEnd ? end + SideBar.rowsTail / 2 : end + SideBar.gap + 18
            let point = page.convert(NSPoint(x: page.bounds.midX, y: documentY), from: document)
            try #require(page.rowsClip.contains(point) && !page.holds(point) && page.item(at: point) == nil,
                         "A real visible blank tail, outside head/footer/scroller/rows, is required")
            let last = try #require(page.items.last { $0.height > 0 })
            let rowPoint = page.convert(NSPoint(x: page.bounds.midX, y: last.y + last.height / 2), from: document)
            try #require(page.rowsClip.contains(rowPoint))
            let rowEvent = try event(.rightMouseDown, rowPoint, in: page)
            try #require(page.cellAt(rowEvent)?.itemID == last.id,
                         "The final New Tab row needs a bound native cell, not only a layout item")
            print("SIDEBAR_SPACE_MENU_FIXTURE space=\(page.space) offset=\(page.offset) end=\(end) point=\(point) clip=\(page.rowsClip)")
            return point
        }

        func event(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView, control: Bool = false) throws -> NSEvent {
            let event = try #require(NSEvent.mouseEvent(with: type, location: view.convert(point, to: nil),
                modifierFlags: control ? [.control] : [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                pressure: type == .leftMouseDown || type == .rightMouseDown ? 1 : 0))
            try #require(event.window === window)
            return event
        }

        func send(_ type: NSEvent.EventType, _ point: NSPoint, in view: NSView, control: Bool = false) throws {
            SidebarSpaceContextMenuTests.deliver(try event(type, point, in: view, control: control))
        }

        func context(_ point: NSPoint, in page: ColumnPage, control: Bool = false) throws {
            ActionMenu.close()
            guard control else {
                try send(.rightMouseDown, point, in: page)
                try send(.rightMouseUp, point, in: page)
                return
            }
            // A ⌃-click sent through NSApp in a unit test never reached the
            // strip's mouseDown and left the test process to die at the next
            // case (AppKit treats it as a context-menu click of its own).
            // The route is the same as a right click's up to the view the
            // press lands on, so that is what is checked: with the press as
            // the current event, the window's hit test reaches the view
            // whose menu is the Space menu, and that menu is put up from it
            // as the strip's ⌃-click does (DragStrip.Strip.mouseDown).
            let down = try event(.leftMouseDown, point, in: page, control: true)
            SidebarSpaceContextMenuTests.current(down)
            let root = try #require(window.contentView)
            let hit = try #require(root.hitTest(root.convert(point, from: page)), "The ⌃-click lands on nothing")
            // menu(for:) answers nil to a ⌃-click on purpose, so AppKit's own
            // menu loop stays out and mouseDown puts up the ActionMenu; the
            // view's menu is the one a right click there gets.
            guard let menu = hit.menu(for: try event(.rightMouseDown, point, in: page)) else { return }
            ActionMenu.show(menu, from: hit, with: down)
        }

        func expectSpaceMenu(first: Bool) throws {
            try #require(ActionMenu.isOpen(in: window) && ActionMenu.parentWindow === window,
                         "The full native event route must actually open its owner's Space menu")
            let lines = try #require(ActionMenu.state()["lines"] as? [[String: Any]])
            let titles = lines.compactMap { $0["title"] as? String }
            #expect(titles.contains("Edit Space…") && !titles.contains("Rename Space…") && !titles.contains("Customize Space…"))
            #expect(titles.contains("Edit Look…") && titles.contains("Space Settings…"))
            #expect(titles.contains("Sign-Ins") == !first)
            print("SIDEBAR_SPACE_MENU owner=\(window.windowNumber) space=\(browser.spaceID) titles=\(titles)")
        }
    }

    private func world(_ density: Density, count: Int, collapsed: Bool = false,
                       _ check: (Fixture) async throws -> Void) async throws {
        try #require(Store.testing && Store.unitTests && Store.world != nil && Store.settings !== UserDefaults.standard,
                     "Isolated serial AppKit unit-test world required before any fixture mutation")
        let world = try #require(Store.world)
        _ = NSApplication.shared
        try #require(ColumnKit.on && !ActionMenu.isOpen && NSEvent.pressedMouseButtons == 0)
        Session.settle()
        let domain = world == "test" ? "dev.serafim.fast.test" : "dev.serafim.fast.test.\(world)"
        let settings = Store.settings.persistentDomain(forName: domain)
        let files = try inputFiles()
        let densityBefore = Density.current
        let foldersBefore = Folders.shared.browser, sharingBefore = Spaces.sharing
        let pageCountsBefore = Spaces.pageCounts, currentBefore = Spaces.current
        let passkeysBefore = FormRelay.passkeysOffered
        let space = Space(id: UUID(), name: "Menu fixture", icon: "F", ownSignIns: false)
        Store.settings.set(false, forKey: "mail")
        Store.settings.set(false, forKey: "search.suggest")
        Store.settings.set([[String: String]](), forKey: FieldFavorites.key)
        Folders.writeShut(collapsed ? [space.id] : [])
        Density.current = density
        let browser = Browser(windowID: UUID())
        var fixture: Fixture?
        defer {
            ActionMenu.close()
            ColumnPages.of(browser)?.stop()
            fixture?.window.close()
            if browser.ownFolders != nil { browser.letGoArranging() }
            browser.letGo(); browser.dropSpare()
            browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
            browser.ownFolders?.browser = nil
            Folders.shared.browser = foldersBefore; Spaces.sharing = sharingBefore
            FormRelay.passkeysOffered = passkeysBefore
            Spaces.pageCounts = pageCountsBefore; Spaces.current = currentBefore
            Session.settle()
            let current: [String: Data]
            do { current = try inputFiles() } catch { Issue.record(error); current = [:] }
            for name in current.keys where files[name] == nil {
                do { try FileManager.default.removeItem(at: Store.folder.appendingPathComponent(name)) }
                catch { Issue.record(error) }
            }
            for (name, data) in files {
                do { try data.write(to: Store.folder.appendingPathComponent(name), options: .atomic) }
                catch { Issue.record(error) }
            }
            if let settings { Store.settings.setPersistentDomain(settings, forName: domain) }
            else { Store.settings.removePersistentDomain(forName: domain) }
            Density.current = densityBefore
        }
        // Browser may temporarily claim the shared book on a fresh host.
        // Release that claim before taking a private fixture book so its
        // cached shutSpaces and every shared row remain untouched.
        Folders.shared.browser = foldersBefore
        browser.takeOwnFolders()
        try #require(browser.ownFolders != nil && browser.folderBook !== Folders.shared,
                     "The fixture must never refresh or mutate the pre-existing shared book")
        browser.lookForMailSignInLink = {}
        browser.dropSpare(); browser.tabs.forEach { $0.close() }
        browser.prefs.sidebar = true; browser.prefs.sideShut = false
        browser.prefs.sideWidth = 240; browser.prefs.usesSpaces = true
        browser.prefs.searchSuggest = false; browser.prefs.fieldRequests = false
        browser.spaces = [Space(id: Space.firstID, name: "First fixture", icon: "F", ownSignIns: false), space]
        browser.parked[Space.firstID] = Parked(tabs: [], active: nil)
        browser.spaceID = space.id
        let tabs = (0..<count).map { n in
            let tab = Tab()
            tab.restore(url: URL(string: "https://sidebar-menu.invalid/\(n)")!, title: "Kept \(n)")
            tab.kept = true; tab.customMark = "key"
            browser.prepare(tab)
            return tab
        }
        browser.lay(tabs); browser.activeID = nil
        browser.folderBook.refresh()
        let made = Fixture(browser: browser)
        fixture = made
        try await check(made)
    }

    private func inputFiles() throws -> [String: Data] {
        let names = try FileManager.default.contentsOfDirectory(atPath: Store.folder.path).filter {
            $0 == "spaces.json" || $0 == "bookmarks.json" || $0 == "empty-folders.json"
            || (($0.hasPrefix("session") || $0.hasPrefix("spaces-window-")) && $0.hasSuffix(".json"))
        }
        return try Dictionary(uniqueKeysWithValues: names.map { ($0, try Data(contentsOf: Store.folder.appendingPathComponent($0))) })
    }
}
