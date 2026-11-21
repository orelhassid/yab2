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
                                             selected: browser.currentRecord == nil && (browser.collectionID ?? library.collections.first?.id) == collection.id,
                                             prefs: browser.prefs, action: {
                                browser.showCollection(collection.id)
                            }) { Symbol(collection.symbol, size: SideBar.mark) }
                            ForEach(browser.recordTabs.filter { $0.collection == collection.id }) { tab in
                                if let entry = collection.entries.first(where: { $0.id == tab.record }) {
                                    HStack(spacing: 0) {
                                        SidebarTabButton(title: entry.values["name"] ?? "", selected: browser.currentRecord == tab.id,
                                                         prefs: browser.prefs, action: { browser.showRecord(tab) }) {
                                            Symbol("doc", size: SideBar.mark)
                                        }
                                        RailButton("Close " + (entry.values["name"] ?? "record"), icon: "xmark", doorSize: .header) {
                                            browser.closeRecord(tab)
                                        }
                                    }.padding(.leading, Folders.indent)
                                }
                            }
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
            if let i = library.collections.firstIndex(where: { $0.id == browser.collectionID }) ?? library.collections.indices.first {
                let item = library.collections[i]
                if let tab = browser.recordTabs.first(where: { $0.collection == item.id && $0.id == browser.currentRecord }),
                   let record = item.entries.first(where: { $0.id == tab.record }) {
                    RecordPage(browser: browser, collection: $library.collections[i], tab: tab, record: record)
                } else {
                    TabWindowHeader(selection: Optional<UUID>.none) {
                        TabWindowSwitcher(title: item.name, prefs: browser.prefs, items: library.collections,
                                          label: { $0.name }, selected: { $0.id == item.id },
                                          choose: { browser.showCollection($0.id) },
                                          rowIcon: { Symbol($0.symbol, size: SideBar.mark) }) {
                            Symbol(item.symbol, size: SideBar.mark)
                        }
                    } tabs: { EmptyView() } actions: {
                        ColumnDoor(browser: browser, prefs: browser.prefs).environment(\.doorSize, .header)
                    }
                    .padding(.horizontal, SideBar.margin)
                    .frame(height: NavigationHeader.height(topInset: 0))
                    Divider()
                    CollectionPage(collection: $library.collections[i], prefs: browser.prefs, adding: $browser.creatingCollectionRecord,
                                   openRecord: { browser.showRecord($0) }, pagesByView: $browser.collectionPages)
                        .id(item.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $browser.creatingCollection) {
            CollectionSetup { collection in
                library.collections.append(collection)
                browser.showCollection(collection.id)
            } cancel: { browser.creatingCollection = false }
            .toned(SpaceSurface.tone(for: paint.color))
        }
        .toned(SpaceSurface.tone(for: paint.color))
        .background {
            CardGround(paint: paint, step: look.shift ? browser.lookStep : 0)
                .environment(browser)
                .background(Color(nsColor: paint.color))
        }
    }
}
