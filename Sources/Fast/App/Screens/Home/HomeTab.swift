import QuartzCore
import SwiftUI

private struct HomeDropArea: NSViewRepresentable {
    var tabKey: String?
    var reorder: ((String) -> Void)?
    var source: HomeShortcut?
    var spaceID: UUID?
    var slot: HomeReorderSlot?
    var moveSpace: ((UUID, CGFloat) -> Void)?
    var begin: (() -> Void)?
    var end: (() -> Void)?
    var hover: ((CGFloat) -> Void)?
    let activate: () -> Void
    var drop: ((HomeShortcut, CGFloat) -> Bool)? = nil
    var pointerChanged: ((Bool) -> Void)? = nil

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
            if let window { HomeGridHand.install(self, in: window) }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero,
                                          options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
                                          owner: self))
        }
        override func mouseEntered(with event: NSEvent) { area?.pointerChanged?(true) }
        override func mouseMoved(with event: NSEvent) { area?.pointerChanged?(true) }
        override func mouseExited(with event: NSEvent) { area?.pointerChanged?(false) }
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

private struct HomeDropHoverKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var homeDropHovered: Bool {
        get { self[HomeDropHoverKey.self] }
        set { self[HomeDropHoverKey.self] = newValue }
    }
}

/// The AppKit drop target is above the button and receives its pointer events.
private struct HomeDropTarget: ViewModifier {
    var area: HomeDropArea
    @State private var hovered = false

    func body(content: Content) -> some View {
        var target = area
        target.pointerChanged = { if hovered != $0 { hovered = $0 } }
        return content
            .environment(\.homeDropHovered, hovered)
            .overlay { target }
    }
}

private struct HomeReorderSlot {
    enum Collection { case spaces, shortcuts }

    let collection: Collection
    let index: Int
    var end = false

    func insertion(at x: CGFloat) -> Int {
        index + (!end && x >= HomeColumns.width / 2 ? 1 : 0)
    }

    static func destination(from index: Int, at insertion: Int) -> Int {
        insertion > index ? insertion - 1 : insertion
    }
}

/// Home uses the column's press threshold and springs. The native handles
/// stay in their original slots while the SwiftUI cards make room.
@MainActor
private final class HomeGridHand {
    private static let hands = NSMapTable<NSWindow, HomeGridHand>.weakToStrongObjects()
    private let grip = ColumnGrip()
    private weak var origin: HomeDropArea.Handle?
    private let handles = NSHashTable<HomeDropArea.Handle>.weakObjects()
    private var targets: [Target] = []
    private var finish: (() -> Void)?
    private var landing: (() -> Void)?
    private var picture: Lift?
    private var grab = CGPoint.zero

    private final class Lift: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    private struct Target {
        let area: HomeDropArea
        let slot: HomeReorderSlot
        let frame: CGRect
    }

    static func install(_ handle: HomeDropArea.Handle, in window: NSWindow) {
        guard let root = window.contentView else { return }
        if let hand = hands.object(forKey: window) {
            hand.grip.view = root
            hand.handles.add(handle)
            return
        }
        let hand = HomeGridHand()
        hand.handles.add(handle)
        hands.setObject(hand, forKey: window)
        hand.grip.view = root
        hand.grip.attempt = { [weak hand] event in hand?.press(event) ?? false }
        hand.grip.changed = { [weak hand] grip in hand?.update(grip) }
        hand.grip.watch(true)
    }

    static func cancel(in window: NSWindow?) -> Bool {
        guard let window, let hand = hands.object(forKey: window),
              hand.grip.state == .began || hand.grip.state == .changed else { return false }
        hand.grip.state = .cancelled
        return true
    }

    private func press(_ event: NSEvent) -> Bool {
        if landing != nil {
            // Snap the last drop into place before accepting another press.
            finishLanding()
            return false
        }
        guard !event.modifierFlags.contains(.control), let target = target(event.locationInWindow),
              let area = target.area, area.source != nil || area.tabKey != nil || area.spaceID != nil else { return false }
        origin = target
        return true
    }

    private func target(_ location: CGPoint) -> HomeDropArea.Handle? {
        guard let root = grip.view, let parent = root.superview else { return nil }
        return parent.hitTest(parent.convert(location, from: nil)) as? HomeDropArea.Handle
    }

    private func tiles(in collection: HomeReorderSlot.Collection) -> [Target] {
        handles.allObjects.compactMap { handle in
            guard handle.window === grip.view?.window, !handle.isHiddenOrHasHiddenAncestor,
                  let area = handle.area, let slot = area.slot, slot.collection == collection,
                  !handle.visibleRect.isEmpty else { return nil }
            return Target(area: area, slot: slot, frame: handle.convert(handle.bounds, to: nil))
        }
    }

    private func tile(at point: CGPoint) -> Target? {
        targets.first { $0.frame.contains(point) } ?? targets.first {
            let rowGap: CGFloat = $0.slot.collection == .shortcuts ? HomeColumns.rowGap / 2 : 0
            return $0.frame.insetBy(dx: -HomeColumns.gap / 2, dy: -rowGap).contains(point)
        }
    }

    private func update(_ grip: ColumnGrip) {
        guard let origin, let area = origin.area else { clear(); return }
        if grip.state == .cancelled { returnToOrigin(origin, area: area); return }
        guard let event = grip.event, let root = grip.view else { clear(); return }
        let location = event.locationInWindow
        let point = root.convert(location, from: nil)
        switch grip.state {
        case .began:
            origin.takePress()
            finish = area.end
            if let slot = area.slot { targets = tiles(in: slot.collection) }
            let frame = origin.convert(origin.bounds, to: root)
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
            area.pointerChanged?(false)
            area.begin?()
            fallthrough
        case .changed:
            picture?.setFrameOrigin(CGPoint(x: point.x - grab.x, y: point.y - grab.y))
            if area.slot != nil {
                if let target = tile(at: location) {
                    target.area.hover?(location.x - target.frame.minX)
                } else {
                    area.hover?(0)
                }
            }
        case .ended:
            if let slot = area.slot {
                if let target = tile(at: location) {
                    let x = location.x - target.frame.minX
                    let index = HomeReorderSlot.destination(from: slot.index, at: target.slot.insertion(at: x))
                    target.area.hover?(x)
                    settle(at: targets.first { $0.slot.index == index }?.frame) {
                        guard index != slot.index else { return }
                        if let id = area.spaceID { target.area.moveSpace?(id, x) }
                        else if let source = area.source { _ = target.area.drop?(source, x) }
                    }
                } else if let source = area.source, let target = target(location), let drop = target.area?.drop,
                          drop(source, target.convert(location, from: nil).x) {
                    clear()
                } else {
                    returnToOrigin(origin, area: area)
                }
            } else {
                if let key = area.tabKey { target(location)?.area?.reorder?(key) }
                clear()
            }
        default: break
        }
    }

    private func returnToOrigin(_ origin: HomeDropArea.Handle, area: HomeDropArea) {
        area.hover?(0)
        settle(at: origin.visibleRect.isEmpty ? nil : origin.convert(origin.bounds, to: nil)) {}
    }

    private func settle(at frame: CGRect?, change: @escaping () -> Void) {
        landing = change
        guard let frame, let root = grip.view, let picture, let layer = picture.layer,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return finishLanding() }
        let target = root.convert(frame, from: nil).origin
        let start = picture.frame.origin
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self, weak picture] in
            MainActor.assumeIsolated {
                guard let self, let picture, self.picture === picture else { return }
                self.finishLanding()
            }
        }
        picture.setFrameOrigin(target)
        ColumnMotion.slide(layer, by: target.y - start.y, dx: target.x - start.x, ColumnMotion.settle)
        CATransaction.commit()
    }

    private func finishLanding() {
        let commit = landing
        landing = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            commit?()
            clear()
        }
    }

    private func clear() {
        picture?.removeFromSuperview()
        picture = nil
        finish?()
        finish = nil
        targets = []
        origin = nil
    }
}

/// Positions stay measured in the unshifted row so the pointer can cross
/// between tiles without changing the insertion slot under it.
private struct HomeTileDrag<Key: Hashable> {
    var held: Key?
    var order: [Key] = []
    var positions: [Key: CGPoint] = [:]

    static func destination(for source: Key, at slot: Int, in keys: [Key]) -> Int? {
        guard let from = keys.firstIndex(of: source) else { return nil }
        return HomeReorderSlot.destination(from: from, at: slot)
    }

    mutating func preview(at slot: Int, in keys: [Key]) {
        guard let held, let index = Self.destination(for: held, at: slot, in: keys) else { return }
        var next = keys.filter { $0 != held }
        next.insert(held, at: index)
        if next != order {
            let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : Motion.settle
            withAnimation(motion) { order = next }
        }
    }

    func displacement(of key: Key, in keys: [Key]) -> CGSize {
        guard let index = order.firstIndex(of: key), keys.indices.contains(index),
              let from = positions[key], let to = positions[keys[index]] else { return .zero }
        return CGSize(width: to.x - from.x, height: to.y - from.y)
    }

    mutating func finish() {
        held = nil
        order = []
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
        _stored = AppStorage(wrappedValue: Data(), WorkspaceTheme.lookKey(browser.spaceID), store: Store.settings)
    }

    var body: some View {
        let custom = try? JSONDecoder().decode(SpacePaint.self, from: stored)
        content(Binding(get: {
            // The color field writes the main color and linked colors in one event.
            WorkspaceTheme.savedLook(for: browser.spaceID) ?? SpacePaint(browser.prefs)
        }, set: { value in
            if let data = try? JSONEncoder().encode(value) { stored = data }
        }), custom != nil, { stored = Data() })
    }
}

struct SpacePageSurface: ViewModifier {
    let browser: Browser
    var library = false
    var themedControls = false
    var active = true
    var frame = EdgeInsets()
    var corner: CGFloat = 0
    @Environment(\.workspaceTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @AppStorage("appearance.spacePages", store: Store.settings) private var share = true

    func body(content: Content) -> some View {
        if active {
            let sharesBackdrop = !library || share
            let tone = sharesBackdrop ? theme.tone ?? SpaceSurface.tone(in: browser) : nil
            let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
            content.background {
                ZStack {
                    sharesBackdrop ? Color.clear : Palette.stage
                    if !library && theme.hasPhoto { HomePhoto(space: browser.spaceID) }
                }
                .clipShape(shape)
                .padding(frame)
                .allowsHitTesting(false)
            }
            .environment(\.tone, themedControls ? tone : nil)
            .environment(\.colorScheme, tone?.scheme ?? scheme)
        } else {
            content
        }
    }
}

/// Home's buttons share a hover target and a focus ring around the whole label.
private struct HomeControl<Outline: InsettableShape, Label: View>: View {
    let outline: Outline
    var selected = false
    var muted = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.homeDropHovered) private var dropHovered
    @FocusState private var focused: Bool
    @State private var buttonHovered = false

    private var hovered: Bool { buttonHovered || dropHovered }

    var body: some View {
        Button(action: action) {
            label()
                .foregroundStyle(muted && !hovered && !focused ? Palette.muted : Palette.ink)
                .background(Palette.ink.opacity(fill), in: outline)
                .contentShape(outline)
        }
        .buttonStyle(.plain)
        .onHover { buttonHovered = $0 }
        .animation(reduceMotion ? nil : Motion.quick, value: hovered)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .overlay {
            if focused {
                outline.strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2)
                    .allowsHitTesting(false)
            }
        }
        .onKeyPress(keys: [.return, .space], phases: .down) { press in
            guard press.modifiers.isEmpty else { return .ignored }
            action()
            return .handled
        }
    }

    private var fill: Double {
        if selected { return hovered ? 0.22 : 0.14 }
        return hovered ? 0.10 : 0
    }
}

/// Compact page navigation shared by Home and template views.
struct PageTabButton: View {
    let title: String
    var symbol: String?
    var showsTitle = true
    let selected: Bool
    var variant: ButtonKind = .secondary
    var size: ButtonSize? = nil
    var state: PageActionButton.State = .ready
    let action: () -> Void

    var body: some View {
        Group {
            if let size {
                PageActionButton(title: title, icon: symbol, variant: selected ? variant : .quiet, size: size,
                                 state: selected && state == .ready ? .active : state,
                                 iconOnly: !showsTitle, capsule: true, action: action)
            } else {
                HomeControl(outline: Capsule(), selected: selected, action: action) {
                    HStack(spacing: 6) {
                        if let symbol { Image(systemName: symbol) }
                        if showsTitle { Text(title).lineLimit(1) }
                    }.font(CardFrame.title).padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HomeHiddenTabs: View {
    @AppStorage("home.hiddenLibraries", store: Store.settings) private var hidden = ""
    private var hiddenKeys: [String] { hidden.split(separator: ",").map(String.init) }
    var body: some View {
        Section("Hidden tabs") {
            ForEach(HomeNavigation.standard.filter(hiddenKeys.contains), id: \.self) { key in
                Button("Show " + key.capitalized) { hidden = hiddenKeys.filter { $0 != key }.joined(separator: ",") }
            }
        }
    }
}

struct HomeSettingsPanel: View {
    let browser: Browser
    let width: CGFloat
    let close: () -> Void
    @AppStorage("home.hiddenLibraries", store: Store.settings) private var hidden = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Home Tab Settings").font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close Home Tab Settings")
            }.padding(16)
            Divider()
            ScrollView {
                SpacePageLook(browser: browser) { look, custom, reset in
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Accent").font(.headline)
                        LookControls(look: .paint(look), width: width - 32, bare: true, offersSite: false,
                                     backgroundControls: AnyView(VStack(alignment: .leading, spacing: 12) {
                                         Divider()
                                         Text("Background").font(.headline)
                                         HomePhotoGallery(space: browser.spaceID)
                                         HomePhotoEffects(space: browser.spaceID, base: .paint(look))
                                     }))
                        if !hidden.isEmpty { Menu("Hidden tabs") { HomeHiddenTabs() } }
                        Button("Use Space Look", action: reset).disabled(!custom)
                    }
                    .padding(16)
                }.id(browser.spaceID)
            }
        }
        .frame(width: width)
    }
}

struct HomeNavigation: View {
    let browser: Browser
    @Binding var selected: String
    @AppStorage("home.tabOrder", store: Store.settings) private var order = ""
    @AppStorage("home.hiddenLibraries", store: Store.settings) private var hidden = ""
    @AppStorage("home.libraryTabStyle", store: Store.settings) private var display = "Text only"
    fileprivate static let standard = ["tabs", "bookmarks", "history", "downloads", "extensions", "settings"]
    private var hiddenKeys: [String] { hidden.split(separator: ",").map(String.init) }
    private var keys: [String] {
        let custom = groups.map { $0.id.uuidString }
        let kept = order.split(separator: ",").map(String.init).filter(custom.contains)
        return ["overview"] + Self.standard.filter { !hiddenKeys.contains($0) } + kept + custom.filter { !kept.contains($0) }
    }

    @ViewBuilder private func libraryOptions(_ key: String) -> some View {
        Menu("Display as") {
            Picker("Display as", selection: $display) {
                ForEach(["Icon only", "Text only", "Text and icon"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.inline)
        }
        if Self.standard.contains(key) {
            Button("Hide " + key.capitalized) {
                hidden = (hiddenKeys + [key]).joined(separator: ",")
                if selected == key { selected = "overview" }
            }
        }
        if !hiddenKeys.isEmpty { HomeHiddenTabs() }
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
                    HomeControl(outline: navigationIconOutline, action: { adding = HomeGroup() }) { navigationIcon("plus") }
                        .accessibilityLabel("Add Home tab")
                        .popover(item: $adding, arrowEdge: .bottom) { group in
                            HomeGroupEditor(group: group, title: "New tab", save: save)
                        }
                }
            }.scrollIndicators(.hidden)
            HomeControl(outline: navigationIconOutline, selected: browser.homeSettingsInColumn && browser.chatOpen, action: {
                if browser.homeSettingsInColumn && browser.chatOpen { browser.hideChat() }
                else { browser.moveChat(open: true, homeSettings: true) }
            }) { navigationIcon("gearshape") }
                .accessibilityLabel("Customize Home")
                .pointerTip("Customize Home")

        }
        .onChange(of: keys) { _, _ in
            if !keys.contains(selected) { selected = "overview" }
        }
        .padding(.bottom, 8)
    }

    private var navigationIconOutline: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control) }

    private func navigationIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15)).frame(width: 32, height: 32)
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
        PageTabButton(title: title, symbol: display == "Text only" ? nil : LibraryPage(rawValue: key)?.icon,
                      showsTitle: !Self.standard.contains(key) || display != "Icon only",
                      selected: selected == key) { selected = key }
        .accessibilityLabel(title + " Home tab")
        .modifier(HomeDropTarget(area: HomeDropArea(tabKey: UUID(uuidString: key) == nil ? nil : key, reorder: { reorder($0, onto: key) }, activate: { selected = key }) { source, _ in
            guard key == "overview" || UUID(uuidString: key) != nil else { return false }
            return moveShortcut(source, data: &savedShortcuts, to: UUID(uuidString: key))
        }))
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

private enum HomeColumns {
    static let width: CGFloat = 96
    static let gap: CGFloat = 16
    static let rowGap: CGFloat = 24

    static func grid(in available: CGFloat) -> [GridItem] {
        let count = max(1, Int((available + gap) / (width + gap)))
        return Array(repeating: GridItem(.fixed(width), spacing: gap), count: count)
    }
}

private struct HomeTile<Mark: View>: View {
    let title: String
    let action: () -> Void
    @ViewBuilder let mark: () -> Mark
    var body: some View {
        HomeControl(outline: RoundedRectangle(cornerRadius: Radius.surface), action: action) {
            VStack(spacing: 8) {
                mark().frame(width: 32, height: 32)
                    .frame(width: 56, height: 56)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.surface))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.surface)
                            .strokeBorder(Palette.ink.opacity(0.12))
                    }
                Text(title).font(CardFrame.detail).lineLimit(1).truncationMode(.middle)
            }.padding(.vertical, 4).frame(width: HomeColumns.width)
        }.accessibilityLabel(title)
    }
}

private struct HomeDraggedTile: ViewModifier {
    let held: Bool
    let shift: CGSize

    func body(content: Content) -> some View {
        ZStack {
            content.opacity(held ? 0 : 1)
                .overlay {
                    if held { ColumnGap(square: true).allowsHitTesting(false) }
                }
                .offset(shift)
        }
    }
}

struct PrivateHomeHeader: View {
    let browser: Browser

    var body: some View {
        HStack(spacing: 8) {
            Label("Private Browsing", systemImage: Space.privateSpace.icon)
                .font(CardFrame.title)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            PageActionButton(title: Command.clearPrivateSession.title, icon: Command.clearPrivateSession.symbol,
                             action: browser.confirmClearPrivateSession)
        }
    }
}

struct HomeTab: View {
    let browser: Browser
    @ObservedObject var history: History
    @ObservedObject var downloads: Loot
    @ObservedObject var bookmarks: Bookmarks
    @Binding var selection: String
    static func cancelDrag(in window: NSWindow?) -> Bool { HomeGridHand.cancel(in: window) }

    private var group: UUID? { UUID(uuidString: selection) }
    @AppStorage("home.shortcuts", store: Store.settings) private var saved = Data()
    @State private var adding: HomeShortcut?
    @State private var editKey: String?
    @State private var shortcutDrag = HomeTileDrag<String>()
    @State private var spaceDrag = HomeTileDrag<UUID>()
    @State private var folderPath: [UUID] = []

    private var shortcuts: [HomeShortcut] {
        (try? JSONDecoder().decode([HomeShortcut].self, from: saved)) ?? []
    }

    var body: some View {
        if browser.inPrivateSpace {
            privateOverview
        } else {
            GeometryReader { geometry in
                overview(width: geometry.size.width)
            }
        }
    }

    @ViewBuilder private var privateOverview: some View {
        let tabs = browser.tabs.filter { $0.shy && !$0.bench && !$0.isBlank }
        if !tabs.isEmpty {
            section("Open tabs") {
                HomeSectionStrip(title: "Open tabs", hovered: hoveredSection == "Open tabs") {
                    ForEach(tabs) { tab in
                        HomeTile(title: tab.label, action: { browser.select(tab) }) {
                            Mark(icon: tab.icon, letter: tab.monogram, size: 28)
                        }
                    }
                }
            }
            .padding(.vertical, LibraryPageLayout.sectionGap)
        }
    }

    private func overview(width: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 56) { // design: extra separation between distinct Home collections
                if group == nil && !browser.turnOrder.isEmpty {
                    section("Spaces") {
                        let spaces = browser.turnOrder
                        let ids = spaces.map(\.id)
                        HomeSectionStrip(title: "Spaces", hovered: hoveredSection == "Spaces") {
                            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                                spaceTile(space, index: index, ids: ids)
                            }
                        }
                        .coordinateSpace(name: "home-spaces")
                    }
                }
                section("Shortcuts") {
                    LazyVGrid(columns: HomeColumns.grid(in: width), alignment: .leading, spacing: HomeColumns.rowGap) {
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
                        .modifier(HomeDropTarget(area: HomeDropArea(slot: HomeReorderSlot(collection: .shortcuts, index: sites.count, end: true), hover: { _ in
                            shortcutDrag.preview(at: sites.count, in: sites.map(\.id))
                        }, activate: { adding = HomeShortcut(group: group) }) { source, _ in
                            moveShortcut(source, data: &saved, to: group, following: group == nil ? automaticSites : [])
                        }))
                    }
                    .coordinateSpace(name: "home-shortcuts")
                }
                if group == nil {
                    if !history.recent().isEmpty {
                        section("Recent history", page: .history) {
                            HomeSectionStrip(title: "Recent history", hovered: hoveredSection == "Recent history") {
                                ForEach(history.recent()) { row in link(row.url, row.title.isEmpty ? row.url.absoluteString : row.title) }
                            }
                        }
                    }
                    if !downloads.kept.isEmpty {
                        section("Downloads", page: .downloads) {
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
                        section("Bookmarks", page: .bookmarks) {
                            let path = resolvedFolders(in: roots)
                            let entries = path.last.map { $0.children ?? [] } ?? roots
                            if let folder = path.last {
                                HomeControl(outline: headingOutline, action: { folderPath = path.dropLast().map(\.id) }) {
                                    Label(folder.title, systemImage: "chevron.left")
                                        .padding(.horizontal, 8).padding(.vertical, 4)
                                }.accessibilityLabel("Back from " + folder.title)
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

    private func spaceTile(_ space: Space, index: Int, ids: [UUID]) -> some View {
        let select = { browser.switchSpace(to: space.id, keepingHome: true) }
        let slot = HomeReorderSlot(collection: .spaces, index: index)
        return HomeTile(title: space.name, action: select) {
            SpaceMark(icon: space.icon, size: 28)
        }
        .modifier(HomeDraggedTile(held: spaceDrag.held == space.id, shift: spaceDrag.displacement(of: space.id, in: ids)))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named("home-spaces")).origin } action: {
            spaceDrag.positions[space.id] = $0
        }
        .background(SpaceAnchor(kind: .homeTile(space.id)))
        .modifier(HomeDropTarget(area: HomeDropArea(spaceID: space.id, slot: slot, moveSpace: { source, x in
            // Resolve against the current order, including Mail when shown.
            let order = browser.turnOrder.map(\.id)
            guard order.indices.contains(index), order[index] == space.id,
                  let to = HomeTileDrag<UUID>.destination(for: source, at: slot.insertion(at: x), in: order) else { return }
            browser.moveInOrder(source, to: to)
        }, begin: { spaceDrag.held = space.id }, end: {
            spaceDrag.finish()
        }, hover: { x in
            spaceDrag.preview(at: slot.insertion(at: x), in: ids)
        }, activate: select)))
        .steadyMenu(actions: true, tone: SpaceSurface.tone(in: browser)) {
            Button("Switch Space", mark: "yab.chevupdown", action: select)
            Divider()
            SpaceMenu(browser: browser, space: space, fromHome: true)
        }
    }

    private func gridTile(_ site: GridSite, index: Int, sites: [GridSite]) -> some View {
        let shortcut = site.shortcut
        let open = {
            if !site.saved, let tab = pins.first(where: { ($0.address ?? $0.pending)?.absoluteString == shortcut.address }) {
                browser.close()
                browser.select(tab)
            } else if let url = shortcut.url { browser.send(url, .here) }
        }
        let ids = sites.map(\.id)
        let slot = HomeReorderSlot(collection: .shortcuts, index: index)
        return HomeTile(title: shortcut.name, action: open) {
            if let url = shortcut.url { PlacePageMark(url: url, side: 28) }
        }
        .modifier(HomeDraggedTile(held: shortcutDrag.held == site.id, shift: shortcutDrag.displacement(of: site.id, in: ids)))
        .onGeometryChange(for: CGPoint.self) { $0.frame(in: .named("home-shortcuts")).origin } action: {
            shortcutDrag.positions[site.id] = $0
        }
        .modifier(HomeDropTarget(area: HomeDropArea(source: shortcut, slot: slot, begin: {
            shortcutDrag.held = site.id
        }, end: {
            shortcutDrag.finish()
        }, hover: { x in
            shortcutDrag.preview(at: slot.insertion(at: x), in: ids)
        }, activate: open) { source, x in
            let insertion = slot.insertion(at: x)
            let target = sites.dropFirst(insertion).first
            let prefix = sites.prefix(insertion).filter { !$0.saved }.map(\.shortcut)
            return moveShortcut(source, data: &saved, to: group, before: target.flatMap { $0.saved ? $0.shortcut.id : nil }, following: prefix)
        }))
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

    private var headingOutline: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.control) }

    private func section<Content: View>(_ title: String, page: LibraryPage? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Group {
                if let page {
                    HomeControl(outline: headingOutline, muted: true, action: { selection = page.rawValue }) {
                        HStack(spacing: 4) {
                            Text(title)
                            Image(systemName: "arrow.up.right").imageScale(.small).accessibilityHidden(true)
                        }.padding(.horizontal, 8).padding(.vertical, 4)
                    }
                    .padding(.leading, -8)
                    .padding(.vertical, -4)
                } else {
                    Text(title).foregroundStyle(.secondary)
                }
            }.font(.headline).accessibilityAddTraits(.isHeader)
            content()
        }.frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
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
            HStack(alignment: .top, spacing: HomeColumns.gap) { content() }
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
        HomeControl(outline: Circle(), action: {
            let offset = visible.minX + (forward ? visible.width : -visible.width)
            withAnimation { position.scrollTo(x: max(0, min(width - visible.width, offset))) }
        }) {
            Image(systemName: icon).font(.body.weight(.semibold)).frame(width: 34, height: 34)
        }
        .background(.regularMaterial, in: Circle())
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
