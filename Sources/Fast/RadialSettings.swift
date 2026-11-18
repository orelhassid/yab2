import SwiftUI

enum RadialPreferences {
    static let layoutKey = "mouse.radial.layout"
    static let slotsKey = "mouse.radial.commands"
    static let countKey = "mouse.radial.count"
    static let extraKey = "mouse.radial.extra"
    static let extraDefaults: [Command?] = [.bookmarks, .history]
    static let spacesID = "radial.spaces"
    static func decode(_ raw: String, defaults: [Command?] = RadialSelection.commands) -> [Command?] {
        let values = raw.components(separatedBy: "|")
        guard values.count == defaults.count else { return defaults }
        return values.enumerated().map { i, value in
            if value == spacesID { return nil }
            return Command(rawValue: value) ?? defaults[i]
        }
    }
    static func encode(_ slots: [Command?]) -> String {
        slots.map { $0?.rawValue ?? spacesID }.joined(separator: "|")
    }
    static func slots(_ raw: String, extra: String, count: Int) -> [Command?] {
        var result = decode(raw)
        if count == 8 {
            let additions = decode(extra, defaults: extraDefaults)
            result.insert(additions[0], at: 2)
            result.insert(additions[1], at: 6)
        }
        return result
    }

    @MainActor static func save(_ slots: [Command?]) {
        var basic = slots
        if basic.count == 8 {
            let second = basic.remove(at: 6)
            let first = basic.remove(at: 2)
            Store.settings.set(encode([first, second]), forKey: extraKey)
        }
        Store.settings.set(encode(basic), forKey: slotsKey)
    }

    @MainActor static var saved: [Command?] {
        slots(Store.settings.string(forKey: slotsKey) ?? "", extra: Store.settings.string(forKey: extraKey) ?? "",
              count: Store.settings.integer(forKey: countKey))
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
    @State private var slot = 1
    @State private var search = ""
    private static let choices: [Command?] = [nil] + Command.allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    var body: some View {
        let slots = RadialPreferences.slots(raw, extra: extra, count: count)
        Section("Radial menu") {
            Picker("Layout", selection: $layout) {
                Text("Wheel").tag("wheel")
                Text("Dropdown").tag("dropdown")
            }.pickerStyle(.segmented).settingsAnchor("radial-layout")
            Picker("Commands", selection: $count) {
                Text("6").tag(6)
                Text("8").tag(8)
            }.pickerStyle(.segmented).settingsAnchor("radial-count")
            .onChange(of: count) { _, _ in selectSlot(0) }
            ViewThatFits(in: .horizontal) {
                HStack { preview(slots); Divider(); editor(slots).frame(minWidth: 180) }
                VStack { preview(slots); editor(slots) }
            }.settingsAnchor("radial-commands")
        }
    }
    private func selectSlot(_ index: Int) {
        slot = index
        search = ""
    }
    @ViewBuilder private func preview(_ slots: [Command?]) -> some View {
        if layout == "dropdown" {
            RadialDropdown(rows: RadialDropdownRow.commands(slots, browser: browser, editing: true),
                           paint: SpacePaint(browser.prefs), selected: slot, choose: selectSlot)
                .frame(width: RadialDropdown.width)
        } else {
            wheel(slots)
        }
    }
    private func wheel(_ slots: [Command?]) -> some View {
        RadialMenu(paint: SpacePaint(browser.prefs), select: selectSlot,
                   spaces: [], available: slots.map { _ in true }, selection: RadialSelection(wedge: min(slot, slots.count - 1), slots: slots))
            .scaleEffect(0.79).frame(width: 224, height: 224)
    }
    private func editor(_ slots: [Command?]) -> some View {
        let slot = min(self.slot, slots.count - 1)
        return VStack(alignment: .leading, spacing: 8) {
            Text(slots[slot]?.title ?? "Spaces").font(.headline)
            ThemedSearchField("Find a command", text: $search)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Self.choices.filter { search.isEmpty || ($0?.title ?? "Spaces").localizedCaseInsensitiveContains(search) }, id: \.self) { command in
                        Button {
                            var updated = slots
                            updated[slot] = command
                            RadialPreferences.save(updated)
                        } label: {
                            HStack {
                                Symbol(command?.symbol ?? "square.stack.3d.up", size: 13)
                                Text(command?.title ?? "Spaces")
                                Spacer()
                                if slots[slot] == command { Image(systemName: "checkmark") }
                            }.padding(4).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }.frame(height: 252)
        }
    }
}
