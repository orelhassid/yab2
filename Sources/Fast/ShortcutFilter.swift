import AppKit
import Combine

/// Values used by Shortcuts' search and menu. Filtering never records keys
/// or changes which commands are enabled.
@MainActor
enum ShortcutFilter {
    @MainActor
    final class Selection: ObservableObject {
        @Published var search = ""
        /// Rows in any of these states; none is every row.
        @Published var modifications: Set<Modification> = []
        /// Rows in any of these sections; none is every section.
        @Published var chosen: Set<String> = []
        @Published var categories: [String] = []
        /// How many rows each state and section has, for the list's numbers.
        @Published var counts = Counts()

        func clear() {
            search = ""
            modifications = []
            chosen = []
        }
    }

    struct Counts: Equatable {
        var modifications: [Modification: Int] = [:]
        var categories: [String: Int] = [:]
        /// The sections an extension's commands are in, by extension.
        var extensions: [String: String] = [:]
    }

    /// Only the values that affect this inventory wake its filters.
    @MainActor
    final class Changes: ObservableObject {
        private var following: AnyCancellable?

        init() {
            var signals = Shortcut.Action.allCases.map { Keymap.shared.slot($0).objectWillChange.eraseToAnyPublisher() }
            signals += CommandHotkeys.commands.map { Keymap.shared.slot(for: $0).objectWillChange.eraseToAnyPublisher() }
            if #available(macOS 15.4, *) {
                signals.append(ExtensionsHere.shared.objectWillChange.eraseToAnyPublisher())
            }
            following = Publishers.MergeMany(signals)
                .debounce(for: .milliseconds(10), scheduler: RunLoop.main)
                .sink { [weak self] _ in self?.objectWillChange.send() }
        }
    }

    enum Modification: String, CaseIterable {
        case set, conflict, alias, enabled, disabled, changed

        var title: String {
            switch self {
            case .set: "Hotkey Set"
            case .conflict: "Hotkey Conflict"
            case .alias: "Alias Set"
            case .enabled: "Enabled"
            case .disabled: "Disabled"
            case .changed: "Changed from Default"
            }
        }

        var icon: String {
            switch self {
            case .set: "keyboard"
            case .conflict: "exclamationmark.triangle"
            case .alias: "character.cursor.ibeam"
            case .enabled: "checkmark.circle"
            case .disabled: "nosign"
            case .changed: "arrow.uturn.backward"
            }
        }

        func holds(_ entry: Entry, clashes: Set<String>) -> Bool {
            switch self {
            case .set: !entry.keys.isEmpty || !entry.caps.isEmpty
            case .conflict: clashes.contains(entry.id)
            case .alias: !entry.alias.isEmpty
            case .enabled: entry.enabled
            case .disabled: !entry.enabled
            case .changed: entry.changed
            }
        }
    }

    /// A section's icon in the list: the one its commands are about.
    static func icon(_ category: String) -> String {
        switch category {
        case "Tabs": "browser.tabs"
        case "Calls": "phone"
        case "Address": "address.bar"
        case "Page": "doc.text"
        case "Window": "macwindow"
        case "Notes": "notes"
        case "Field": "magnifyingglass"
        case "Answer": "sparkles"
        case "Field Answer": "bubble.sparkle"
        case "Selection": "cursor"
        case "Capture": "capture.screen"
        case "Chat": "bubble"
        case "Other Windows": "macwindow.on.rectangle"
        case "Page Copy": "doc.on.doc"
        case "Snippets": "quote.bubble"
        case "Mail": "envelope"
        case "Mail Formatting": "yab.bold"
        default: "command"
        }
    }

    struct Entry {
        let id: String
        let category: String
        let name: String
        var alias = ""
        var keys: [Hotkey] = []
        var caps: [[String]] = []
        var changed = false
        var enabled = true
        var action: Shortcut.Action? = nil
        var browser = true
        var global = false
        /// The extension the command is from.
        var fromExtension: String? = nil
    }

    static func counts(_ entries: [Entry]) -> Counts {
        let clashes = conflicts(entries)
        var counts = Counts()
        for value in Modification.allCases {
            counts.modifications[value] = entries.filter { value.holds($0, clashes: clashes) }.count
        }
        for entry in entries {
            counts.categories[entry.category, default: 0] += 1
            if let id = entry.fromExtension { counts.extensions[entry.category] = id }
        }
        return counts
    }

    static func categories(_ entries: [Entry]) -> [String] {
        var seen = Set<String>()
        let titles = entries.map(\.category).filter { seen.insert($0).inserted }
        return titles.filter { !$0.hasPrefix("Mail") } + titles.filter { $0.hasPrefix("Mail") }
    }

    @MainActor static func catalog(groups: [Shortcut.Group], snippets: [MailSnippet]) -> [Entry] {
        var entries = groups.flatMap { group in
            group.items.map { item in
                let keys = item.action.flatMap { Keymap.shared.keys($0) }.map { [$0] } ?? item.holds
                return Entry(id: item.id, category: group.title, name: item.does, keys: keys,
                             caps: item.action == nil ? item.fixed : keys.map(\.caps),
                             changed: item.action.map { !Keymap.shared.isDefault($0) } ?? false,
                             action: item.action, browser: !group.title.hasPrefix("Mail"))
            }
        }
        entries += CommandHotkeys.commands.map { command in
            let keys = Keymap.shared.keys(for: command).map { [$0] } ?? []
            return Entry(id: command.shortcutID, category: "Commands", name: command.shortcutTitle,
                         alias: CommandHotkeys.variants(of: command).flatMap(\.searchNames).joined(separator: " "),
                         keys: keys, caps: keys.map(\.caps), changed: !Keymap.shared.isDefault(command: command))
        }
        entries += snippets.filter { !$0.hotkey.isEmpty }.map {
            let keys = Hotkey(stored: $0.hotkey).map { [$0] } ?? []
            return Entry(id: "snippet." + $0.id, category: "Snippets", name: $0.name,
                         alias: ";" + $0.name, keys: keys, caps: keys.map(\.caps), changed: true, global: true)
        }
        if #available(macOS 15.4, *) {
            for group in Extensions.here.commandGroups() {
                let saved = Store.settings.dictionary(forKey: "extensions.keys." + group.item.id) ?? [:]
                entries += group.commands.map { entry in
                    let keys = entry.keys.map { [$0] } ?? []
                    return Entry(id: "ext." + entry.id, category: group.short, name: entry.title,
                                 alias: entry.kept.alias, keys: keys, caps: keys.map(\.caps),
                                 changed: saved[entry.command] != nil || entry.kept != .init(), enabled: !entry.kept.off,
                                 fromExtension: group.item.id)
                }
            }
        }
        return entries
    }

    /// Conflict is computed against the whole inventory before category or
    /// search filtering, and respects the keymap's intentional context reuse.
    static func conflicts(_ entries: [Entry]) -> Set<String> {
        var result = Set<String>()
        let active = entries.filter { $0.enabled && !$0.keys.isEmpty }
        for (index, first) in active.enumerated() {
            for second in active.dropFirst(index + 1) {
                let overlap = first.keys.contains { a in second.keys.contains { b in
                    guard Keymap.keysOverlap(a, b) else { return false }
                    if first.global || second.global { return true }
                    if let x = first.action, let y = second.action { return Keymap.conflicts(x, a, y, b) }
                    if let x = first.action { return second.browser && Keymap.conflicts(x, a, .duplicate, b) }
                    if let y = second.action { return first.browser && Keymap.conflicts(.duplicate, a, y, b) }
                    return first.browser == second.browser
                } }
                if overlap { result.insert(first.id); result.insert(second.id) }
            }
        }
        return result
    }

    /// Any of the states and any of the sections, both at once; an empty
    /// set lets every row through.
    static func visible(_ entries: [Entry], search: String, modifications: Set<Modification> = [],
                        categories: Set<String> = []) -> [Entry] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let keys = Hotkey.typed(needle)?.lowercased()
        let clashes = modifications.contains(.conflict) ? conflicts(entries) : []
        return entries.filter { entry in
            guard categories.isEmpty || categories.contains(entry.category) else { return false }
            guard modifications.isEmpty || modifications.contains(where: { $0.holds(entry, clashes: clashes) }) else { return false }
            guard !needle.isEmpty else { return true }
            if let keys { return ShortcutsPage.keysMatch(entry.caps, keys, whole: Hotkey.isWhole(keys)) }
            return ShortcutsPage.says(entry.name + " " + entry.alias + " " + entry.category, needle)
                || entry.caps.contains { $0.joined().lowercased() == needle }
        }
    }
}

/// Shortcuts' search and its filters, both real toolbar items (ToolbarSearch
/// says why).
@MainActor
final class ShortcutFilterToolbar: NSObject, NSMenuDelegate {
    static let searchID = NSToolbarItem.Identifier("SearchSettingsShortcutSearch")
    static let filterID = NSToolbarItem.Identifier("SearchSettingsShortcutFilters")
    static var identifiers: [NSToolbarItem.Identifier] { [searchID, filterID] }

    private let selection: ShortcutFilter.Selection
    private weak var toolbar: NSToolbar?
    private weak var window: NSWindow?
    private let search: ToolbarSearch
    private var filters: NSMenuToolbarItem?
    private var following: AnyCancellable?
    nonisolated(unsafe) private var keys: Any?

    init(selection: ShortcutFilter.Selection, window: NSWindow) {
        self.selection = selection
        self.window = window
        search = ToolbarSearch(id: Self.searchID, label: "Search shortcuts", prompt: "Search by name or alias", window: window,
                               words: { selection.search }, typed: { selection.search = $0 })
        super.init()
        following = selection.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.sync() }
        }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.searchPressed(event) == true ? nil : event
        }
    }

    deinit { if let keys { NSEvent.removeMonitor(keys) } }

    /// Editing keys the field keeps; any other press with ⌘, ⌥ or ⌃
    /// while it is focused becomes the query, so ⌘T finds what ⌘T does.
    private static let editing: Set<String> = ["⌘A", "⌘C", "⌘V", "⌘X", "⌘Z", "⇧⌘Z", "⌘⌫", "⌥⌫", "⌃⌫"]

    func searchPressed(_ event: NSEvent) -> Bool {
        guard !Keymap.shared.recording,
              let field = search.field, field.currentEditor() != nil, event.window === window,
              let key = Hotkey(event), !key.flags.intersection([.command, .option, .control]).isEmpty,
              !["←", "→", "↑", "↓", "home", "end"].contains(key.key), !Self.editing.contains(key.text) else { return false }
        field.stringValue = key.text
        field.currentEditor()?.selectedRange = NSRange(location: (key.text as NSString).length, length: 0)
        selection.search = key.text
        return true
    }

    func attach(to toolbar: NSToolbar, visible: Bool) {
        self.toolbar = toolbar
        search.attach(to: toolbar)
        toolbar.keep(Self.identifiers, shown: visible)
        if !visible { search.detach(); filters = nil }
        else { sync() }
    }

    func item(for id: NSToolbarItem.Identifier) -> NSToolbarItem? {
        if id == Self.searchID { return search.item() }
        if id == Self.filterID {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Shortcut filters"
            item.toolTip = "Shortcut filters" // design: native toolbar items have no custom view for keyTip.
            item.isBordered = true
            item.showsIndicator = true
            item.autovalidates = false
            item.visibilityPriority = .high
            // The system's button and glass, our list: the menu only says
            // when the button was pressed, and puts itself away unseen.
            let menu = NSMenu()
            menu.addItem(withTitle: "Filters", action: nil, keyEquivalent: "")
            menu.delegate = self
            item.menu = menu
            filters = item
            sync()
            return item
        }
        return nil
    }

    /// What is on, states first, in the list's order.
    private var active: [(title: String, icon: String)] {
        ShortcutFilter.Modification.allCases.filter(selection.modifications.contains).map { ($0.title, $0.icon) }
            + selection.categories.filter(selection.chosen.contains).map { ($0, ShortcutFilter.icon($0)) }
    }

    private var filterTitle: String {
        let active = active
        return active.count > 1 ? "\(active.count) Filters" : active.first?.title ?? "Filters"
    }

    private func sync() {
        search.sync()
        filters?.title = filterTitle
        let active = active
        filters?.image = Glyphs.image(active.count == 1 ? active[0].icon : "line.3.horizontal.decrease", side: 14)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menu.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async { [weak self] in self?.openList() }
    }

    /// Raycast's filter list: a search, then the states and the sections
    /// in parts, each row with a box, its icon and how many rows it has.
    /// Boxes tick in place and the list stays until Esc or a press beside.
    private func openList() {
        guard let button = menuButton(in: window?.contentView?.superview) else { return }
        openList(under: button)
    }

    func openList(under button: NSButton) {
        guard button.window != nil, !DropPopup.closed(from: button) else { return }
        let counts = selection.counts
        let mods = ShortcutFilter.Modification.allCases
        var lines = mods.enumerated().map { index, value in
            DropList.Line(title: value.title, picture: Glyphs.image(value.icon, side: 16),
                          head: index == 0 ? "Modifications" : nil, checked: selection.modifications.contains(value),
                          count: counts.modifications[value] ?? 0, warns: value == .conflict)
        }
        let all = selection.categories
        let parts: [(String, [String])] = [
            ("Browser", all.filter { !$0.hasPrefix("Mail") && $0 != "Snippets" && counts.extensions[$0] == nil }),
            ("Mail", all.filter { $0.hasPrefix("Mail") || $0 == "Snippets" }),
            ("Extensions", all.filter { counts.extensions[$0] != nil }),
        ]
        var titles: [String] = []
        for (head, titlesInPart) in parts {
            for (index, title) in titlesInPart.enumerated() {
                var picture = Glyphs.image(ShortcutFilter.icon(title), side: 16)
                if #available(macOS 15.4, *), let id = counts.extensions[title],
                   let icon = Extensions.here.icon(for: id, side: 16)?.copy() as? NSImage {
                    // The loader's resolution hint doesn't set the image's logical size.
                    icon.size = NSSize(width: 16, height: 16)
                    picture = icon
                }
                lines.append(DropList.Line(title: title, picture: picture, head: index == 0 ? head : nil,
                                           checked: selection.chosen.contains(title), count: counts.categories[title] ?? 0))
                titles.append(title)
            }
        }
        let list = DropList(options: lines, chosen: 0, divideBefore: nil, inset: 8, searchWords: "Search\u{2026}",
                            alwaysSearch: true, tallest: 520)
        list.ticked = { [selection] on in
            selection.modifications = Set(on.filter { $0 < mods.count }.map { mods[$0] })
            selection.chosen = Set(on.filter { $0 >= mods.count }.map { titles[$0 - mods.count] })
        }
        DropPopup.show(list, under: button, width: 300, trailing: true) { _ in }
    }

    @discardableResult
    func beginSearch() -> NSSearchField? { search.begin() }

    /// Press the system-created button in probes, through its own action.
    var state: [String: Any] {
        var result: [String: Any] = ["title": filterTitle, "searching": search.searching,
         "nativeMenu": filters != nil && filters?.view == nil,
         "bordered": filters?.isBordered == true, "filterVisible": filters?.isVisible == true,
         "noFocusRing": search.field?.focusRingType == NSFocusRingType.none,
         "focused": search.field?.currentEditor() != nil,
         "fieldAttached": search.field?.window != nil, "query": selection.search]
        result["trailingItem"] = toolbar?.items.last?.itemIdentifier.rawValue
        result["filterIconWidth"] = filters?.image?.size.width
        if let frame = window?.contentView?.superview, let button = menuButton(in: frame) {
            result["trailingGap"] = frame.bounds.maxX - button.convert(button.bounds, to: frame).maxX
            // The glass stands just before the filters, for a real press in a probe.
            if let window {
                let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
                result["glassX"] = rect.minX - 22
                result["glassY"] = (NSScreen.screens.first?.frame.maxY ?? 0) - rect.midY
            }
        }
        if #available(macOS 26.0, *) {
            result["automaticGlassColor"] = filters?.backgroundTintColor == nil
        }
        return result
    }

    func menuButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton,
           button.title == filterTitle || button.toolTip == "Shortcut filters" || button.accessibilityLabel() == "Shortcut filters" { // design: probes locate AppKit's generated toolbar button by its native label.
            return button
        }
        return view.subviews.lazy.compactMap { self.menuButton(in: $0) }.first
    }
}
