import SwiftUI

struct CollectionRuleMenu: View {
    let kind: CollectionRuleKind
    let collection: PageCollection
    @Binding var view: CollectionTableView
    @GestureState private var held: UUID?
    @GestureState private var travel: CGFloat = 0
    @State private var open = false
    @State private var choosing = false
    @State private var customRule: UUID?
    @State private var customValue = ""
    @State private var search = ""
    @Environment(\.tone) private var tone

    private var rules: [CollectionFilter] {
        get { view.rules(for: kind) }
        nonmutating set { view.setRules(newValue, for: kind) }
    }

    private var available: [CollectionProperty] {
        collection.properties.filter { property in !rules.contains { $0.property == property.id } }
    }

    private func values(_ key: String) -> [String] {
        guard kind == .filter else { return ["Ascending", "Descending"] }
        let stored = collection.entries.map { $0.values[key] ?? "" }
        return Set(stored + rules.filter { $0.property == key }.map(\.value) + [""]).sorted()
    }

    private func displacement(_ id: UUID, index: Int) -> CGFloat {
        guard let held, let source = rules.firstIndex(where: { $0.id == held }) else { return 0 }
        if held == id { return travel }
        let target = max(0, min(rules.count - 1, source + Int((travel / 38).rounded())))
        return ColumnHand.shift(index, from: source, to: target, rows: nil, step: 38)
    }

    private func move(_ id: UUID, by distance: Int) {
        var next = rules
        guard let index = next.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(next.count - 1, index + distance))
        guard index != target else { return }
        next.insert(next.remove(at: index), at: target)
        withAnimation(Motion.quick) { rules = next }
    }

    private func field(_ rule: CollectionFilter, key: Bool) -> Binding<String> {
        Binding(get: {
            let current = rules.first { $0.id == rule.id } ?? rule
            return key ? current.property : current.value
        }, set: { value in
            var next = rules
            guard let i = next.firstIndex(where: { $0.id == rule.id }) else { return }
            if key {
                next[i].property = value
                if kind == .filter { next[i].value = values(value).first ?? "" }
            } else { next[i].value = value }
            rules = next
        })
    }

    var body: some View {
        let first = rules.first.flatMap { rule in collection.properties.first { $0.id == rule.property }?.title }
        let title = first.map { kind.rawValue + " · " + $0 + (rules.count > 1 ? " +\(rules.count - 1)" : "") } ?? kind.rawValue
        PageActionButton(title: title, icon: kind.icon, state: rules.isEmpty && !open ? .ready : .active) { open.toggle() }
        .accessibilityLabel(kind.rawValue + " rules")
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                    let name = collection.properties.first { $0.id == rule.property }?.title ?? rule.property
                    HStack(spacing: 6) {
                        Symbol("circle.grid.2x3.fill", size: 10).foregroundStyle(Palette.muted)
                            .frame(width: 20, height: 32).contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .global)
                                .updating($held) { _, key, _ in key = rule.id }
                                .updating($travel) { value, delta, _ in delta = value.translation.height }
                                .onEnded {
                                move(rule.id, by: Int(($0.translation.height / 38).rounded()))
                            })
                            .focusable().accessibilityElement().accessibilityLabel("Reorder " + kind.rawValue.lowercased() + " by " + name)
                            .accessibilityAdjustableAction { move(rule.id, by: $0 == .increment ? 1 : -1) }
                        DropMenu("Rule property", options: collection.properties.filter { property in property.id == rule.property || available.contains(where: { $0.id == property.id }) }.map { DropOption(title: $0.title, value: $0.id) }, selection: field(rule, key: true), fillsField: true)
                        DropMenu("Rule value", options: values(rule.property).map { DropOption(title: $0.isEmpty ? "Empty" : $0, value: $0) }, selection: field(rule, key: false),
                                 link: kind == .filter ? DropLink(title: "Enter value…", go: {
                                     customValue = rule.value
                                     customRule = rule.id
                                 }) : nil, fillsField: true)
                            .popover(isPresented: Binding(get: { customRule == rule.id }, set: { if !$0 { customRule = nil } })) {
                                HStack {
                                    YabFormField("Filter value", text: $customValue)
                                    Button("Apply") {
                                        field(rule, key: false).wrappedValue = customValue
                                        customRule = nil
                                    }.buttonStyle(.yab(.primary, .small)).keyboardShortcut(.defaultAction)
                                }.padding(8).frame(width: 240)
                            }
                        Button { rules.removeAll { $0.id == rule.id } } label: { Symbol("xmark", size: 10) }
                            .buttonStyle(.yab(.quiet, .small)).accessibilityLabel("Remove " + kind.rawValue.lowercased())
                    }
                    .frame(minHeight: 32)
                    .background { if held == rule.id { RoundedRectangle(cornerRadius: Radius.control).fill(Palette.wash) } }
                    .offset(y: displacement(rule.id, index: index))
                    .zIndex(held == rule.id ? 1 : 0)
                    .onMoveCommand { direction in
                        if direction == .up { move(rule.id, by: -1) }
                        if direction == .down { move(rule.id, by: 1) }
                    }
                }
                PageActionButton(title: "Add " + kind.rawValue.lowercased(), icon: "plus",
                                       state: available.isEmpty ? .disabled : .ready) { choosing.toggle() }
                    .popover(isPresented: $choosing) {
                        VStack(alignment: .leading, spacing: 4) {
                            ThemedSearchField("Search properties", text: $search)
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(available.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { property in
                                        TrailMenuRow(title: property.title, action: {
                                            view.addRule(kind, property: property.id, entries: collection.entries)
                                            choosing = false
                                        }) { Symbol(property.type.symbol, size: 14) }
                                    }
                                }
                            }.frame(height: CGFloat(min(7, available.count)) * SideBar.row)
                        }.padding(8).frame(width: 240).onDisappear { search = "" }.toned(tone)
                    }
            }.padding(8).frame(width: 370, alignment: .leading).toned(tone)
        }
    }
}
