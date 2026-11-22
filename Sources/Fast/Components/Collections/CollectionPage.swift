import SwiftUI

struct CollectionPage: View {
    @Binding var collection: PageCollection
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
            HStack(spacing: 6) {
                ForEach(CollectionRuleKind.allCases, id: \.self) { kind in
                    CollectionRuleMenu(kind: kind, collection: collection, view: $collection.views[index])
                }
                Spacer()
            }.padding(.vertical, 6)
            Divider()
            CollectionDataGrid(properties: properties, entries: visible, start: start, total: entries.count,
                               selection: $selection, view: $collection.views[index], schema: collection.properties,
                               matching: entries, collection: collection, update: { id, key, value in
                                   if let row = collection.entries.firstIndex(where: { $0.id == id }) {
                                       collection.entries[row].values[key] = value
                                   }
                               }, collectionName: collection.name, filteredEmpty: !collection.entries.isEmpty,
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
            CollectionEntryForm(collection: collection, filters: view.filters) { entry in
                collection.entries.append(entry)
                adding = false
            } cancel: { adding = false }
            .toned(tone)
        }
    }

    private var toolbar: some View {
        HStack(spacing: SideBar.markGap) {
            ForEach(collection.views.prefix(2)) { item in
                PageTabButton(title: item.name, symbol: "tablecells", selected: item.id == view.id, size: .regular) {
                    collection.selectedView = item.id
                }
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
            PageActionButton(title: "View settings", icon: "slider.horizontal.3", variant: .quiet, size: .regular,
                                   state: settings ? .active : .ready, iconOnly: true) { settings.toggle() }
                .popover(isPresented: $settings) {
                    VStack(alignment: .leading) {
                        Text("Visible properties").font(.headline)
                        ForEach(collection.properties.dropFirst()) { property in
                            Toggle(property.title, isOn: Binding(get: { !view.hidden.contains(property.id) }, set: { show in
                                if show { collection.views[index].hidden.remove(property.id) }
                                else { collection.views[index].hidden.insert(property.id) }
                            }))
                        }
                        Text("Row height").font(CardFrame.detail)
                        ChoiceMenu(title: "Row height", options: [("Comfortable", false), ("Compact", true)],
                                   selection: Binding(get: { view.compactRows == true }, set: { collection.views[index].compactRows = $0 }))
                        Text("Rows per page").font(CardFrame.detail)
                        ChoiceMenu(title: "Rows per page", options: [10, 25, 50, 100].map { (String($0), $0) },
                                   selection: $collection.views[index].pageSize)
                    }.toggleStyle(NetCheckboxStyle()).padding()
                }
            PageActionButton(title: "New Record", icon: "plus", variant: .primary, size: .regular) { adding = true }
        }.padding(.vertical, 6)
    }
}
