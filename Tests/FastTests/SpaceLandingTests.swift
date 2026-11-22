import Foundation
import Testing
@testable import Fast

@Suite(.serialized)
@MainActor
struct SpaceLandingTests {
    private func world(_ body: (Browser, UUID, UUID, [Tab], [Tab]) throws -> Void) rethrows {
        let saved = Store.settings.object(forKey: "spaces")
        let window = UUID()
        let browser = Browser(windowID: window)
        browser.prefs.usesSpaces = true
        let previousFolders = Folders.shared.browser
        Folders.shared.browser = browser
        let home = browser.spaceID
        let away = Space(id: UUID(), name: "podcast", icon: "🎙️", ownSignIns: false)
        browser.spaces.append(away)
        Spaces.sharing.insert(away.id)
        func tabs(_ prefix: String, _ count: Int) -> [Tab] {
            (0..<count).map { index in
                let tab = Tab()
                tab.restore(url: URL(string: "https://space-landing.test/\(prefix)/\(index)")!, title: "\(prefix) \(index)")
                browser.prepare(tab)
                return tab
            }
        }
        let source = tabs("home", 3), destination = tabs("podcast", 3)
        browser.lay(source)
        browser.activeID = source[1].id
        browser.parked[away.id] = Parked(tabs: destination, active: destination[0].id)
        let wasHand = Browser.pretendHand
        Browser.pretendHand = true
        defer {
            Browser.pretendHand = wasHand
            browser.letGo()
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            Folders.shared.browser = previousFolders
            Spaces.sharing.remove(away.id)
            Spaces.pageCounts[away.id] = nil
            Store.settings.set(saved, forKey: "spaces")
            for space in [home, away.id] {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(window.uuidString)-\(space.uuidString).json"))
            }
            try? FileManager.default.removeItem(at: Store.file("session-window-\(window.uuidString).json"))
            Store.settings.removeObject(forKey: "window.\(window.uuidString).space")
        }
        try body(browser, home, away.id, source, destination)
    }

    @Test func spacesMenuUsesThePersonalLookInSiteColorMode() throws {
        try world { browser, home, _, _, _ in
            let key = WorkspaceTheme.lookKey(home)
            let saved = Store.settings.data(forKey: key)
            let backdrop = browser.prefs.backdrop
            let mode = browser.prefs.lookMode
            defer {
                browser.prefs.backdrop = backdrop
                browser.prefs.lookMode = mode
                Store.settings.set(saved, forKey: key)
            }
            browser.prefs.backdrop = .site
            browser.prefs.lookMode = "dark"
            let look = SpacePaint(swatch: .sky, color: .blue, grain: 0, mode: "dark")
            Store.settings.set(try JSONEncoder().encode(look), forKey: key)
            #expect(SpaceSurface.tone(in: browser) == SpaceSurface.tone(for: SpaceWash.painted(look).color))

            Store.settings.removeObject(forKey: key)
            let fallback = browser.prefs.swatch.color(dark: true, custom: browser.prefs.backdropColor)
            #expect(SpaceSurface.tone(in: browser) == SpaceSurface.tone(for: fallback))
        }
    }

    @Test func developmentIsAWindowSpaceWithNoTabOrNumberedShortcut() throws {
        try world { browser, home, _, source, _ in
            let sidebar = browser.prefs.sidebar
            let shut = browser.prefs.sideShut
            defer { browser.prefs.sidebar = sidebar; browser.prefs.sideShut = shut }
            browser.enterDevelopment()
            #expect(browser.sidebarSpaceID == Space.development.id)
            #expect(browser.tabs.map(\.id) == source.map(\.id))
            #expect(!browser.switcherSpaces.contains { $0.id == Space.development.id })
            browser.developmentProject = .sunday
            browser.switchSpace(to: home)
            #expect(!browser.inDevelopment)
            #expect(browser.activeID == source[1].id)
            browser.enterDevelopment()
            #expect(browser.developmentProject == .sunday)
            let first = browser.switcherSpaces.first?.id
            let last = browser.switcherSpaces.last(where: { $0.id != Space.privateID })?.id
            browser.stepSpace(-1)
            #expect(browser.sidebarSpaceID == last)
            browser.enterDevelopment()
            browser.stepSpace(1)
            #expect(browser.sidebarSpaceID == first)
        }
    }

    @Test func developmentChromeFollowsTheSelectedProjectAndRestoresTheSpace() {
        world { browser, home, _, _, _ in
            let directory = DevelopmentDirectory.shared
            let original = directory.details(.yab)
            let stored = Store.settings.data(forKey: "development.projectDetails")
            defer {
                directory.save(original, for: .yab)
                Store.settings.set(stored, forKey: "development.projectDetails")
            }
            var edited = original
            let light = SpacePaint(swatch: .custom, color: .cyan, grain: 0, mode: "light")
            edited.paint = light
            directory.save(edited, for: .yab)
            browser.enterDevelopment()
            #expect(browser.developmentLook == light)
            #expect(SpaceWash.grounded(in: browser) == SpaceWash.painted(light))
            browser.developmentProject = .sunday
            let sunday = directory.details(.sunday).paint ?? SpacePaint(browser.prefs)
            #expect(SpaceWash.grounded(in: browser) == SpaceWash.painted(sunday))
            browser.switchSpace(to: home)
            #expect(browser.developmentLook == nil)
        }
    }

    @Test func developmentProjectSurvivesReloadAlongsideLegacyProjects() throws {
        let key = "development.projectDetails"
        let previous = Store.settings.data(forKey: key)
        defer { Store.settings.set(previous, forKey: key) }
        Store.settings.set(Data(#"{"sunday":{"name":"Sunday Studio","icon":"","folder":""}}"#.utf8), forKey: key)
        let directory = DevelopmentDirectory()
        let project = directory.create(folder: URL(fileURLWithPath: "/tmp/Example"))
        var details = directory.details(project)
        details.paint = SpacePaint(swatch: .custom, color: .red, grain: 0.3,
                                   colors: ["B6A6E6"], mode: "light")
        directory.save(details, for: project)
        let reopened = DevelopmentDirectory()
        #expect(reopened.details(project).paint == details.paint)
        #expect(reopened.details(.sunday).paint == nil)
        #expect(reopened.projects.last == project)
        #expect(reopened.details(.sunday).name == "Sunday Studio")
        #expect(reopened.details(.sunday).createdAt == nil)
        #expect(reopened.details(project).folder == "/tmp/Example")
        #expect(reopened.details(project).createdAt != nil)
        #expect(reopened.details(project).activity?.first?.title == "Project created")
    }

    /// Hovering another space with a tab in hand opens nothing there: the
    /// page stays, the field stays away, and what that space had in front
    /// is still in front on a real visit afterwards.
    @Test func carriedVisitOpensNothing() throws {
        try world { browser, home, away, source, destination in
            browser.carryHome = home
            browser.switchSpace(to: away)
            #expect(browser.spaceID == away)
            #expect(browser.activeID == nil)
            #expect(browser.underTab === source[1])
            #expect(!browser.fieldShowing)
            #expect(destination[0].built == nil)
            browser.switchSpace(to: home)
            #expect(browser.activeID == source[1].id)
            #expect(browser.parked[away]?.active == destination[0].id)
            browser.carryHome = nil
            browser.switchSpace(to: away)
            #expect(browser.activeID == destination[0].id)
            browser.switchSpace(to: home)
        }
    }

    @Test func aSpaceSelectedFromHomeKeepsHomeOverItsRememberedTab() {
        world { browser, home, away, source, destination in
            browser.openFresh()
            #expect(browser.showsHomeField)

            browser.switchSpace(to: away, keepingHome: true)
            #expect(browser.spaceID == away)
            #expect(browser.showsHomeField)
            #expect(browser.tabs.map(\.id) == destination.map(\.id))
            #expect(browser.activeID == destination[0].id)

            browser.select(destination[0])
            #expect(!browser.showsHomeField)
            browser.switchSpace(to: home)
            #expect(browser.activeID == source[1].id)
            #expect(!browser.showsHomeField)
        }
    }

    @Test func rowInTheVisitedSpaceIsInsertedAndChosenWithOneUndo() {
        world { browser, home, away, source, destination in
            browser.holdArranging()
            browser.switchSpace(to: away)
            let steps = browser.steps.count
            let arrived = browser.landTabs([source[1]], from: home, to: away, at: .row(index: 1, kept: false, nest: nil))
            browser.letGoArranging()
            #expect(arrived.first === source[1])
            #expect(browser.spaceID == away)
            #expect(browser.tabs.map(\.id) == [destination[0], source[1], destination[1], destination[2]].map(\.id))
            #expect(browser.activeID == source[1].id)
            #expect(browser.steps.count == steps + 1)
            #expect(browser.undoWindow())
            #expect(browser.spaceID == home)
            #expect(browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.activeID == source[1].id)
            #expect(browser.parked[away]?.tabs.map(\.id) == destination.map(\.id))
            // The tab in front there comes back too: no field on the next visit.
            #expect(browser.parked[away]?.active == destination[0].id)
        }
    }

    @Test func librariesFollowTheRequestingSpaceWithTheirControls() throws {
        try world { browser, home, away, _, _ in
            browser.showLibrary(.bookmarks)
            let tab = try #require(browser.active)
            let controls = browser.libraryControls(for: .bookmarks, tab: tab)
            let folder = UUID()
            controls.search = "design"
            controls.folder = folder
            for space in [away, home] {
                browser.switchSpace(to: space)
                browser.showLibrary(.bookmarks)
                #expect(browser.spaceID == space && browser.active === tab)
                #expect(browser.everyTab.filter { $0.libraryPage == .bookmarks }.count == 1)
                #expect(!browser.sidebarLooseTabs.contains { $0 === tab })
                let current = browser.libraryControls(for: .bookmarks, tab: tab)
                #expect(current.search == "design" && current.folder == folder)
            }
            #expect(browser.libraryControls(for: .history, tab: tab) !== controls)
            let privateTab = Tab(shy: true, configuration: Web.configuration(shy: true))
            #expect(browser.libraryControls(for: .bookmarks, tab: privateTab) !== controls)
        }
    }

    @Test func parkedFolderExpansionFinishesInItsOwningSpace() throws {
        try world { browser, home, away, source, destination in
            let scope = SidebarSpaceActions(browser: browser, id: away)
            scope.run { browser.newFolder(with: destination, today: true) }
            let nest = try #require(destination[0].nest)
            for expected in [false, true] {
                scope.run { browser.folderBook.toggle(nest.key, knownNest: nest, immediately: true) }
                #expect(nest.open == expected)
                #expect(browser.spaceID == home && browser.active === source[1])
                let parked = try #require(browser.parked[away])
                let space = try #require(browser.spaces.first { $0.id == away })
                let page = ColumnLayout.parked(browser, row: parked, travelling: [], space: space)
                #expect(page.items.contains { $0.tab === destination[2] } == expected)
            }
        }
    }

    @Test func sharedSidebarRowsOperateInTheirOwningSpace() {
        world { browser, home, away, source, destination in
            let scope = SidebarSpaceActions(browser: browser, id: away)
            scope.run { browser.newFolder(with: Array(destination.prefix(2)), today: true, around: destination[0]) }
            #expect(destination[0].nest != nil && destination[0].nest === destination[1].nest)
            #expect(browser.spaceID == home && browser.active === source[1])
            scope.run { browser.shut(destination[2]) }
            #expect(browser.parked[away]?.tabs.contains { $0 === destination[2] } == false)
            #expect(browser.spaceID == home && browser.active === source[1])
            scope.run({ browser.tapTab(destination[1]) }, stay: true)
            #expect(browser.spaceID == away && browser.active === destination[1])
        }
    }

    @Test func overviewMovesBetweenColumnsAndKeepsTheBoardOpen() {
        world { browser, home, away, source, destination in
            let board = source[1], tab = source[0]
            #expect(browser.moveOverviewTab(tab, from: home, to: away, before: destination[1].id, board: board))
            #expect(browser.active === board)
            #expect(browser.parked[away]?.tabs.map(\.id) == [destination[0], tab, destination[1], destination[2]].map(\.id))
            #expect(!browser.moveOverviewTab(tab, from: home, to: away, before: nil, board: board))
            #expect(browser.moveOverviewTab(tab, from: away, to: home, before: board.id, board: board))
            #expect(browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.parked[away]?.tabs.map(\.id) == destination.map(\.id))
            #expect(browser.spaceID == home && browser.active === board)
        }
    }

    @Test func modalOverviewCanMoveTheSelectedTabWithoutOpeningABoardTab() {
        world { browser, home, away, source, destination in
            let active = source[1]
            #expect(browser.active === active)
            #expect(browser.moveOverviewTab(active, from: home, to: away, before: destination[0].id))
            #expect(browser.spaceID == home && browser.parked[away]?.tabs.first === active)
            #expect(browser.everyTab.allSatisfy { $0.libraryPage != .tabs })
        }
    }

    @Test func overviewReordersActiveAndParkedRowsInSidebarOrder() {
        world { browser, home, away, source, destination in
            let board = source[1]
            #expect(browser.moveOverviewTab(source[0], from: home, to: home, before: nil, board: board, afterLastVisible: source[2].id))
            #expect(browser.tabs.map(\.id) == [board, source[2], source[0]].map(\.id))
            #expect(browser.undoWindow())
            #expect(browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.moveOverviewTab(destination[2], from: away, to: away, before: destination[0].id, board: board))
            #expect(browser.spaceID == home && browser.active === board)
            let expected = [destination[2], destination[0], destination[1]].map(\.id)
            #expect(browser.parked[away]?.tabs.map(\.id) == expected)
            browser.switchSpace(to: away)
            #expect(browser.sidebarLooseTabs.map(\.id) == expected)
        }
    }

    @Test func overviewMovesSplitPartnersTogetherAndPreservesTheirOrder() {
        world { browser, _, away, source, destination in
            let board = source[1]
            browser.parked[away]?.pairs = [Pair(first: destination[0].id, second: destination[1].id, share: 0.5)]
            #expect(browser.moveOverviewTab(destination[1], from: away, to: away, before: nil, board: board))
            #expect(browser.parked[away]?.tabs.map(\.id) == [destination[2], destination[0], destination[1]].map(\.id))
            #expect(browser.active === board)
        }
    }

    @Test func filteredOverviewDropsAfterLastVisibleAndRespectsKeptBoundary() {
        world { browser, home, _, source, _ in
            let board = source[1]
            source[0].kept = true
            #expect(!browser.moveOverviewTab(source[0], from: home, to: home, before: nil, board: board))
            source[0].kept = false
            #expect(browser.moveOverviewTab(source[0], from: home, to: home, before: nil, board: board, afterLastVisible: board.id))
            #expect(browser.tabs.map(\.id) == [board, source[0], source[2]].map(\.id))
        }
    }

    @Test func overviewCanSendBetweenTwoParkedSpacesAndUndo() {
        world { browser, home, away, source, destination in
            let third = Space(id: UUID(), name: "Reading", icon: "📚", ownSignIns: false)
            browser.spaces.append(third)
            Spaces.sharing.insert(third.id)
            defer {
                Spaces.sharing.remove(third.id)
                if let window = browser.windowID {
                    try? FileManager.default.removeItem(at: Store.file("session-window-\(window.uuidString)-\(third.id.uuidString).json"))
                }
            }
            browser.parked[third.id] = Parked(tabs: [], active: nil)
            let board = source[1], tab = destination[1]
            #expect(browser.moveOverviewTab(tab, from: away, to: third.id, before: nil, board: board))
            #expect(browser.parked[third.id]?.tabs.first === tab)
            #expect(browser.spaceID == home && browser.active === board)
            #expect(browser.undoWindow())
            #expect(browser.spaceID == away && browser.tabs.map(\.id) == destination.map(\.id))
            #expect(browser.parked[third.id]?.tabs.isEmpty == true)
        }
    }

    @Test func dotDropIsTopOfTodayAndCanStayAtHome() {
        world { browser, home, away, source, destination in
            destination[0].kept = true
            source[1].kept = true
            browser.lay([source[1], source[0], source[2]])
            let before = browser.tabs.map(\.id)
            browser.landTabs([source[1]], from: home, to: away, at: .todayTop, showing: false)
            #expect(browser.spaceID == home)
            #expect(browser.parked[away]?.tabs.map(\.id) == [destination[0], source[1], destination[1], destination[2]].map(\.id))
            #expect(!source[1].kept && source[1].nest == nil)
            #expect(browser.undoWindow())
            #expect(source[1].kept)
            #expect(browser.tabs.map(\.id) == before)
        }
    }

    @Test func keptAndFolderLandingsRestoreSourceMarks() {
        world { browser, home, away, source, destination in
            let folder = Nest(name: "Listen")
            destination[0].kept = true
            destination[0].nest = folder
            browser.switchSpace(to: away)
            browser.landTabs([source[1]], from: home, to: away, at: .folder(folder.id))
            #expect(source[1].kept && source[1].nest === folder)
            #expect(browser.tabs.map(\.id) == [destination[0], source[1], destination[1], destination[2]].map(\.id))
            #expect(browser.undoWindow())
            #expect(!source[1].kept && source[1].nest == nil)
            #expect(browser.spaceID == home)
        }
    }

    @Test func overviewFilesIntoParkedFolderAndKeepsBoardSelected() {
        world { browser, home, away, source, destination in
            let folder = Nest(name: "Listen", open: false)
            destination[0].kept = true
            destination[0].nest = folder
            let moved = browser.moveOverviewTab(source[2], from: home, to: away, before: nil,
                                                board: source[1], placement: .folder(folder.id))
            #expect(moved && source[2].nest === folder && source[2].kept)
            #expect(browser.parked[away]?.tabs.map(\.id) == [destination[0], source[2], destination[1], destination[2]].map(\.id))
            #expect(browser.spaceID == home && browser.active === source[1])
            #expect(browser.undoWindow())
            #expect(source[2].nest == nil && browser.tabs.map(\.id) == source.map(\.id))
        }
    }

    @Test func overviewInsertsIntoExpandedFolderAndBackIntoLooseRows() {
        world { browser, home, _, source, _ in
            let folder = Nest(name: "Reading")
            folder.fleeting = true
            source[0].nest = folder
            let filed = browser.moveOverviewTab(source[2], from: home, to: home, before: nil, board: source[1],
                                                placement: .row(index: 0, kept: false, nest: folder.id))
            #expect(filed && source[2].nest === folder && browser.tabs.first === source[2])
            let unfiled = browser.moveOverviewTab(source[2], from: home, to: home, before: nil, board: source[1],
                                                  placement: .row(index: 2, kept: false, nest: nil))
            #expect(unfiled && source[2].nest == nil && browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.active === source[1])
        }
    }

    @Test func pinLandingAndUndoRestoreBothRows() {
        world { browser, home, away, source, destination in
            browser.switchSpace(to: away)
            browser.landTabs([source[1]], from: home, to: away, at: .pin(0))
            #expect(browser.tabs.first === source[1] && source[1].pin != nil)
            #expect(browser.activeID == source[1].id)
            #expect(browser.undoWindow())
            #expect(source[1].pin == nil && source[1].everywhere == nil)
            #expect(browser.spaceID == home && browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.parked[away]?.tabs.map(\.id) == destination.map(\.id))
        }
    }

    @Test func wholeFolderKeepsItsChildrenAndUndoRestoresItsParent() {
        world { browser, home, away, source, destination in
            let parent = Nest(name: "Parent"), folder = Nest(name: "Episodes")
            folder.parent = parent
            for tab in source.prefix(2) { tab.kept = true; tab.nest = folder }
            browser.folderBook.refresh()
            browser.switchSpace(to: away)
            browser.landTabs(Array(source.prefix(2)), from: home, to: away,
                             at: .row(index: 0, kept: true, nest: nil), folder: folder)
            #expect(folder.parent == nil)
            #expect(source[0].nest === folder && source[1].nest === folder)
            #expect(browser.tabs.prefix(2).map(\.id) == Array(source.prefix(2)).map(\.id))
            #expect(browser.undoWindow())
            #expect(folder.parent === parent && browser.spaceID == home)
            #expect(browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.parked[away]?.tabs.map(\.id) == destination.map(\.id))
        }
    }

    @Test func emptyFolderCanLandBetweenKeptTabsAndUndo() throws {
        try world { browser, home, away, _, destination in
            for tab in destination.prefix(2) { tab.kept = true }
            let folder = try #require(browser.folderBook.makeEmpty(named: "Empty episodes"))
            defer { browser.folderBook.removeEmpty(folder) }
            browser.switchSpace(to: away)
            browser.landTabs([], from: home, to: away, at: .row(index: 1, kept: true, nest: nil), folder: folder)
            #expect(browser.folderBook.empties.contains { $0 === folder })
            #expect(folder.stand?.before == destination[1].id)
            #expect(browser.undoWindow())
            #expect(browser.spaceID == home)
            #expect(browser.folderBook.empties.contains { $0 === folder })
            #expect(!browser.folderBook.empties(in: away).contains { $0 === folder })
        }
    }

    @Test func aTodayLandingCannotSplitTheKeptBlock() {
        world { browser, home, away, source, destination in
            destination[0].kept = true
            browser.landTabs([source[1]], from: home, to: away, at: .row(index: -100, kept: false, nest: nil))
            #expect(browser.tabs.map(\.id) == [destination[0], source[1], destination[1], destination[2]].map(\.id))
            #expect(!source[1].kept)
        }
    }

    @Test func invalidTargetDoesNotChangeAnything() {
        world { browser, home, _, source, _ in
            let steps = browser.steps.count
            #expect(browser.landTabs([source[1]], from: home, to: UUID(), at: .todayTop).isEmpty)
            #expect(browser.spaceID == home && browser.tabs.map(\.id) == source.map(\.id))
            #expect(browser.steps.count == steps)
        }
    }

    @Test func identityReplacementRestoresMarksOrderAndPairs() {
        world { browser, _, _, source, _ in
            source[1].kept = true
            browser.lay([source[1], source[0], source[2]])
            browser.pairs = [Pair(first: source[1].id, second: source[2].id)]
            let shape = RowShape(browser)
            // The pair's halves sit together, so the order to come back is
            // the one the shape took, not the one laid above.
            let laid = browser.tabs.map(\.id)
            let fresh = Tab()
            fresh.restore(url: URL(string: "https://space-landing.test/reopened")!, title: "Reopened")
            browser.prepare(fresh)
            browser.lay([source[0], source[2], fresh])
            browser.put(shape, replacing: [source[1].id: fresh])
            #expect(browser.tabs.map(\.id) == laid.map { $0 == source[1].id ? fresh.id : $0 })
            #expect(fresh.kept)
            #expect(browser.pairs == [Pair(first: fresh.id, second: source[2].id)])
        }
    }
}
