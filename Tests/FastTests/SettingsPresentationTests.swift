import AppKit
import Foundation
import Testing
@testable import Fast

@Suite(.serialized)
struct SettingsPresentationTests {
    @Test func groupedNavigationContainsEveryTopLevelPageOnce() {
        let pages = SettingsNavigation.groups.flatMap(\.pages)
        #expect(Set(pages) == Set(SettingsPage.allCases.map(SettingsNavigation.destination(for:))))
        #expect(SettingsNavigation.groups.map(\.title) == ["Personal", "Workspace", "Tools", "Other"])
        #expect(pages.count == Set(pages).count)
        #expect(Array(pages.prefix(3)) == [.profile, .appearance, .general])
        #expect(SettingsNavigation.maximumWidth(for: .general) < SettingsNavigation.maximumWidth(for: .shortcuts))
    }

    @MainActor @Test func profileIsTheInitialPageAndEditorsKeepTheirDestination() {
        let model = SettingsModel()
        #expect(model.page == .profile)
        #expect(SettingsNavigation.destination(for: .passwords) == .profile)
        #expect(SettingsNavigation.destination(for: .bringIn) == .profile)
        #expect(SettingsNavigation.destination(for: .search) == .general)
        #expect(SettingsNavigation.collections(for: .boosts) == [.extensions, .boosts])
        #expect(SettingsNavigation.collections(for: .liveFolders) == [.tabs, .liveFolders])
        #expect(SettingsNavigation.collections(for: .snippets) == [.shortcuts, .snippets])
        #expect(SettingsItem.all.first { $0.id == "updates" }?.page == .about)
        #expect(SettingsResult.search("Check for updates").best?.page == .about)
    }

    @Test func submenusFollowExistingPageOwnership() {
        #expect(SettingsNavigation.children(of: .websites).contains(.reading))
        #expect(SettingsNavigation.children(of: .ai).contains(.models))
        #expect(SettingsNavigation.children(of: .tabs).isEmpty)
        let children = SettingsPage.sidebar.flatMap { SettingsNavigation.children(of: $0) }
        #expect(Set(children) == Set(SettingsPage.allCases.filter { $0.parent != nil && $0.available }))
        #expect(children.count == Set(children).count)
    }

    @Test func freshAndUnknownPreferencesOpenInATab() throws {
        let domain = "SettingsPresentationTests.\(UUID().uuidString)"
        let store = try #require(UserDefaults(suiteName: domain))
        defer { store.removePersistentDomain(forName: domain) }
        #expect(SettingsPresentation.read(from: store) == .tab)
        store.set("window", forKey: SettingsPresentation.key)
        #expect(SettingsPresentation.read(from: store) == .window)
        store.set("tab", forKey: SettingsPresentation.key)
        #expect(SettingsPresentation.read(from: store) == .tab)
        store.set("popup", forKey: SettingsPresentation.key)
        #expect(SettingsPresentation.read(from: store) == .tab)
    }

    @MainActor @Test func presentationIsSearchableAndAgentChangeable() throws {
        let row = try #require(SettingsItem.all.first { $0.id == "settings-presentation" })
        #expect(row.page == .general)
        #expect(NativeActions.classification(row) == "read_write")
        let descriptor = try #require(NativeActions.descriptors.first { $0["id"] as? String == "settings.set.settings-presentation" })
        try NativeActions.validate(["value": .string("tab")], descriptor: descriptor)
        try NativeActions.validate(["value": .string("window")], descriptor: descriptor)
        #expect(throws: NativeFailure.self) { try NativeActions.validate(["value": .string("popup")], descriptor: descriptor) }
        #expect(throws: NativeFailure.self) { try NativeActions.validate(["value": .bool(true)], descriptor: descriptor) }
        #expect(LibraryPage(url: URL(string: "yab://settings")) == .settings)
    }

    @MainActor @Test func theSameSettingsMovesBetweenTabAndWindow() throws {
        _ = NSApplication.shared
        let old = Store.settings.object(forKey: SettingsPresentation.key)
        let browser = Browser(windowID: UUID())
        let frame = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 750),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        frame.isReleasedWhenClosed = false
        defer {
            SettingsWindow.shared.hide()
            frame.close()
            for tab in browser.tabs { tab.close() }
            Store.settings.set(old, forKey: SettingsPresentation.key)
        }
        Store.settings.removeObject(forKey: SettingsPresentation.key)
        SettingsWindow.shared.show(.general, for: browser)
        let tab = try #require(browser.active)
        #expect(tab.libraryPage == .settings)
        let model = try #require(SettingsWindow.shared.model)
        let host = SettingsTabHost(browser: browser, tab: tab)
        frame.contentView = host
        frame.makeKeyAndOrderFront(nil)
        host.attach()
        #expect(SettingsWindow.shared.window === frame)
        #expect(SettingsWindow.shared.isShowing)
        #expect(SettingsCards.owns(frame))
        frame.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        func fields(in view: NSView) -> [NSTextField] {
            ((view as? NSTextField).map { [$0] } ?? []) + view.subviews.flatMap { fields(in: $0) }
        }
        let search = try #require(fields(in: host).first { $0.placeholderString == "Search settings" })
        let searchRect = search.convert(search.bounds, to: host)
        #expect(searchRect.width > 200 && searchRect.width <= LibraryPageLayout.searchWidth,
                "Search belongs to the header actions")
        #expect(searchRect.minX > host.bounds.width / 2)
        #expect(searchRect.maxX <= host.bounds.width - LibraryPageLayout.inset)
        SettingsWindow.shared.detachTab(host)
        #expect(!SettingsCards.shared.showing)
        #expect(!SettingsCards.owns(frame))
        host.attach()
        #expect(SettingsCards.shared.showing)
        SettingsWindow.shared.show(.privacy, for: browser)
        #expect(browser.tabs.filter { $0.libraryPage == .settings }.count == 1)
        #expect(SettingsWindow.shared.model === model)
        #expect(model.page == .privacy)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        #expect(tab.canGoBack)
        browser.back()
        #expect(model.page == .general)
        #expect(tab.canGoForward)
        browser.forward()
        #expect(model.page == .privacy)
        Store.settings.set("window", forKey: SettingsPresentation.key)
        SettingsWindow.shared.show(.general, for: browser)
        #expect(SettingsWindow.shared.window is SettingsFrame)
        #expect(SettingsWindow.shared.window?.isVisible == true)
        #expect(SettingsWindow.shared.model === model)
        #expect(!browser.tabs.contains { $0.libraryPage == .settings })
        let settingsFrame = try #require(SettingsWindow.shared.window)
        let size = settingsFrame.frame.size
        for _ in 0..<3 { SettingsWindow.shared.show(.general, for: browser) }
        settingsFrame.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        #expect(settingsFrame.contentViewController?.view.window === settingsFrame)
        #expect(settingsFrame.frame.size == size)
        #expect(settingsFrame.contentView?.bounds.width == size.width)
        #expect((settingsFrame.contentView?.bounds.height ?? 0) > 400)
        // An explicitly opened internal tab works even when future Settings
        // opens are configured to use a separate window.
        browser.showLibrary(.settings)
        host.tab = browser.active
        host.attach()
        #expect(SettingsWindow.shared.window === frame)
        Store.settings.set("tab", forKey: SettingsPresentation.key)
        SettingsWindow.shared.show(.general, for: browser)
        let next = try #require(browser.active)
        host.tab = next
        host.attach()
        #expect(SettingsWindow.shared.window === frame)
        #expect(SettingsWindow.shared.model === model)
        #expect(SettingsWindow.shared.isShowing)
        SettingsWindow.shared.hide()
        #expect(frame.isVisible)
        #expect(!browser.tabs.contains { $0.libraryPage == .settings })
    }

}
