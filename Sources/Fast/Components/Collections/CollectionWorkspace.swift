import SwiftUI

extension Space {
    var isWorkspace: Bool { id == Self.development.id || id == Self.collections.id }

    static let collections = Space(id: UUID(uuidString: "00000000-0000-0000-0000-00000000C011")!,
                                   name: "Collections", icon: "square.stack.3d.up", ownSignIns: false)
}

struct CollectionSidebar: View {
    let browser: Browser
    @AppStorage("collections.sidebar.collapsed", store: Store.settings) private var collapsed = false
    private let library = CollectionLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SideBar.gap) {
            SpaceName(space: .collections, browser: browser)
            SidebarSectionDivider()
            Quiet(icon: "plus", title: "New Collection", prefs: browser.prefs, browser: browser) {
                browser.creatingCollection = true
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SideBar.gap) {
                    SidebarSection(collapsed: collapsed) {
                        SidebarSectionHeader(title: "Collections", paint: browser.developmentLook ?? SpacePaint(browser.prefs),
                                             collapsed: collapsed, toggle: { collapsed.toggle() }) {
                            Symbol("square.stack.3d.up", size: SideBar.mark)
                        }
                    } rows: {
                        ForEach(library.collections) { collection in
                            SidebarTabButton(title: collection.name,
                                             selected: !browser.creatingCollection && (browser.collectionID ?? library.collections.first?.id) == collection.id,
                                             prefs: browser.prefs, action: {
                                browser.collectionID = collection.id
                                browser.creatingCollection = false
                            }) { Symbol(collection.symbol, size: SideBar.mark) }
                        }
                    }
                }
            }
        }
    }
}

struct CollectionWorkspace: View {
    let browser: Browser
    @Bindable private var library = CollectionLibrary.shared

    var body: some View {
        @Bindable var browser = browser
        let look = browser.developmentLook ?? SpacePaint(browser.prefs)
        let paint = SpaceWash.painted(look)
        VStack(alignment: .leading, spacing: 0) {
            if browser.creatingCollection {
                CollectionSetup { collection in
                    library.collections.append(collection)
                    browser.collectionID = collection.id
                    browser.creatingCollection = false
                } cancel: { browser.creatingCollection = false }
            } else if let i = library.collections.firstIndex(where: { $0.id == browser.collectionID }) ?? library.collections.indices.first {
                let item = library.collections[i]
                TabWindowHeader(selection: Optional<UUID>.none) {
                    TabWindowSwitcher(title: item.name, prefs: browser.prefs, items: library.collections,
                                      label: { $0.name }, selected: { $0.id == item.id },
                                      choose: { browser.collectionID = $0.id },
                                      rowIcon: { Symbol($0.symbol, size: SideBar.mark) }) {
                        Symbol(item.symbol, size: SideBar.mark)
                    }
                } tabs: { EmptyView() } actions: {
                    ColumnDoor(browser: browser, prefs: browser.prefs).environment(\.doorSize, .header)
                }
                .padding(.horizontal, SideBar.margin)
                .frame(height: NavigationHeader.height(topInset: 0))
                Divider()
                CollectionPage(collection: $library.collections[i], prefs: browser.prefs, adding: $browser.creatingCollectionRecord)
                    .id(item.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toned(SpaceSurface.tone(for: paint.color))
        .background {
            CardGround(paint: paint, step: look.shift ? browser.lookStep : 0)
                .environment(browser)
                .background(Color(nsColor: paint.color))
        }
    }
}

private struct CollectionSetup: View {
    let create: (PageCollection) -> Void
    let cancel: () -> Void
    @State private var template = CollectionTemplate.blank
    @State private var name = ""
    @State private var symbol = CollectionTemplate.blank.symbol
    @State private var draft: PageCollection?
    @State private var newProperty = ""
    @State private var excluded: Set<String> = []

    var body: some View {
        Form {
            if let draft {
                Section("Properties") {
                    ForEach(draft.properties) { property in
                        HStack {
                            Toggle(property.title, isOn: Binding(get: { !excluded.contains(property.id) }, set: { on in
                                if on { excluded.remove(property.id) } else { excluded.insert(property.id) }
                            })).disabled(property.id == "name")
                            Spacer()
                            Toggle("Required", isOn: Binding(get: { property.required }, set: { required in
                                guard let i = self.draft?.properties.firstIndex(where: { $0.id == property.id }) else { return }
                                self.draft?.properties[i].required = required
                            })).disabled(property.id == "name" || excluded.contains(property.id))
                        }
                    }
                    TextField("New property", text: $newProperty)
                    Button("Add property") {
                        self.draft?.properties.append(.init(id: UUID().uuidString, title: newProperty))
                        newProperty = ""
                    }.disabled(newProperty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                HStack {
                    Button("Back") { self.draft = nil }
                    Button("Create Collection") {
                        var result = draft
                        result.properties.removeAll { excluded.contains($0.id) }
                        let keys = Set(result.properties.map(\.id))
                        for i in result.views.indices {
                            result.views[i].filters.removeAll { !keys.contains($0.property) }
                        }
                        create(result)
                    }
                }
            } else {
                Section("New Collection") {
                    Picker("Template", selection: $template) {
                        ForEach(CollectionTemplate.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: template) { old, value in
                        if name.isEmpty || name == old.rawValue { name = value == .blank ? "" : value.rawValue }
                        symbol = value.symbol
                    }
                    TextField("Collection name", text: $name)
                    Picker("Icon", selection: $symbol) {
                        ForEach(CollectionTemplate.allCases, id: \.self) { Image(systemName: $0.symbol).tag($0.symbol) }
                    }
                }
                HStack {
                    Button("Cancel", action: cancel)
                    Button(template == .blank ? "Create Collection" : "Customize") {
                        var item = template.make(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
                        item.symbol = symbol
                        if template == .blank { create(item) } else { excluded.removeAll(); draft = item }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .formStyle(.grouped)
    }
}
