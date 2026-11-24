import SwiftUI

enum RadialItem: Equatable {
    case command(Command)
    case spaces
    case submenu(RadialSubmenu)

    var title: String {
        switch self {
        case .command(let command): command.title
        case .spaces: "Spaces"
        case .submenu: "Submenu"
        }
    }

    var hasChildren: Bool {
        if case .command = self { return false }
        return true
    }

    var icon: String {
        switch self {
        case .command(let command): command.symbol
        case .spaces: "square.stack.3d.up"
        case .submenu: "list.bullet"
        }
    }

    @MainActor func available(in browser: Browser) -> Bool {
        switch self {
        case .command(let command): command.available(in: browser)
        case .spaces: browser.spacesShown && !browser.spaces.isEmpty
        case .submenu(let menu): !menu.commands.isEmpty
        }
    }
}

struct RadialSubmenu: Equatable {
    var commands: [Command] = [.forward, .downloads, .newTab, .back, .reload, .history]

    var items: [RadialItem] { commands.map(RadialItem.command) }

    init() {}

    init?(encoded: Substring) {
        let fields = encoded.split(separator: ",", omittingEmptySubsequences: false)
        guard let first = fields.first, let count = Int(first),
              RadialPreferences.itemCounts.contains(count),
              fields.count == count + 1 || fields.count == 11 else { return nil }
        let commands = fields.dropFirst().compactMap { Command(rawValue: String($0)) }
        guard commands.count == fields.count - 1 else { return nil }
        self.commands = Array(commands.prefix(count))
    }

    var encoded: String {
        ([String(commands.count)] + commands.map(\.rawValue)).joined(separator: ",")
    }
}

enum RadialPreferences {
    static let layoutKey = "mouse.radial.layout"
    static let slotsKey = "mouse.radial.commands"
    static let countKey = "mouse.radial.count"
    static let extraKey = "mouse.radial.extra"
    static let additionalKey = "mouse.radial.additional"
    static let sensitivityKey = "mouse.radial.sensitivity"
    static let itemsKey = "mouse.radial.items"
    static let itemCounts = 0...10
    static let sensitivityRange = 8...64
    static let defaultSensitivity = 8
    static let extraDefaults: [RadialItem] = [.command(.bookmarks), .command(.history)]
    static let additionalDefaults: [RadialItem] = [.command(.settings), .command(.tabOverview)]
    static let spacesID = "radial.spaces"
    static let submenuID = "radial.menu"

    private static func item(_ value: String) -> RadialItem? {
        if value == spacesID { return .spaces }
        if value == submenuID { return .submenu(RadialSubmenu()) }
        if value.hasPrefix(submenuID + ":"),
           let submenu = RadialSubmenu(encoded: value.dropFirst(submenuID.count + 1)) { return .submenu(submenu) }
        return Command(rawValue: value).map(RadialItem.command)
    }

    static func validated(_ raw: String) -> [RadialItem]? {
        if raw.isEmpty { return [] }
        let values = raw.components(separatedBy: "|")
        let items = values.compactMap(item)
        return itemCounts.contains(values.count) && items.count == values.count ? items : nil
    }

    static func decode(_ raw: String, defaults: [RadialItem] = RadialSelection.commands) -> [RadialItem] {
        let values = raw.components(separatedBy: "|")
        guard values.count == defaults.count else { return defaults }
        return zip(values, defaults).map { item($0.0) ?? $0.1 }
    }

    static func encode(_ slots: [RadialItem]) -> String {
        slots.map {
            switch $0 {
            case .command(let command): command.rawValue
            case .spaces: spacesID
            case .submenu(let submenu): submenuID + ":" + submenu.encoded
            }
        }.joined(separator: "|")
    }

    static func slots(_ raw: String, extra: String, additional: String = "", count: Int) -> [RadialItem] {
        var result = decode(raw)
        if count == 8 || count == 10 {
            let additions = decode(extra, defaults: extraDefaults)
            result.insert(additions[0], at: 2)
            result.insert(additions[1], at: 6)
        }
        if count == 10 {
            let additions = decode(additional, defaults: additionalDefaults)
            result.insert(additions[0], at: 1)
            result.insert(additions[1], at: 6)
        }
        return result
    }

    @MainActor static func save(_ slots: [RadialItem]) {
        Store.settings.set(encode(slots), forKey: itemsKey)
    }

    @MainActor static var saved: [RadialItem] {
        if let raw = Store.settings.string(forKey: itemsKey), let items = validated(raw) { return items }
        return slots(Store.settings.string(forKey: slotsKey) ?? "", extra: Store.settings.string(forKey: extraKey) ?? "",
                     additional: Store.settings.string(forKey: additionalKey) ?? "", count: Store.settings.integer(forKey: countKey))
    }

    @MainActor static var sensitivity: CGFloat {
        let value = Store.settings.object(forKey: sensitivityKey) as? Int ?? defaultSensitivity
        return CGFloat(min(sensitivityRange.upperBound, max(sensitivityRange.lowerBound, value)))
    }

    @MainActor static func run(_ command: Command, in browser: Browser) {
        guard command.available(in: browser) else { return }
        if command == .downloads { browser.showLibrary(.downloads) }
        else { command.run(in: browser) }
    }
}

struct RadialSettings: View {
    @ObservedObject var browser: Browser
    @AppStorage(RadialPreferences.layoutKey, store: Store.settings) private var layout = "wheel"
    @AppStorage(RadialPreferences.itemsKey, store: Store.settings) private var raw: String?
    @AppStorage(RadialPreferences.sensitivityKey, store: Store.settings) private var sensitivity = RadialPreferences.defaultSensitivity

    var body: some View {
        let slots = raw.flatMap(RadialPreferences.validated) ?? RadialPreferences.saved
        Section("Radial menu") {
            Picker("Layout", selection: $layout) {
                Text("Wheel").tag("wheel")
                Text("Dropdown").tag("dropdown")
            }.pickerStyle(.segmented).settingsAnchor("radial-layout")
            SettingsRow("Activation distance") {
                Slider(value: Binding(get: { Double(sensitivity) }, set: { sensitivity = Int($0) }),
                       in: Double(RadialPreferences.sensitivityRange.lowerBound)...Double(RadialPreferences.sensitivityRange.upperBound),
                       step: 1)
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Activation distance")
                Text("\(sensitivity) pt").monospacedDigit()
            }.settingsAnchor("radial-sensitivity")
            RadialCommandEditor(browser: browser, layout: layout, slots: slots, allowsSubmenu: true) {
                raw = RadialPreferences.encode($0)
            }.settingsAnchor("radial-commands")
        }

        ForEach(slots.indices, id: \.self) { index in
            if case .submenu(let submenu) = slots[index] {
                Section("Submenu (Command \(index + 1))") {
                    RadialCommandEditor(browser: browser, layout: layout, slots: submenu.items) { items in
                        var updated = slots
                        var submenu = submenu
                        submenu.commands = items.compactMap {
                            if case .command(let command) = $0 { return command }
                            return nil
                        }
                        updated[index] = .submenu(submenu)
                        raw = RadialPreferences.encode(updated)
                    }
                }
            }
        }
    }
}

private struct RadialCommandEditor: View {
    let browser: Browser
    let layout: String
    let slots: [RadialItem]
    @State private var slot: Int? = 0
    var allowsSubmenu = false
    let save: ([RadialItem]) -> Void
    @State private var search = ""
    private static let commands = Command.allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(RadialItem.command)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top) { list.frame(width: RadialDropdown.width); Divider(); editor.frame(minWidth: 180) }
            VStack { list; editor }
        }
    }

    private var selected: Int? {
        slot.flatMap { slots.isEmpty ? nil : min($0, slots.count - 1) }
    }

    private func selectSlot(_ index: Int?) {
        slot = index
        search = ""
    }

    private var list: some View {
        VStack(spacing: 0) {
            Quiet(icon: "plus", title: "New Item", lit: selected == nil, prefs: browser.prefs) {
                selectSlot(nil)
            }
            .disabled(!canAdd)
            ForEach(slots.indices, id: \.self) { index in
                let item = slots[index]
                SidebarTabButton(title: item.title, selected: selected == index, prefs: browser.prefs,
                                 remove: { remove(index) }, action: { selectSlot(index) }) {
                    Symbol(item.icon, size: 13)
                }
            }
            if layout == "wheel", !slots.isEmpty {
                RadialMenu(paint: SpacePaint(browser.prefs), select: { selectSlot($0) }, rows: [],
                           available: slots.map { _ in true }, selection: RadialSelection(wedge: selected, slots: slots))
                    .scaleEffect(0.48).frame(width: 176, height: 176)
            }
        }
    }

    private var canAdd: Bool { slots.count < RadialPreferences.itemCounts.upperBound }

    private func remove(_ index: Int) {
        var updated = slots
        updated.remove(at: index)
        if let selected {
            selectSlot(updated.isEmpty ? nil : min(selected > index ? selected - 1 : selected, updated.count - 1))
        }
        save(updated)
    }

    private func choose(_ item: RadialItem) {
        var updated = slots
        if let selected {
            updated[selected] = item
        } else {
            guard canAdd else { return }
            selectSlot(updated.count)
            updated.append(item)
        }
        save(updated)
    }

    private func isSelected(_ item: RadialItem, current: RadialItem) -> Bool {
        if case .submenu = item, case .submenu = current { return true }
        return item == current
    }

    private var editor: some View {
        let current = selected.map { slots[$0] }
        let special: [RadialItem] = allowsSubmenu ? [.spaces, .submenu(RadialSubmenu())] : []
        let choices = (special + Self.commands).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(current?.title ?? "New Item").font(.headline)
            ThemedSearchField("Find a command", text: $search)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(choices.indices, id: \.self) { index in
                        let item = choices[index]
                        let selected = current.map { isSelected(item, current: $0) } ?? false
                        Button {
                            if !selected { choose(item) }
                        } label: {
                            HStack {
                                Symbol(item.icon, size: 13)
                                Text(item.title)
                                Spacer()
                                if selected { Image(systemName: "checkmark") }
                            }.padding(4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 252)
        }
    }
}
