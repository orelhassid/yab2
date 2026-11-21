import SwiftUI

struct CollectionPage: View {
    @Binding var collection: PageCollection
    let prefs: Preferences
    @Binding var adding: Bool
    @State private var selection = Set<UUID>()
    let openRecord: (OpenRecord) -> Void
    @Binding var pagesByView: [UUID: Int]
    private var page: Int {
        get { pagesByView[view.id] ?? 0 }
        nonmutating set { pagesByView[view.id] = newValue }
    }
    @State private var moreViews = false
    @Environment(\.tone) private var tone
    @State private var filtering = false
    @State private var settings = false
    @State private var namingView = false
    @State private var viewName = ""

    private var index: Int { collection.views.firstIndex { $0.id == collection.selectedView } ?? 0 }
    private var view: CollectionTableView { collection.views[index] }

    var body: some View {
        let entries = view.records(in: collection)
        let properties = view.visibleProperties(collection.properties)
        let pages = max(1, (entries.count + view.pageSize - 1) / view.pageSize)
        let start = min(page, pages - 1) * view.pageSize
        let visible = Array(entries.dropFirst(start).prefix(view.pageSize))
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider()
            if !view.filters.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(view.filters) { rule in
                            let title = collection.properties.first { $0.id == rule.property }?.title ?? rule.property
                            Button {
                                collection.views[index].filters.removeAll { $0.id == rule.id }
                            } label: {
                                HStack { Text("\(title) is \(rule.value)"); Symbol("xmark", size: 9) }
                            }
                            .keyTip("Remove filter")
                        }
                    }.padding(.vertical, 6)
                }
                Divider()
            }
            CollectionDataGrid(properties: properties, entries: visible, start: start, total: entries.count,
                               selection: $selection, view: $collection.views[index], schema: collection.properties,
                               matching: entries, collectionName: collection.name, filteredEmpty: !collection.entries.isEmpty,
                               create: { adding = true }, clear: { collection.views[index].filters.removeAll() }) { entry in
                openRecord(OpenRecord(collection: collection.id, record: entry.id, view: view.id, page: start / view.pageSize))
            }
            if pages > 1 {
                HStack {
                    Spacer()
                    Button("Previous") { page -= 1 }.disabled(page == 0)
                    Text("\(min(page + 1, pages)) of \(pages)").monospacedDigit()
                    Button("Next") { page += 1 }.disabled(page + 1 >= pages)
                }.padding(.vertical, 8)
            }
        }
        .buttonStyle(.yab(.secondary, .small))
        .padding(.horizontal, SideBar.margin)
        .onChange(of: view.id) { page = 0; selection.removeAll() }
        .onChange(of: view.filters) { page = 0; selection.removeAll() }
        .onChange(of: view.pageSize) { page = 0 }
        .sheet(isPresented: $namingView) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Save view as").font(CardFrame.title)
                YabFormField("View name", text: $viewName)
                HStack {
                    Spacer()
                    Button("Cancel") { namingView = false }.buttonStyle(.yab(.secondary, .regular)).keyboardShortcut(.cancelAction)
                    Button("Save") {
                        var copy = view
                        copy.id = UUID()
                        copy.name = viewName.trimmingCharacters(in: .whitespacesAndNewlines)
                        collection.views.append(copy)
                        collection.selectedView = copy.id
                        namingView = false
                    }.buttonStyle(.yab(.primary, .regular)).disabled(viewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(20).frame(width: 320).background(tone?.color ?? Palette.ground)
        }
        .sheet(isPresented: $adding) {
            CollectionEntryForm(collection: collection, prefs: prefs, filters: view.filters) { entry in
                collection.entries.append(entry)
                adding = false
            } cancel: { adding = false }
            .toned(tone)
        }
    }

    private var toolbar: some View {
        HStack(spacing: SideBar.markGap) {
            ForEach(collection.views.prefix(2)) { item in
                SidebarTabButton(title: item.name, selected: item.id == view.id, prefs: prefs, inTabStrip: true,
                                 action: { collection.selectedView = item.id }) { Symbol("tablecells", size: 12) }
            }
            RailMoreButton(title: "More views", selected: moreViews || index >= 2) { moreViews.toggle() }
                .popover(isPresented: $moreViews) {
                    VStack(spacing: 0) {
                        ThreadScrollView {
                            VStack(spacing: 0) {
                                ForEach(collection.views) { item in
                                    TrailMenuRow(title: item.name, selected: item.id == view.id, action: {
                                        moreViews = false
                                        collection.selectedView = item.id
                                    }) { Symbol("tablecells", size: SideBar.mark) }
                                }
                            }
                        }.frame(height: CGFloat(min(8, collection.views.count)) * SideBar.row)
                        Divider()
                        TrailMenuRow(title: "Save view as…", action: {
                            moreViews = false
                            viewName = ""
                            namingView = true
                        }) { Symbol("plus", size: SideBar.mark) }
                    }.padding(6).frame(width: 220).background(tone?.color ?? Palette.ground)
                }
            Spacer()
            if !selection.isEmpty { Text("\(selection.count) selected").font(.caption) }
            RailButton("Add filter", icon: "line.3.horizontal.decrease", selected: filtering || !view.filters.isEmpty, doorSize: .header) { filtering.toggle() }
                .keyTip("Add filter")
                .popover(isPresented: $filtering) {
                    CollectionFilterForm(properties: collection.properties) { filter in
                        collection.views[index].filters.append(filter)
                        filtering = false
                    }
                }
            RailButton("View settings", icon: "gearshape", selected: settings, doorSize: .header) { settings.toggle() }
                .keyTip("View settings")
                .popover(isPresented: $settings) {
                    VStack(alignment: .leading) {
                        Text("Visible properties").font(.headline)
                        ForEach(collection.properties.dropFirst()) { property in
                            Toggle(property.title, isOn: Binding(get: { !view.hidden.contains(property.id) }, set: { show in
                                if show { collection.views[index].hidden.remove(property.id) }
                                else { collection.views[index].hidden.insert(property.id) }
                            }))
                        }
                        Text("Sort by").font(CardFrame.detail)
                        ChoiceMenu(title: "Sort by", options: [("Record order", nil)] + collection.properties.map { ($0.title, Optional($0.id)) },
                                   selection: $collection.views[index].sortProperty)
                        if view.sortProperty != nil {
                            Toggle("Descending", isOn: Binding(get: { view.descending == true }, set: { collection.views[index].descending = $0 }))
                        }
                        Text("Row height").font(CardFrame.detail)
                        ChoiceMenu(title: "Row height", options: [("Comfortable", false), ("Compact", true)],
                                   selection: Binding(get: { view.compactRows == true }, set: { collection.views[index].compactRows = $0 }))
                        Text("Rows per page").font(CardFrame.detail)
                        ChoiceMenu(title: "Rows per page", options: [10, 25, 50, 100].map { (String($0), $0) },
                                   selection: $collection.views[index].pageSize)
                    }.toggleStyle(NetCheckboxStyle()).padding()
                }
            Button { adding = true } label: { Label("New Record", systemImage: "plus") }
                .buttonStyle(.yab(.primary, .regular))
        }.padding(.vertical, 6)
    }
}

private struct CollectionFilterForm: View {
    let properties: [CollectionProperty]
    let apply: (CollectionFilter) -> Void
    @State private var property = "name"
    @State private var value = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Property").font(CardFrame.detail)
            ChoiceMenu(title: "Property", options: properties.map { ($0.title, $0.id) }, selection: $property)
            YabFormField("Value equals", text: $value)
            Button("Apply filter") { apply(.init(property: property, value: value)) }
                .buttonStyle(.yab(.primary, .regular)).disabled(value.isEmpty)
        }.padding().frame(minWidth: 220)
    }
}
