import SwiftUI

struct RecordPage: View {
    let browser: Browser
    @Binding var collection: PageCollection
    let tab: OpenRecord
    let record: CollectionEntry
    @State private var headingHovered = false
    @State private var settings = false
    @State private var activeTab = "Overview"
    @State private var folded: Set<UUID> = []
    @Environment(\.tone) private var tone

    private var name: String { record.values["name"] ?? "" }
    private var template: RecordTemplate { collection.resolvedRecordTemplate }

    var body: some View {
        @Bindable var browser = browser
        VStack(spacing: 0) {
            header
            GeometryReader { room in
                HStack(alignment: .top, spacing: 0) {
                    ThreadScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if !availableButtons.isEmpty {
                                ViewThatFits(in: .horizontal) {
                                    HStack { actions }
                                    VStack(alignment: .leading) { actions }
                                }
                            }
                            let grouped = Set(template.groups.flatMap(\.fields))
                            propertyRows(template.order.filter { !grouped.contains($0) })
                            ForEach(template.groups) { group in
                                let fields = template.order.filter { group.fields.contains($0) && keyExists($0) }
                                if !fields.isEmpty {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Button(group.title) {
                                            if !folded.insert(group.id).inserted { folded.remove(group.id) }
                                        }
                                        .buttonStyle(.plain).font(CardFrame.title)
                                        .foregroundStyle(Palette.muted(on: tone))
                                        .accessibilityValue(folded.contains(group.id) ? "Collapsed" : "Expanded")
                                        if !folded.contains(group.id) { propertyRows(fields) }
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                    .frame(width: min(max(220, room.size.width * 0.36), room.size.width * 0.6))
                    Divider()
                    VStack(alignment: .leading, spacing: 0) {
                        ThreadScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(template.tabs, id: \.self) { title in
                                    PageTabButton(title: title, symbol: title == "Overview" ? "square.grid.2x2" : "doc",
                                                  selected: title == activeTab) { activeTab = title }
                                }
                            }
                        }.fixedSize(horizontal: false, vertical: true).padding(SideBar.margin)
                        Divider()
                        Spacer()
                    }
                }
            }
        }
        .onAppear { if collection.recordTemplate?.configuredButtons == nil { collection.recordTemplate = template } }
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
        return CollectionTemplateHeader(browser: browser) {
            HStack(spacing: SideBar.markGap) {
                TabWindowSwitcher(title: name, prefs: browser.prefs, items: collection.entries, spaceHeading: true, searchPrompt: "Search records",
                                  label: { $0.values["name"] ?? "" }, selected: { $0.id == record.id },
                                  choose: navigate, rowIcon: { _ in Symbol("doc", size: SideBar.mark) }) {
                    Symbol(collection.symbol, size: SideBar.mark)
                }.accessibilityLabel("Switch record, " + name)
                HStack(spacing: 2) {
                    ForEach([-1, 1], id: \.self) { step in
                        let neighbor = index.map { $0 + step }.flatMap { ordered.indices.contains($0) ? ordered[$0] : nil }
                        RailButton(step == -1 ? "Previous record" : "Next record", icon: step == -1 ? "chevron.up" : "chevron.down", doorSize: .header) {
                            if let neighbor { navigate(neighbor) }
                        }.disabled(neighbor == nil)
                    }
                    RailMoreButton(title: "Record settings", selected: settings) { settings.toggle() }
                        .popover(isPresented: $settings) {
                            TrailMenuRow(title: "Customize Template…", action: {
                                settings = false
                                browser.customizingRecord = true
                            }) { Symbol("slider.horizontal.3", size: 14) }.padding(6)
                        }
                }.opacity(headingHovered || settings ? 1 : 0.65)
            }
            .background { if headingHovered || settings { SelectionPlate(corner: SideBar.radius, state: .hover) } }
            .contentShape(Rectangle())
            .onHover { headingHovered = $0 }
        } actions: {
            RailButton("Back to collection", icon: "xmark", doorSize: .header) { browser.closeRecord(tab) }
        }
    }

    private func navigate(_ entry: CollectionEntry) {
        var next = tab
        next.record = entry.id
        browser.showRecord(next, replacing: true)
    }

    private func keyExists(_ key: String) -> Bool { collection.properties.contains { $0.id == key } }

    private var availableButtons: [RecordButtonProperty] { template.buttons.filter { keyExists($0.field) } }

    @ViewBuilder private var actions: some View {
        ForEach(availableButtons) { button in
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
