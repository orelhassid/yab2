import AppKit
import Foundation
import Testing
import WebKit
@testable import Fast

@MainActor
@Suite(.serialized)
struct AppTabsTests {
    private func withModel(_ body: (TrailApps, UserDefaults, Browser) throws -> Void) rethrows {
        let domain = "AppTabsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        let browser = Browser(windowID: UUID())
        let settings = ["sidebar", "spaces", Preferences.leftTrailKey].map { ($0, Store.settings.object(forKey: $0)) }
        defer {
            browser.dismiss()
            browser.letGo()
            for tab in browser.tabs + browser.parked.values.flatMap(\.tabs) { tab.close() }
            defaults.removePersistentDomain(forName: domain)
            for (key, value) in settings { Store.settings.set(value, forKey: key) }
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            }
        }
        try body(TrailApps(defaults: defaults), defaults, browser)
    }

    private func page(_ browser: Browser, name: String = "Mail", store: WKWebsiteDataStore? = nil) -> Tab {
        let tab = Tab(configuration: Web.configuration(store: store ?? Spaces.store(for: browser.spaceID)))
        browser.prepare(tab)
        tab.restore(url: URL(string: "https://app-tabs.example/\(name)")!, title: name)
        return tab
    }

    @Test func layoutTogglePreservesIdentitySelectionAndMembership() throws {
        try withModel { model, _, browser in
            browser.prefs.sidebar = true
            browser.prefs.usesSpaces = true
            let tab = page(browser)
            browser.lay([tab])
            browser.activeID = tab.id
            model.pin(tab)
            let app = try #require(model.apps.first)
            browser.prefs.showLeftTrail = true
            let width = browser.spaceRailWidth
            browser.prefs.showLeftTrail = false
            #expect(width > 0)
            #expect(browser.spaceRailWidth == 0)
            #expect(browser.activeID == tab.id)
            #expect(browser.tabs.count == 1)
            #expect(browser.tabs.first === tab)
            #expect(model.backingTab(for: app, among: browser.tabs, in: browser) === tab)
            #expect(model.sidebarTabs(browser.tabs).isEmpty)
            #expect(tab.kept)
            browser.prefs.showLeftTrail = true
            #expect(browser.spaceRailWidth == width)
        }
    }

    @Test func membershipSurvivesNavigationAndRestorationUnderTheSavedKey() throws {
        try withModel { model, defaults, browser in
            let tab = page(browser)
            tab.keptKey = UUID()
            browser.lay([tab])
            model.pin(tab)
            let key = try #require(tab.keptKey)
            let restored = page(browser, name: "Inbox")
            restored.keptKey = key
            let reread = TrailApps(defaults: defaults)
            let app = try #require(reread.apps.first)
            #expect(reread.backingTab(for: app, among: [restored], in: browser) === restored)
            #expect(reread.address(for: restored) == app.id)
            restored.close()
        }
    }

    @Test func sameAddressDoesNotHideAnUnrelatedOpenTab() throws {
        try withModel { model, _, browser in
            let tab = page(browser), duplicate = page(browser)
            browser.lay([tab, duplicate])
            model.pin(tab)
            #expect(model.sidebarTabs(browser.tabs).map(\.id) == [duplicate.id])
        }
    }

    @Test func backingPageMustUseTheCurrentProfilesStore() throws {
        try withModel { model, _, browser in
            let tab = page(browser)
            browser.lay([tab])
            model.pin(tab)
            let app = try #require(model.apps.first)
            let own = Space(id: UUID(), name: "Own", icon: "person", ownSignIns: true)
            browser.spaces.append(own)
            let prior = Spaces.read()
            defer { Spaces.write(prior) }
            Spaces.write(browser.spaces)
            browser.spaceID = own.id
            #expect(model.backingTab(for: app, among: [tab], in: browser) == nil)
            let other = page(browser)
            model.pin(other)
            #expect(other.store !== tab.store)
            #expect(model.application(for: tab)?.id == app.id)
            #expect(model.backingTab(for: app, among: [tab, other], in: browser) === other)
            other.close()
        }
    }

    @Test func privateTabsCannotBecomeAppTabs() {
        withModel { model, _, browser in
            let tab = Tab(shy: true, configuration: Web.configuration(shy: true))
            browser.prepare(tab)
            tab.restore(url: URL(string: "https://app-tabs.example/private")!, title: "Private")
            browser.lay([tab])
            model.pin(tab)
            #expect(model.apps.isEmpty)
            #expect(model.address(for: tab) == nil)
        }
    }

    @Test func anotherSpaceInTheSameProfileReusesTheParkedPage() throws {
        try withModel { model, _, browser in
            let tab = page(browser)
            browser.lay([tab])
            model.pin(tab)
            let app = try #require(model.apps.first)
            let other = UUID()
            browser.parked[other] = Parked(tabs: [tab], active: tab.id)
            browser.lay([])
            browser.activeID = nil
            model.open(app, in: browser)
            #expect(browser.tabs.count == 1)
            #expect(browser.tabs.first === tab)
            #expect(browser.activeID == tab.id)
            #expect(browser.parked[other]?.tabs.isEmpty == true)
            model.open(app, in: browser)
            #expect(browser.tabs.count == 1)
        }
    }

    @Test func migrationKeepsLocalPinsLocalAndRegistersSharedPinsOnce() throws {
        try withModel { model, defaults, browser in
            let local = page(browser, name: "Local"), shared = page(browser, name: "Shared")
            local.pin = "L"
            let home = URL(string: "https://app-tabs.example/saved-home")!
            local.home = home
            local.homeTitle = "Saved home"
            shared.pin = "S"
            shared.everywhere = UUID()
            model.migrate([local], shared: false)
            #expect(local.pin == nil && local.kept && local.everywhere == nil)
            #expect(local.home == home && local.homeTitle == "Saved home")
            #expect(model.apps.isEmpty)
            model.migrate([shared], shared: true)
            model.migrate([shared], shared: true)
            #expect(model.apps.count == 1)
            #expect(TrailApps(defaults: defaults).apps.count == 1)
            #expect(model.application(for: shared) != nil)
            local.close()
            shared.close()
        }
    }

    @Test func unpinRestoresTheCurrentPageAsAnOpenTab() throws {
        try withModel { model, _, browser in
            let tab = page(browser)
            browser.lay([tab])
            browser.activeID = tab.id
            model.pin(tab)
            let app = try #require(model.apps.first)
            model.remove(app.id, in: browser)
            #expect(model.apps.isEmpty)
            #expect(!tab.kept && tab.pin == nil)
            #expect(browser.tabs.first === tab)
            #expect(browser.activeID == tab.id)
        }
    }

    @Test func settingIsSearchablePersistedAndAgentChangeable() throws {
        let row = try #require(SettingsItem.all.first { $0.id == "left-trail" })
        #expect(row.page == .appearance)
        #expect(NativeActions.classification(row) == "read_write")
        let descriptor = try #require(NativeActions.descriptors.first { $0["id"] as? String == "settings.set.left-trail" })
        try NativeActions.validate(["value": .bool(false)], descriptor: descriptor)
        #expect(throws: NativeFailure.self) { try NativeActions.validate(["value": .string("false")], descriptor: descriptor) }
        let prefs = Preferences()
        prefs.showLeftTrail = false
        #expect(!Preferences().showLeftTrail)
        prefs.showLeftTrail = true
        #expect(Preferences().showLeftTrail)
    }
}
