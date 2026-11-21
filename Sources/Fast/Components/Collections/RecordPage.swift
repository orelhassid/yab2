import SwiftUI

struct RecordPage: View {
    let browser: Browser
    @Binding var collection: PageCollection
    let tab: OpenRecord
    let record: CollectionEntry
    @State private var settings = false
    @State private var activeTab = "Overview"
    @State private var folded: Set<UUID> = []
    @Environment(\.tone) private var tone

    private var name: String { record.values["name"] ?? "" }
    private var template: RecordTemplate { collection.recordTemplate ?? RecordTemplate(collection: collection) }

    var body: some View {
        @Bindable var browser = browser
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { room in
                HStack(alignment: .top, spacing: 0) {
                    ThreadScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(name, systemImage: "doc.text").font(.headline)
                            ViewThatFits(in: .horizontal) {
                                HStack { actions }
                                VStack(alignment: .leading) { actions }
                            }
                            let grouped = Set(template.groups.flatMap(\.fields))
                            propertyRows(template.order.filter { !grouped.contains($0) })
                            ForEach(template.groups) { group in
                                SidebarSection(collapsed: folded.contains(group.id), indent: 0) {
                                    SidebarSectionHeader(title: group.title, paint: browser.developmentLook ?? SpacePaint(browser.prefs),
                                                         collapsed: folded.contains(group.id), toggle: {
                                        if !folded.insert(group.id).inserted { folded.remove(group.id) }
                                    }) { Symbol("folder", size: SideBar.mark) }
                                } rows: { propertyRows(template.order.filter(group.fields.contains)) }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(SideBar.margin)
                    }
                    .frame(width: min(max(220, room.size.width * 0.36), room.size.width * 0.6))
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        ThreadScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(template.tabs, id: \.self) { title in
                                    SidebarTabButton(title: title, selected: title == activeTab, prefs: browser.prefs,
                                                     inTabStrip: true, action: { activeTab = title }) {
                                        Symbol(title == "Overview" ? "square.grid.2x2" : "doc", size: 12)
                                    }
                                }
                            }
                        }.fixedSize(horizontal: false, vertical: true).padding(SideBar.margin)
                        Divider()
                        Spacer()
                    }
                }
            }
        }
        .onAppear { if collection.recordTemplate == nil { collection.recordTemplate = RecordTemplate(collection: collection) } }
        .onChange(of: template.tabs) { if !template.tabs.contains(activeTab) { activeTab = template.tabs.first ?? "Overview" } }
        .sheet(isPresented: $browser.customizingRecord) {
            RecordTemplateEditor(collection: collection) { result in
                collection.recordTemplate = result
                browser.customizingRecord = false
            } cancel: { browser.customizingRecord = false }
        }
    }

    private var header: some View {
        let ordered = collection.views.first { $0.id == tab.view }?.records(in: collection, including: record.id) ?? collection.entries
        let index = ordered.firstIndex { $0.id == record.id }
        return TabWindowHeader(selection: Optional<UUID>.none) {
            HStack(spacing: SideBar.markGap) {
                RailButton("Back to collection", icon: "xmark", doorSize: .header) { browser.closeRecord(tab) }
                TabWindowSwitcher(title: name, prefs: browser.prefs, items: collection.entries, searchPrompt: "Search records",
                                  label: { $0.values["name"] ?? "" }, selected: { $0.id == record.id },
                                  choose: navigate, rowIcon: { _ in Symbol("doc", size: SideBar.mark) }) {
                    Symbol(collection.symbol, size: SideBar.mark)
                }.accessibilityLabel("Switch record, " + name)
                ForEach([-1, 1], id: \.self) { step in
                    let neighbor = index.map { $0 + step }.flatMap { ordered.indices.contains($0) ? ordered[$0] : nil }
                    RailButton(step == -1 ? "Previous record" : "Next record", icon: step == -1 ? "arrow.up" : "arrow.down", doorSize: .header) {
                        if let neighbor { navigate(neighbor) }
                    }.disabled(neighbor == nil)
                }
            }
        } tabs: { EmptyView() } actions: {
            RailButton("Record settings", icon: "gearshape", selected: settings, doorSize: .header) { settings.toggle() }
                .popover(isPresented: $settings) {
                    TrailMenuRow(title: "Customize Template…", action: {
                        settings = false
                        browser.customizingRecord = true
                    }) { Symbol("slider.horizontal.3", size: 14) }.padding(6)
                }
        }
        .padding(.horizontal, SideBar.margin)
        .frame(height: NavigationHeader.height(topInset: 0))
    }

    private func navigate(_ entry: CollectionEntry) {
        var next = tab
        next.record = entry.id
        browser.showRecord(next, replacing: true)
    }

    @ViewBuilder private var actions: some View {
        ForEach(template.buttons) { button in
            if collection.properties.contains(where: { $0.id == button.field }) {
                Button {
                    switch button.command {
                    case .copy:
                        let board = NSPasteboard.general
                        board.clearContents()
                        board.setString(record.values[button.field] ?? "", forType: .string)
                    case .set:
                        if let i = collection.entries.firstIndex(where: { $0.id == record.id }) {
                            collection.entries[i].values[button.field] = button.value
                        }
                    }
                } label: {
                    Label(button.title, systemImage: button.command == .copy ? "doc.on.doc" : "checkmark")
                }.buttonStyle(.yab(.secondary, .small))
                .disabled(button.command == .set && record.values[button.field] == button.value)
            }
        }
    }

    private func propertyRows(_ fields: [String]) -> some View {
        ForEach(fields, id: \.self) { key in
            if let field = collection.properties.first(where: { $0.id == key }) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Symbol(field.type.symbol, size: 12)
                    Text(field.title).foregroundStyle(Palette.muted(on: tone)).frame(maxWidth: .infinity, alignment: .leading)
                    Text(record.values[key] ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }.font(CardFrame.detail)
                Divider()
            }
        }
    }
}
