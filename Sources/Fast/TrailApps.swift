import SwiftUI

/// App membership is shared; live pages always belong to the current profile.
@MainActor
final class TrailApps: ObservableObject {
    struct App: Identifiable, Codable {
        var id: URL
        var title: String
        var members: Set<UUID>?
        var legacy: Bool?
    }

    static let shared = TrailApps(defaults: Store.settings)
    @Published private(set) var apps: [App]
    private let defaults: UserDefaults
    private static let key = "sidebar.pinnedApps"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        apps = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([App].self, from: $0) } ?? []
    }

    func address(for tab: Tab?) -> URL? {
        guard let tab, !tab.shy, !tab.bench, tab.agent == nil, let url = tab.address ?? tab.pending, Bookmark.keepable(url) else { return nil }
        if let app = application(for: tab) { return app.id }
        return url
    }

    func application(for tab: Tab) -> App? {
        guard !tab.shy, tab.agent == nil else { return nil }
        return apps.first { app in
            app.members?.contains(tab.id) == true || tab.keptKey.map { app.members?.contains($0) == true } == true
                || tab.everywhere.map { app.members?.contains($0) == true } == true
        }
    }

    func contains(_ url: URL) -> Bool { apps.contains { $0.id == url } }

    func pin(_ tab: Tab) {
        guard let url = address(for: tab) else { return }
        if let browser = tab.delegate as? Browser {
            guard browser.windowPurpose == .normal, !browser.blank,
                  tab.store === Spaces.store(for: browser.spaceID) else { return }
            // A split stays intact: its app opens a separate page, rather
            // than hiding one half of a row that still draws both halves.
            if browser.pair(of: tab.id) != nil {
                if !contains(url) { apps.append(App(id: url, title: tab.label, members: [])); save() }
                return
            }
            tab.nest = nil
            if tab.pin == nil { tab.kept = true }
        }
        if let index = apps.firstIndex(where: { $0.id == url }) {
            associate(tab, at: index)
        } else {
            apps.append(App(id: url, title: tab.label, members: [tab.id]))
            save()
        }
        if let browser = tab.delegate as? Browser {
            browser.lay(browser.tabs.filter { $0.pin != nil } + browser.tabs.filter { $0.pin == nil && $0.kept } + browser.tabs.filter { $0.pin == nil && !$0.kept })
            browser.writeSession(now: true)
            if let index = apps.firstIndex(where: { $0.id == url }) { associate(tab, at: index) }
        }
    }

    private func associate(_ tab: Tab, at index: Int) {
        var app = apps[index]
        let keys = Set([tab.id] + [tab.keptKey, tab.everywhere].compactMap { $0 })
        if keys.isSubset(of: app.members ?? []) { return }
        if app.members == nil { app.legacy = true }
        var members = app.members ?? []
        if let browser = tab.delegate as? Browser {
            members.subtract(browser.tabs.filter { $0.store === tab.store }.map(\.id))
        }
        members.insert(tab.id)
        if let key = tab.keptKey { members.insert(key) }
        if let key = tab.everywhere { members.insert(key) }
        app.members = members
        apps[index] = app
        save()
    }

    func backingTab(for app: App, among tabs: [Tab], in browser: Browser? = nil) -> Tab? {
        let tabs = tabs.filter { tab in
            !tab.shy && tab.agent == nil && (browser.map { tab.store === Spaces.store(for: $0.spaceID) } ?? true)
        }
        if let member = tabs.first(where: { application(for: $0)?.id == app.id }) { return member }
        // Previous versions saved only the URL. Adopt one existing tab per Space.
        guard app.members == nil || app.legacy == true else { return nil }
        return tabs.first { !$0.shy && $0.agent == nil && ($0.address ?? $0.pending) == app.id }
    }

    func sidebarTabs(_ tabs: [Tab]) -> [Tab] {
        guard !apps.isEmpty else { return tabs }
        let hidden = Set(apps.compactMap { backingTab(for: $0, among: tabs)?.id })
        return tabs.filter { !hidden.contains($0.id) }
    }

    func remove(_ url: URL, in owner: Browser? = nil) {
        // Release all live copies before forgetting their stable membership.
        var browsers = BrowserWindows.shared.normalBrowsers
        if let owner, !browsers.contains(where: { $0 === owner }) { browsers.append(owner) }
        let copies = browsers.map { browser in
            (browser, (browser.tabs + browser.parked.values.flatMap(\.tabs)).filter { application(for: $0)?.id == url })
        }
        apps.removeAll { $0.id == url }
        save()
        for (browser, tabs) in copies {
            for tab in tabs {
                tab.pin = nil
                tab.everywhere = nil
                tab.kept = false
            }
            browser.lay(browser.tabs.filter { $0.pin != nil } + browser.tabs.filter { $0.pin == nil && $0.kept } + browser.tabs.filter { $0.pin == nil && !$0.kept })
            browser.writeRows()
        }
    }

    func open(_ app: App, in browser: Browser) {
        guard browser.windowPurpose == .normal, !browser.blank, !browser.privateBrowsing,
              let index = apps.firstIndex(where: { $0.id == app.id }) else { return }
        let candidates = browser.tabs.filter { !$0.shy && $0.agent == nil && $0.store === Spaces.store(for: browser.spaceID) }
        var existing = backingTab(for: apps[index], among: candidates, in: browser)
        if existing == nil {
            for (space, var row) in browser.parked where space != Space.pinsID {
                guard let tab = backingTab(for: apps[index], among: row.tabs, in: browser), browser.pair(of: tab.id) == nil,
                      !row.pairs.contains(where: { $0.contains(tab.id) }) else { continue }
                row.tabs.removeAll { $0 === tab }
                if row.active == tab.id { row.active = nil }
                browser.parked[space] = row
                browser.writeRow(row.tabs, active: row.active, space: space, pairs: row.pairs, now: true)
                browser.lay(browser.tabs + [tab])
                existing = tab
                break
            }
        }
        // Do not adopt an unrelated normal tab just because its URL matches.
        // Opening without `from` deliberately uses the current Space's store.
        let tab = existing ?? browser.open(app.id, foreground: true, rowNow: true)
        if tab.pin == nil { tab.kept = true }
        associate(tab, at: index)
        browser.lay(browser.tabs.filter { $0.pin != nil } + browser.tabs.filter { $0.pin == nil && $0.kept } + browser.tabs.filter { $0.pin == nil && !$0.kept })
        browser.writeSession(now: true)
        associate(tab, at: index)
        if existing != nil { browser.select(tab) }
    }

    /// Older shared icon pins join App Tabs without changing their live page.
    /// Space-specific icon pins become named Pinned Tabs instead.
    func migrate(_ row: [Tab], shared: Bool) {
        for tab in row where tab.pin != nil && !MailPage.isMail(tab.pending ?? tab.address) {
            if shared {
                guard let url = tab.home ?? tab.address ?? tab.pending, Bookmark.keepable(url) else { continue }
                if let index = apps.firstIndex(where: { $0.id == url }) {
                    associate(tab, at: index)
                } else {
                    apps.append(App(id: url, title: tab.label, members: [tab.everywhere ?? tab.id, tab.id]))
                    save()
                }
            } else {
                // Keep the home before clearing the old icon-pin flag.
                // Clearing both saved states even briefly forgets its URL.
                tab.kept = true
                tab.pin = nil
                tab.everywhere = nil
            }
        }
        for app in apps {
            if let tab = backingTab(for: app, among: row), tab.pin == nil { tab.kept = true }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(apps) { defaults.set(data, forKey: Self.key) }
    }
}

extension Browser {
    func sidebarTabs(_ row: [Tab]) -> [Tab] {
        let pages = row.filter { $0.libraryPage == nil }
        return TrailApps.shared.sidebarTabs(pages)
    }

    var sidebarLooseTabs: [Tab] { sidebarTabs(tabs).filter { $0.pin == nil } }
    func moveSidebarTab(_ tab: Tab, toLooseRow index: Int) {
        let loose = sidebarLooseTabs
        guard loose.indices.contains(index), let at = tabs.firstIndex(where: { $0 === loose[index] }) else { return }
        move(tab, to: at)
    }

    var sidebarGridPins: [Tab] { sidebarTabs(tabs).filter { $0.pin != nil && !pinTucked($0) } }

    var sidebarAppsShown: Bool { prefs.sidebar && spaceRailWidth == 0 && windowPurpose == .normal && !blank && !inMail }
    var sidebarAppsHeight: CGFloat {
        guard sidebarAppsShown, !TrailApps.shared.apps.isEmpty else { return 0 }
        return ColumnLayout.pinBlock(count: TrailApps.shared.apps.count, width: sidebarContentWidth)
    }

    func pinInCurrentSpace(_ group: [Tab]) {
        guard !blank else { return }
        let group = group.filter { !$0.shy && !$0.bench && !$0.isBlank && !Agents.shared.sealed($0) }
        for tab in group {
            let home = tab.home, title = tab.homeTitle
            if let app = TrailApps.shared.application(for: tab) { TrailApps.shared.remove(app.id, in: self) }
            tab.kept = true
            tab.pin = nil
            tab.everywhere = nil
            if let home { tab.home = home; tab.homeTitle = title }
        }
        keepTabs(group)
    }
}

struct RailGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { VStack(spacing: SideBar.gap, content: content) }
}

struct TrailAppButton: View {
    let app: TrailApps.App
    let browser: Browser
    var grid = false

    var body: some View {
        RailButton(app.title, selected: browser.activeID != nil && TrailApps.shared.backingTab(for: app, among: browser.tabs, in: browser)?.id == browser.activeID,
                   grid: grid,
                   action: { TrailApps.shared.open(app, in: browser) }) {
            if let image = Favicons.shared.cached(page: app.id) {
                Image(nsImage: image).resizable().scaledToFit()
                    .frame(width: SideBar.mark, height: SideBar.mark)
            } else {
                Text(Tab.monogram(for: app.id)).font(.system(size: SideBar.mark, weight: .medium))
            }
        }
        .keyTip(app.title, side: browser.trailFlank == .right ? .left : .right)
        .steadyMenu(actions: true) {
            Button(Command.unpinTrailApp.title, mark: "pin.slash") { TrailApps.shared.remove(app.id, in: browser) }
        }
    }
}

struct SidebarAppTabs: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var apps = TrailApps.shared

    var body: some View {
        if browser.sidebarAppsShown, !apps.apps.isEmpty {
            let grid = ColumnLayout.grid(count: apps.apps.count, width: browser.sidebarContentWidth)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: SideBar.pinGap), count: grid.cols), spacing: SideBar.pinGap) {
                ForEach(apps.apps) { app in TrailAppButton(app: app, browser: browser, grid: true) }
            }
            .padding(.bottom, SideBar.margin)
            .background(SpaceAnchor(kind: .trailPins))
            .background(SpaceAnchor(kind: .trail))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("App Tabs")
        }
    }
}
