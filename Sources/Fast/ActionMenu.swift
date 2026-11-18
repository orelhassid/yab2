import AppKit
import Combine
import SwiftUI

// A right-click's menu drawn as ⌘K's list (FieldActionsPanel), Raycast's
// Action Panel: the same lines the AppKit menu would have shown, their
// marks, words and keys, and a search that has the keyboard as it comes up.
// The lines are the menu's own (NSHostingMenu of the SwiftUI menu), so what
// is on, off, ticked or hidden is what the menu says, and a line picked is
// the menu's item performed. A submenu opens beside its line in a panel of
// its own, under the pointer or on →, as the Mac's menus open theirs, and
// a search finds its lines too, its name beside them.
//
// It hangs from the pointer, down where there is room under it and up where
// there isn't, and its search stands at the end nearest the pointer: on top
// as it falls, at its foot as it rises, as ⌘K's does.

/// Optional row content supplied by a menu's own item, kept when searched
/// or opened as a submenu, without teaching the panel about bookmarks.
@MainActor
protocol ActionMenuContent {
    var menuPlaceholder: String { get }
    var menuChanges: AnyPublisher<Void, Never> { get }
}

@MainActor
protocol ActionMenuItemContent {
    var menuDetail: String? { get }
    var menuContext: ((NSPoint) -> Void)? { get }
}

/// The corridor from the previous pointer point to a submenu's near edge.
/// It protects diagonal travel only while making progress toward that edge.
enum ActionMenuAim {
    static func contains(origin: CGPoint, point: CGPoint, submenu: CGRect) -> Bool {
        let right = submenu.midX > origin.x
        let edge = right ? submenu.minX : submenu.maxX
        let distance = edge - origin.x
        guard abs(distance) > 0.5 else { return false }
        let progress = (point.x - origin.x) / distance
        guard progress > 0, progress <= 1 else { return false }
        let low = origin.y + (submenu.minY - 8 - origin.y) * progress
        let high = origin.y + (submenu.maxY + 8 - origin.y) * progress
        return point.y >= min(low, high) && point.y <= max(low, high)
    }
}

@MainActor
final class ActionMenuList: ObservableObject {
    struct Line: Identifiable {
        let id: Int
        let title: String
        var image: NSImage?
        let keys: String
        let enabled: Bool
        let checked: Bool
        /// The menu it is in, and where, to perform it.
        let menu: NSMenu
        private let sourceItem: NSMenuItem?
        /// Menus can rebuild while SwiftUI still holds the previous rows.
        /// Resolve the same item at use time; an old position may now name
        /// another command, or be outside the menu altogether.
        @MainActor var index: Int { sourceItem.map { menu.index(of: $0) } ?? -1 }
        @MainActor var item: NSMenuItem? {
            guard let sourceItem, sourceItem.menu === menu else { return nil }
            return sourceItem
        }

        @MainActor init(id: Int, title: String, image: NSImage? = nil, keys: String,
                        enabled: Bool, checked: Bool, menu: NSMenu, index: Int,
                        submenu: NSMenu?, from: String?, boundary: Boundary? = nil, score: Int = 0) {
            self.id = id
            self.title = title
            self.image = image
            self.keys = keys
            self.enabled = enabled
            self.checked = checked
            self.menu = menu
            let items = menu.items
            sourceItem = items.indices.contains(index) ? items[index] : nil
            self.submenu = submenu
            self.from = from
            self.boundary = boundary
            self.score = score
        }
        let submenu: NSMenu?
        /// The submenu it was found in by a search, beside its words.
        let from: String?
        /// A space or a line over it, where the menu had a separator.
        var boundary: Boundary?
        var score = 0
        @MainActor var detail: String? { (item as? ActionMenuItemContent)?.menuDetail }
        @MainActor var context: ((NSPoint) -> Void)? { (item as? ActionMenuItemContent)?.menuContext }

        @MainActor static func leadsWithEmoji(_ title: String) -> Bool {
            Line(id: 0, title: title, image: nil, keys: "", enabled: true, checked: false, menu: NSMenu(), index: 0,
                 submenu: nil, from: nil).emoji != nil
        }

        /// A space's emoji before its name ("🏠  Personal"): drawn in the
        /// marks' column, its name beside it as the others' words are.
        var emoji: String? {
            guard let first = title.first, first.unicodeScalars.first?.properties.isEmojiPresentation == true
                    || (first.unicodeScalars.count > 1 && first.unicodeScalars.contains { $0.properties.isEmoji }),
                  title.dropFirst().first?.isWhitespace == true else { return nil }
            return String(first)
        }

        var name: String {
            emoji == nil ? title : String(title.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
    }

    enum Boundary: Equatable { case space, line }

    private let root: NSMenu
    private var contentWatch: AnyCancellable?
    var placeholder: String { (root as? ActionMenuContent)?.menuPlaceholder ?? (compact ? "Search more actions\u{2026}" : "Search\u{2026}") }
    let compact: Bool
    @Published private(set) var option = false
    @Published var searching = false
    var searchVisible: Bool { !nested || root is ActionMenuContent }
    /// A submenu uses the shared row treatment and each item's own mark.
    /// Search belongs to the root panel nearest the opening point, unless the
    /// menu is one of its own content (bookmarks): each of its folders has one.
    let nested: Bool
    private let mark: NSImage?
    @Published private(set) var lines: [Line] = []
    @Published var query = "" {
        didSet {
            searching = !query.isEmpty
            cancelPendingHover()
            hovered = nil
            keyboardChoice = !query.isEmpty
            closeChild()
            refresh()
        }
    }
    /// The submenu open beside a line, and which line.
    private(set) var child: ActionMenuList?
    private(set) var childLine: Int?
    weak var parent: ActionMenuList?
    /// Whether the keys are this panel's: a submenu has them once it is
    /// opened with → or Return, or the pointer is in it.
    var focused = true
    /// Told to put a submenu's panel up beside a line, or nil to take the
    /// one up away (ActionMenu).
    var showChild: (ActionMenuList?, Int) -> Void = { _, _ in }
    /// Where the lines that open a submenu are in the panel's window,
    /// top-left, for the submenu to hang beside.
    var frames: [Int: CGRect] = [:]
    var wordFrames: [Int: CGRect] = [:]
    var keyFrames: [Int: CGRect] = [:]
    @Published var spot = -1
    @Published private(set) var hovered: Int?
    private var keyboardChoice = false
    var highlighted: Int? { hovered ?? (keyboardChoice && lines.indices.contains(spot) ? spot : nil) }
    var childFrame: CGRect?
    var screenPoint: (CGPoint) -> CGPoint = { $0 }
    private var lastPointer: CGPoint?
    private var hoverGeneration = 0
    private var hoverWork: DispatchWorkItem?
    /// Set by the keys, so the list scrolls to them; never by the pointer.
    @Published var scrollTo: Int?
    /// Whether the panel hangs down from the pointer: then its search is on top.
    let falls: Bool
    var changed: () -> Void = {}
    var close: () -> Void = {}
    var dispatch: (() -> Void) -> Void = { $0() }

    /// Fits the visible commands, expanding for longer search results. Option
    /// alternates resize only while shown, as opposed to widening every menu.
    @Published private(set) var width: CGFloat

    init(menu: NSMenu, falls: Bool, nested: Bool = false, mark: NSImage? = nil, compact: Bool? = nil) {
        root = menu
        self.falls = falls
        self.nested = nested
        self.mark = mark
        menu.update()
        self.compact = compact ?? ActionMenu.prepare(menu)
        let measured = Self.lines(of: menu, mark: mark)
        width = Self.widest(measured)
        refresh()
        contentWatch = (menu as? ActionMenuContent)?.menuChanges.sink { [weak self] in self?.refreshImages() }
    }

    private func refreshImages() {
        var next = lines
        var changed = false
        for index in next.indices {
            let line = next[index]
            let image = line.item?.image
            if line.image !== image { next[index].image = image; changed = true }
        }
        if changed { lines = next }
    }

    private static func widest(_ lines: [Line]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let native = NSMenu()
        native.autoenablesItems = false
        native.font = font
        let widest = lines.map { line -> CGFloat in
            let source = line.item
            let item = NSMenuItem(title: line.name, action: nil, keyEquivalent: source?.keyEquivalent ?? "")
            item.keyEquivalentModifierMask = source?.keyEquivalentModifierMask ?? []
            item.image = line.image
            item.state = line.checked ? .on : .off
            if line.submenu != nil { item.submenu = NSMenu() }
            native.addItem(item)
            let words = (line.name as NSString).size(withAttributes: [.font: font]).width
            let keys = (line.keys as NSString).size(withAttributes: [.font: font]).width
            let tail: CGFloat
            if line.checked { tail = 14 }
            else if line.submenu != nil { tail = 12 }
            else if !line.keys.isEmpty { tail = keys }
            else { tail = ((line.from ?? "") as NSString).size(withAttributes: [.font: font]).width }
            // The rendered columns only: no hidden Option actions or spare width.
            let m = MenuMetrics.self
            let detail = line.detail.map { ($0 as NSString).size(withAttributes: [.font: font]).width + m.iconGap } ?? 0
            return m.mark + 3 * m.iconGap + words + detail + tail + 2 * m.inset + 2 * m.pad
        }.max() ?? 0
        return min(ceil(max(widest, native.size.width, MenuMetrics.narrowest)), MenuMetrics.widest)
    }

    private func refresh() {
        let menu = root
        menu.update()
        if compact { _ = ActionMenu.prepare(menu) }
        let ordinary = Self.lines(of: menu, mark: mark)
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            lines = ordinary
            if compact, option, let extra = Self.extras(menu) {
                let alternatives = Self.lines(of: extra)
                lines = lines.map { line in
                    let title: String?
                    if line.title == "Copy Link" { title = "Copy Markdown Link" }
                    else if line.title == "Close" { title = "Close and Keep" }
                    else { title = nil }
                    guard let title, var alternate = alternatives.first(where: { $0.title == title }) else { return line }
                    alternate = Line(id: line.id, title: alternate.title, image: alternate.image, keys: alternate.keys,
                                     enabled: alternate.enabled, checked: alternate.checked, menu: alternate.menu,
                                     index: alternate.index, submenu: alternate.submenu, from: nil, boundary: line.boundary)
                    return alternate
                }
                if let sleep = alternatives.first(where: { $0.title.contains(" to Sleep") }),
                   !lines.contains(where: { $0.title == sleep.title }) {
                    var line = sleep
                    line = Line(id: lines.count, title: line.title, image: line.image, keys: line.keys, enabled: line.enabled,
                                checked: line.checked, menu: line.menu, index: line.index, submenu: nil, from: nil)
                    let at = lines.firstIndex { $0.boundary == .line && $0.title.hasPrefix("Close") } ?? lines.count
                    lines.insert(line, at: at)
                    lines = lines.enumerated().map { index, line in
                        Line(id: index, title: line.title, image: line.image, keys: line.keys, enabled: line.enabled,
                             checked: line.checked, menu: line.menu, index: line.index, submenu: line.submenu,
                             from: line.from, boundary: line.boundary)
                    }
                }
            }
        } else {
            var candidates: [Line] = []
            func collect(_ source: NSMenu, from: String? = nil, mark: NSImage? = nil) {
                source.update()
                _ = ActionMenu.prepare(source)
                for line in Self.lines(of: source, from: from, mark: mark) {
                    candidates.append(line)
                    if let submenu = line.submenu { collect(submenu, from: line.title, mark: line.image) }
                }
            }
            collect(menu, mark: mark)
            if compact, let extra = Self.extras(menu) { collect(extra) }
            var seen = Set<String>()
            lines = candidates.compactMap { line -> Line? in
                let name = line.title.replacingOccurrences(of: "Copy URL", with: "Copy Link")
                    .replacingOccurrences(of: "Close Tab", with: "Close")
                // Only the tab's hidden legacy actions duplicate its root.
                // Same-named destinations in different submenus stay distinct.
                let parent = line.from == "Move to Folder" ? "Folder"
                    : line.from == "Move to Space" ? "Space" : line.from ?? ""
                let identity = name + "\u{0}" + parent
                guard (!compact || seen.insert(identity).inserted),
                      let score = Self.score(line.name + (line.detail.map { " " + $0 } ?? ""), query) else { return nil }
                var found = line
                found.score = score - (line.from == nil ? 0 : 1)
                return found
            }.enumerated()
                .sorted { $0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset }
                .enumerated().map { index, pair in
                    let line = pair.element
                    return Line(id: index, title: line.title, image: line.image, keys: line.keys, enabled: line.enabled,
                                checked: line.checked, menu: line.menu, index: line.index, submenu: line.submenu, from: line.from)
                }
        }
        width = query.trimmingCharacters(in: .whitespaces).isEmpty
            ? Self.widest(lines) : max(Self.widest(ordinary), Self.widest(lines))
        spot = query.isEmpty ? -1 : lines.firstIndex(where: \.enabled) ?? -1
        scrollTo = spot
        changed()
    }

    private static func extras(_ menu: NSMenu) -> NSMenu? {
        let extra = menu.items.first { $0.title == ActionMenu.tabSearchActions }?.submenu
        extra?.update()
        return extra
    }

    func modifiers(_ flags: NSEvent.ModifierFlags) {
        guard compact, option != flags.contains(.option) else { return }
        // Alternates are the same selected action. Sleep adds a row before
        // Close, so an index alone would move the selection onto Sleep.
        func identity(_ title: String) -> String {
            title.replacingOccurrences(of: "Copy Markdown Link", with: "Copy Link")
                .replacingOccurrences(of: " Markdown Links", with: " URLs")
                .replacingOccurrences(of: "Close and Keep", with: "Close")
        }
        let selected = lines.indices.contains(spot) ? lines[spot] : nil
        cancelPendingHover()
        option = flags.contains(.option)
        closeChild()
        refresh()
        if let selected, let at = lines.firstIndex(where: { $0.menu === selected.menu && $0.index == selected.index })
            ?? (query.trimmingCharacters(in: .whitespaces).isEmpty
                ? lines.firstIndex(where: { identity($0.title) == identity(selected.title) }) : nil) {
            spot = at
            if hovered != nil { hovered = at }
            scrollTo = at
        } else {
            hovered = nil
        }
    }

    /// Each item keeps its own image; a parent arrow is not a leaf icon.
    private static func lines(of menu: NSMenu, from: String? = nil, mark: NSImage? = nil) -> [Line] {
        var out: [Line] = []
        var split = false
        for (index, item) in menu.items.enumerated() {
            if item.isSeparatorItem {
                split = !out.isEmpty
                continue
            }
            guard shown(item) else { continue }
            // A space's emoji is its mark; no submenu's mark beside it.
            let own = item.image
            var line = Line(id: out.count, title: item.title, image: own, keys: keys(of: item),
                            enabled: item.isEnabled, checked: item.state == .on, menu: menu, index: index,
                            submenu: item.submenu, from: from)
            if (split || destructive(item.title) && !out.isEmpty && !destructive(out.last!.title)), from == nil {
                line.boundary = .line
            }
            split = false
            out.append(line)
        }
        return out
    }

    /// A row the list shows: not hidden, not an Option alternate, and not
    /// a submenu with nothing in it, which opened onto "No actions" (a pin
    /// in a split's Move to › Folder). Whatever menu builds it.
    private static func shown(_ item: NSMenuItem) -> Bool {
        guard !item.isHidden, !item.isAlternate, !item.isSectionHeader, item.view == nil else { return false }
        guard let submenu = item.submenu else { return true }
        submenu.update()
        return submenu.items.contains { !$0.isSeparatorItem && shown($0) }
    }

    /// The run a line sets apart from what comes before: closing, removing.
    private static func destructive(_ title: String) -> Bool {
        ["Close", "Remove", "Delete", "Forget", "Discard"].contains { title.hasPrefix($0) }
    }

    /// Each word typed starts a word of the title, or the letters typed are
    /// the first letters of its words ("cml", Copy Markdown Link).
    static func score(_ title: String, _ query: String) -> Int? {
        let typed = words(query)
        guard !typed.isEmpty else { return 0 }
        let own = words(title)
        var score = 0
        for word in typed {
            if own.first?.hasPrefix(word) == true {
                score += 4
            } else if own.contains(where: { $0.hasPrefix(word) }) {
                score += 3
            } else if typed.count == 1, word.count > 1, String(own.compactMap(\.first)).hasPrefix(word) {
                score += 2
            } else {
                return nil
            }
        }
        return score
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "." }.map(String.init)
    }

    /// The item's key as KeyGlyphs draws it, "⇧⌘D".
    private static func keys(of item: NSMenuItem) -> String {
        let equivalent = item.keyEquivalent
        guard !equivalent.isEmpty else { return "" }
        let named: [String: String] = [
            "\r": "↩", "\t": "⇥", "\u{8}": "⌫", "\u{7f}": "⌫", "\u{1b}": "esc", " ": "space",
            String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←",
            String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
            String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑",
            String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
            String(UnicodeScalar(NSDeleteFunctionKey)!): "⌦",
        ]
        var flags = item.keyEquivalentModifierMask
        // A capital is its letter with ⇧, as AppKit reads it.
        if equivalent != equivalent.lowercased() { flags.insert(.shift) }
        let key = named[equivalent] ?? equivalent.lowercased()
        return Hotkey.caps(key, flags).joined()
    }

    /// The keystroke an item's key equivalent is, as Hotkey reads a press:
    /// nil when it has none.
    static func hotkey(of item: NSMenuItem) -> Hotkey? {
        let equivalent = item.keyEquivalent
        guard !equivalent.isEmpty else { return nil }
        let named: [String: String] = [
            "\r": "↩", "\t": "⇥", "\u{8}": "⌫", "\u{7f}": "⌫", "\u{1b}": "esc", " ": "space",
            String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←",
            String(UnicodeScalar(NSRightArrowFunctionKey)!): "→",
            String(UnicodeScalar(NSUpArrowFunctionKey)!): "↑",
            String(UnicodeScalar(NSDownArrowFunctionKey)!): "↓",
            String(UnicodeScalar(NSDeleteFunctionKey)!): "⌦",
        ]
        var flags = item.keyEquivalentModifierMask
        // A capital is its letter with ⇧, as AppKit reads it.
        if equivalent != equivalent.lowercased() { flags.insert(.shift) }
        return Hotkey(named[equivalent] ?? equivalent.lowercased(), flags)
    }

    /// A key a line shows, pressed with ⌘ or ⌃ while the list is up: that
    /// line done, as the Mac's own menus do the item whose key is pressed
    /// while they are open. The panel is the key window, so the key never
    /// reached the line otherwise: a folder's "Close 2 Tabs ⌘W" sent ⌘W to
    /// File's Close Tab, which found no browser window in front and closed
    /// nothing (register 1890).
    @discardableResult
    func press(_ event: NSEvent) -> Bool {
        guard !event.modifierFlags.intersection([.command, .control]).isEmpty else { return false }
        let readings = Hotkey.readings(event)
        guard !readings.isEmpty else { return false }
        let at = active
        for list in at === self ? [self] : [at, self] {
            guard let index = list.lines.firstIndex(where: { line in
                line.enabled && line.submenu == nil
                    && line.item.flatMap(Self.hotkey(of:)).map(readings.contains) == true
            }) else { continue }
            list.take(index)
            return true
        }
        return false
    }

    /// The panel the keys go to: the deepest submenu that has them.
    var active: ActionMenuList {
        if let child, child.focused { return child.active }
        return self
    }

    func move(_ by: Int) {
        guard lines.contains(where: \.enabled) else { return }
        cancelPendingHover()
        hovered = nil
        keyboardChoice = true
        var at = !lines.indices.contains(spot) && by < 0 ? 0 : spot
        repeat { at = (at + by + lines.count) % lines.count } while !lines[at].enabled
        spot = at
        scrollTo = at
        if child != nil, childLine != at { closeChild() }
    }

    /// Pointer highlighting has its own lifetime; a departed row must not
    /// remain selected merely because no other enabled row was entered.
    func point(_ index: Int, at point: CGPoint? = nil) {
        parent?.cancelPendingHover()
        guard lines.indices.contains(index), lines[index].enabled else { leave(); return }
        let previous = lastPointer
        let pendingForSameRow = hoverWork != nil && hovered == index
        if let point { lastPointer = point }
        if hovered != index { hovered = index }
        keyboardChoice = false
        if spot != index { spot = index }
        focused = true
        parent?.child?.focused = true
        if child?.searchVisible != true { child?.focused = false }
        if child != nil, childLine != index, let previous, let point, let childFrame,
           ActionMenuAim.contains(origin: previous, point: point, submenu: childFrame) {
            // A bounded native-menu-style grace while crossing another row
            // diagonally toward the already-open child's near edge.
            // Further motion in this row keeps the first crossing's deadline.
            if pendingForSameRow { return }
            cancelPendingHover()
            let generation = hoverGeneration
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverGeneration == generation, self.hovered == index else { return }
                self.hoverWork = nil
                self.presentChild(for: index)
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        } else {
            cancelPendingHover()
            presentChild(for: index)
        }
    }

    func leave(_ index: Int? = nil) {
        guard index == nil || hovered == index else { return }
        cancelPendingHover()
        if hovered != nil { hovered = nil }
        if !keyboardChoice, spot != -1 { spot = -1 }
    }

    func cancelPendingHover() {
        hoverGeneration += 1
        hoverWork?.cancel()
        hoverWork = nil
    }

    private func presentChild(for index: Int) {
        guard lines.indices.contains(index) else { return }
        if lines[index].submenu != nil { open(index, keys: false) } else { closeChild() }
    }

    /// A line's submenu beside it; with `keys`, the keys go to it and its
    /// first line is lit.
    private func open(_ index: Int, keys: Bool) {
        cancelPendingHover()
        guard let submenu = lines[index].submenu else { return }
        if childLine != index || child == nil {
            closeChild()
            let inner = ActionMenuList(menu: submenu, falls: falls, nested: true, mark: lines[index].image, compact: compact)
            inner.parent = self
            inner.close = close
            inner.dispatch = dispatch
            child = inner
            childLine = index
            showChild(inner, index)
        }
        guard let child else { return }
        child.focused = keys || child.searchVisible
        if keys { child.keyboardChoice = true; child.hovered = nil }
        if keys, !child.lines.indices.contains(child.spot) || !child.lines[child.spot].enabled {
            child.spot = child.lines.firstIndex(where: \.enabled) ?? -1
        }
    }

    func closeChild() {
        cancelPendingHover()
        childFrame = nil
        guard let child else { return }
        child.closeChild()
        self.child = nil
        childLine = nil
        showChild(nil, -1)
    }

    /// Return, a click: a submenu opened with the keys in it, or the item
    /// done.
    func take(_ index: Int? = nil) {
        cancelPendingHover()
        let at = index ?? spot
        guard lines.indices.contains(at), lines[at].enabled else { return }
        let line = lines[at]
        if line.submenu != nil {
            spot = at
            open(at, keys: true)
            return
        }
        dispatch {
            close()
            // Closing may itself rebuild the menu; check after it returns.
            guard let item = line.item, item.isEnabled, !item.isHidden,
                  line.index >= 0 else { return }
            line.menu.performActionForItem(at: line.index)
        }
    }

    /// → into the lit line's submenu, ← back out of one.
    func side(_ by: Int) {
        if by > 0, lines.indices.contains(spot), lines[spot].submenu != nil { take() }
        if by < 0, query.isEmpty, let parent { parent.closeChild() }
    }

    /// Escape: out of the submenu the keys are in, the search emptied, or
    /// the panel put away.
    func escape() {
        let at = active
        if !at.query.isEmpty {
            at.query = ""
        } else if let parent = at.parent {
            parent.closeChild()
        } else {
            close()
        }
    }
}

struct ActionMenuView: View {
    @ObservedObject var list: ActionMenuList
    @Environment(\.tone) private var tone

    // The Mac's own menu's rhythm on yab's scale (MenuMetrics).
    static let row = MenuMetrics.row
    static let pad = MenuMetrics.pad
    static let gap = MenuMetrics.gap
    static let search = MenuMetrics.search

    private var rowHeight: CGFloat { Self.row }
    private var padding: CGFloat { Self.pad }
    private var spacing: CGFloat { Self.gap }

    var body: some View {
        VStack(spacing: 0) {
            if list.searchVisible, list.falls {
                search
                Divider()
            }
            ScrollViewReader { reader in
                ThreadScrollView(.vertical) {
                    rows.padding(padding)
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: Self.listHeight(list))
                .onChange(of: list.scrollTo) { _, to in
                    if let to { reader.scrollTo(to) }
                }
            }
            if list.searchVisible, !list.falls {
                Divider()
                search
            }
        }
        .frame(width: list.width, height: Self.height(list))
        .modifier(ActionMenuGlass(tone: tone))
        .transaction { $0.animation = nil }
    }

    private var search: some View {
        // The keys go to the submenu that has them, the words to this list.
        PickerSearch(text: $list.query, placeholder: list.placeholder,
                     move: { list.active.move($0) }, side: { list.active.side($0) },
                     pick: { list.active.take() }, close: { list.escape() }, size: 13, beginsAtEnd: true)
            .frame(height: 20)
            .padding(.horizontal, MenuMetrics.pad + MenuMetrics.inset) // the rows' words
            .frame(height: Self.search)
    }

    private var rows: some View {
        VStack(spacing: spacing) {
            if list.lines.isEmpty {
                Text("No actions")
                    .font(.system(size: MenuMetrics.words))
                    .foregroundStyle(Palette.muted(on: tone))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, MenuMetrics.inset)
                    .frame(height: rowHeight)
            }
            ForEach(list.lines) { line in
                switch line.boundary {
                case .line?, .space?:
                    Divider().padding(.horizontal, MenuMetrics.inset).frame(height: MenuMetrics.separator)
                case nil:
                    EmptyView()
                }
                row(line).id(line.id)
            }
        }
    }

    private func row(_ line: ActionMenuList.Line) -> some View {
        let ink = line.enabled ? Palette.strong(on: tone) : Palette.faint(on: tone)
        return HStack(spacing: MenuMetrics.iconGap) {
            // A line with no mark keeps the marks' column, so every title
            // starts in one place, as the Mac's own menus have them.
            Group {
                if let emoji = line.emoji {
                    Text(emoji).font(.system(size: 13))
                } else if let image = line.image {
                    Image(nsImage: image)
                        .renderingMode(image.isTemplate ? .template : .original)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .foregroundStyle(ink)
                } else {
                    Color.clear
                }
            }
            .frame(width: MenuMetrics.mark, height: MenuMetrics.mark)
            Text(line.name)
                .foregroundStyle(ink)
                .lineLimit(1)
                .fixedSize(horizontal: false, vertical: false)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                    list.wordFrames[line.id] = frame
                }
            Spacer(minLength: 0)
            if let detail = line.detail {
                Text(detail)
                    .foregroundStyle(Palette.muted(on: tone))
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            // Its own keys; a submenu's line shows where it goes.
            if line.checked {
                Symbol("checkmark", size: 10, weight: .semibold, side: 14).foregroundStyle(ink)
            } else if line.submenu != nil {
                Symbol("chevron.right", size: 9, weight: .semibold, side: 12).foregroundStyle(Palette.muted(on: tone))
            } else if !line.keys.isEmpty {
                Text(line.keys).font(.system(size: 13)).foregroundStyle(Palette.muted(on: tone))
                    .fixedSize()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                        list.keyFrames[line.id] = frame
                    }
            } else if let from = line.from {
                Text(from)
                    .foregroundStyle(Palette.muted(on: tone))
                    .lineLimit(1)
            }
        }
        .font(.system(size: MenuMetrics.words))
        .padding(.horizontal, MenuMetrics.inset)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill((tone == nil ? Color.primary.opacity(0.1) : Palette.wash(on: tone))
                    .opacity(line.id == list.highlighted && line.enabled ? 1 : 0))
        )
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                let frame = list.frames[line.id] ?? .zero
                list.point(line.id, at: list.screenPoint(CGPoint(x: frame.minX + point.x, y: frame.minY + point.y)))
            case .ended: list.leave(line.id)
            }
        }
        .onTapGesture { list.take(line.id) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            list.frames[line.id] = frame
        }
    }

    /// Fit every approved root row, with scrolling only for longer menus.
    static func listHeight(_ list: ActionMenuList) -> CGFloat {
        let row: CGFloat = Self.row
        let gap: CGFloat = Self.gap
        let pad: CGFloat = Self.pad
        let count = max(1, list.lines.count)
        var tall = CGFloat(count) * row + CGFloat(count - 1) * gap + 2 * pad
        for line in list.lines {
            switch line.boundary {
            case .line?, .space?: tall += MenuMetrics.separator + gap
            case nil: break
            }
        }
        return min(tall, 600)
    }

    static func height(_ list: ActionMenuList) -> CGFloat {
        listHeight(list) + (list.searchVisible ? search + 1 : 0)
    }
}

/// A shared blur under Liquid Glass keeps short submenus as frosted as
/// taller ones: glass alone adapts to its size and leaves a one- or two-row
/// Share menu almost clear. Where glass is not drawn, the Settings menus'
/// plate, lifted by its own shadow, its window casting none (ActionMenu.room).
struct ActionMenuGlass: ViewModifier {
    var corner: CGFloat = Radius.floating
    var tone: Tone? = nil
    @Environment(\.accessibilityReduceTransparency) private var solid

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        if let tone {
            content
                .clipShape(shape)
                .background(tone.color, in: shape)
                .overlay { shape.strokeBorder(Color(nsColor: SpaceSurface.rim(on: tone)), lineWidth: 1).allowsHitTesting(false) }
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6) // design: same lift as the neutral menu
        } else if #available(macOS 26.0, *), !solid {
            content
                .clipShape(shape)
                .background(.regularMaterial, in: shape)
                .glassEffect(.regular, in: shape)
        } else {
            content
                .modifier(PickerPlate())
                .shadow(color: .black.opacity(0.16), radius: 14, y: 6) // design: a menu's lift, as DropListView's
        }
    }
}

/// Where each list stands in the panel's window: the panel's own, then
/// each submenu beside the line it opens from, all in one window, so the
/// window that has the keys draws every one, its glass live.
@MainActor
final class ActionMenuLayout: ObservableObject {
    struct Plate: Identifiable {
        let id: Int
        let list: ActionMenuList
        /// In the window, from its top-left.
        let at: CGPoint
    }

    @Published var plates: [Plate] = []
    @Published var size: CGSize = .zero

    func place(_ lists: [ActionMenuList], frames: [CGRect], in window: NSWindow, room: CGFloat) {
        guard let first = frames.first else { return }
        let all = frames.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -room, dy: -room)
        if window.frame != all { window.setFrame(all, display: false) }
        // AppKit may round a requested frame to backing pixels. Position the
        // plates within the frame it actually applied, keeping screen anchors.
        let actual = window.frame
        size = actual.size
        plates = zip(lists, frames).enumerated().map { index, pair in
            Plate(id: index, list: pair.0, at: CGPoint(x: pair.1.minX - actual.minX, y: actual.maxY - pair.1.maxY))
        }
    }
}

struct ActionMenuStack: View {
    @ObservedObject var layout: ActionMenuLayout
    let tone: Tone?

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(layout.plates) { plate in
                // Placed by padding, not an offset, so the rows' frames read
                // where they are drawn.
                ActionMenuView(list: plate.list)
                    .padding(.leading, plate.at.x)
                    .padding(.top, plate.at.y)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .toned(tone)
    }
}

/// The panel's window, hung from the pointer in the window it was asked in,
/// taking the keys while it is open and gone when anything else is pressed
/// (DropPanel, the Settings menus' own window). A submenu opens beside the
/// line it comes from, on the right where there is room, else the left,
/// the window grown round both.
@MainActor
enum ActionMenu {
    static let tabSearchActions = "__yab_tab_search_actions__"

    static func isTab(_ menu: NSMenu) -> Bool {
        menu.items.contains { $0.title == tabSearchActions }
    }

    @discardableResult
    static func prepare(_ menu: NSMenu) -> Bool {
        guard let item = menu.items.first(where: { $0.title == tabSearchActions }) else { return false }
        item.isHidden = true
        return true
    }
    private static var panel: DropPanel?
    private static var list: ActionMenuList?
    private static var menu: NSMenu?
    /// A scoped owner across close -> action -> deferred picker handoff.
    private static weak var dispatchWindow: NSWindow?
    /// The lists up, the panel's first, and where each plate is on screen.
    private static var lists: [ActionMenuList] = []
    private static var plates: [NSRect] = []
    private static let layout = ActionMenuLayout()
    /// Told once the panel is put away, however it went.
    private static var done: (() -> Void)?
    /// Room round the plates for their shadow, as DropPopup has.
    static let room = DropPopup.room

    static func show(_ menu: NSMenu, from view: NSView, with event: NSEvent, scope: SidebarSpaceActions? = nil, tone: Tone? = nil) {
        guard let window = view.window else { return }
        show(menu, in: window, at: window.convertPoint(toScreen: event.locationInWindow), scope: scope, tone: tone)
    }

    /// `pointer` on the screen, where the press was. `up`: rising from it
    /// or falling whatever room there is (the column's plus, whose menu
    /// stands over it); `done`, once it is put away.
    static func show(_ menu: NSMenu, in window: NSWindow, at pointer: NSPoint, up: Bool? = nil, scope: SidebarSpaceActions? = nil, tone: Tone? = nil, done: (() -> Void)? = nil) {
        close()
        self.done = done
        menu.appearance = window.effectiveAppearance
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        // Measured as it would fall: the same parts either way.
        let tall = ActionMenuView.height(ActionMenuList(menu: menu, falls: true))
        let falls = up.map { !$0 } ?? (pointer.y - tall >= screen.minY + 8)
        let list = ActionMenuList(menu: menu, falls: falls)
        let width = list.width
        // Whole points: AppKit snaps the window, and a fractional plate would
        // snap one way or the other as a submenu changes the window's height.
        let x = round(min(max(pointer.x, screen.minX + 8), screen.maxX - width - 8))
        let y = round(falls ? pointer.y - tall : min(pointer.y, screen.maxY - tall - 8))
        let plate = NSRect(x: x, y: y, width: width, height: tall)

        let panel = DropPanel(contentRect: plate.insetBy(dx: -room, dy: -room),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = window.level
        panel.isReleasedWhenClosed = false
        panel.room = room
        panel.appearance = tone?.appearance ?? window.effectiveAppearance
        lists = [list]
        plates = [plate]
        self.panel = panel
        self.list = list
        self.menu = menu
        relayout()
        let host = NSHostingView(rootView: ActionMenuStack(layout: layout, tone: tone))
        // Yab sets this window's frame; SwiftUI keeping it inside the content's
        // least and greatest size after each window layout can loop (crash #112).
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.closes = { close() }
        panel.actionFlags = { list.modifiers($0) }
        panel.actionKey = { key($0) }
        panel.actionKeyEquivalent = { [weak list] event in list?.press(event) ?? false }
        panel.actionMouse = { [weak panel] event in
            guard let panel, event.type == .rightMouseDown || event.type == .leftMouseDown && event.modifierFlags.contains(.control) else { return false }
            let point = CGPoint(x: event.locationInWindow.x, y: panel.frame.height - event.locationInWindow.y)
            for list in lists.reversed() {
                guard let line = list.lines.first(where: { list.frames[$0.id]?.contains(point) == true }),
                      let context = line.context else { continue }
                let at = panel.convertPoint(toScreen: event.locationInWindow)
                close()
                DispatchQueue.main.async { context(at) }
                return true
            }
            return false
        }
        list.close = { close() }
        list.dispatch = { [weak window] action in
            let previous = dispatchWindow
            dispatchWindow = window
            defer { dispatchWindow = previous }
            if let scope { scope.run(action) } else { action() }
        }
        wire(list, depth: 0)
        // A search that leaves fewer lines shortens the panel away from the
        // pointer: from below as it falls, from above as it rises.
        list.changed = { [weak list] in
            guard let list, !plates.isEmpty else { return }
            var frame = plates[0]
            let height = ActionMenuView.height(list)
            if list.falls { frame.origin.y = frame.maxY - height }
            frame.size.height = height
            frame.size.width = list.width
            frame.origin.x = min(frame.origin.x, screen.maxX - list.width - 8)
            plates[0] = frame
            relayout()
            focusDeepest()
        }
        list.modifiers(NSEvent.modifierFlags)
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        host.layoutSubtreeIfNeeded()
        panel.focusSearch()
    }

    /// The window round every plate up, each plate where it is on screen.
    private static func relayout() {
        guard let panel else { return }
        layout.place(lists, frames: plates, in: panel, room: room)
    }

    /// A list's submenus come up `depth` + 1 deep, beside the line they
    /// open from.
    private static func wire(_ list: ActionMenuList, depth: Int) {
        list.screenPoint = { point in
            guard let panel else { return point }
            return CGPoint(x: panel.frame.minX + point.x, y: panel.frame.maxY - point.y)
        }
        list.showChild = { [weak list] inner, line in
            // Hover can arrive during SwiftUI layout. Resizing its hosting
            // window there re-enters layout and generates another hover.
            DispatchQueue.main.async { [weak list] in
                guard let list, lists.indices.contains(depth), lists[depth] === list else { return }
                if let inner {
                    guard list.child === inner, list.childLine == line else { return }
                } else {
                    guard list.child == nil else { return }
                }
                // Discard a queued opening after the pointer changed rows,
                // and a queued close after another child already replaced it.
                if lists.count > depth + 1 {
                    lists.removeSubrange((depth + 1)...)
                    plates.removeSubrange((depth + 1)...)
                }
                defer {
                    relayout()
                    focusDeepest()
                }
                guard let inner, let panel, let frame = list.frames[line], plates.indices.contains(depth) else { return }
                let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
                let outer = plates[depth]
                let width = inner.width
                let tall = ActionMenuView.height(inner)
                // Align the first child row with the parent row, its search above.
                let top = panel.frame.maxY - frame.minY + ActionMenuView.pad
                    + (inner.searchVisible && inner.falls ? ActionMenuView.search + 1 : 0)
                var x = outer.maxX + 4
                if x + width > screen.maxX - 8 { x = outer.minX - 4 - width }
                let y = min(max(top - tall, screen.minY + 8), screen.maxY - tall - 8)
                lists.append(inner)
                let childPlate = NSRect(x: x, y: y, width: width, height: tall)
                plates.append(childPlate)
                list.childFrame = childPlate
                wire(inner, depth: depth + 1)
                // Its search shortens it from below, as the panel's does.
                inner.changed = { [weak inner] in
                    guard let inner, plates.indices.contains(depth + 1) else { return }
                    var frame = plates[depth + 1]
                    let height = ActionMenuView.height(inner)
                    if inner.falls { frame.origin.y = frame.maxY - height }
                    frame.size.height = height
                    frame.size.width = inner.width
                    plates[depth + 1] = frame
                    relayout()
                }
            }
        }
    }

    /// The keyboard to the deepest search up; two passes, as a plate's field
    /// only stands in the window after the layout that follows `relayout`.
    private static func focusDeepest() {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                guard let panel, let content = panel.contentView else { return }
                func fields(_ view: NSView) -> [PickerSearch.Field] {
                    (view as? PickerSearch.Field).map { [$0] } ?? view.subviews.flatMap(fields)
                }
                guard let deepest = lists.last(where: \.searchVisible), let field = fields(content).last(where: {
                    $0.placeholderString == deepest.placeholder
                }), !field.isEditing(in: panel) else { return }
                panel.makeFirstResponder(field)
            }
        }
    }

    /// Hung under `view`, its left edge with the view's, as a menu under a
    /// button is; up over it where there is no room below.
    static func show(_ menu: NSMenu, under view: NSView, done: (() -> Void)? = nil) {
        guard let window = view.window else { done?(); return }
        let frame = window.convertToScreen(view.convert(view.bounds, to: nil))
        show(menu, in: window, at: NSPoint(x: frame.minX, y: frame.minY - 4), done: done)
    }

    static var isOpen: Bool { panel != nil }

    /// Whether a point on the screen is on a plate up.
    static func holds(_ point: NSPoint) -> Bool { plates.contains { $0.insetBy(dx: -6, dy: -6).contains(point) } }

    /// Whether words stand in a search: a menu a person is using stays.
    static var typed: Bool { lists.contains { !$0.query.isEmpty } }

    static func isOpen(in window: NSWindow) -> Bool { panel?.parent === window || dispatchWindow === window }

    static var parentWindow: NSWindow? { panel?.parent }

    /// The bench's look at the panel up: where it hangs, its search's
    /// place, its lines as shown, and the submenus open beside it.
    static func state() -> [String: Any] {
        guard let panel, let list else { return ["open": false] }
        var out = look(list, plate: plates[0], window: panel)
        out["falls"] = list.falls
        out["query"] = list.query
        out["room"] = room
        out["measuredWidth"] = list.width
        out["windowSize"] = [panel.frame.width, panel.frame.height]
        out["searchVisible"] = list.searchVisible
        out["option"] = list.option
        out["textSize"] = 13
        out["rowHeight"] = ActionMenuView.row
        out["insets"] = MenuMetrics.inset + ActionMenuView.pad
        out["keyStyle"] = "plain"
        out["searchHeight"] = ActionMenuView.search
        if let editor = panel.firstResponder as? NSTextView {
            out["searchSelection"] = [editor.selectedRange().location, editor.selectedRange().length]
        }
        out["children"] = zip(lists, plates).dropFirst().map { inner, plate -> [String: Any] in
            var one = look(inner, plate: plate, window: panel)
            one["focused"] = inner.focused
            one["query"] = inner.query
            return one
        }
        out["keys"] = ((panel.firstResponder as? NSText)?.delegate as? PickerSearch.Field)?.placeholderString ?? ""
        return out
    }

    private static func look(_ list: ActionMenuList, plate: NSRect, window: NSWindow) -> [String: Any] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return ["open": true, "spot": list.spot, "window": window.windowNumber,
                "frame": [plate.minX, top - plate.maxY, plate.width, plate.height],
                "lines": list.lines.map { line in
                    ["title": line.title, "keys": line.keys, "enabled": line.enabled, "checked": line.checked,
                     "wordFrame": list.wordFrames[line.id].map { [$0.minX, $0.minY, $0.width, $0.height] } ?? [],
                     "keyFrame": list.keyFrames[line.id].map { [$0.minX, $0.minY, $0.width, $0.height] } ?? [],
                     "rowFrame": list.frames[line.id].map { [$0.minX, $0.minY, $0.width, $0.height] } ?? [],
                     "image": line.image != nil,
                     "submenu": line.submenu != nil, "from": line.from ?? "", "boundary": line.boundary.map { "\($0)" } ?? ""] as [String: Any]
                }]
    }

    /// The bench's hand: words typed into the search, a line pointed at or
    /// taken by its title in the list that has the keys, a key.
    static func bench(type words: String?, point: String? = nil, take title: String?, key: String?, option: Bool? = nil, letters: String? = nil) {
        guard let list else { return }
        if let option, let panel,
           let event = NSEvent.keyEvent(with: .flagsChanged, location: .zero, modifierFlags: option ? .option : [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                       context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58) {
            panel.sendEvent(event)
        }
        if let letters, let panel,
           let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                                       context: nil, characters: letters, charactersIgnoringModifiers: letters,
                                       isARepeat: false, keyCode: ["s": 1, "l": 37, "e": 14][letters] ?? 0) {
            panel.sendEvent(event)
        }
        if let words { list.query = words }
        func find(_ name: String, in shown: ActionMenuList) -> Int? {
            shown.lines.firstIndex { $0.title == name || $0.title.hasSuffix("  " + name) }
        }
        if let point, let index = find(point, in: list.active) { list.active.point(index) }
        if let title, let index = find(title, in: list.active) { list.active.take(index) }
        switch key {
        case "down": list.active.move(1)
        case "up": list.active.move(-1)
        case "return": list.active.take()
        case "right": list.active.side(1)
        case "left": list.active.side(-1)
        case "esc": list.escape()
        default: break
        }
    }

    private static func key(_ event: NSEvent) -> Bool {
        guard let list else { return false }
        switch event.keyCode {
        case 125: list.active.move(1)
        case 126: list.active.move(-1)
        case 124: list.active.side(1)
        case 123: list.active.side(-1)
        case 36, 76: list.active.take()
        case 53: list.escape()
        default:
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  let typed = event.characters, typed.contains(where: \.isLetter) else { return false }
            list.query += typed
        }
        return true
    }

    static func close() {
        guard let panel else { return }
        self.panel = nil
        list?.cancelPendingHover()
        list?.closeChild()
        list = nil
        lists = []
        plates = []
        let window = panel.parent
        panel.closes = {}
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        window?.makeKey()
        let finish = done
        done = nil
        finish?()
        // The menu stays until its item has been performed, just after.
        DispatchQueue.main.async {
            if self.panel == nil {
                menu = nil
                layout.plates = []
            }
        }
    }
}
