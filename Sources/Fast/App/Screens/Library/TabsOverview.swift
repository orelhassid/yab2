import AppKit
import SwiftUI

@MainActor private final class OverviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        sheetParent?.endSheet(self)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            cancelOperation(nil)
        } else {
            super.sendEvent(event)
        }
    }
}

extension Browser {
    func showTabsOverview() {
        guard let window = BrowserWindows.shared.window(for: self),
              window.attachedSheet == nil else { return }
        let available = (window.screen?.visibleFrame ?? window.frame).size
        let size = CGSize(width: available.width * 0.95, height: available.height * 0.95)
        let panel = OverviewPanel(contentRect: CGRect(origin: .zero, size: size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = SpaceSurface.tone(in: self)?.appearance ?? window.effectiveAppearance
        let glass = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Radius.window
        glass.layer?.cornerCurve = .continuous
        glass.layer?.masksToBounds = true
        let host = NSHostingView(rootView: TabsOverview(browser: self, shy: privateBrowsing) { [weak panel] in
            panel?.cancelOperation(nil)
        }.frame(width: size.width, height: size.height))
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        glass.addSubview(host)
        panel.contentView = glass
        window.beginSheet(panel)
    }
}

struct TabsOverview: View {
    @ObservedObject var browser: Browser
    let shy: Bool
    let dismiss: () -> Void

    @State private var filter: UUID?
    @State private var search = ""
    @State private var sort = OverviewSort.sidebar
    @State private var frames: [UUID: CGRect] = [:]
    @GestureState private var drag: OverviewDrag?

    private var spaces: [Space] {
        if browser.blank || browser.windowPurpose != .normal { return [browser.space] }
        return browser.turnOrder.filter {
            browser.prefs.usesSpaces || $0.id == browser.spaceID || $0.id == Space.mailID || $0.id == browser.homeSpaceID
        }
    }

    private func tabs(in space: Space) -> [Tab] {
        let row = space.id == browser.spaceID ? browser.tabs : browser.parked[space.id]?.tabs ?? []
        let result = row.filter {
            $0.shy == shy && !Agents.shared.sealed($0) && $0.libraryPage != .tabs &&
            (search.isEmpty || [space.name, $0.rowLabel, ($0.pending ?? $0.address)?.absoluteString ?? ""]
                .contains { $0.localizedCaseInsensitiveContains(search) })
        }
        switch sort {
        case .sidebar: return result
        case .name: return result.sorted { $0.rowLabel.localizedStandardCompare($1.rowLabel) == .orderedAscending }
        case .recent: return result.sorted { $0.touched > $1.touched }
        }
    }

    var body: some View {
        let tone = SpaceSurface.tone(in: browser)
        VStack(spacing: 16) {
            HStack {
                Text("Tabs Overview").font(.title2.weight(.semibold))
                Spacer()
                ThemedSearchField("Search tabs", text: $search).frame(maxWidth: 220)
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(OverviewSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }.fixedSize()
                Button(action: dismiss) { Image(systemName: "xmark") }
                    .buttonStyle(.yab(.secondary, .regular, capsule: true))
                    .accessibilityLabel("Close overview")
            }
            .padding(.horizontal, LibraryPageLayout.inset)
            ScrollView(.horizontal) {
                HStack {
                    filterButton("All tabs", nil)
                    ForEach(spaces) { filterButton($0.name, $0.id) }
                }.padding(.horizontal, CardFrame.inset)
            }.scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.center, for: .alignment)
            groups
        }
        .padding(.top, LibraryPageLayout.sectionGap)
        .foregroundStyle(Palette.ink)
        .background(Color.blue.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: Radius.window))
        .toned(tone)
        .onChange(of: spaces.map(\.id)) { if let filter, !spaces.contains(where: { $0.id == filter }) { self.filter = nil } }
        .onChange(of: browser.active?.asks.contains(where: { $0.kind == .leave }) == true) {
            if browser.active?.asks.contains(where: { $0.kind == .leave }) == true { dismiss() }
        }
        .onExitCommand(perform: dismiss)
    }

    private func filterButton(_ name: String, _ id: UUID?) -> some View {
        Button(name) { filter = id }
            .buttonStyle(.yab(filter == id ? .primary : .secondary, .regular, capsule: true))
            .accessibilityAddTraits(filter == id ? .isSelected : [])
    }

    private var groups: some View {
        let sections = spaces.filter { filter == nil || filter == $0.id }.map { ($0, tabs(in: $0)) }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: LibraryPageLayout.sectionGap) {
                ForEach(sections, id: \.0.id) { space, tabs in
                    if !tabs.isEmpty {
                        VStack(alignment: .leading, spacing: CardFrame.inset) {
                            HStack {
                                SpaceMark(icon: space.icon, size: 16)
                                Text(space.name).font(.headline)
                                Text(tabs.count.formatted()).foregroundStyle(Palette.muted)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 248, maximum: 360), spacing: 16)], spacing: 16) {
                                ForEach(tabs) { tab in card(tab, in: space, tabs: tabs) }
                            }
                        }
                    }
                }
                if sections.allSatisfy({ $0.1.isEmpty }) {
                    Text(search.isEmpty ? "No open tabs" : "No matching tabs")
                        .frame(maxWidth: .infinity).padding(.top, 32)
                }
            }.padding(.horizontal, LibraryPageLayout.inset).padding(.bottom, 32)
        }
        .coordinateSpace(name: "overview")
        .onPreferenceChange(OverviewFrames.self) { frames = $0 }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.thinMaterial).frame(height: 32)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
    }

    private func card(_ tab: Tab, in space: Space, tabs: [Tab]) -> some View {
        let scope = SidebarSpaceActions(browser: browser, id: space.id)
        let open = { dismiss(); scope.run({ browser.select(tab) }, stay: true) }
        let close = {
            Leaving.each([tab]) { leave in
                guard leave, !tab.gone, let owner = browser.spaceHolding(tab) else { return }
                SidebarSpaceActions(browser: browser, id: owner).run { browser.close(tab) }
            }
        }
        let destinations = spaces.filter {
            browser.prefs.usesSpaces && space.id != Space.mailID && $0.id != space.id && $0.id != Space.mailID &&
            browser.sendable(tab) && !browser.pinnedAlready(tab, in: $0.id)
        }
        return OverviewCard(tab: tab, open: open, close: close)
            .opacity(drag?.source == tab.id ? 0.6 : 1)
            .overlay(alignment: .leading) {
                if let drag, drag.source != tab.id, frames[tab.id]?.contains(drag.point) == true {
                    Capsule().fill(Color.accentColor).frame(width: 3)
                        .frame(maxWidth: .infinity, alignment: drag.point.x < (frames[tab.id]?.midX ?? 0) ? .leading : .trailing)
                        .allowsHitTesting(false)
                }
            }
            .background(GeometryReader { proxy in
                Color.clear.preference(key: OverviewFrames.self, value: [tab.id: proxy.frame(in: .named("overview"))])
            })
            .simultaneousGesture(reorder(tab, space: space.id, tabs: tabs),
                                 including: sort == .sidebar && space.id != Space.mailID ? .all : .subviews)
            .contextMenu {
                Button("Open", action: open)
                Button("Copy Link") { browser.copyAddress(tab) }.disabled(tab.address == nil)
                Menu("Move to Space") {
                    ForEach(destinations) { target in
                        Button(target.name) { browser.moveOverviewTab(tab, from: space.id, to: target.id, before: nil) }
                    }
                }.disabled(destinations.isEmpty)
                Divider()
                Button("Close", role: .destructive, action: close)
            }
    }

    private func reorder(_ tab: Tab, space: UUID, tabs: [Tab]) -> some Gesture {
        LongPressGesture(minimumDuration: 0.32)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("overview")))
            .updating($drag) { value, state, _ in
                if case .second(true, let move?) = value { state = OverviewDrag(source: tab.id, point: move.location) }
            }
            .onEnded { value in
                guard case .second(true, let move?) = value,
                      let target = tabs.first(where: { frames[$0.id]?.contains(move.location) == true }),
                      target !== tab, let rect = frames[target.id] else { return }
                let before = move.location.x < rect.midX
                browser.moveOverviewTab(tab, from: space, to: space, before: before ? target.id : nil,
                                        afterLastVisible: before ? nil : target.id)
            }
    }
}

private enum OverviewSort: String, CaseIterable {
    case sidebar = "Sidebar order", recent = "Recently viewed", name = "Name A–Z"
}

private struct OverviewDrag {
    let source: UUID
    let point: CGPoint
}

private struct OverviewFrames: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct OverviewCard: View {
    @ObservedObject var tab: Tab
    let open: () -> Void
    let close: () -> Void
    @State private var preview: NSImage?
    @State private var hovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.aspectRatio(16 / 9, contentMode: .fit)
                .background(Color.blue.opacity(0.12))
                .overlay {
                    if let preview {
                        GeometryReader { geo in
                            Image(nsImage: preview).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height, alignment: .top).clipped()
                        }
                    } else { icon(38) }
                }
            HStack(spacing: 8) {
                icon(16)
                Text(tab.rowLabel).font(CardFrame.detail).lineLimit(1)
            }.padding(CardFrame.inset)
        }
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Radius.surface))
        .overlay { RoundedRectangle(cornerRadius: Radius.surface).strokeBorder(Palette.muted.opacity(hovered ? 0.6 : 0.2)) }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: "Close") { close() }
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button(action: close) { Image(systemName: "xmark").font(.caption.bold()).padding(8).background(.regularMaterial, in: Circle()) }
                    .buttonStyle(.plain).padding(8).accessibilityLabel("Close " + tab.rowLabel)
            }
        }
        .onHover { hovered = $0 }
        .task(id: tab.pending ?? tab.address) {
            preview = nil
            let image = await withCheckedContinuation { reply in tab.glance(width: 560) { reply.resume(returning: $0) } }
            if !Task.isCancelled { preview = image }
        }
    }

    @ViewBuilder private func icon(_ size: CGFloat) -> some View {
        if let icon = tab.displayIcon {
            Image(nsImage: icon).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: tab.libraryPage?.icon ?? "globe").font(.system(size: size)).foregroundStyle(Palette.muted)
        }
    }
}
