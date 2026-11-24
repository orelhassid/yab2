import SwiftUI

struct NavigationHeader: View {
    let browser: Browser
    let tab: Tab?
    let corner: CGFloat
    let topInset: CGFloat
    var emptyTone: Tone? = nil
    var inheritsPageSurface = false

    @State private var switcher: Switcher?
    @State private var sidebarPeeking = false

    private enum Switcher { case tabs }

    static func height(topInset: CGFloat) -> CGFloat {
        Metrics.strip - Backdrop.inset - topInset
    }

    private var size: Door.Size {
        guard browser.prefs.sidebar else { return .header }
        return ColumnHead.doors(width: browser.presentedSidebarWidth, right: browser.flank == .right)
    }

    var body: some View {
        if inheritsPageSurface {
            row
        } else if let tab {
            Toned(tab: tab) { tone in
                row
                    .toned(tone)
                    .background {
                        UnevenRoundedRectangle(topLeadingRadius: corner, topTrailingRadius: corner)
                            .fill(tone?.color ?? Palette.ground)
                    }
            }
        } else {
            row.toned(emptyTone)
        }
    }

    private var row: some View {
        let size = self.size
        let sidebarHidden = browser.sideShown == 0 && !sidebarPeeking
        let showHelm = sidebarHidden && !browser.bandDoors && tab?.isBlank == false
        let showToggle = sidebarHidden && browser.prefs.sidebarButton && (!browser.prefs.sidebar || !browser.bandDoors)
        return GeometryReader { room in
            TabWindowHeader(selection: tab?.id) {
                let order = browser.switcherSpaces + (browser.offersDevelopment ? [.development, .collections] : [])
                TabWindowSwitcher(title: browser.sidebarSpace.name, prefs: browser.prefs, items: order,
                                  label: { $0.name }, selected: { $0.id == browser.sidebarSpaceID },
                                  choose: { space in
                    browser.switchSpace(to: space.id)
                }, rowIcon: { SpaceMark(icon: $0.icon, size: SideBar.mark) }) {
                    SpaceMark(icon: browser.sidebarSpace.icon, size: SideBar.mark)
                }
                .disabled(!(browser.offersAllTabs || browser.swipesSpaces) || browser.blank)
                .keyTip("Switch Space")
            } tabs: {
                ForEach(browser.tabs.filter { !Agents.shared.sealed($0) }) { candidate in
                    NavigationPageTab(tab: candidate, selected: candidate.id == tab?.id, prefs: browser.prefs) {
                        browser.select(candidate)
                    }
                    .id(candidate.id)
                }
            } actions: {
                RailButton("New Tab", icon: "plus", doorSize: size) { browser.newTab() }
                    .keyTip("New Tab")
                RailButton("Switch Tab", icon: "chevron.down", selected: switcher == .tabs, doorSize: size) { switcher = .tabs }
                    .disabled(browser.tabs.isEmpty)
                    .popover(isPresented: presented(.tabs), arrowEdge: .bottom) { tabs }
                if showToggle { ColumnDoor(browser: browser, prefs: browser.prefs) }
                if showHelm, let tab { Helm(browser: browser, tab: tab, reads: false) }
                if let tab, !tab.isBlank {
                    NavigationPinnedExtensions(tab: tab, extensions: Extensions.of(tab: tab),
                                               available: room.size.width / 3, size: size)
                }
            }
            .environment(\.doorSize, size)
            .padding(.horizontal, SideBar.margin)
            .frame(height: size.side)
            // The card begins below the window edge. Measure the controls
            // from that same edge as the sidebar while keeping the card inset.
            .padding(.top, (Metrics.strip - size.side) / 2 - topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Self.height(topInset: topInset))
        .onReceive(browser.peek.$out.removeDuplicates()) { sidebarPeeking = $0 }
    }

    private var tabs: some View {
        let visible = browser.tabs.filter { !Agents.shared.sealed($0) }
        return choices(count: visible.count) {
            ForEach(visible) { candidate in
                NavigationTabChoice(tab: candidate, selected: candidate.id == browser.activeID) {
                    switcher = nil
                    browser.select(candidate)
                }
            }
        }
    }

    private func choices<Rows: View>(count: Int, @ViewBuilder rows: () -> Rows) -> some View {
        ThreadScrollView {
            VStack(spacing: 0, content: rows)
        }
        .frame(width: 240, height: CGFloat(min(8, max(1, count))) * SideBar.row)
        .padding(6)
    }

    private func presented(_ item: Switcher) -> Binding<Bool> {
        Binding(get: { switcher == item }, set: { if !$0, switcher == item { switcher = nil } })
    }
}

/// One page header for website tabs and project tools. Only the destinations
/// scroll, so the switcher and the window actions stay within reach.
struct TabWindowHeader<ID: Hashable, Switcher: View, Tabs: View, Actions: View>: View {
    let selection: ID?
    var showsDivider = true
    @ViewBuilder let switcher: () -> Switcher
    @ViewBuilder let tabs: () -> Tabs
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: SideBar.markGap) {
            switcher()
            if showsDivider { Divider().frame(height: SideBar.mark) }
            ScrollViewReader { proxy in
                ThreadScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.tabGap, content: tabs)
                }
                .onAppear { if let selection { proxy.scrollTo(selection) } }
                .onChange(of: selection) { _, id in if let id { proxy.scrollTo(id) } }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: Door.Size.header.gap, content: actions)
                .fixedSize()
        }
    }
}

struct TabWindowSwitcher<Item: Identifiable, Icon: View, RowIcon: View>: View {
    let title: String
    let prefs: Preferences
    let items: [Item]
    var spaceHeading = false
    var hidesMark = false
    var searchPrompt: String? = nil
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    let label: (Item) -> String
    let selected: (Item) -> Bool
    let choose: (Item) -> Void
    @ViewBuilder let rowIcon: (Item) -> RowIcon
    @ViewBuilder let icon: () -> Icon
    @State private var open = false
    @Environment(\.tone) private var tone

    var body: some View {
        Group {
            if spaceHeading {
                Button { open.toggle() } label: { SpaceHeadingLabel(title: title, mark: icon) }
                    .buttonStyle(.plain)
            } else {
                SidebarTabButton(title: title, selected: open, prefs: prefs, inTabStrip: true,
                                 showsDisclosure: true, showsMark: !hidesMark, action: { open.toggle() }, mark: icon)
            }
        }
            .popover(isPresented: $open, arrowEdge: .bottom) {
                let matches = search.isEmpty ? items : items.filter { label($0).localizedCaseInsensitiveContains(search) }
                VStack(alignment: .leading, spacing: 4) {
                    if let searchPrompt {
                        ThemedSearchField(searchPrompt, text: $search)
                            .focused($searchFocused)
                            .onAppear { searchFocused = true }
                    }
                    ThreadScrollView {
                        LazyVStack(spacing: 0) {
                            if matches.isEmpty { Text("No matching records").font(CardFrame.detail) }
                            ForEach(matches) { item in
                                TrailMenuRow(title: label(item), selected: selected(item), action: {
                                    open = false
                                    choose(item)
                                }) { rowIcon(item) }
                            }
                        }
                    }
                    .frame(height: CGFloat(min(8, max(1, matches.count))) * SideBar.row)
                }
                .onDisappear { search = "" }
                .frame(width: 240)
                .padding(6)
                .background(tone?.color ?? Palette.ground)
                .toned(tone)
            }
    }
}

private struct NavigationPageTab: View {
    @ObservedObject var tab: Tab
    let selected: Bool
    let prefs: Preferences
    let action: () -> Void

    var body: some View {
        SidebarTabButton(title: tab.label, selected: selected, prefs: prefs, inTabStrip: true, action: action) {
            Mark(icon: tab.displayIcon, letter: tab.monogram, size: SideBar.mark)
        }
        .frame(maxWidth: 200)
        .keyTip(tab.label)
    }
}

private struct NavigationTabChoice: View {
    @ObservedObject var tab: Tab
    let selected: Bool
    let action: () -> Void

    var body: some View {
        TrailMenuRow(title: tab.label, selected: selected, action: action) {
            Mark(icon: tab.displayIcon, letter: tab.monogram, size: SideBar.mark)
        }
    }
}

private struct NavigationPinnedExtensions: View {
    let tab: Tab
    @ObservedObject var extensions: Extensions
    let available: CGFloat
    let size: Door.Size

    @ObservedObject private var column = ChromiumColumn.shared
    @ObservedObject private var nativePopup = ChromiumPopupHost.shared

    var body: some View {
        let native = tab.engineKind == .chromium
        let pins = native ? column.buttons(for: tab) : extensions.buttons.filter(\.pinned)
        let popupID = native ? nativePopup.shownExtension(for: tab) : ExtensionPopup.shared.extensionID
        let fromDoor = native ? nativePopup.shownFromDoor(for: tab) : ExtensionPopup.shared.fromDoor
        if !pins.isEmpty {
            ThreadScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: size.gap) {
                    ForEach(pins) { pin in
                        PlatePin(button: pin, lit: !fromDoor && popupID == pin.id,
                                 side: size.side, corner: size.corner, native: native ? tab : nil) {
                            if native { column.press(pin.id, tab: tab) } else { extensions.press(pin.id) }
                        }
                    }
                }
            }
            .frame(width: min(CGFloat(pins.count) * (size.side + size.gap) - size.gap, available))
        }
    }
}
