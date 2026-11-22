import AppKit
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct PrivateSpaceTests {
    private func withBrowser(_ run: (Browser) throws -> Void) rethrows {
        _ = NSApplication.shared
        let id = UUID()
        let browser = Browser(windowID: id)
        let key = "window.\(id.uuidString).space"
        let suggestions = browser.prefs.searchSuggest
        let menuCommands = browser.prefs.menuCommands
        let commands = FieldUnder.shared.commands
        browser.prefs.searchSuggest = false
        browser.prefs.menuCommands = false
        FieldUnder.shared.commands = true
        defer {
            browser.letGo()
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            browser.prefs.searchSuggest = suggestions
            browser.prefs.menuCommands = menuCommands
            FieldUnder.shared.commands = commands
            Store.settings.removeObject(forKey: key)
        }
        try run(browser)
    }

    @Test func privateSpaceParksTabsAndClearsBothEngineIdentities() throws {
        try withBrowser { browser in
            let home = browser.spaceID
            let window = try #require(browser.windowID)
            let key = "window.\(window.uuidString).space"
            Store.settings.set(home.uuidString, forKey: key)
            let ordinary = browser.blankTab()
            browser.lay([ordinary])
            browser.activeID = ordinary.id

            Command.privateTab.run(in: browser)
            #expect(browser.inPrivateSpace && browser.privateBrowsing)
            #expect(browser.windowID == window && browser.windowPurpose == .normal)
            #expect(browser.switcherSpaces.contains { $0.id == Space.privateID })
            #expect(browser.tabs.isEmpty && browser.fieldShowing)
            #expect(Store.settings.string(forKey: key) == home.uuidString)

            let first = browser.open(URL(string: "about:blank")!, foreground: true)
            let second = browser.open(URL(string: "about:blank")!, foreground: true, from: first)
            #expect(first.shy && second.shy && !first.store.isPersistent)
            #expect(first.store === second.store && first.store !== ordinary.store)
            let profile = ChromiumPrivateProfiles.profile(for: first)
            #expect(ChromiumPrivateProfiles.profile(for: second) == profile)

            Command.leavePrivateSpace.run(in: browser)
            #expect(browser.spaceID == home && browser.tabs.map(\.id) == [ordinary.id])
            #expect(!browser.privateBrowsing && !first.gone && !second.gone)
            browser.openPrivateSpace()
            #expect(Set(browser.tabs.map(\.id)) == Set([first.id, second.id]))
            #expect(browser.activeID == second.id)
            browser.flushSession()
            let privateSessionFile = Store.file("session-window-\(window.uuidString)-\(Space.privateID.uuidString).json")
            #expect(!FileManager.default.fileExists(atPath: privateSessionFile.path))
            #expect(Session.read(space: Space.privateID, window: window).tabs.isEmpty)

            browser.clearPrivateSession()
            #expect(browser.inPrivateSpace && browser.privateBrowsing && browser.fieldShowing)
            #expect(browser.tabs.isEmpty && first.gone && second.gone)
            #expect(ChromiumPrivateProfiles.existing(for: first.store) == nil)
            let fresh = browser.open(URL(string: "about:blank")!, foreground: true)
            #expect(fresh.shy && !fresh.store.isPersistent && fresh.store !== first.store)
            #expect(ChromiumPrivateProfiles.profile(for: fresh) != profile)

            browser.leavePrivateSpace()
            browser.endPrivateSession()
            browser.openPrivateSpace()
            #expect(fresh.gone && browser.tabs.isEmpty && browser.privateBrowsing)
        }
    }

    @Test func newTabShowsPrivateHomeAndKeepsNavigationInTheSession() {
        withBrowser { browser in
            let historyURL = "https://personal-history.example/"
            browser.history = History([Visit(url: historyURL, key: historyURL, title: "Personal History",
                                             count: 20, last: Date(), typed: 10)])
            browser.homeSection = "history"
            browser.openPrivateSpace()
            #expect(browser.showsHomeField && browser.tabs.isEmpty)
            browser.replaceTyped("personal-history")
            #expect(browser.showsHomeField)
            #expect(!browser.offers.contains { $0.url?.absoluteString == historyURL })
            browser.openCommandField()
            #expect(browser.fieldShowing && !browser.showsHomeField)
            browser.pressNewTab()
            #expect(browser.showsHomeField)

            browser.replaceTyped("about:blank")
            browser.submit()
            let first = browser.active
            #expect(first?.shy == true && browser.tabs.count == 1)
            browser.pressNewTab()
            #expect(browser.showsHomeField && browser.active === first)
            browser.replaceTyped("about:blank")
            browser.submit()
            #expect(browser.tabs.count == 2)
            #expect(browser.tabs.allSatisfy { $0.shy && $0.store === first?.store })
            browser.clearPrivateSession()
            #expect(browser.showsHomeField && browser.tabs.isEmpty)
            #expect(browser.homeSection == "history")
        }
    }

    @Test func privateCommandsLeadComposedOffers() {
        withBrowser { browser in
            let url = "https://private-command.test/"
            browser.history = History([Visit(url: url, key: url, title: "Open Private Space Clear Session Leave Private Space",
                                             count: 20, last: Date(), typed: 10)])
            #expect(!Command.clearPrivateSession.available(in: browser))
            #expect(!Command.leavePrivateSpace.available(in: browser))
            browser.replaceTyped("Open Private Space")
            #expect(browser.offers.first?.kind == .command(.privateTab))
            #expect(Command.privateTab.keys == Keymap.shared.text(.privateTab))
            Command.privateTab.run(in: browser)
            for (words, command) in [("Clear Session", Command.clearPrivateSession), ("Leave Private Space", .leavePrivateSpace)] {
                browser.replaceTyped(words)
                #expect(browser.offers.first?.kind == .command(command))
            }
        }
    }
}
