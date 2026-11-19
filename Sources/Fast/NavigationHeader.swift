import SwiftUI

struct NavigationHeader: View {
    let browser: Browser
    let tab: Tab?
    let corner: CGFloat
    let topInset: CGFloat
    var emptyTone: Tone? = nil
    var inheritsPageSurface = false

    @State private var switcher: Switcher?
    @State private var hoveringTabs = false

    private enum Switcher { case spaces, tabs }

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
        return GeometryReader { room in
            HStack(spacing: size.gap) {
                RailButton(browser.columnTitle, icon: ColumnDoor.mark(browser.flank), doorSize: size) { browser.toggleColumn() }
                    .keyTip(browser.columnTitle)
                RailButton("New Tab", icon: "plus", doorSize: size) { browser.newTab() }
                    .keyTip("New Tab")
                RailButton("Switch Space", icon: "folder", selected: switcher == .spaces, doorSize: size) { switcher = .spaces }
                    .disabled(!browser.swipesSpaces || browser.blank)
                    .keyTip("Switch Space")
                    .popover(isPresented: presented(.spaces), arrowEdge: .bottom) { spaces }

                HStack(spacing: size.gap) {
                    RailButton("Switch Tab", selected: switcher == .tabs, fitsLabel: true, doorSize: size, action: { switcher = .tabs }) {
                        HStack(spacing: SideBar.markGap) {
                            if let tab { NavigationTabLabel(tab: tab) }
                            else { Text("Tabs").sidebarFont(size: 12.5) }
                            Symbol("chevron.down", size: 10)
                        }
                        .padding(.horizontal, SideBar.inner)
                    }
                    .disabled(browser.tabs.isEmpty)
                    .popover(isPresented: presented(.tabs), arrowEdge: .bottom) { tabs }

                    if hoveringTabs, let tab, switcher == nil {
                        if !tab.isBlank {
                            RailButton("Reload Page", icon: "arrow.clockwise", doorSize: size) { browser.reload(tab) }
                                .keyTip("Reload Page")
                        }
                        if browser.tabs.count > 1 {
                            RailButton("Previous Tab", icon: "arrow.up", doorSize: size) { browser.step(-1) }
                                .keyTip("Previous Tab")
                            RailButton("Next Tab", icon: "arrow.down", doorSize: size) { browser.step(1) }
                                .keyTip("Next Tab")
                        }
                    }
                }
                .contentShape(Rectangle())
                .onHover { hoveringTabs = $0 }

                Spacer(minLength: 0)
                if let tab, !tab.isBlank {
                    NavigationPinnedExtensions(tab: tab, extensions: Extensions.of(tab: tab),
                                               available: room.size.width / 3, size: size)
                }
            }
            .padding(.horizontal, SideBar.margin)
            .frame(height: size.side)
            // The card begins below the window edge. Measure the controls
            // from that same edge as the sidebar while keeping the card inset.
            .padding(.top, (Metrics.strip - size.side) / 2 - topInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: Self.height(topInset: topInset))
    }

    private var spaces: some View {
        let order = browser.turnOrder
        return choices(count: order.count) {
            ForEach(order) { space in
                TrailMenuRow(title: space.name, selected: space.id == browser.spaceID, action: {
                    switcher = nil
                    browser.switchSpace(to: space.id)
                }) {
                    SpaceMark(icon: space.icon, size: SideBar.mark)
                }
            }
        }
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

private struct NavigationTabLabel: View {
    @ObservedObject var tab: Tab

    var body: some View {
        Mark(icon: tab.displayIcon, letter: tab.monogram, size: SideBar.mark)
        Text(tab.label)
            .sidebarFont(size: 12.5)
            .lineLimit(1)
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
