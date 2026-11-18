import SwiftUI

struct HomeLibraryList: View {
    @ObservedObject var browser: Browser
    let page: LibraryPage
    @ObservedObject private var bookmarks: Bookmarks
    @ObservedObject private var history: History
    @ObservedObject private var downloads: Loot
    @ObservedObject private var extensions: Extensions
    @State private var collapsed: Set<UUID> = []
    @AppStorage("home.historyGrouping", store: Store.settings) private var grouping = HomePeriod.day

    init(browser: Browser, page: LibraryPage) {
        self.browser = browser
        self.page = page
        bookmarks = browser.bookmarks
        history = browser.history
        downloads = browser.loot
        extensions = Extensions.of(browser)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                switch page {
                case .tabs:
                    ForEach(browser.turnOrder) { space in
                        let tabs = space.id == browser.spaceID ? browser.tabs : browser.parked[space.id]?.tabs ?? []
                        let visible = browser.sidebarTabs(tabs).filter { !$0.shy && !Agents.shared.sealed($0) }
                        if !visible.isEmpty { heading(space.name) }
                        ForEach(visible) { tab in
                            row(tab.rowLabel, "", url: tab.pending ?? tab.address, icon: "macwindow") {
                                browser.close()
                                if space.id != browser.spaceID { browser.switchSpace(to: space.id) }
                                browser.select(tab)
                            }
                        }
                    }
                case .bookmarks:
                    ForEach(outline, id: \.item.id) { entry in
                        let item = entry.item
                        let url = item.url.flatMap(URL.init(string:))
                        row(item.title, url?.host() ?? "", url: url, icon: collapsed.contains(item.id) ? "chevron.right" : "chevron.down") {
                            if item.isFolder {
                                if !collapsed.insert(item.id).inserted { collapsed.remove(item.id) }
                            } else if let url { browser.send(url, .here) }
                        }.padding(.leading, CGFloat(entry.depth) * 16)
                    }
                case .history:
                    let sections = grouping.groups(history.everything(), date: \.last)
                    ForEach(sections, id: \.start) { section in
                        heading(grouping.title(section.start))
                        ForEach(section.items, id: \.key) { item in
                            row(item.title.isEmpty ? Address.shown(item.url) : item.title,
                                item.last.formatted(date: grouping == .day ? .omitted : .abbreviated, time: .shortened), url: item.url) {
                                browser.send(item.url, .here)
                            }
                        }
                    }
                case .downloads:
                    ForEach(HomePeriod.day.groups(downloads.kept, date: \.date), id: \.start) { section in
                        heading(HomePeriod.day.title(section.start))
                        ForEach(section.items) { item in
                            row(item.name, item.date.formatted(date: .omitted, time: .shortened), icon: "doc") { downloads.reveal(item) }
                        }
                    }
                case .extensions:
                    ForEach(extensions.installed) { item in
                        LibraryExtensionRow(row: item, store: extensions, browser: browser)
                        LibrarySeparator()
                    }
                case .settings:
                    ForEach(SettingsNavigation.groups, id: \.title) { group in
                        ForEach(group.pages) { destination in
                            row(destination.title, group.title, icon: destination.icon) {
                                SettingsWindow.shared.show(destination, for: browser)
                            }
                        }
                    }
                }
            }.padding(.vertical, LibraryPageLayout.sectionGap)
        }
    }

    private var outline: [(item: Bookmark, depth: Int)] {
        var result: [(item: Bookmark, depth: Int)] = []
        func append(_ items: [Bookmark], depth: Int) {
            for item in items {
                result.append((item, depth))
                if let children = item.children, !collapsed.contains(item.id) { append(children, depth: depth + 1) }
            }
        }
        append(bookmarks.roots, depth: 0)
        return result
    }

    private func heading(_ title: String) -> some View {
        Text(title).font(.headline).foregroundStyle(Palette.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func row(_ title: String, _ detail: String, url: URL? = nil, icon: String = "globe", action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let url { PlacePageMark(url: url, side: 18) }
                else { Image(systemName: icon).frame(width: 18) }
                Text(title).font(CardFrame.title)
                Spacer()
                Text(detail).font(CardFrame.detail).foregroundStyle(Palette.muted)
            }.lineLimit(1).padding(.horizontal, 8).frame(height: 40).contentShape(Rectangle())
        }.buttonStyle(.plain)
        LibrarySeparator()
    }
}

enum HomePeriod: String, CaseIterable {
    case day, week, month

    func groups<Item>(_ items: [Item], date: KeyPath<Item, Date>) -> [(start: Date, items: [Item])] {
        let component: Calendar.Component = self == .day ? .day : self == .week ? .weekOfYear : .month
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: items) {
            calendar.dateInterval(of: component, for: $0[keyPath: date])?.start ?? calendar.startOfDay(for: $0[keyPath: date])
        }
        return buckets.map { (start: $0.key, items: $0.value.sorted { $0[keyPath: date] > $1[keyPath: date] }) }
            .sorted { $0.start > $1.start }
    }

    func title(_ start: Date) -> String {
        if self == .month { return start.formatted(.dateTime.month(.wide).year()) }
        let date = start.formatted(date: .abbreviated, time: .omitted)
        return self == .week ? "Week of " + date : date
    }
}

struct HomeHistoryGrouping: View {
    @AppStorage("home.historyGrouping", store: Store.settings) private var grouping = HomePeriod.day
    var body: some View {
        Picker("Group by", selection: $grouping) {
            ForEach(HomePeriod.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
        }.pickerStyle(.menu).fixedSize()
    }
}
