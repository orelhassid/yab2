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
        case .submenu: true
        }
    }
}

struct RadialSubmenu: Equatable {
    var count = 6
    var commands: [Command] = [.forward, .downloads, .newTab, .back, .reload, .history,
                               .bookmarks, .tabOverview, .settings, .closeTab]

    var items: [RadialItem] { commands.prefix(count).map(RadialItem.command) }

    init() {}

    init?(encoded: Substring) {
        let fields = encoded.split(separator: ",")
        guard fields.count == commands.count + 1, let count = Int(fields[0]),
              RadialPreferences.counts.contains(count) else { return nil }
        let commands = fields.dropFirst().compactMap { Command(rawValue: String($0)) }
        guard commands.count == self.commands.count else { return nil }
        self.count = count
        self.commands = commands
    }

    var encoded: String {
        ([String(count)] + commands.map(\.rawValue)).joined(separator: ",")
    }
}

enum RadialPreferences {
    static let layoutKey = "mouse.radial.layout"
    static let slotsKey = "mouse.radial.commands"
    static let countKey = "mouse.radial.count"
    static let extraKey = "mouse.radial.extra"
    static let additionalKey = "mouse.radial.additional"
    static let sensitivityKey = "mouse.radial.sensitivity"
    static let counts = [6, 8, 10]
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

    static func validated(_ raw: String, count: Int) -> [RadialItem]? {
        let values = raw.components(separatedBy: "|")
        let items = values.compactMap(item)
        return values.count == count && items.count == count ? items : nil
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
        var basic = slots
        if basic.count == 10 {
            let second = basic.remove(at: 6)
            let first = basic.remove(at: 1)
            Store.settings.set(encode([first, second]), forKey: additionalKey)
        }
        if basic.count == 8 {
            let second = basic.remove(at: 6)
            let first = basic.remove(at: 2)
            Store.settings.set(encode([first, second]), forKey: extraKey)
        }
        Store.settings.set(encode(basic), forKey: slotsKey)
    }

    @MainActor static var saved: [RadialItem] {
        slots(Store.settings.string(forKey: slotsKey) ?? "", extra: Store.settings.string(forKey: extraKey) ?? "",
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
    @AppStorage(RadialPreferences.slotsKey, store: Store.settings) private var raw = ""
    @AppStorage(RadialPreferences.countKey, store: Store.settings) private var count = 6
    @AppStorage(RadialPreferences.extraKey, store: Store.settings) private var extra = ""
    @AppStorage(RadialPreferences.additionalKey, store: Store.settings) private var additional = ""
    @AppStorage(RadialPreferences.sensitivityKey, store: Store.settings) private var sensitivity = RadialPreferences.defaultSensitivity
    @State private var slot = 1

    var body: some View {
        let slots = RadialPreferences.slots(raw, extra: extra, additional: additional, count: count)
        Section("Radial menu") {
            Picker("Layout", selection: $layout) {
                Text("Wheel").tag("wheel")
                Text("Dropdown").tag("dropdown")
            }.pickerStyle(.segmented).settingsAnchor("radial-layout")
            RadialCommandCount(count: $count).settingsAnchor("radial-count")
                .onChange(of: count) { _, _ in slot = min(slot, slots.count - 1) }
            SettingsRow("Activation distance") {
                Slider(value: Binding(get: { Double(sensitivity) }, set: { sensitivity = Int($0) }),
                       in: Double(RadialPreferences.sensitivityRange.lowerBound)...Double(RadialPreferences.sensitivityRange.upperBound),
                       step: 1)
                    .frame(maxWidth: 140)
                    .accessibilityLabel("Activation distance")
                Text("\(sensitivity) pt").monospacedDigit()
            }.settingsAnchor("radial-sensitivity")
            RadialCommandEditor(browser: browser, layout: layout, slots: slots, slot: $slot, allowsSubmenu: true) {
                save($0, at: slot, in: slots)
            }.settingsAnchor("radial-commands")
        }

        // Each assigned submenu keeps its own commands as the main selection changes.
        ForEach(slots.indices, id: \.self) { index in
            if case .submenu(let submenu) = slots[index] {
                RadialSubmenuSettings(browser: browser, layout: layout, submenu: submenu,
                                      title: "Submenu (Command \(index + 1))") {
                    save(.submenu($0), at: index, in: slots)
                }
            }
        }
    }

    private func save(_ item: RadialItem, at index: Int, in slots: [RadialItem]) {
        var updated = slots
        updated[min(index, slots.count - 1)] = item
        RadialPreferences.save(updated)
    }
}

private struct RadialCommandCount: View {
    @Binding var count: Int

    var body: some View {
        Picker("Commands", selection: $count) {
            ForEach(RadialPreferences.counts, id: \.self) { count in Text(String(count)).tag(count) }
        }.pickerStyle(.segmented)
    }
}

private struct RadialSubmenuSettings: View {
    let browser: Browser
    let layout: String
    let submenu: RadialSubmenu
    let title: String
    let save: (RadialSubmenu) -> Void
    @State private var slot = 0

    var body: some View {
        Section(title) {
            RadialCommandCount(count: Binding(get: { submenu.count }, set: { count in
                var updated = submenu
                updated.count = count
                slot = min(slot, count - 1)
                save(updated)
            }))
            RadialCommandEditor(browser: browser, layout: layout, slots: submenu.items, slot: $slot) { item in
                guard case .command(let command) = item else { return }
                var updated = submenu
                updated.commands[min(slot, submenu.count - 1)] = command
                save(updated)
            }
        }
    }
}

private struct RadialCommandEditor: View {
    let browser: Browser
    let layout: String
    let slots: [RadialItem]
    @Binding var slot: Int
    var allowsSubmenu = false
    let choose: (RadialItem) -> Void
    @State private var search = ""
    private static let commands = Command.allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        .map(RadialItem.command)

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack { preview; Divider(); editor.frame(minWidth: 180) }
            VStack { preview; editor }
        }
    }

    private func selectSlot(_ index: Int) {
        slot = index
        search = ""
    }

    @ViewBuilder private var preview: some View {
        if layout == "dropdown" {
            RadialDropdown(rows: RadialDropdownRow.commands(slots, browser: browser, editing: true),
                           paint: SpacePaint(browser.prefs), selected: slot, choose: selectSlot)
                .frame(width: RadialDropdown.width)
        } else {
            RadialMenu(paint: SpacePaint(browser.prefs), select: selectSlot, rows: [],
                       available: slots.map { _ in true }, selection: RadialSelection(wedge: min(slot, slots.count - 1), slots: slots))
                .scaleEffect(0.79).frame(width: 224, height: 224)
        }
    }

    private func isSelected(_ item: RadialItem, current: RadialItem) -> Bool {
        if case .submenu = item, case .submenu = current { return true }
        return item == current
    }

    private var editor: some View {
        let current = slots[min(slot, slots.count - 1)]
        let special: [RadialItem] = allowsSubmenu ? [.spaces, .submenu(RadialSubmenu())] : []
        let choices = (special + Self.commands).filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
        return VStack(alignment: .leading, spacing: 8) {
            Text(current.title).font(.headline)
            ThemedSearchField("Find a command", text: $search)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(choices.indices, id: \.self) { index in
                        let item = choices[index]
                        let selected = isSelected(item, current: current)
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
