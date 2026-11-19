import SwiftUI

extension Space {
    static let allTabs = Space(id: UUID(uuidString: "00000000-0000-0000-0000-00000000A117")!,
                               name: "All Tabs", icon: "square.stack.3d.up", ownSignIns: false)
}

/// Membership refers to the original tab. Two pages at the same address can be pinned independently.
@MainActor @Observable
final class AllTabsConfiguration {
    static let shared = AllTabsConfiguration(defaults: Store.settings)
    private let defaults: UserDefaults
    private let key = "sidebar.allTabs.pins"
    private(set) var order: [UUID]
    var space: Space {
        didSet {
            if let data = try? JSONEncoder().encode(space) { defaults.set(data, forKey: "sidebar.allTabs.space") }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        space = defaults.data(forKey: "sidebar.allTabs.space")
            .flatMap { try? JSONDecoder().decode(Space.self, from: $0) } ?? .allTabs
        order = (defaults.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    func move(_ key: UUID, before target: UUID) {
        guard key != target, order.contains(key), order.contains(target) else { return }
        order.removeAll { $0 == key }
        if let index = order.firstIndex(of: target) { order.insert(key, at: index) }
        saveOrder()
    }

    func set(_ tabs: [Tab], pinned: Bool) {
        for tab in tabs {
            let key = tab.allTabsKey
            if pinned {
                if !order.contains(key) { order.append(key) }
            } else {
                order.removeAll { $0 == key }
            }
        }
        saveOrder()
    }

    private func saveOrder() {
        defaults.set(order.map(\.uuidString), forKey: key)
    }
}

extension Tab {
    var allTabsKey: UUID { everywhere ?? keptKey ?? id }
}

extension Browser {
    var offersAllTabs: Bool { spacesShown && prefs.sidebar && !privateBrowsing && !blank }
    var showingAllTabs: Bool { allTabsSelected && offersAllTabs }
    var sidebarSpace: Space { showingAllTabs ? AllTabsConfiguration.shared.space : space }
    var sidebarSpaceID: UUID { sidebarSpace.id }
    var switcherSpaces: [Space] { offersAllTabs ? turnOrder + [AllTabsConfiguration.shared.space] : turnOrder }

    func isPinnedInSidebar(_ tab: Tab) -> Bool {
        if showingAllTabs { return AllTabsConfiguration.shared.order.contains(tab.allTabsKey) }
        return tab.pin != nil || prefs.sidebar && tab.kept
    }

    func showAllTabs() {
        guard offersAllTabs else { return }
        if inMail { switchSpace(to: homeSpaceID) }
        for space in spaces where space.id != spaceID && parked[space.id] == nil {
            parked[space.id] = loadRow(space.id)
        }
        if pinsShared, sharedPins == nil, spaces.contains(where: { showsShared($0.id) }) {
            parked[Space.pinsID] = loadRow(Space.pinsID)
        }
        allTabsSelected = true
    }

    struct SpaceTab: Identifiable {
        let space: Space
        let tab: Tab
        var id: UUID { tab.id }
    }

    var allTabsRows: [SpaceTab] {
        var seen = Set<UUID>()
        let sharedSpace = sharedLeft.flatMap { showsShared($0) ? $0 : nil } ?? spaces.first { showsShared($0.id) }?.id
        return spaces.flatMap { space in
            var row = space.id == spaceID ? tabs : parked[space.id]?.tabs ?? []
            if sharedSpace == space.id { row += parked[Space.pinsID]?.tabs ?? [] }
            return row.compactMap { tab -> SpaceTab? in
                guard !tab.shy, !tab.bench, !Agents.shared.sealed(tab), seen.insert(tab.id).inserted else { return nil }
                return SpaceTab(space: space, tab: tab)
            }
        }.sorted {
            if $0.id == activeID || $1.id == activeID { return $0.id == activeID && $1.id != activeID }
            if $0.tab.touched == $1.tab.touched { return $0.id.uuidString < $1.id.uuidString }
            return $0.tab.touched > $1.tab.touched
        }
    }
}

struct AllTabsRows: View {
    let browser: Browser
    let pins = AllTabsConfiguration.shared

    var body: some View {
        let rows = browser.allTabsRows
        let ranks = Dictionary(uniqueKeysWithValues: pins.order.enumerated().map { ($1, $0) })
        let pinned = rows.filter { ranks[$0.tab.allTabsKey] != nil }
            .sorted { ranks[$0.tab.allTabsKey, default: 0] < ranks[$1.tab.allTabsKey, default: 0] }
        ThreadScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: SideBar.gap) {
                ForEach(pinned) { entry in
                    row(entry)
                        .draggable(entry.tab.allTabsKey.uuidString)
                        .dropDestination(for: String.self) { items, _ in
                            guard let key = items.first.flatMap(UUID.init(uuidString:)), pins.order.contains(key) else { return false }
                            pins.move(key, before: entry.tab.allTabsKey)
                            return true
                        }
                }
                if pinned.count < rows.count { Divider().padding(.horizontal, SideBar.inner).frame(height: SideBar.line) }
                Quiet(icon: "plus", title: "New tab", height: SideBar.row, news: true,
                      lit: browser.newTabLit, prefs: browser.prefs, browser: browser) { browser.newTab() }
                ForEach(rows.filter { ranks[$0.tab.allTabsKey] == nil }) { row($0) }
            }
        }
    }

    private func row(_ entry: Browser.SpaceTab) -> some View {
        SideRow(browser: browser, prefs: browser.prefs, tab: entry.tab, live: entry.id == browser.activeID,
                sourceSpace: entry.space)
            .environment(\.sidebarSpaceActions, SidebarSpaceActions(browser: browser, id: entry.space.id, allTabs: true))
    }
}
