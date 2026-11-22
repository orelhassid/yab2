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
                                             selected: (browser.collectionID ?? library.collections.first?.id) == collection.id,
                                             prefs: browser.prefs, action: {
                                browser.showCollection(collection.id)
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
            if let i = library.collections.firstIndex(where: { $0.id == browser.collectionID }) ?? library.collections.indices.first {
                let item = library.collections[i]
                if let tab = browser.recordTabs.first(where: { $0.collection == item.id && $0.id == browser.currentRecord }),
                   let record = item.entries.first(where: { $0.id == tab.record }) {
                    RecordPage(browser: browser, collection: $library.collections[i], tab: tab, record: record)
                } else {
                    CollectionTemplateHeader(browser: browser) {
                        SpaceHeadingLabel(title: item.name) { Symbol(item.symbol, size: SideBar.mark) }
                    } actions: { EmptyView() }
                    CollectionPage(collection: $library.collections[i], adding: $browser.creatingCollectionRecord,
                                   openRecord: { browser.showRecord($0) }, pagesByView: $browser.collectionPages)
                        .id(item.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $browser.creatingCollection) {
            CollectionSetup(ground: Color(nsColor: paint.color)) { collection in
                library.collections.append(collection)
                browser.showCollection(collection.id)
            } cancel: { browser.creatingCollection = false }
            .toned(SpaceSurface.tone(for: paint.color))
        }
        .toned(SpaceSurface.tone(for: paint.color))
        .background(Color(nsColor: SpaceSurface.tone(for: paint.color).page))
    }
}

struct CollectionTemplateHeader<Heading: View, Actions: View>: View {
    let browser: Browser
    @ViewBuilder let heading: () -> Heading
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        TabWindowHeader(selection: Optional<UUID>.none) {
            heading().padding(.horizontal, SideBar.inner)
        } tabs: { EmptyView() } actions: {
            actions()
            ColumnDoor(browser: browser, prefs: browser.prefs).environment(\.doorSize, .header)
        }
        .padding(.horizontal, SideBar.margin)
        .frame(height: NavigationHeader.height(topInset: 0))
        Divider()
    }
}
