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
    enum Sort: String, CaseIterable {
        case recent = "Last Visited"
        case oldest = "Oldest Visit First"
        case manual = "Manual Order"
    }
    enum Group: String, CaseIterable {
        case none = "None"
        case space = "Space"
        case domain = "Domain"
    }

    private(set) var sort: Sort {
        didSet { defaults.set(sort.rawValue, forKey: "sidebar.allTabs.sort") }
    }
    var group: Group {
        didSet { defaults.set(group.rawValue, forKey: "sidebar.allTabs.group") }
    }
    private var collapsed: Set<Browser.SpaceTab.Section> {
        didSet {
            if let data = try? JSONEncoder().encode(collapsed) { defaults.set(data, forKey: Self.collapsedKey) }
        }
    }
    private static let collapsedKey = "sidebar.allTabs.collapsed"

    func isCollapsed(_ section: Browser.SpaceTab.Section) -> Bool { collapsed.contains(section) }

    func toggleCollapse(_ section: Browser.SpaceTab.Section) {
        guard section != .ungrouped else { return }
        if collapsed.remove(section) == nil { collapsed.insert(section) }
    }

    func setAllCollapsed(_ collapse: Bool, rows: [Browser.SpaceTab]) {
        guard group != .none else { return }
        let pins = Set(order)
        let groups = rows.lazy.filter { !pins.contains($0.tab.allTabsKey) }.map { $0.section(self.group) }
        if collapse { collapsed.formUnion(groups) } else { collapsed.subtract(groups) }
    }

    private var manual: [UUID] {
        didSet { defaults.set(manual.map(\.uuidString), forKey: "sidebar.allTabs.manual") }
    }

    var space: Space {
        didSet {
            if let data = try? JSONEncoder().encode(space) { defaults.set(data, forKey: "sidebar.allTabs.space") }
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        collapsed = defaults.data(forKey: Self.collapsedKey)
            .flatMap { try? JSONDecoder().decode(Set<Browser.SpaceTab.Section>.self, from: $0) } ?? []
        sort = defaults.string(forKey: "sidebar.allTabs.sort").flatMap(Sort.init(rawValue:)) ?? .recent
        group = defaults.string(forKey: "sidebar.allTabs.group").flatMap(Group.init(rawValue:)) ?? .none
        manual = (defaults.stringArray(forKey: "sidebar.allTabs.manual") ?? []).compactMap(UUID.init(uuidString:))
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

    func arranged(_ rows: [Browser.SpaceTab]) -> [Browser.SpaceTab] {
        switch sort {
        case .recent: return rows
        case .oldest: return Array(rows.reversed())
        case .manual:
            let ranks = Dictionary(manual.enumerated().map { ($1, $0) }, uniquingKeysWith: min)
            return rows.sorted {
                let left = ranks[$0.tab.allTabsKey, default: .max]
                let right = ranks[$1.tab.allTabsKey, default: .max]
                return left == right ? $0.id.uuidString < $1.id.uuidString : left < right
            }
        }
    }

    func choose(_ sort: Sort, rows: [Browser.SpaceTab]) {
        if sort == .manual, manual.isEmpty { manual = arranged(rows).map { $0.tab.allTabsKey } }
        self.sort = sort
    }

    func reorder(_ key: UUID, at target: UUID, after: Bool, rows: [Browser.SpaceTab]) -> Bool {
        let loose = rows.filter { !order.contains($0.tab.allTabsKey) }
        guard key != target, let source = loose.first(where: { $0.tab.allTabsKey == key }),
              let destination = loose.first(where: { $0.tab.allTabsKey == target }),
              source.section(group) == destination.section(group) else { return false }
        var keys = arranged(loose).map { $0.tab.allTabsKey }.filter { $0 != key }
        guard let index = keys.firstIndex(of: target) else { return false }
        keys.insert(key, at: index + (after ? 1 : 0))
        let visible = Set(keys)
        // A second window can have other tabs in the same saved order.
        var replacements = keys.makeIterator()
        manual = manual.compactMap { visible.contains($0) ? replacements.next() : $0 } + Array(replacements)
        sort = .manual
        return true
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

extension Browser.SpaceTab {
    enum Section: Hashable, Codable {
        case ungrouped, space(UUID), domain(String), localFiles, browserPages
    }

    @MainActor func section(_ group: AllTabsConfiguration.Group) -> Section {
        switch group {
        case .none: return .ungrouped
        case .space: return .space(space.id)
        case .domain:
            let url = tab.pending ?? tab.address
            if url?.isFileURL == true { return .localFiles }
            if let url, ["https", "http"].contains(url.scheme), let host = url.host(), !host.isEmpty {
                return .domain(Vault.registrable(host))
            }
            return .browserPages
        }
    }
}

extension AllTabsConfiguration {
    struct Section: Identifiable {
        let id: Browser.SpaceTab.Section
        let title: String
        var rows: [Browser.SpaceTab]
    }

    func sections(_ rows: [Browser.SpaceTab]) -> [Section] {
        var result: [Section] = []
        var indices: [Browser.SpaceTab.Section: Int] = [:]
        for row in arranged(rows) {
            let id = row.section(group)
            if let index = indices[id] { result[index].rows.append(row); continue }
            let title: String
            switch id {
            case .ungrouped: title = ""
            case .space: title = row.space.name
            case .domain(let name): title = name
            case .localFiles: title = "Local Files"
            case .browserPages: title = "Browser Pages"
            }
            indices[id] = result.count
            result.append(Section(id: id, title: title, rows: [row]))
        }
        return result
    }
}

struct AllTabsOrganizationMenu: View {
    let browser: Browser
    private let config = AllTabsConfiguration.shared

    var body: some View {
        Menu("Sort by", mark: "arrow.up.arrow.down") {
            ForEach(AllTabsConfiguration.Sort.allCases, id: \.self) { choice in
                Toggle(choice.rawValue, isOn: Binding(get: { config.sort == choice }, set: { _ in
                    config.choose(choice, rows: browser.allTabsRows)
                }))
            }
        }
        Menu("Group by", mark: "rectangle.3.group") {
            ForEach(AllTabsConfiguration.Group.allCases, id: \.self) { choice in
                Toggle(choice.rawValue, isOn: Binding(get: { config.group == choice }, set: { _ in config.group = choice }))
            }
        }
        if config.group != .none {
            Divider()
            Button(Command.collapseAllTabGroups.title, mark: "arrow.down.right.and.arrow.up.left") {
                config.setAllCollapsed(true, rows: browser.allTabsRows)
            }
            Button(Command.expandAllTabGroups.title, mark: "arrow.up.left.and.arrow.down.right") {
                config.setAllCollapsed(false, rows: browser.allTabsRows)
            }
        }
    }
}

private struct AllTabsSectionHeader: View {
    let section: AllTabsConfiguration.Section
    let browser: Browser
    @State private var hovered = false
    @Environment(\.tone) private var tone
    @Environment(\.tabTitleSize) private var titleSize

    var body: some View {
        let config = AllTabsConfiguration.shared
        let collapsed = config.isCollapsed(section.id)
        HStack(spacing: 0) {
            Button { config.toggleCollapse(section.id) } label: {
                HStack(spacing: SideBar.markGap) {
                    Symbol(collapsed ? "chevron.right" : "chevron.down", size: 9, weight: .semibold)
                        .frame(width: SideBar.mark)
                    Text(section.title).lineLimit(1)
                }
                .padding(.leading, SideBar.inner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(section.title)
            .accessibilityValue(collapsed ? "Collapsed" : "Expanded")
            .accessibilityAddTraits(.isHeader)
            Button {
                if case .space(let id) = section.id { browser.switchSpace(to: id) }
                else if let first = section.rows.first {
                    SidebarSpaceActions(browser: browser, id: first.space.id, allTabs: true)
                        .run({ browser.select(first.tab) }, stay: true)
                }
            } label: {
                Symbol("arrow.up.right", size: SideBar.mark / Glyphs.scale)
                    .frame(width: RowPlate.column.side, height: RowPlate.column.side)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionTitle)
            .keyTip(actionTitle)
            .opacity(hovered ? 1 : 0)
        }
        .font(.system(size: titleSize, weight: .semibold))
        .foregroundStyle(Palette.muted(on: tone))
        .padding(.trailing, SideBar.inner)
        .frame(height: SideBar.row)
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
    }

    private var actionTitle: String {
        if case .space = section.id { return "Open " + section.title + " Space" }
        return "Show " + (section.rows.first?.tab.rowLabel ?? section.title)
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
        GeometryReader { viewport in
            ThreadScrollView(.vertical) {
                VStack(spacing: 0) {
                    list(rows, ranks: ranks, pinned: pinned)
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .steadyMenu(actions: true, tone: SpaceSurface.tone(in: browser)) {
                            SpaceMenu(browser: browser, space: browser.sidebarSpace)
                        }
                }
                .frame(minHeight: viewport.size.height, alignment: .top)
            }
        }
    }

    private func list(_ rows: [Browser.SpaceTab], ranks: [UUID: Int], pinned: [Browser.SpaceTab]) -> some View {
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
            ForEach(pins.sections(rows.filter { ranks[$0.tab.allTabsKey] == nil })) { section in
                if section.id != .ungrouped { AllTabsSectionHeader(section: section, browser: browser) }
                if !pins.isCollapsed(section.id) {
                    ForEach(section.rows) { entry in
                        row(entry, showSpaceBadge: pins.group != .space)
                            .draggable(entry.tab.allTabsKey.uuidString)
                            .dropDestination(for: String.self) { items, point in
                                guard let key = items.first.flatMap(UUID.init(uuidString:)) else { return false }
                                return pins.reorder(key, at: entry.tab.allTabsKey, after: point.y >= SideBar.row / 2,
                                                    rows: browser.allTabsRows)
                            }
                    }
                }
            }
        }
    }

    private func row(_ entry: Browser.SpaceTab, showSpaceBadge: Bool = true) -> some View {
        SideRow(browser: browser, prefs: browser.prefs, tab: entry.tab, live: entry.id == browser.activeID,
                sourceSpace: showSpaceBadge ? entry.space : nil)
            .environment(\.sidebarSpaceActions, SidebarSpaceActions(browser: browser, id: entry.space.id, allTabs: true))
    }
}
