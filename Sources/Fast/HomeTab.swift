import SwiftUI

private struct HomeDropArea: NSViewRepresentable {
    var tabKey: String?
    var reorder: ((String) -> Void)?
    var source: HomeShortcut?
    var begin: (() -> Void)?
    var end: (() -> Void)?
    var hover: ((CGFloat) -> Void)?
    let activate: () -> Void
    let drop: (HomeShortcut, CGFloat) -> Bool

    func makeNSView(context: Context) -> Handle {
        Handle()
    }

    func updateNSView(_ view: Handle, context: Context) {
        view.area = self
    }

    final class Handle: NSView {
        var area: HomeDropArea?
        private var pressed = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { HomeGridHand.install(in: window) }
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            if NSApp.currentEvent?.type == .rightMouseDown || NSApp.currentEvent?.modifierFlags.contains(.control) == true { return nil }
            return super.hitTest(point)
        }
        override func mouseDown(with event: NSEvent) { pressed = true }
        override func mouseUp(with event: NSEvent) {
            defer { pressed = false }
            if pressed && bounds.contains(convert(event.locationInWindow, from: nil)) { area?.activate() }
        }
        func takePress() { pressed = false }
    }
}

/// The column's press threshold, Escape handling and mouse-up suppression, shared
/// by every shortcut in a window. Drop targets stay still as their tiles move.
@MainActor
private final class HomeGridHand {
    private static let hands = NSMapTable<NSWindow, HomeGridHand>.weakToStrongObjects()
    private let grip = ColumnGrip()
    private weak var origin: HomeDropArea.Handle?
    private var source: HomeShortcut?
    private var finish: (() -> Void)?
    private var picture: Lift?
    private var grab = CGPoint.zero

    private final class Lift: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    static func install(in window: NSWindow) {
        guard let root = window.contentView else { return }
        if let hand = hands.object(forKey: window) { hand.grip.view = root; return }
        let hand = HomeGridHand()
        hands.setObject(hand, forKey: window)
        hand.grip.view = root
        hand.grip.attempt = { [weak hand] event in
            guard !event.modifierFlags.contains(.control), let target = hand?.target(event.locationInWindow),
                  target.area?.source != nil || target.area?.tabKey != nil else { return false }
            hand?.origin = target
            return true
        }
        hand.grip.changed = { [weak hand] grip in hand?.update(grip) }
        hand.grip.watch(true)
    }

    private func target(_ location: CGPoint) -> HomeDropArea.Handle? {
        guard let root = grip.view, let parent = root.superview else { return nil }
        return parent.hitTest(parent.convert(location, from: nil)) as? HomeDropArea.Handle
    }

    private func update(_ grip: ColumnGrip) {
        guard let event = grip.event, let root = grip.view else { clear(); return }
        let location = event.locationInWindow
        let point = root.convert(location, from: nil)
        switch grip.state {
        case .began:
            guard let origin, let area = origin.area else { return }
            origin.takePress()
            source = area.source
            finish = area.end
            let tile = CGRect(x: origin.bounds.midX - 28, y: origin.isFlipped ? 0 : origin.bounds.maxY - 56, width: 56, height: 56)
            let frame = origin.convert(area.tabKey == nil ? tile : origin.bounds, to: root)
            if let rep = root.bitmapImageRepForCachingDisplay(in: frame) {
                root.cacheDisplay(in: frame, to: rep)
                let image = NSImage(size: frame.size)
                image.addRepresentation(rep)
                let lifted = Lift(frame: frame)
                lifted.image = image
                lifted.imageScaling = .scaleAxesIndependently
                lifted.wantsLayer = true
                lifted.layer?.cornerRadius = Radius.surface
                lifted.layer?.masksToBounds = true
                root.addSubview(lifted, positioned: .above, relativeTo: nil)
                picture = lifted
                grab = CGPoint(x: grip.start.x - frame.minX, y: grip.start.y - frame.minY)
            }
            area.begin?()
            fallthrough
        case .changed:
            picture?.setFrameOrigin(CGPoint(x: point.x - grab.x, y: point.y - grab.y))
            if source != nil, let target = target(location) { target.area?.hover?(target.convert(location, from: nil).x) }
        case .ended:
            if let key = origin?.area?.tabKey { target(location)?.area?.reorder?(key) }
            else if let source, let target = target(location) {
                _ = target.area?.drop(source, target.convert(location, from: nil).x)
            }
            clear()
        case .cancelled: clear()
        default: break
        }
    }

    private func clear() {
        picture?.removeFromSuperview()
        picture = nil
        finish?()
        finish = nil
        origin = nil
        source = nil
    }
}

private func moveShortcut(_ source: HomeShortcut, data: inout Data, to group: UUID?,
                          before target: UUID? = nil, following prefix: [HomeShortcut] = []) -> Bool {
    guard source.id != target, var items = data.isEmpty ? [] : try? JSONDecoder().decode([HomeShortcut].self, from: data) else { return false }
    var item = source
    if let index = items.firstIndex(where: { $0.id == source.id }) { item = items.remove(at: index) }
    item.group = group
    let insertion = items.firstIndex { $0.id == target } ?? items.endIndex
    items.insert(contentsOf: prefix.filter { $0.address != item.address } + [item], at: insertion)
    guard let encoded = try? JSONEncoder().encode(items) else { return false }
    data = encoded
    return true
}

private struct HomeShortcut: Codable, Identifiable {
    var id = UUID()
    var name = ""
    var address = ""
    var group: UUID?
    var originalAddress: String? = nil

    var url: URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let url = Address.url(from: text),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil else { return nil }
        return url
    }
}

private struct HomeGroup: Identifiable, Codable {
    var id = UUID()
    var name = ""
}

private struct SpacePageLook<Content: View>: View {
    let browser: Browser
    @AppStorage private var stored: Data
    let content: (Binding<SpacePaint>, Bool, @escaping () -> Void) -> Content

    init(browser: Browser, @ViewBuilder content: @escaping (Binding<SpacePaint>, Bool, @escaping () -> Void) -> Content) {
        self.browser = browser
        self.content = content
        _stored = AppStorage(wrappedValue: Data(), "home.look." + browser.spaceID.uuidString, store: Store.settings)
    }

    var body: some View {
        let custom = try? JSONDecoder().decode(SpacePaint.self, from: stored)
        content(Binding(get: { custom ?? SpacePaint(browser.prefs) }, set: { value in
            if let data = try? JSONEncoder().encode(value) { stored = data }
        }), custom != nil, { stored = Data() })
    }
}

struct SpacePageSurface: ViewModifier {
    let browser: Browser
    var library = false
    var active = true
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance.spacePages", store: Store.settings) private var share = true

    func body(content: Content) -> some View {
        if active {
            SpacePageLook(browser: browser) { binding, custom, _ in
                let look = binding.wrappedValue
                let paint = (!library || share) && (custom || browser.prefs.backdrop != .site) ? SpaceWash.painted(look) : nil
                content.background {
                    ZStack {
                        if let paint {
                            Color(nsColor: paint.color)
                            CardGround(paint: paint, step: look.shift ? browser.lookStep : 0)
                                .environment(browser)
                        } else { Palette.stage }
                        if !library { HomePhoto(space: browser.spaceID) }
                    }.allowsHitTesting(false)
                }
                .environment(\.colorScheme, paint != nil ? LookMode(rawValue: look.mode)?.scheme ?? scheme : scheme)
            }
        } else {
            content
        }
    }
}

struct HomeNavigation: View {
    let browser: Browser
    @Binding var selected: String
    @AppStorage("home.tabOrder", store: Store.settings) private var order = ""
    @AppStorage("home.hiddenLibraries", store: Store.settings) private var hidden = ""
    @AppStorage("home.libraryTabStyle", store: Store.settings) private var display = "Text only"
    private let standard = ["tabs", "bookmarks", "history", "downloads", "extensions", "settings"]
    private var hiddenKeys: [String] { hidden.split(separator: ",").map(String.init) }
    private var keys: [String] {
        let custom = groups.map { $0.id.uuidString }
        let kept = order.split(separator: ",").map(String.init).filter(custom.contains)
        return ["overview"] + standard.filter { !hiddenKeys.contains($0) } + kept + custom.filter { !kept.contains($0) }
    }

    @ViewBuilder private var hiddenTabs: some View {
        if !hiddenKeys.isEmpty {
            Section("Hidden tabs") {
                ForEach(standard.filter(hiddenKeys.contains), id: \.self) { key in
                    Button("Show " + key.capitalized) { hidden = hiddenKeys.filter { $0 != key }.joined(separator: ",") }
                }
            }
        }
    }

    @ViewBuilder private func libraryOptions(_ key: String) -> some View {
        Menu("Display as") {
            Picker("Display as", selection: $display) {
                ForEach(["Icon only", "Text only", "Text and icon"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.inline)
        }
        if standard.contains(key) {
            Button("Hide " + key.capitalized) {
                hidden = (hiddenKeys + [key]).joined(separator: ",")
                if selected == key { selected = "overview" }
            }
        }
        hiddenTabs
    }

    private func reorder(_ source: String, onto target: String) {
        var tabs = keys.filter { UUID(uuidString: $0) != nil }
        guard let from = tabs.firstIndex(of: source), let to = tabs.firstIndex(of: target), from != to else { return }
        tabs.insert(tabs.remove(at: from), at: to)
        order = tabs.joined(separator: ",")
    }
    @AppStorage("home.groups", store: Store.settings) private var data = Data()
    @AppStorage("home.shortcuts", store: Store.settings) private var savedShortcuts = Data()
    @State private var adding: HomeGroup?
    @State private var renaming: UUID?
    @State private var customizing = false
    private var groups: [HomeGroup] { (try? JSONDecoder().decode([HomeGroup].self, from: data)) ?? [] }

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        if let group = groups.first(where: { $0.id.uuidString == key }) {
                            tab(group.name, key: key)
                                .contextMenu {
                                    Button("Rename Tab") { renaming = group.id }
                                    Button("Delete Tab", role: .destructive) { delete(group) }
                                    libraryOptions(key)
                                }
                                .popover(isPresented: Binding(get: { renaming == group.id }, set: { if !$0 { renaming = nil } }), arrowEdge: .bottom) {
                                    HomeGroupEditor(group: group, title: "Rename tab", save: save)
                                }
                        } else { tab(key.capitalized, key: key).contextMenu { libraryOptions(key) } }
                    }
                    Button { adding = HomeGroup() } label: { navigationIcon("plus") }
                        .accessibilityLabel("Add Home tab")
                        .popover(item: $adding, arrowEdge: .bottom) { group in
                            HomeGroupEditor(group: group, title: "New tab", save: save)
                        }
                }
            }.scrollIndicators(.hidden)
            Button { customizing = true } label: { navigationIcon("gearshape") }
                .accessibilityLabel("Customize Home")
                .pointerTip("Customize Home")
                .popover(isPresented: $customizing) {
                    SpacePageLook(browser: browser) { look, custom, reset in
                        VStack(spacing: 12) {
                            LookControls(look: .paint(look), bare: true, offersSite: false)
                            HomePhotoMenu(space: browser.spaceID)
                            if !hiddenKeys.isEmpty { Menu("Hidden tabs") { hiddenTabs } }
                            Button("Use Space Look", action: reset).disabled(!custom)
                        }.padding(16)
                    }
                }
        }
        .onChange(of: keys) { _, _ in
            if !keys.contains(selected) { selected = "overview" }
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private func navigationIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15)).frame(width: 32, height: 32).contentShape(Rectangle())
    }

    private func save(_ value: HomeGroup) {
        var all = groups
        if let i = all.firstIndex(where: { $0.id == value.id }) { all[i] = value }
        else { all.append(value) }
        if let encoded = try? JSONEncoder().encode(all) { data = encoded; selected = value.id.uuidString }
    }

    private func delete(_ group: HomeGroup) {
        guard let remaining = try? JSONEncoder().encode(groups.filter { $0.id != group.id }) else { return }
        if !savedShortcuts.isEmpty {
            guard var links = try? JSONDecoder().decode([HomeShortcut].self, from: savedShortcuts) else { return }
            for index in links.indices where links[index].group == group.id { links[index].group = nil }
            guard let moved = try? JSONEncoder().encode(links) else { return }
            savedShortcuts = moved
        }
        data = remaining
        if selected == group.id.uuidString { selected = "overview" }
    }

    private func tab(_ title: String, key: String) -> some View {
        Button { selected = key } label: {
            HStack(spacing: 6) {
                if let page = LibraryPage(rawValue: key), display != "Text only" { Image(systemName: page.icon) }
                if !standard.contains(key) || display != "Icon only" { Text(title) }
            }.font(CardFrame.title).padding(.horizontal, 12).padding(.vertical, 8)
                .background(selected == key ? Palette.ink.opacity(0.14) : .clear, in: Capsule())
        }.accessibilityLabel(title + " Home tab").accessibilityAddTraits(selected == key ? .isSelected : [])
        .overlay {
            HomeDropArea(tabKey: UUID(uuidString: key) == nil ? nil : key, reorder: { reorder($0, onto: key) }, activate: { selected = key }) { source, _ in
                guard key == "overview" || UUID(uuidString: key) != nil else { return false }
                return moveShortcut(source, data: &savedShortcuts, to: UUID(uuidString: key))
            }
        }
    }
}

private struct HomeGroupEditor: View {
    @State var group: HomeGroup
    let title: String
    let save: (HomeGroup) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            TextField("Tab name", text: $group.name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    group.name = group.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    save(group)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(group.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(16).frame(width: 256)
    }
}

private struct HomeTile<Mark: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                mark().frame(width: 32, height: 32)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.surface))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.surface)
                            .strokeBorder(Palette.ink.opacity(hovered ? 0.30 : 0.12))
                    }
                Text(title).font(CardFrame.detail).lineLimit(1).truncationMode(.middle)
            }.frame(width: 96).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }.accessibilityLabel(title)
    }
}

struct HomeTab: View {
    let browser: Browser
    @ObservedObject var history: History
    @ObservedObject var downloads: Loot
    @ObservedObject var bookmarks: Bookmarks
    @Binding var selection: String
    private var group: UUID? { UUID(uuidString: selection) }
    @AppStorage("home.shortcuts", store: Store.settings) private var saved = Data()
    @State private var adding: HomeShortcut?
    @State private var editKey: String?
    @State private var held: String?
    @State private var dragOrder: [String] = []
    @State private var tilePositions: [String: CGPoint] = [:]
    @State private var folderPath: [UUID] = []

    private var shortcuts: [HomeShortcut] {
        (try? JSONDecoder().decode([HomeShortcut].self, from: saved)) ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 56) { // design: extra separation between distinct Home collections
                if group == nil && !browser.turnOrder.isEmpty {
                    section("Spaces") {
                        HomeSectionStrip(title: "Spaces", hovered: hoveredSection == "Spaces") {
                            ForEach(browser.turnOrder) { space in
                                HomeTile(title: space.name, action: { browser.switchSpace(to: space.id) }) {
                                    SpaceMark(icon: space.icon, size: 28)
                                }.contextMenu {
                                    Button("Switch Space") { browser.switchSpace(to: space.id) }
                                }
                            }
                        }
                    }
                }
                section("Shortcuts") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 16, alignment: .leading)], alignment: .leading, spacing: 24) {
                        let sites = gridSites
                        ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                            gridTile(site, index: index, sites: sites)
                        }
                        HomeTile(title: "Add shortcut", action: { adding = HomeShortcut(group: group) }) {
                            Image(systemName: "plus")
                        }.contextMenu {
                            Button("Add Shortcut") { adding = HomeShortcut(group: group) }
                        }.popover(item: $adding, arrowEdge: .bottom) { item in
                            HomeShortcutPicker(browser: browser, history: history, bookmarks: bookmarks, group: item.group, excluded: Set((shortcuts + automaticSites).compactMap { $0.url.map(HomeShortcutPicker.key) }), save: saveShortcut)
                        }
                        .overlay {
                            HomeDropArea(hover: { _ in
                                if let held { preview(held, at: sites.count, sites: sites) }
                            }, activate: { adding = HomeShortcut(group: group) }) { source, _ in
                                moveShortcut(source, data: &saved, to: group, following: group == nil ? automaticSites : [])
                            }
                        }
                    }
                    .coordinateSpace(name: "home-shortcuts")
                }
                if group == nil {
                    if !history.recent().isEmpty {
                        section("Recent history", all: "All history", page: .history) {
                            HomeSectionStrip(title: "Recent history", hovered: hoveredSection == "Recent history") {
                                ForEach(history.recent()) { row in link(row.url, row.title.isEmpty ? row.url.absoluteString : row.title) }
                            }
                        }
                    }
                    if !downloads.kept.isEmpty {
                        section("Downloads", all: "All downloads", page: .downloads) {
                            HomeSectionStrip(title: "Downloads", hovered: hoveredSection == "Downloads") {
                                ForEach(downloads.kept.prefix(20)) { file in
                                    HomeTile(title: file.name, action: { downloads.reveal(file) }) {
                                        FilePicture(path: file.path, side: 32)
                                    }.pointerTip("Show in Finder").contextMenu {
                                        Button("Show in Finder") { downloads.reveal(file) }
                                    }
                                }
                            }
                        }
                    }
                    let roots = bookmarks.barRoots(in: browser.spaceID, profile: browser.space.signedInAs ?? browser.space.origin)
                    if !roots.isEmpty {
                        section("Bookmarks", all: "All bookmarks", page: .bookmarks) {
                            let path = resolvedFolders(in: roots)
                            let entries = path.last.map { $0.children ?? [] } ?? roots
                            if let folder = path.last {
                                Button { folderPath = path.dropLast().map(\.id) } label: {
                                    Label(folder.title, systemImage: "chevron.left")
                                }.buttonStyle(.plain).accessibilityLabel("Back from " + folder.title)
                            }
                            if entries.isEmpty {
                                Text(path.isEmpty ? "No bookmarks" : "Empty folder").foregroundStyle(.secondary)
                            } else {
                                HomeSectionStrip(title: "Bookmarks", hovered: hoveredSection == "Bookmarks") {
                                    ForEach(entries) { node in
                                        if node.isFolder {
                                            HomeTile(title: node.title, action: { folderPath = path.map(\.id) + [node.id] }) {
                                                BookmarkBar.FolderMark(size: 28)
                                            }.contextMenu {
                                                Button("Open Folder") { folderPath = path.map(\.id) + [node.id] }
                                            }
                                        } else if let url = node.url.flatMap(URL.init(string:)) { link(url, node.title) }
                                    }
                                }.id(path.last?.id)
                            }
                        }
                    }
                }
            }.padding(.vertical, LibraryPageLayout.sectionGap)
        }
    }

    private struct GridSite: Identifiable {
        let shortcut: HomeShortcut
        let saved: Bool
        var id: String { saved ? shortcut.id.uuidString : shortcut.address }
    }

    private var gridSites: [GridSite] {
        let kept = shortcuts.filter { $0.group == group }.map { GridSite(shortcut: $0, saved: true) }
        return group == nil ? kept + automaticSites.map { GridSite(shortcut: $0, saved: false) } : kept
    }

    private func preview(_ source: String, at slot: Int, sites: [GridSite]) {
        var keys = sites.map(\.id)
        guard let from = keys.firstIndex(of: source) else { return }
        keys.remove(at: from)
        keys.insert(source, at: slot > from ? slot - 1 : slot)
        if keys != dragOrder { withAnimation(Motion.settle) { dragOrder = keys } }
    }

    private func displacement(_ key: String, sites: [GridSite]) -> CGSize {
        guard let index = dragOrder.firstIndex(of: key), sites.indices.contains(index),
              let from = tilePositions[key], let to = tilePositions[sites[index].id] else { return .zero }
        return CGSize(width: to.x - from.x, height: to.y - from.y)
    }

    private func gridTile(_ site: GridSite, index: Int, sites: [GridSite]) -> some View {
        let shortcut = site.shortcut
        let open = {
            if !site.saved, let tab = pins.first(where: { ($0.address ?? $0.pending)?.absoluteString == shortcut.address }) {
                browser.close()
                browser.select(tab)
            } else if let url = shortcut.url { browser.send(url, .here) }
        }
        let shift = displacement(site.id, sites: sites)
        return ZStack {
            if held == site.id {
                ColumnGap(square: true).frame(width: 56, height: 56)
                    .offset(y: -12).offset(shift)
            }
            HomeTile(title: shortcut.name, action: open) {
                if let url = shortcut.url { PlacePageMark(url: url, side: 28) }
            }
            .opacity(held == site.id ? 0 : 1).offset(shift)
        }
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named("home-shortcuts")).origin } action: {
            tilePositions[site.id] = $0
        }
        .overlay {
            HomeDropArea(source: shortcut, begin: {
                held = site.id
            }, end: {
                withAnimation(Motion.settle) { held = nil; dragOrder = [] }
            }, hover: { x in
                if let held { preview(held, at: index + (x < 48 ? 0 : 1), sites: sites) }
            }, activate: open) { source, x in
                let slot = index + (x < 48 ? 0 : 1)
                let target = sites.dropFirst(slot).first
                let prefix = sites.prefix(slot).filter { !$0.saved }.map(\.shortcut)
                return moveShortcut(source, data: &saved, to: group, before: target.flatMap { $0.saved ? $0.shortcut.id : nil }, following: prefix)
            }
        }
        .contextMenu {
            Button("Open", action: open)
            if let url = shortcut.url { Button("Copy Link") { browser.put(url.absoluteString) } }
            Button("Edit Shortcut") { editKey = site.id }
            if site.saved {
                Button("Move Earlier") { move(shortcut, by: -1) }
                Button("Move Later") { move(shortcut, by: 1) }
                Button("Remove Shortcut") { save(shortcuts.filter { $0.id != shortcut.id }) }
            }
        }
        .popover(isPresented: Binding(get: { editKey == site.id }, set: { if !$0 { editKey = nil } }), arrowEdge: .bottom) {
            HomeShortcutEditor(shortcut: shortcut) { value in
                var edited = value
                if !site.saved { edited.originalAddress = shortcut.address }
                saveShortcut(edited)
            }
        }
    }

    private func resolvedFolders(in roots: [Bookmark]) -> [Bookmark] {
        var children = roots
        var folders: [Bookmark] = []
        for id in folderPath {
            guard let folder = children.first(where: { $0.id == id && $0.isFolder }) else { break }
            folders.append(folder)
            children = folder.children ?? []
        }
        return folders
    }

    private func saveShortcut(_ value: HomeShortcut) {
        var items = shortcuts
        if let index = items.firstIndex(where: { $0.id == value.id }) {
            items[index].name = value.name
            items[index].address = value.address
        } else { items.append(value) }
        save(items)
    }

    private var pins: [Tab] {
        browser.tabs.filter { $0.pin != nil && !$0.shy }
    }

    private var automaticSites: [HomeShortcut] {
        var addresses = Set(shortcuts.compactMap { $0.url?.absoluteString } + shortcuts.compactMap(\.originalAddress))
        var seen = Set(addresses.compactMap { URL(string: $0)?.host()?.lowercased() })
        var sites: [HomeShortcut] = []
        for pin in pins {
            guard let url = pin.address ?? pin.pending, let host = url.host()?.lowercased(),
                  addresses.insert(url.absoluteString).inserted else { continue }
            seen.insert(host)
            sites.append(HomeShortcut(id: pin.id, name: pin.label, address: url.absoluteString))
        }
        for row in history.frequent(8) + history.recent() {
            guard let host = row.url.host(), seen.insert(host.lowercased()).inserted else { continue }
            sites.append(HomeShortcut(name: host, address: row.url.absoluteString))
        }
        return sites
    }

    private func move(_ shortcut: HomeShortcut, by delta: Int) {
        var all = shortcuts
        let indices = all.indices.filter { all[$0].group == shortcut.group }
        guard let index = indices.firstIndex(where: { all[$0].id == shortcut.id }), indices.indices.contains(index + delta) else { return }
        all.swapAt(indices[index], indices[index + delta])
        save(all)
    }

    @State private var hoveredSection: String?

    private func section<Content: View>(_ title: String, all: String? = nil, page: LibraryPage? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(title).font(.headline).foregroundStyle(.secondary)
                Spacer()
                if let all, let page { Button(all) { selection = page.rawValue }.buttonStyle(.plain).font(CardFrame.detail) }
            }
            content()
        }.frame(minHeight: 120, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredSection = title }
            else if hoveredSection == title { hoveredSection = nil }
        }
    }

    private func link(_ url: URL, _ name: String) -> some View {
        HomeTile(title: name, action: { browser.send(url, .here) }) { PlacePageMark(url: url, side: 28) }
            .pointerTip(url.absoluteString)
            .contextMenu {
                Button("Open") { browser.send(url, .here) }
                Button("Copy Link") { browser.put(url.absoluteString) }
            }
    }

    private func save(_ items: [HomeShortcut]) {
        if let data = try? JSONEncoder().encode(items) { saved = data }
    }
}

/// Trackpads scroll the strip natively. A notched wheel pages through bookmarks
/// while the pointer is over them, then passes through at either end.
private struct BookmarkWheel: NSViewRepresentable {
    let scroll: (CGFloat) -> Bool

    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) { view.scroll = scroll }

    final class Marker: NSView {
        var scroll: ((CGFloat) -> Bool)?
        private var monitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                self?.enclosingScrollView?.hasHorizontalScroller = false
            }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, event.window === self.window, !event.hasPreciseScrollingDeltas,
                          event.scrollingDeltaX == 0, self.visibleRect.contains(self.convert(event.locationInWindow, from: nil)),
                          self.scroll?(event.scrollingDeltaY) == true else { return event }
                    return nil
                }
            }
        }
    }
}

private struct HomeSectionStrip<Content: View>: View {
    let title: String
    let hovered: Bool
    @ViewBuilder let content: () -> Content
    @State private var position = ScrollPosition(edge: .leading)
    @State private var visible = CGRect.zero
    @State private var width: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) { content() }
                .background {
                    BookmarkWheel { lines in
                        let next = max(0, min(width - visible.width, visible.minX - lines * 32))
                        guard abs(next - visible.minX) > 0.5 else { return false }
                        position.scrollTo(x: next)
                        return true
                    }
                }
        }
        .scrollIndicators(.never)
        .scrollPosition($position)
                .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, value in
                    visible = value.visibleRect
                    width = value.contentSize.width
                }
                .overlay(alignment: .leading) {
                    if hovered && visible.minX > 1 { arrow("chevron.left", forward: false) }
                }
                .overlay(alignment: .trailing) {
                    if hovered && visible.width > 0 && visible.maxX < width - 1 {
                        arrow("chevron.right", forward: true)
                    }
                }
    }

    private func arrow(_ icon: String, forward: Bool) -> some View {
        Button {
            let offset = visible.minX + (forward ? visible.width : -visible.width)
            withAnimation { position.scrollTo(x: max(0, min(width - visible.width, offset))) }
        } label: { Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 34, height: 34)
                .background(.regularMaterial, in: Circle()).contentShape(Circle()) }
        .buttonStyle(.plain)
        .accessibilityLabel((forward ? "Next " : "Previous ") + title.lowercased())
    }
}

private struct HomeShortcutEditor: View {
    @State var shortcut: HomeShortcut
    let save: (HomeShortcut) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Shortcut").font(.headline)
            TextField("Name", text: $shortcut.name)
            TextField("Website address", text: $shortcut.address)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    guard let url = shortcut.url else { return }
                    shortcut.address = url.absoluteString
                    shortcut.name = shortcut.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if shortcut.name.isEmpty { shortcut.name = url.host() ?? url.absoluteString }
                    save(shortcut)
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(shortcut.url == nil)
            }
        }.padding(20).frame(width: 340)
    }
}

private struct HomeShortcutPicker: View {
    let browser: Browser
    let history: History
    let bookmarks: Bookmarks
    let group: UUID?
    let excluded: Set<String>
    let save: (HomeShortcut) -> Void
    @State private var query = ""
    @State private var sections: [Section] = []
    @Environment(\.dismiss) private var dismiss

    private struct Site: Identifiable {
        let url: URL
        let title: String
        let searchText: String
        var id: URL { url }
    }
    private struct Section: Identifiable {
        let name: String
        let sites: [Site]
        var id: String { name }
    }

    static func key(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return url.absoluteString }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) { parts.port = nil }
        if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        return parts.string ?? url.absoluteString
    }

    private func collect() -> [Section] {
        let visits = history.visits(since: .distantPast)
        let metadata = Dictionary(visits.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        func section(_ name: String, _ rows: [(URL?, String)]) -> Section {
            let sites = rows.compactMap { address, label -> Site? in
                guard let url = address, Bookmark.keepable(url), seen.insert(Self.key(url)).inserted else { return nil }
                let visit = metadata[url.absoluteString]
                let title = label.isEmpty ? visit?.metaTitle ?? url.host() ?? url.absoluteString : label
                let terms = [title, visit?.title, visit?.metaTitle, visit?.metaDescription, url.absoluteString]
                return Site(url: url, title: title, searchText: terms.compactMap { $0 }.joined(separator: " "))
            }
            return Section(name: name, sites: sites)
        }
        var links: [(URL?, String)] = []
        func collectBookmarks(_ nodes: [Bookmark]) {
            for node in nodes {
                if let children = node.children { collectBookmarks(children) }
                else if let address = node.url { links.append((URL(string: address), node.title)) }
            }
        }
        collectBookmarks(bookmarks.barRoots(in: browser.spaceID, profile: browser.space.signedInAs ?? browser.space.origin))
        let tabs = (browser.tabs + browser.parkedTabs).filter { !$0.shy && browser.history(for: $0) === history }
        return [section("Open tabs", tabs.map { ($0.address ?? $0.pending, $0.label) }),
                section("Bookmarks", links)]
    }

    var body: some View {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        let address = HomeShortcut(address: query).url
        let matches = sections.map { section in
            Section(name: section.name, sites: section.sites.filter { site in
                !excluded.contains(Self.key(site.url)) && words.allSatisfy { site.searchText.localizedStandardContains($0) }
            })
        }.filter { !$0.sites.isEmpty }
        VStack(alignment: .leading, spacing: 12) {
            Text("Add shortcut").font(.headline)
            SidebarAddressPlate {
                ShortcutAddressInput(text: $query) {
                    if let address {
                        choose(address, title: sections.flatMap(\.sites).first { Self.key($0.url) == Self.key(address) }?.title)
                    } else if let site = matches.first?.sites.first { choose(site.url, title: site.title) }
                }.padding(.trailing, 8)
            }
            if let address, excluded.contains(Self.key(address)) {
                Text("Already a shortcut").font(CardFrame.detail).foregroundStyle(.secondary)
            } else if let address, !matches.contains(where: { $0.sites.contains { Self.key($0.url) == Self.key(address) } }) {
                Button { choose(address, title: matches.flatMap(\.sites).first { $0.url == address }?.title) } label: {
                    Label("Add " + address.absoluteString, systemImage: "plus").lineLimit(1)
                }.buttonStyle(.plain)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(matches) { section in
                        Text(section.name).font(.headline).foregroundStyle(.secondary).padding(.top, 8)
                        ForEach(section.sites) { site in
                            Button { choose(site.url, title: site.title) } label: {
                                HStack(spacing: 8) {
                                    PlacePageMark(url: site.url, side: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(site.title).font(CardFrame.detail)
                                        Text(site.url.absoluteString).font(.caption).foregroundStyle(.secondary)
                                    }.lineLimit(1)
                                    Spacer()
                                }.padding(.vertical, 4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if matches.isEmpty && address == nil {
                        Text(query.isEmpty ? "Paste a website address to add a shortcut." : "No matching sites")
                            .foregroundStyle(.secondary)
                    }
                }
            }.frame(height: 280)
        }.padding(16).frame(width: 360).onAppear { sections = collect() }
    }

    private func choose(_ url: URL, title: String?) {
        guard !excluded.contains(Self.key(url)) else { return }
        save(HomeShortcut(name: title ?? url.host() ?? url.absoluteString, address: url.absoluteString, group: group))
        dismiss()
    }
}


private struct ShortcutAddressInput: NSViewRepresentable {
    @Binding var text: String
    let submit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> AddressTextField {
        let field = AddressTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12.5)
        field.contentType = .URL
        field.isAutomaticTextCompletionEnabled = false
        field.cell?.usesSingleLineMode = true
        field.placeholderString = "Search sites or paste a URL"
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: AddressTextField, context: Context) {
        context.coordinator.input = self
        if field.stringValue != text { field.stringValue = text }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var input: ShortcutAddressInput
        init(_ input: ShortcutAddressInput) { self.input = input }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { input.text = field.stringValue }
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            guard command == #selector(NSResponder.insertNewline(_:)) else { return false }
            input.submit()
            return true
        }
    }
}
