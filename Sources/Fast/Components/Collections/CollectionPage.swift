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
    @State private var filtering = false
    @State private var settings = false
    @State private var namingView = false
    @State private var viewName = ""

    private var index: Int { collection.views.firstIndex { $0.id == collection.selectedView } ?? 0 }
    private var view: CollectionTableView { collection.views[index] }

    var body: some View {
        let entries = view.records(in: collection)
        let properties = collection.properties.filter { !view.hidden.contains($0.id) }
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
                               selection: $selection, calculations: $collection.views[index].calculations,
                               matching: entries) { entry in
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
        .padding(.horizontal, SideBar.margin)
        .onChange(of: view.id) { page = 0; selection.removeAll() }
        .onChange(of: view.filters) { page = 0; selection.removeAll() }
        .onChange(of: view.pageSize) { page = 0 }
        .alert("Save view as", isPresented: $namingView) {
            TextField("View name", text: $viewName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                var copy = view
                copy.id = UUID()
                copy.name = viewName.trimmingCharacters(in: .whitespacesAndNewlines)
                collection.views.append(copy)
                collection.selectedView = copy.id
            }.disabled(viewName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .sheet(isPresented: $adding) {
            CollectionEntryForm(properties: collection.properties, filters: view.filters) { entry in
                collection.entries.append(entry)
                adding = false
            } cancel: { adding = false }
        }
    }

    private var toolbar: some View {
        HStack(spacing: SideBar.markGap) {
            let first = collection.views[0]
            let second = index > 1 ? view : collection.views.dropFirst().first
            ForEach([first, second].compactMap { $0 }) { item in
                SidebarTabButton(title: item.name, selected: item.id == view.id, prefs: prefs, inTabStrip: true,
                                 action: { collection.selectedView = item.id }) { Symbol("tablecells", size: 12) }
            }
            Menu {
                ForEach(collection.views) { item in Button(item.name) { collection.selectedView = item.id } }
                Divider()
                Button("Save view as…") { viewName = ""; namingView = true }
            } label: { Symbol("chevron.down", size: 11) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Switch view")
            Spacer()
            if !selection.isEmpty { Text("\(selection.count) selected").font(.caption) }
            Button { filtering.toggle() } label: { Symbol("line.3.horizontal.decrease", size: 14) }
                .buttonStyle(.plain).accessibilityLabel("Add filter").keyTip("Add filter")
                .popover(isPresented: $filtering) {
                    CollectionFilterForm(properties: collection.properties) { filter in
                        collection.views[index].filters.append(filter)
                        filtering = false
                    }
                }
            Button { settings.toggle() } label: { Symbol("gearshape", size: 14) }
                .buttonStyle(.plain).accessibilityLabel("View settings").keyTip("View settings")
                .popover(isPresented: $settings) {
                    VStack(alignment: .leading) {
                        Text("Visible properties").font(.headline)
                        ForEach(collection.properties.dropFirst()) { property in
                            Toggle(property.title, isOn: Binding(get: { !view.hidden.contains(property.id) }, set: { show in
                                if show { collection.views[index].hidden.remove(property.id) }
                                else { collection.views[index].hidden.insert(property.id) }
                            }))
                        }
                        Picker("Sort by", selection: $collection.views[index].sortProperty) {
                            Text("Record order").tag(Optional<String>.none)
                            ForEach(collection.properties) { Text($0.title).tag(Optional($0.id)) }
                        }
                        if view.sortProperty != nil {
                            Toggle("Descending", isOn: Binding(get: { view.descending == true }, set: { collection.views[index].descending = $0 }))
                        }
                        Picker("Rows per page", selection: $collection.views[index].pageSize) {
                            ForEach([10, 25, 50, 100], id: \.self) { Text(String($0)).tag($0) }
                        }
                    }.padding()
                }
            Menu("New Record") { Button("Create record") { adding = true } }
                .fixedSize()
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
            Picker("Property", selection: $property) {
                ForEach(properties) { Text($0.title).tag($0.id) }
            }
            TextField("Value equals", text: $value)
            Button("Apply filter") { apply(.init(property: property, value: value)) }
                .disabled(value.isEmpty)
        }.padding().frame(minWidth: 220)
    }
}

private struct CollectionEntryForm: View {
    let properties: [CollectionProperty]
    let save: (CollectionEntry) -> Void
    let cancel: () -> Void
    @State private var values: [String: String]

    init(properties: [CollectionProperty], filters: [CollectionFilter],
         save: @escaping (CollectionEntry) -> Void, cancel: @escaping () -> Void) {
        self.properties = properties
        self.save = save
        self.cancel = cancel
        _values = State(initialValue: Dictionary(filters.map { ($0.property, $0.value) }, uniquingKeysWith: { first, _ in first }))
    }

    private var valid: Bool {
        guard properties.filter(\.required).allSatisfy({ !(values[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return false }
        return properties.filter(\.numeric).allSatisfy { field in
            let value = values[field.id] ?? ""
            return value.isEmpty || (try? Decimal(value, format: .number)) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Record").font(.headline)
            Form {
                ForEach(properties) { property in
                    TextField(property.title, text: Binding(get: { values[property.id] ?? "" }, set: { values[property.id] = $0 }))
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create") {
                    var stored = values
                    for field in properties where field.numeric {
                        if let number = try? Decimal(values[field.id] ?? "", format: .number) {
                            stored[field.id] = NSDecimalNumber(decimal: number).stringValue
                        }
                    }
                    save(.init(values: stored))
                }.keyboardShortcut(.defaultAction).disabled(!valid)
            }
        }.padding().frame(minWidth: 320)
    }
}
