import SwiftUI

private struct LibraryNavigationInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var libraryNavigationInset: CGFloat? {
        get { self[LibraryNavigationInsetKey.self] }
        set { self[LibraryNavigationInsetKey.self] = newValue }
    }
}

/// Search, scope and ordering for one library.
@Observable final class LibraryControls {
    var search = ""
    fileprivate var filter: String?
    var folder: Bookmark.ID?
    fileprivate var expandedFolders = Set<Bookmark.ID>()
    fileprivate var day: Date?
    fileprivate var month = Date()
    fileprivate var sort: LibrarySort?
}

enum LibraryPageLayout {
    static let inset: CGFloat = 32
    static let sectionGap: CGFloat = 24
    static let searchWidth: CGFloat = 280
    static let navigationWidth: CGFloat = 182
    static let columnGap: CGFloat = 20
    static let formWidth: CGFloat = 880
    static let collectionWidth: CGFloat = 1100
}

struct LibraryPageHeader<Action: View, Search: View>: View {
    let page: LibraryPage
    var breadcrumbs: [String] = []
    @ViewBuilder var action: () -> Action
    @ViewBuilder var search: () -> Search
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                title
                Spacer(minLength: 16)
                action()
                search().frame(width: LibraryPageLayout.searchWidth)
            }
            VStack(alignment: .leading, spacing: CardFrame.inset) {
                title
                HStack(spacing: CardFrame.inset) {
                    action()
                    search().frame(maxWidth: .infinity)
                }
            }
        }
        .foregroundStyle(Palette.ink)
    }

    private var title: some View {
        HStack(spacing: 10) {
            Text(page.title).foregroundStyle(breadcrumbs.isEmpty ? Palette.ink : Palette.muted)
            ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { _, name in
                Text("/").foregroundStyle(Palette.muted)
                Text(name)
            }
        }
        .font(.title.weight(.semibold))
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }
}

/// The shared page template: a title and actions header, then navigation and data.
struct LibraryPageFrame<Action: View, Search: View, Content: View>: View {
    let page: LibraryPage
    var breadcrumbs: [String] = []
    @ViewBuilder var action: () -> Action
    @ViewBuilder var search: () -> Search
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: LibraryPageLayout.sectionGap) {
            LibraryPageHeader(page: page, breadcrumbs: breadcrumbs, action: action, search: search)
            content()
        }
        .padding(LibraryPageLayout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Palette.ink)
    }
}

/// Forms stay readable and centered within the data column. Collections may fill it.
struct LibraryDataColumn<Content: View>: View {
    var maximumWidth: CGFloat? = nil
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .frame(maxWidth: maximumWidth ?? .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// A shared horizontal identity variant for page introductions and rich rows.
struct LibraryIdentityRow<Icon: View, Detail: View>: View {
    let title: String
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var detail: () -> Detail
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            icon()
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold)).foregroundStyle(Palette.ink)
                detail().foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A quiet card variant for dense forms, using Yab's surface and corner tokens.
struct LibraryCardSurface: ViewModifier {
    @Environment(\.tone) private var tone
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        content.background(tone?.color ?? Palette.ground.opacity(0.65), in: shape) // design: quiet library card variant retains the shared surface and corner with a softer rim.
            .overlay(shape.strokeBorder(tone.map { Color(nsColor: SpaceSurface.rim(on: $0)) } ?? Palette.hairline.opacity(0.4)).allowsHitTesting(false)) // design: quieter rim for dense library forms.
    }
}

/// Use the existing hairline token with quieter emphasis inside library surfaces.
struct LibrarySeparator: View {
    @Environment(\.tone) private var tone

    var body: some View {
        Rectangle().fill(tone.map { Color(nsColor: SpaceSurface.rim(on: $0)) } ?? Palette.hairline)
            .frame(height: 1).opacity(0.4)
    }
}

/// The same search surface around either a library field or Settings' native field.
struct LibrarySearchWell<Content: View>: View {
    @Environment(\.tone) private var tone
    @Binding var text: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            Symbol("magnifyingglass", size: 12).foregroundStyle(Palette.muted(on: tone))
            content()
            if !text.isEmpty {
                Button { text = "" } label: { Symbol("xmark.circle.fill", size: 12) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, CardFrame.inset)
        .frame(height: 32)
        .background(tone?.color ?? Palette.ground, in: Capsule())
        .overlay(Capsule().strokeBorder(tone.map { Color(nsColor: SpaceSurface.rim(on: $0)) } ?? Palette.hairline).allowsHitTesting(false)) // design: shared library search bezel.
    }
}

/// Shared chrome for Yab's library tabs. Each data source supplies its own
/// filter identities, ordering choices, and SwiftUI results view.
private struct LibraryScreen<Content: View>: View {
    @ObservedObject var browser: Browser
    let page: LibraryPage
    let filters: [LibraryFilter]
    let sorts: [LibrarySort]
    var openDownloadFolder: (() -> Void)? = nil
    @ViewBuilder var content: (String, String?, LibrarySort) -> Content
    @Environment(LibraryControls.self) private var controls

    var body: some View {
        LibraryPageFrame(page: page) {
            if let openDownloadFolder {
                Button(action: openDownloadFolder) {
                    Label("Open Downloads Folder", systemImage: "folder")
                }.buttonStyle(.yab(.secondary, .regular, capsule: true))
            }
        } search: {
            LibrarySearch(page: page)
        } content: {
            VStack(alignment: .leading, spacing: LibraryPageLayout.sectionGap) {
                HStack(spacing: CardFrame.inset) {
                    ThreadScrollView(.horizontal) {
                        HStack(spacing: 6) {
                            chip("All " + page.rawValue, id: nil)
                            ForEach(filters) { chip($0.title, id: $0.id) }
                        }
                    }.scrollIndicators(.hidden)
                    LibrarySortMenu(page: page, sorts: sorts)
                }
                let results = content(controls.search.trimmingCharacters(in: .whitespacesAndNewlines), controls.filter, controls.sort ?? sorts[0])
                    .frame(maxWidth: .infinity, alignment: .leading)
                if page == .tabs { ThreadScrollView { results } } else { results }
            }
        }

        .onChange(of: filters) {
            if let filter = controls.filter, !filters.contains(where: { $0.id == filter }) { controls.filter = nil }
        }
    }

    private func chip(_ title: String, id: String?) -> some View {
        Button(title) { controls.filter = id }
            .buttonStyle(.yab(controls.filter == id ? .primary : .secondary, .regular, capsule: true))
            .accessibilityAddTraits(controls.filter == id ? .isSelected : [])
    }
}

struct ThemedSearchField: View {
    let placeholder: String
    @Binding var text: String

    init(_ placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        _text = text
    }

    var body: some View {
        LibrarySearchWell(text: $text) {
            TextField(placeholder, text: $text).textFieldStyle(.plain).font(CardFrame.detail)
        }
    }
}

private struct LibrarySearch: View {
    let page: LibraryPage
    @Environment(LibraryControls.self) private var controls

    var body: some View {
        @Bindable var controls = controls
        ThemedSearchField("Search " + page.rawValue, text: $controls.search)
    }
}

private struct LibrarySortMenu: View {
    let page: LibraryPage
    let sorts: [LibrarySort]
    @Environment(LibraryControls.self) private var controls

    var body: some View {
        DropMenu("Sort " + page.rawValue,
                 options: sorts.map { DropOption(title: $0.rawValue, value: $0) },
                 selection: Binding(get: { controls.sort ?? sorts[0] }, set: { controls.sort = $0 }),
                 trailing: true, faceTitle: "Sort", showsCheck: true)
            .fixedSize()
    }
}

private struct LibraryFilter: Identifiable, Equatable {
    let id: String
    let title: String
}

private enum LibrarySort: String, Hashable {
    case sidebar = "Sidebar order", recent = "Recently viewed"
    case saved = "Folder order", newest = "Newest first", name = "Name A–Z", frequent = "Most visited"
}

enum LibraryPage: String {
    case tabs, bookmarks, history, downloads, extensions, settings
    var title: String { rawValue.capitalized }
    var url: URL { URL(string: "yab://" + rawValue)! }
    init?(url: URL?) {
        guard url?.scheme == DiaryPage.scheme, let host = url?.host() else { return nil }
        self.init(rawValue: host)
    }
    var icon: String {
        switch self {
        case .settings: "gearshape"
        case .tabs: "square.grid.2x2"
        case .bookmarks: "bookmark"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .extensions: "puzzlepiece.extension"
        }
    }

    @MainActor @ViewBuilder func screen(browser: Browser, tab: Tab) -> some View {
        switch self {
        case .settings: SettingsTab(browser: browser, tab: tab)
        case .tabs: TabsLibrary(browser: browser, board: tab)
        case .bookmarks: BookmarkLibrary(store: browser.bookmarks, browser: browser, tab: tab)
        case .history: HistoryLibrary(store: browser.history(for: tab), browser: browser, tab: tab)
        case .downloads: DownloadLibrary(store: browser.loot, browser: browser)
        case .extensions: ExtensionLibrary(store: Extensions.of(browser), browser: browser)
        }
    }
}

extension Tab {
    var libraryPage: LibraryPage? { LibraryPage(url: pending ?? address) }
    var showsLibrary: Bool { LibraryPage(url: address) != nil && !floating }
}

extension Browser {
    func showLibrary(_ page: LibraryPage) {
        let shy = privateBrowsing
        if fieldShowing { close() }
        func matches(_ tab: Tab) -> Bool { tab.shy == shy && tab.libraryPage == page }
        if let existing = tabs.first(where: matches) {
            select(existing)
            return
        }
        for space in turnOrder where space.id != spaceID {
            guard let row = parked[space.id], let tab = row.tabs.first(where: matches),
                  tab.pin == nil, !tab.kept, tab.nest == nil, !row.pairs.contains(where: { $0.contains(tab.id) }),
                  detachParked(tab, from: space.id) else { continue }
            if !shy && Spaces.store(for: space.id) !== Spaces.store(for: spaceID) {
                // Keep the library's controls, but use this Space's web session for links.
                tab.close()
                open(page.url, foreground: true, from: active)
            } else {
                tab.from = activeID
                var current = tabs
                current.insert(tab, at: Browser.askedLanding(count: tabs.count, keptEnd: keptEnd, strip: !prefs.sidebar))
                lay(current)
                select(tab)
            }
            writeSession(now: true)
            return
        }
        open(page.url, foreground: true, from: active, shy: shy)
    }
}

private struct TabsLibrary: View {
    @ObservedObject var browser: Browser
    let board: Tab

    @GestureState private var drag: BoardDrag?
    @GestureState private var folderDrag: BoardFolderDrag?
    @GestureState private var spaceDrag: BoardSpaceDrag?
    private var draggingRows: Bool { drag != nil || folderDrag != nil }
    @State private var viewport: CGRect = .zero
    @State private var lastScroll: TimeInterval = 0
    @State private var frames: [UUID: CGRect] = [:]
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var ready: UUID?

    private var spaces: [Space] {
        if browser.blank || browser.windowPurpose != .normal { return [browser.space] }
        return browser.turnOrder.filter { browser.prefs.usesSpaces || $0.id == browser.spaceID || $0.id == Space.mailID || $0.id == browser.homeSpaceID }
    }

    var body: some View {
        let order = spaces
        LibraryScreen(browser: browser, page: .tabs, filters: order.map { LibraryFilter(id: $0.id.uuidString, title: $0.name) },
                      sorts: [.sidebar, .recent, .name]) { query, filter, sort in
            // Keep the source in place while revealing other drop targets from a Space filter.
            let ordered = draggingRows && filter != nil ? order.filter { $0.id.uuidString == filter } + order.filter { $0.id.uuidString != filter } : order
            let columns = ordered.compactMap { space -> (Space, [Tab])? in
                guard draggingRows || filter == nil || filter == space.id.uuidString else { return nil }
                let row = space.id == browser.spaceID ? browser.tabs : browser.parked[space.id]?.tabs ?? []
                var matches = browser.sidebarTabs(row).filter {
                    $0.shy == board.shy && !Agents.shared.sealed($0)
                        && matchesLibrary(query, space.name, $0.rowLabel, ($0.pending ?? $0.address)?.absoluteString ?? "")
                }
                if sort == .name { matches.sort { alphabetic($0.rowLabel, $1.rowLabel) } }
                if sort == .recent { matches.sort { $0.touched > $1.touched } }
                return query.isEmpty || !matches.isEmpty || draggingRows ? (space, matches) : nil
            }
            if columns.isEmpty {
                LibraryEmpty(page: .tabs, filtered: true)
            } else {
                ScrollViewReader { reader in
                    ThreadScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: CardFrame.inset) {
                            ForEach(columns, id: \.0.id) { space, tabs in
                                let target = landing(drag, space: space.id, tabs: tabs, sort: sort)
                                let folderSlot = folderDrag.flatMap { folderLanding($0, in: space.id) }
                                let spaceSlot = spaceDrag.flatMap { spaceLanding($0, in: space.id) }
                                VStack(alignment: .leading, spacing: SideBar.gap) {
                                    HStack(spacing: SideBar.gap) {
                                        SpaceName(space: space, browser: browser)
                                            .environment(\.sidebarSpaceActions, SidebarSpaceActions(browser: browser, id: space.id))
                                        Text(tabs.count.formatted())
                                            .font(CardFrame.detail).foregroundStyle(Palette.muted)
                                            .padding(.trailing, SideBar.inner)
                                    }
                                    .contentShape(Rectangle())
                                    .simultaneousGesture(reorderSpace(space.id), including: columns.count > 1 ? .all : .subviews)
                                    .allowsWindowActivationEvents()
                                    SidebarSpaceTabList(browser: browser, space: space, tabs: tabs,
                                                        grouped: query.isEmpty && sort == .sidebar) { item, cell in
                                        if let tab = item.tab {
                                            cell
                                                .opacity(drag?.tab === tab ? 0.5 : 1)
                                                .contentShape(Rectangle())
                                                .simultaneousGesture(move(tab, from: space.id, columns: columns, sort: sort),
                                                         including: canDrag(tab, in: space.id) && tab !== board ? .all : .subviews)
                                                .overlay {
                                                    if ready == tab.id && groupTarget == tab.id {
                                                        TabDropChoices(choice: TabDropChoice(target: tab.id, side: .folder,
                                                            canSplit: false, revealed: true, fill: 1, ready: true))
                                                    }
                                                }
                                                .overlay(alignment: .top) {
                                                    if ((target?.before == tab.id || (target?.indicator == tab.id && target?.below == false)) && ready == nil) || folderSlot?.key == tab.id.uuidString { insertion.offset(y: -SideBar.gap / 2) }
                                                }
                                                .overlay(alignment: .bottom) {
                                                    if target?.indicator == tab.id && target?.below == true && ready == nil { insertion.offset(y: SideBar.gap / 2) }
                                                }
                                                .background(rowFrame(tab.id.uuidString))
                                        } else if case .nest(let nest, _, _) = item.kind {
                                            cell.aimingAtFolder(target?.placement == .folder(nest.id)).contentShape(Rectangle())
                                                .simultaneousGesture(moveFolder(nest, from: space.id))
                                                .opacity(folderDrag?.nest === nest ? 0.5 : 1)
                                                .overlay(alignment: .top) {
                                                    if folderSlot?.key == nest.key { insertion.offset(y: -SideBar.gap / 2) }
                                                }
                                                .task(id: target?.placement == .folder(nest.id)) {
                                                    guard target?.placement == .folder(nest.id), !nest.open,
                                                          tabs.contains(where: { $0.nest?.within(nest) == true }) else { return }
                                                    try? await Task.sleep(for: .milliseconds(600))
                                                    guard !Task.isCancelled, !nest.open else { return }
                                                    SidebarSpaceActions(browser: browser, id: space.id).run {
                                                        browser.folderBook.toggle(nest.key, knownNest: nest, immediately: true)
                                                    }
                                                }
                                                .background(rowFrame(nest.key))
                                        } else if let key = item.folderKey {
                                            cell.background(rowFrame(key))
                                        } else { cell }
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if (target != nil && target?.before == nil && target?.placement == nil && sort == .sidebar) || (folderSlot != nil && folderSlot?.key == nil) { insertion }
                                }
                                .frame(width: max(220, browser.sidebarContentWidth))
                                .restingCardFrame(inset: SideBar.margin)
                                .overlay(alignment: spaceSlot == true ? .trailing : .leading) {
                                    if spaceSlot != nil { Capsule().fill(Color.accentColor).frame(width: 2).allowsHitTesting(false) }
                                }
                                .overlay {
                                    if target != nil || folderSlot != nil {
                                        RoundedRectangle(cornerRadius: SideBar.margin + Radius.control)
                                            .strokeBorder(Color.accentColor, lineWidth: 2).allowsHitTesting(false)
                                    }
                                }
                                .id(space.id)
                                .background(GeometryReader { geo in
                                    Color.clear.preference(key: BoardFrames.self,
                                        value: [space.id: geo.frame(in: .named(board.id))])
                                })
                            }
                        }
                    }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(board.id)) } action: { viewport = $0 }
                    .onChange(of: drag?.point ?? folderDrag?.point ?? spaceDrag?.point) { _, point in
                        guard let point, viewport.contains(point),
                              ProcessInfo.processInfo.systemUptime - lastScroll > 0.25 else { return }
                        let ids = columns.map { $0.0.id }
                        let next: UUID?
                        if point.x > viewport.maxX - SideBar.row {
                            next = ids.first { frames[$0].map { $0.maxX > viewport.maxX + 1 } ?? false }
                        } else if point.x < viewport.minX + SideBar.row {
                            next = ids.last { frames[$0].map { $0.minX < viewport.minX - 1 } ?? false }
                        } else { return }
                        if let next {
                            lastScroll = ProcessInfo.processInfo.systemUptime
                            withAnimation(Motion.glide) { reader.scrollTo(next, anchor: .center) }
                        }
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if let drag {
                SideRow(browser: browser, prefs: browser.prefs, tab: drag.tab, live: false, closes: false)
                    .environment(\.columnHosted, true)
                    .environment(\.columnPointed, false)
                    .frame(width: max(220, browser.sidebarContentWidth))
                    .restingCardFrame(inset: 0)
                    .offset(x: drag.point.x + SideBar.margin, y: drag.point.y + SideBar.margin)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .coordinateSpace(name: board.id)
        .onPreferenceChange(BoardRowFrames.self) { rowFrames = $0 }
        .task(id: groupTarget) {
            ready = nil
            guard let target = groupTarget else { return }
            try? await Task.sleep(for: .seconds(TabDropChoice.folderHold))
            if !Task.isCancelled { ready = target }
        }
        .onPreferenceChange(BoardFrames.self) { frames = $0 }
        .modifier(SidebarTypography())
        .task(id: order.map(\.id)) {
            for space in order where space.id != browser.spaceID && browser.parked[space.id] == nil {
                guard !Task.isCancelled else { return }
                browser.parked[space.id] = browser.loadRow(space.id)
                await Task.yield()
            }
        }
    }

    private var insertion: some View {
        Capsule().fill(Color.accentColor).frame(height: 2).allowsHitTesting(false)
    }

    private func rowFrame(_ key: String) -> some View {
        GeometryReader { geo in
            Color.clear.preference(key: BoardRowFrames.self, value: [key: geo.frame(in: .named(board.id))])
        }
    }

    private var groupTarget: UUID? { drag.flatMap(folderTarget) }

    private func folderTarget(_ drag: BoardDrag) -> UUID? {
        guard drag.tab.keepable, frames[drag.source]?.contains(drag.point) == true,
              let row = rowFrames.first(where: { $0.value.insetBy(dx: SideBar.inner, dy: SideBar.row / 3).contains(drag.point) }),
              let id = UUID(uuidString: row.key), id != drag.tab.id,
              let target = browser.everyTab.first(where: { $0.id == id }), target !== board, target.keepable,
              target.pin == nil, drag.tab.pin == nil else { return nil }
        return id
    }

    private func tabOwners(_ space: UUID) -> [Tab] {
        space == browser.spaceID ? browser.tabs : browser.parked[space]?.tabs ?? []
    }

    private func canDrag(_ tab: Tab, in space: UUID) -> Bool {
        space != Space.mailID && !Agents.shared.sealed(tab)
    }

    private func landing(_ drag: BoardDrag?, space: UUID, tabs: [Tab], sort: LibrarySort) -> BoardLanding? {
        guard let drag, viewport.contains(drag.point), space != Space.mailID, let frame = frames[space],
              frame.contains(drag.point) else { return nil }
        if drag.source == space {
            guard sort == .sidebar else { return nil }
        } else {
            guard browser.prefs.usesSpaces, browser.windowPurpose == .normal, !browser.blank,
                  browser.sendable(drag.tab), !browser.pinnedAlready(drag.tab, in: space) else { return nil }
        }
        // In a sorted view the sort menu owns row order. Highlight the receiving column.
        guard sort == .sidebar else { return BoardLanding(before: nil) }
        let tabs = tabs.filter { rowFrames[$0.id.uuidString] != nil }
        let owners = tabOwners(space)
        let folders = browser.folderBook.empties(in: space) + owners.compactMap(\.nest).flatMap(\.chain)
        if let folder = folders.first(where: { rowFrames[$0.key]?.contains(drag.point) == true }) {
            guard drag.tab.keepable, drag.tab.pin == nil else { return nil }
            return BoardLanding(before: nil, placement: .folder(folder.id))
        }
        if drag.tab.keepable, drag.tab.pin == nil,
           let neighbor = tabs.first(where: { rowFrames[$0.id.uuidString]?.contains(drag.point) == true }),
           neighbor !== drag.tab, neighbor.pin == nil,
           (neighbor.nest != nil || drag.tab.nest != nil),
           neighbor.nest?.chain.contains(where: { rowFrames[$0.key] != nil }) ?? true,
           let rect = rowFrames[neighbor.id.uuidString] {
            let pairs = space == browser.spaceID ? browser.pairs : browser.parked[space]?.pairs ?? []
            let moving = pairs.first { $0.contains(drag.tab.id) }
            let rest = owners.filter { $0.pin == nil && $0 !== drag.tab && moving?.contains($0.id) != true }
            guard let index = rest.firstIndex(where: { $0 === neighbor }) else { return nil }
            let pair = pairs.first { $0.contains(neighbor.id) }
            let after = drag.point.y >= rect.midY
            let slot = after ? (rest.lastIndex { pair?.contains($0.id) == true } ?? index) + 1
                             : (rest.firstIndex { pair?.contains($0.id) == true } ?? index)
            return BoardLanding(before: nil, placement: .row(index: slot, kept: neighbor.kept, nest: neighbor.nest?.id),
                                indicator: neighbor.id, below: after)
        }
        var slot = tabs.firstIndex { tab in
            guard let rect = rowFrames[tab.id.uuidString] else { return false }
            return rect.midY > drag.point.y || (tab.pin != nil && rect.contains(drag.point) && rect.midX > drag.point.x)
        } ?? tabs.count
        let group = boardSection(drag.tab)
        slot = min(max(slot, tabs.prefix { boardSection($0) < group }.count), tabs.prefix { boardSection($0) <= group }.count)
        let pairs = space == browser.spaceID ? browser.pairs : browser.parked[space]?.pairs ?? []
        if slot > 0, slot < tabs.count, pairs.contains(where: { $0.first == tabs[slot - 1].id && $0.second == tabs[slot].id }) {
            slot += 1
        }
        return BoardLanding(before: slot < tabs.count ? tabs[slot].id : nil)
    }

    private func spaceLanding(_ hand: BoardSpaceDrag, in space: UUID) -> Bool? {
        guard hand.source != space, viewport.contains(hand.point), let frame = frames[space],
              frame.contains(hand.point) else { return nil }
        return hand.point.x >= frame.midX
    }

    private func reorderSpace(_ id: UUID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(board.id))
            .updating($spaceDrag) { value, state, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                state = BoardSpaceDrag(source: id, point: value.location)
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height),
                      let from = browser.turnOrder.firstIndex(where: { $0.id == id }) else { return }
                let hand = BoardSpaceDrag(source: id, point: value.location)
                for (index, space) in browser.turnOrder.enumerated() {
                    if let after = spaceLanding(hand, in: space.id) {
                        browser.moveInOrder(id, to: index + (after ? 1 : 0) - (from < index ? 1 : 0))
                        return
                    }
                }
            }
    }

    private func folderLanding(_ hand: BoardFolderDrag, in space: UUID) -> BoardFolderLanding? {
        guard hand.source != space, space != Space.mailID, hand.source != Space.mailID,
              browser.prefs.usesSpaces, !browser.blank, browser.windowPurpose == .normal,
              viewport.contains(hand.point), frames[space]?.contains(hand.point) == true else { return nil }
        let members = tabOwners(hand.source).filter { $0.nest?.within(hand.nest) == true }
        guard members.allSatisfy({ $0 !== board && $0.shy == board.shy && browser.sendable($0)
            && $0.everywhere == nil && !Agents.shared.sealed($0) }) else { return nil }
        let loose = tabOwners(space).filter { $0.pin == nil }
        let kept = !hand.nest.today
        let boundary = loose.prefix(while: \.kept).count
        let range = kept ? 0..<boundary : boundary..<loose.count
        // A whole folder lands between root rows. Children, including hidden
        // children of folded folders, keep their parent's position.
        var seen = Set<String>()
        for index in range {
            let tab = loose[index]
            let root = tab.nest?.chain.first
            let key = root?.key ?? tab.id.uuidString
            guard seen.insert(key).inserted, let rect = rowFrames[key] else { continue }
            if hand.point.y < rect.midY { return BoardFolderLanding(index: index, key: key) }
        }
        let next = kept ? loose.dropFirst(boundary).first : nil
        return BoardFolderLanding(index: range.upperBound, key: next.map { $0.nest?.chain.first?.key ?? $0.id.uuidString })
    }

    private func moveFolder(_ nest: Nest, from source: UUID) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(board.id))
            .updating($folderDrag) { value, state, _ in
                state = BoardFolderDrag(nest: nest, source: source, point: value.location)
            }
            .onEnded { value in
                let hand = BoardFolderDrag(nest: nest, source: source, point: value.location)
                for space in spaces {
                    guard let slot = folderLanding(hand, in: space.id) else { continue }
                    let origin = browser.spaceID
                    _ = browser.landTabs([], from: source, to: space.id,
                                         at: .row(index: slot.index, kept: !nest.today, nest: nil), folder: nest, showing: false)
                    if browser.spaceID != origin { browser.switchSpace(to: origin) }
                    if browser.active !== board && browser.tabs.contains(where: { $0 === board }) { browser.select(board) }
                    return
                }
            }
    }

    private func move(_ tab: Tab, from source: UUID, columns: [(Space, [Tab])], sort: LibrarySort) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .named(board.id))
            .updating($drag) { value, state, _ in
                state = BoardDrag(tab: tab, source: source, point: value.location)
            }
            .onEnded { value in
                let end = BoardDrag(tab: tab, source: source, point: value.location)
                if let id = ready, folderTarget(end) == id,
                   let rect = rowFrames[id.uuidString], rect.contains(value.location),
                   let target = browser.everyTab.first(where: { $0.id == id }) {
                    SidebarSpaceActions(browser: browser, id: source).run {
                        browser.newFolder(with: [target, tab], today: !target.kept, around: target)
                    }
                    return
                }
                for (space, tabs) in columns {
                    if let slot = landing(end, space: space.id, tabs: tabs, sort: sort) {
                        browser.moveOverviewTab(tab, from: source, to: space.id, before: slot.before, board: board,
                                                afterLastVisible: tabs.last?.id, placement: slot.placement)
                        break
                    }
                }
            }
    }
}

private struct BoardSpaceDrag {
    let source: UUID
    let point: CGPoint
}

private struct BoardFolderDrag {
    let nest: Nest
    let source: UUID
    let point: CGPoint
}

private struct BoardFolderLanding {
    let index: Int
    let key: String?
}

private struct BoardDrag {
    let tab: Tab
    let source: UUID
    let point: CGPoint
}

private struct BoardLanding {
    let before: Tab.ID?
    var placement: SpaceLanding?
    var indicator: UUID?
    var below = false
}

private struct BoardFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

@MainActor private func boardSection(_ tab: Tab) -> Int {
    if tab.pin != nil { return 0 }
    return tab.kept ? 1 : 2
}

extension Browser {
    @discardableResult
    func moveOverviewTab(_ tab: Tab, from source: UUID, to destination: UUID, before anchor: Tab.ID?, board: Tab, afterLastVisible last: Tab.ID? = nil, placement: SpaceLanding? = nil) -> Bool {
        let origin = spaceID
        guard active === board, source != Space.mailID, destination != Space.mailID,
              spaceHolding(tab) == source, tab.shy == board.shy, tab !== board,
              !Agents.shared.sealed(tab) else { return false }
        if source != destination {
            guard prefs.usesSpaces, windowPurpose == .normal, !blank, sendable(tab),
                  spaces.contains(where: { $0.id == source }), spaces.contains(where: { $0.id == destination }),
                  !pinnedAlready(tab, in: destination), !(source == origin && partner(of: tab) === board) else { return false }
        }
        let still = SpaceTurn.still
        SpaceTurn.still = true
        defer {
            if spaceID != origin { switchSpace(to: origin) }
            if active !== board && tabs.contains(where: { $0 === board }) { select(board) }
            SpaceTurn.still = still
        }
        if spaceID != source { switchSpace(to: source) }
        guard spaceID == source, tabs.contains(where: { $0 === tab }) else { return false }
        if let placement {
            let carried = tabs.filter { $0 === tab || $0 === partner(of: tab) }
            guard carried.allSatisfy({ $0 !== board && $0.pin == nil && $0.keepable && !Agents.shared.sealed($0) }) else { return false }
            if source == destination {
                arranging { placeCarried(carried, at: placement) }
                return true
            }
            return !landTabs(carried, from: source, to: destination, at: placement, showing: false).isEmpty
        }
        if source == destination {
            return reorderOverviewTab(tab, before: anchor, afterLastVisible: last)
        }
        return moveTabs([tab], to: destination, say: false, before: anchor) != nil
    }

    private func reorderOverviewTab(_ tab: Tab, before anchor: Tab.ID?, afterLastVisible last: Tab.ID?) -> Bool {
        guard let from = tabs.firstIndex(where: { $0 === tab }) else { return false }
        let slot: Int
        if let anchor {
            guard let index = tabs.firstIndex(where: { $0.id == anchor }) else { return false }
            // A filtered board can expose only the second half of a split.
            let pair = self.pair(of: anchor)
            slot = pair.flatMap { p in tabs.firstIndex { p.contains($0.id) } } ?? index
        } else if let last {
            guard let index = tabs.lastIndex(where: { $0.id == last }) else { return false }
            let pair = self.pair(of: last)
            slot = (pair.flatMap { p in tabs.lastIndex { p.contains($0.id) } } ?? index) + 1
        } else {
            slot = tabs.count
        }
        let group = boardSection(tab)
        let start = tabs.prefix { boardSection($0) < group }.count
        let end = tabs.prefix { boardSection($0) <= group }.count
        let boundary = min(max(slot, start), end)
        let index = boundary > from ? boundary - 1 : boundary
        guard index != from else { return false }
        // The Sidebar move carries split partners, records undo and saves the session.
        move(tab, to: index)
        return true
    }
}

private struct BoardRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// The filter column becomes a popover when the browser sidebar leaves little room.
private struct SplitLibrary<Filters: View, Action: View, Results: View>: View {
    @ObservedObject var browser: Browser
    let page: LibraryPage
    let heading: String
    let sorts: [LibrarySort]
    @ViewBuilder let filters: () -> Filters
    @ViewBuilder let action: () -> Action
    @ViewBuilder let results: (CGFloat) -> Results
    @State private var showFilters = false

    var body: some View {
        LibraryPageFrame(page: page, action: action) {
            LibrarySearch(page: page)
        } content: {
            GeometryReader { bounds in
                let narrow = bounds.size.width < 650
                HStack(alignment: .top, spacing: LibraryPageLayout.columnGap) {
                    if !narrow {
                        ThreadScrollView { filters() }.frame(width: LibraryPageLayout.navigationWidth)
                    }
                    VStack(alignment: .leading, spacing: CardFrame.inset) {
                        HStack {
                            if narrow {
                                Button { showFilters.toggle() } label: {
                                    Label(page == .history ? "Date" : "Folder",
                                          systemImage: page == .history ? "calendar" : "folder")
                                }
                                .buttonStyle(.yab(.secondary, .regular))
                                .popover(isPresented: $showFilters) {
                                    ThreadScrollView { filters() }.padding(CardFrame.inset).frame(width: 220, height: 320)
                                }
                            }
                            Text(heading).font(.headline).lineLimit(1)
                            Spacer()
                            LibrarySortMenu(page: page, sorts: sorts)
                        }
                        GeometryReader { area in
                            results(area.size.width)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                }
            }
        }

    }
}

/// Shared navigation row: optional hierarchy indentation and a separate disclosure control.
struct LibraryScopeRow: View {
    let title: String
    let symbol: String
    let selected: Bool
    var depth = 0
    var selectedIconTint: Color? = nil
    var expanded: Bool? = nil
    var toggleExpanded: (() -> Void)? = nil
    let action: () -> Void
    @Environment(\.tone) private var tone

    var body: some View {
        HStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 8) {
                    if depth == 0 { Symbol(symbol, size: 14).foregroundStyle(selected && tone == nil ? selectedIconTint ?? Palette.ink : Palette.strong(on: tone)) }
                    Text(title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8 + CGFloat(depth) * 20) // design: submenu indentation adds one navigation step while keeping the trailing inset.
                .padding(.trailing, 8)
                .frame(height: 32).contentShape(Rectangle())
            }
            .accessibilityAddTraits(selected ? .isSelected : [])
            if let expanded, let toggleExpanded {
                Button(action: toggleExpanded) {
                    Symbol(expanded ? "chevron.down" : "chevron.right", size: 10)
                        .foregroundStyle(Palette.muted(on: tone))
                        .frame(width: 24, height: 32).contentShape(Rectangle())
                }
                .accessibilityLabel("\(expanded ? "Collapse" : "Expand") \(title)")
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            }
        }
        .buttonStyle(.plain).font(CardFrame.detail)
        .background(selected ? Palette.wash(on: tone) : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control))
    }
}

private struct BookmarkFolders: View {
    let store: Bookmarks
    let nodes: [Bookmark]
    @Environment(LibraryControls.self) private var controls

    var body: some View {
        ForEach(nodes.filter(\.isFolder)) { node in
            let hasFolders = node.children?.contains(where: \.isFolder) == true
            let expanded = controls.expandedFolders.contains(node.id)
            HStack(spacing: 0) {
                if hasFolders {
                    Button {
                        if expanded { controls.expandedFolders.remove(node.id) }
                        else { controls.expandedFolders.insert(node.id) }
                    } label: {
                        Symbol(expanded ? "chevron.down" : "chevron.right", size: 10)
                            .frame(width: 20, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel((expanded ? "Collapse " : "Expand ") + node.title)
                } else {
                    Spacer().frame(width: 20)
                }
                BookmarkFolderRow(node: node, store: store)
            }
            if expanded && hasFolders {
                VStack(spacing: 2) { BookmarkFolders(store: store, nodes: node.children ?? []) }
                    .padding(.leading, 12) // design: indent the children below their parent
            }
        }
    }
}

private struct BookmarkFolderRow: View {
    let node: Bookmark
    let store: Bookmarks
    @Environment(LibraryControls.self) private var controls
    @Environment(\.colorScheme) private var scheme
    @State private var hovering = false
    @State private var editing = false

    var body: some View {
        let selected = controls.folder == node.id
        let tint = FolderTint(stored: node.folderColor)
        HStack(spacing: 0) {
            Button { controls.folder = node.id } label: {
                HStack(spacing: 8) {
                    SpaceMark(icon: node.folderIcon ?? "folder", size: 14)
                        .foregroundStyle(tint == .black ? Palette.ink : tint.ink(dark: scheme == .dark))
                    Text(node.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 8).frame(height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
            Button {
                controls.folder = node.id
                editing = true
            } label: { Symbol("pencil", size: 12) }
            .buttonStyle(.yab(.quiet, .small, icon: .square))
            .opacity(selected || hovering || editing ? 1 : 0)
            .accessibilityLabel("Edit " + node.title)
            .popover(isPresented: $editing, arrowEdge: .trailing) {
                IconPicker(mark: node.folderIcon ?? "folder", space: [], spaceTint: tint,
                           pick: { store.setFolderIcon($0, for: node.id) }, close: { editing = false },
                           setColor: { store.setFolderColor($0, for: node.id) }, bookmark: node,
                           rename: { store.update(node.id, title: $0, url: nil) })
            }
        }
        .font(CardFrame.detail)
        .background(selected ? Palette.wash : Color.clear, in: RoundedRectangle(cornerRadius: Radius.control))
        .onHover { hovering = $0 }
    }
}

private struct LibraryPageCell: View {
    let title: String
    let url: URL?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let url, let image = Favicons.shared.cached(page: url) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Symbol("globe", size: 15).foregroundStyle(Palette.muted)
                }
            }.frame(width: 18, height: 18)
            Text(title).font(CardFrame.title).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LibraryTable<Header: View, Rows: View>: View {
    let count: Int
    @ViewBuilder let header: () -> Header
    @ViewBuilder let rows: () -> Rows

    var body: some View {
        VStack(spacing: 0) {
            header().font(CardFrame.detail).foregroundStyle(Palette.muted)
                .padding(.horizontal, CardFrame.inset).frame(height: 34)
            Divider()
            ThreadScrollView {
                LazyVStack(spacing: 0) { rows() }
            }.scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: 35 + CGFloat(count) * 39, alignment: .top)
        .restingCardFrame(inset: 0)
    }
}

private struct BookmarkLibrary: View {
    @ObservedObject var store: Bookmarks
    let browser: Browser
    let tab: Tab
    @Environment(LibraryControls.self) private var controls
    @State private var naming = false
    @State private var folderName = ""

    private var entries: [Bookmark] {
        let folder = controls.folder.flatMap(store.node)
        let query = controls.search.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [Bookmark] = []
        func walk(_ nodes: [Bookmark], path: String) {
            for node in nodes {
                if node.isFolder { walk(node.children ?? [], path: path + " › " + node.title) }
                else if matchesLibrary(query, node.title, node.url ?? "", path) {
                    matches.append(node)
                }
            }
        }
        walk(folder?.children ?? store.roots, path: folder.map { store.path(of: $0.id) } ?? "")
        switch controls.sort {
        case .newest: matches.sort { ($0.added ?? .distantPast) > ($1.added ?? .distantPast) }
        case .name: matches.sort { alphabetic($0.title, $1.title) }
        default: break
        }
        return matches
    }

    var body: some View {
        SplitLibrary(browser: browser, page: .bookmarks, heading: controls.folder.flatMap(store.node)?.title ?? "All bookmarks",
                     sorts: [.saved, .newest, .name]) {
            VStack(spacing: 2) {
                LibraryScopeRow(title: "All bookmarks", symbol: "bookmark", selected: controls.folder == nil) {
                    controls.folder = nil
                }
                Divider().padding(.vertical, 8)
                BookmarkFolders(store: store, nodes: store.roots)
            }
        } action: {
            Button { folderName = ""; naming = true } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }.buttonStyle(.yab(.primary, .regular, capsule: true))
        } results: { width in
            let addressWidth = min(218, width * 0.30)
            let rows = entries
            if rows.isEmpty {
                Text(controls.search.isEmpty ? (controls.folder == nil ? "No bookmarks yet" : "Empty folder") : "No matches")
                    .font(CardFrame.detail).foregroundStyle(Palette.muted)
            } else {
                LibraryTable(count: rows.count) {
                    HStack(spacing: 8) {
                        Text("Page").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Address").frame(width: addressWidth, alignment: .leading)
                        Color.clear.frame(width: 24)
                    }
                } rows: {
                    ForEach(rows) { row in
                        bookmarkRow(row, addressWidth: addressWidth)
                        Divider()
                    }
                }
            }
        }
        .alert("New Folder", isPresented: $naming) {
            TextField("Folder name", text: $folderName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let title = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                let parent = controls.folder
                let folder = store.insert(.folder(title, []), into: parent)
                if let parent { controls.expandedFolders.insert(parent) }
                controls.folder = folder.id
                controls.search = ""
            }.disabled(folderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .onChange(of: store.revision) {
            if let id = controls.folder, store.node(id) == nil { controls.folder = nil }
        }
    }

    private func bookmarkRow(_ node: Bookmark, addressWidth: CGFloat) -> some View {
        let url = node.url.flatMap(URL.init(string:))
        let address = url.map { IDN.shownAddress(Address.pretty($0, port: true)) } ?? ""
        return HStack(spacing: 8) {
            Button {
                if let url { browser.open(url, foreground: true, from: tab) }
            } label: {
                HStack(spacing: 8) {
                    LibraryPageCell(title: node.title.isEmpty || node.title == node.url ? address : node.title, url: url)
                    Text(address).lineLimit(1).font(CardFrame.detail).foregroundStyle(Palette.muted)
                        .frame(width: addressWidth, alignment: .leading)
                }.frame(height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Menu {
                if let url {
                    Button("Open in Background Tab") { browser.open(url, foreground: false, from: tab) }
                    Button("Copy URL") { browser.copyPlain(url.absoluteString) }
                }
                Button("Edit Bookmark…") {
                    browser.openPlace(.bookmarks)
                    browser.beginEdit(.bookmark(node.id))
                }
            } label: { Symbol("ellipsis", size: 12).frame(width: 24, height: 24) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Actions for " + node.title)
        }.padding(.horizontal, CardFrame.inset)
    }
}

private func matchesLibrary(_ query: String, _ fields: String...) -> Bool {
    query.split(whereSeparator: \.isWhitespace).allSatisfy { word in
        fields.contains { $0.localizedStandardContains(String(word)) }
    }
}

private func alphabetic(_ a: String, _ b: String) -> Bool { a.localizedStandardCompare(b) == .orderedAscending }

private struct LibraryEmpty: View {
    let page: LibraryPage
    let filtered: Bool
    var body: some View {
        Text(filtered ? "No matches" : "No " + page.rawValue + " yet")
            .font(CardFrame.detail).foregroundStyle(Palette.muted).padding(.vertical, CardFrame.inset)
    }
}

private struct HistoryLibrary: View {
    @ObservedObject var store: History
    let browser: Browser
    let tab: Tab
    @Environment(LibraryControls.self) private var controls

    var body: some View {
        SplitLibrary(browser: browser, page: .history, heading: controls.day?.formatted(.dateTime.weekday(.wide).month().day().year()) ?? "All history",
                     sorts: [.newest, .frequent, .name]) {
            VStack(spacing: 2) {
                LibraryScopeRow(title: "All history", symbol: "clock", selected: controls.day == nil) {
                    controls.day = nil
                }
                LibraryScopeRow(title: "Today", symbol: "sun.max", selected: controls.day.map(Calendar.current.isDateInToday) == true) {
                    controls.day = .now
                    controls.month = .now
                }
                Divider().padding(.vertical, 8)
                LibraryCalendar()
            }
        } action: { EmptyView() } results: { width in
            let rows = matches
            let siteWidth = min(218, width * 0.28)
            let timeWidth: CGFloat = controls.day == nil ? 124 : 90
            if rows.isEmpty {
                LibraryEmpty(page: .history, filtered: controls.day != nil || !controls.search.isEmpty)
            } else {
                LibraryTable(count: rows.count) {
                    HStack(spacing: 8) {
                        Text("Last visited").frame(width: timeWidth, alignment: .leading)
                        Text("Page").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Site").frame(width: siteWidth, alignment: .leading)
                    }
                } rows: {
                    ForEach(rows, id: \.key) { row in
                        Button { browser.open(row.url, foreground: true, from: tab) } label: {
                            HStack(spacing: 8) {
                                Text(row.last.formatted(date: controls.day == nil ? .numeric : .omitted, time: .shortened))
                                    .monospacedDigit().frame(width: timeWidth, alignment: .leading)
                                LibraryPageCell(title: row.title.isEmpty ? Address.shown(row.url) : row.title, url: row.url)
                                    .foregroundStyle(Palette.ink)
                                Text(row.url.host().map(IDN.shownAddress) ?? Address.shown(row.url))
                                    .frame(width: siteWidth, alignment: .leading)
                            }.font(CardFrame.detail).foregroundStyle(Palette.muted).lineLimit(1)
                                .padding(.horizontal, CardFrame.inset).frame(height: 38).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    private var matches: [History.Trace] {
        let calendar = Calendar.current
        var rows = store.everything().filter { row in
            (controls.day.map { calendar.isDate(row.last, inSameDayAs: $0) } ?? true)
                && matchesLibrary(controls.search, row.title, row.url.absoluteString)
        }
        switch controls.sort {
        case .frequent: rows.sort { $0.count > $1.count }
        case .name: rows.sort { alphabetic($0.title, $1.title) }
        default: break
        }
        return rows
    }
}

private struct LibraryCalendar: View {
    @Environment(LibraryControls.self) private var controls
    @Environment(\.calendar) private var calendar

    var body: some View {
        if let month = calendar.dateInterval(of: .month, for: controls.month),
           let days = calendar.range(of: .day, in: .month, for: month.start) {
            let offset = (calendar.component(.weekday, from: month.start) - calendar.firstWeekday + 7) % 7
            VStack(spacing: 8) {
                HStack {
                    Text(month.start, format: .dateTime.month(.wide).year()).fontWeight(.medium)
                    Spacer()
                    step(-1)
                    step(1)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 2) {
                    ForEach(0..<7) { index in
                        Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                            .foregroundStyle(Palette.muted)
                    }
                    ForEach(0..<(offset + days.count), id: \.self) { index in
                        if index < offset { Color.clear.frame(height: 24) }
                        else if let date = calendar.date(byAdding: .day, value: index - offset, to: month.start) {
                            let selected = controls.day.map { calendar.isDate(date, inSameDayAs: $0) } == true
                            Button { controls.day = date } label: {
                                Text(date, format: .dateTime.day()).frame(width: 24, height: 24)
                                    .foregroundStyle(selected ? Palette.ground : Palette.ink)
                                    .background(selected ? Palette.ink : Color.clear, in: Circle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
                                .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }.font(CardFrame.detail)
        }
    }

    private func step(_ delta: Int) -> some View {
        Button {
            if let month = calendar.date(byAdding: .month, value: delta, to: controls.month) { controls.month = month }
        } label: {
            Symbol(delta < 0 ? "chevron.left" : "chevron.right", size: 12).frame(width: 22, height: 24)
        }.buttonStyle(.plain).accessibilityLabel(delta < 0 ? "Previous month" : "Next month")
    }
}

private struct DownloadLibrary: View {
    @ObservedObject var store: Loot
    let browser: Browser

    var body: some View {
        LibraryScreen(browser: browser, page: .downloads, filters: [.init(id: "today", title: "Today")], sorts: [.newest, .name],
                      openDownloadFolder: { NSWorkspace.shared.open(browser.currentDownloadFolder) }) { query, filter, sort in
            let rows = store.kept.filter {
                (filter == nil || Calendar.current.isDateInToday($0.date)) && matchesLibrary(query, $0.name, $0.from, $0.source?.absoluteString ?? "")
            }.sorted { sort == .newest ? $0.date > $1.date : alphabetic($0.name, $1.name) }
            if rows.isEmpty {
                LibraryEmpty(page: .downloads, filtered: filter != nil || !query.isEmpty)
            } else {
                GeometryReader { area in
                    let sourceWidth = min(180, area.size.width * 0.22)
                    let dateWidth = min(146, area.size.width * 0.25)
                    LibraryTable(count: rows.count) {
                        HStack(spacing: 8) {
                            Text("File").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Source").frame(width: sourceWidth, alignment: .leading)
                            Text("Downloaded").frame(width: dateWidth, alignment: .leading)
                            Color.clear.frame(width: 24)
                        }
                    } rows: {
                        ForEach(rows) { row in
                            let site = row.source?.host() ?? URL(string: row.from)?.host() ?? row.from
                            Button { store.reveal(row) } label: {
                                HStack(spacing: 8) {
                                    if let icon = ActionIcons.file(row.url) {
                                        Image(nsImage: icon).resizable().scaledToFit().frame(width: 18, height: 18)
                                    } else {
                                        Symbol("doc", size: 16).frame(width: 18)
                                    }
                                    Text(row.name).font(CardFrame.title).foregroundStyle(Palette.ink)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(IDN.shownAddress(site)).frame(width: sourceWidth, alignment: .leading)
                                    Text(Browser.day(row.date) + ", " + row.date.formatted(date: .omitted, time: .shortened))
                                        .frame(width: dateWidth, alignment: .leading)
                                    Symbol("magnifyingglass", size: 12).frame(width: 24)
                                }
                                .lineLimit(1).font(CardFrame.detail).foregroundStyle(Palette.muted)
                                .padding(.horizontal, CardFrame.inset).frame(height: 38).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).pointerTip("Show in Finder")
                            .accessibilityHint("Show in Finder")
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

private struct ExtensionLibrary: View {
    @ObservedObject var store: Extensions
    let browser: Browser

    var body: some View {
        LibraryScreen(browser: browser, page: .extensions, filters: [.init(id: "on", title: "Enabled"), .init(id: "off", title: "Disabled")], sorts: [.name, .newest]) { query, filter, sort in
            let rows = store.installed.filter {
                (filter == nil || $0.enabled == (filter == "on")) && matchesLibrary(query, $0.name, $0.version)
            }.sorted {
                sort == .name ? alphabetic($0.name, $1.name) : ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast)
            }
            if rows.isEmpty {
                LibraryEmpty(page: .extensions, filtered: filter != nil || !query.isEmpty)
            } else {
                GeometryReader { area in
                    let versionWidth = min(180, area.size.width * 0.22)
                    let switchWidth = min(146, area.size.width * 0.18)
                    LibraryTable(count: rows.count) {
                        HStack(spacing: 8) {
                            Text("Extension").frame(maxWidth: .infinity, alignment: .leading)
                            Text("Version").frame(width: versionWidth, alignment: .leading)
                            Text("Enabled").frame(width: switchWidth, alignment: .leading)
                        }
                    } rows: {
                        ForEach(rows) { row in
                            LibraryExtensionRow(row: row, store: store, browser: browser, versionWidth: versionWidth, switchWidth: switchWidth)
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

struct LibraryExtensionRow: View {
    let row: Installed
    let store: Extensions
    let browser: Browser
    var versionWidth: CGFloat? = nil
    var switchWidth: CGFloat? = nil

    var body: some View {
        HStack(spacing: 8) {
            Button { SettingsWindow.shared.showExtension(row.id, for: browser) } label: {
                HStack(spacing: 8) {
                    ExtensionMark(id: row.id, side: 18, extensions: store)
                    Text(row.name).font(CardFrame.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.version).font(CardFrame.detail).foregroundStyle(Palette.muted)
                        .frame(width: versionWidth, alignment: .leading)
                }.lineLimit(1).frame(height: 38).contentShape(Rectangle())
            }.buttonStyle(.plain)
            Group {
                if ExtensionDetail.replacedByYab(row) {
                    Text("Off").font(CardFrame.detail).foregroundStyle(Palette.muted)
                } else {
                    Toggle("Enable " + row.name, isOn: Binding(get: { row.enabled }, set: { store.setEnabled(row.id, $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                }
            }.frame(width: switchWidth, alignment: .leading)
        }.padding(.horizontal, CardFrame.inset)
    }
}

@MainActor @Observable final class TrailPreviewState {
    var page: LibraryPage?
    private var pinned = false
    private var pending: Task<Void, Never>?
    private var hovered: LibraryPage?

    func pin(_ page: LibraryPage) {
        pending?.cancel()
        pinned = true
        self.page = page
    }

    func dismiss(_ page: LibraryPage) {
        guard self.page == page else { return }
        pending?.cancel()
        pinned = false
        self.page = nil
    }

    func hover(_ page: LibraryPage, inside: Bool) {
        guard !pinned else { return }
        if inside { hovered = page }
        else if hovered == page { hovered = nil }
        else { return }
        pending?.cancel()
        pending = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(inside ? 280 : 240)) }
            catch { return }
            self.page = self.hovered
        }
    }
}

struct TrailLibraryPopover: ViewModifier {
    let page: LibraryPage
    let browser: Browser
    let state: TrailPreviewState
    var vertical = true

    func body(content: Content) -> some View {
        content
            .onHover { state.hover(page, inside: $0) }
            .popover(isPresented: Binding(get: { state.page == page }, set: {
                if !$0 { state.dismiss(page) }
            }), arrowEdge: vertical ? (browser.trailFlank == .right ? .leading : .trailing) : .bottom) {
                TrailPreviewContent(page: page, browser: browser, bookmarks: browser.bookmarks,
                                    history: browser.active.map(browser.history(for:)) ?? browser.history,
                                    loot: browser.loot, hoard: browser.hoard, extensions: Extensions.of(browser)) { state.dismiss(page) }
                    .onHover { state.hover(page, inside: $0) }
            }
    }
}

private struct TrailPreviewContent: View {
    let page: LibraryPage
    let browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    @ObservedObject var history: History
    @ObservedObject var loot: Loot
    @ObservedObject var hoard: Hoard
    @ObservedObject var extensions: Extensions
    let close: () -> Void
    private let limit = 5
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(page.title).font(.headline)
                Spacer()
                Button {
                    close()
                    browser.showLibrary(page)
                } label: { Label("View All", systemImage: "arrow.up.right.square") }
                .buttonStyle(.yab(.secondary, .small))
            }.padding(CardFrame.inset)
            Divider()
            VStack(alignment: .leading, spacing: 2) { rows }.padding(8)
        }.frame(width: 280)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.escape) { close(); return .handled }
    }

    @ViewBuilder private var rows: some View {
        switch page {
        case .bookmarks:
            let recent = Bookmarks.recent(bookmarks.roots).prefix(limit).map(\.node)
            if recent.isEmpty { empty("No recent bookmarks") }
            ForEach(recent) { node in
                if let url = node.url.flatMap(URL.init(string:)) { link(node.title, url) }
            }
        case .history:
            let today = history.everything().prefix(while: { Calendar.current.isDateInToday($0.last) }).prefix(limit)
            if today.isEmpty { empty("No history today") }
            ForEach(today) { link($0.title, $0.url) }
        case .downloads:
            let transfers = hoard.fetches.prefix(limit)
            let latest = loot.kept.sorted { $0.date > $1.date }.prefix(limit - transfers.count)
            if transfers.isEmpty && latest.isEmpty { empty("No downloads") }
            ForEach(transfers) { fetch in
                HoardList.FetchRow(hoard: hoard, meter: hoard.meter, fetch: fetch)
            }
            ForEach(latest) { file in
                HoardList.KeptRow(hoard: hoard, showActions: true, keep: file, open: {
                    close()
                    loot.open(file)
                }, reveal: {
                    close()
                    loot.reveal(file)
                })
            }
        case .extensions:
            let active = extensions.installed.filter(\.enabled).sorted { alphabetic($0.name, $1.name) }.prefix(limit)
            if active.isEmpty { empty("No active extensions") }
            ForEach(active) { item in
                row(item.name, action: { SettingsWindow.shared.showExtension(item.id, for: browser) }) {
                    ExtensionMark(id: item.id, side: SideBar.mark, extensions: extensions)
                }
            }
        default: EmptyView()
        }
    }

    private func empty(_ title: String) -> some View {
        Text(title).font(CardFrame.detail).foregroundStyle(Palette.muted).padding(8)
    }

    private func link(_ title: String, _ url: URL) -> some View {
        row(title.isEmpty ? Address.shown(url) : title, action: { browser.open(url, foreground: true, from: browser.active) }) {
            if let icon = Favicons.shared.cached(page: url) {
                Image(nsImage: icon).resizable().scaledToFit()
            } else { Symbol("globe", size: SideBar.mark) }
        }
    }

    private func row<Icon: View>(_ title: String, action: @escaping () -> Void, @ViewBuilder icon: @escaping () -> Icon) -> some View {
        TrailPreviewItem(title: title, action: { close(); action() }, icon: icon)
    }
}

private struct TrailPreviewItem<Icon: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @Environment(\.tabTitleSize) private var titleSize
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            SidebarTabRow {
                icon().frame(width: SideBar.mark, height: SideBar.mark)
                Text(title).font(.system(size: titleSize)).lineLimit(1)
            }
            .background {
                if hovering { SelectionPlate(corner: SideBar.radius, state: .hover) }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}
