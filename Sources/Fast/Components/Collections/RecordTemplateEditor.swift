import SwiftUI

struct RecordTemplateEditor: View {
    let collection: PageCollection
    let save: (RecordTemplate) -> Void
    let cancel: () -> Void
    @State private var draft: RecordTemplate
    @State private var groupName = ""
    @State private var tabName = ""

    init(collection: PageCollection, save: @escaping (RecordTemplate) -> Void, cancel: @escaping () -> Void) {
        self.collection = collection
        self.save = save
        self.cancel = cancel
        _draft = State(initialValue: collection.recordTemplate ?? RecordTemplate(collection: collection))
    }

    private var valid: Bool {
        draft.buttons.allSatisfy { button in
            guard !button.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let field = collection.properties.first(where: { $0.id == button.field }) else { return false }
            if button.command == .copy { return true }
            let trimmed = button.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return !field.required }
            return !field.numeric || (try? Decimal(trimmed, format: .number)) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Customize Template").font(.headline)
            Divider()
            ThreadScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Groups").font(.headline)
                    ForEach(draft.groups) { group in
                        HStack {
                            Text(group.title)
                            Spacer()
                            ordering(group.id, ids: draft.groups.map(\.id), name: group.title) { draft.groups.swapAt($0, $1) }
                            remove(group.title) { draft.groups.removeAll { $0.id == group.id } }
                        }
                    }
                    addRow("Group", name: $groupName, existing: draft.groups.map(\.title)) {
                        draft.groups.append(.init(title: $0))
                    }
                    Divider()
                    Text("Properties").font(.headline)
                    ForEach(draft.order, id: \.self) { key in
                        if let field = collection.properties.first(where: { $0.id == key }) {
                            HStack {
                                Text(field.title)
                                Spacer()
                                DropMenu("Group for " + field.title,
                                         options: [DropOption(title: "Ungrouped", value: Optional<UUID>.none)] +
                                            draft.groups.map { DropOption(title: $0.title, value: Optional($0.id)) },
                                         selection: Binding(get: { draft.groups.first { $0.fields.contains(key) }?.id },
                                                            set: { draft.move(field: key, to: $0) }), showsCheck: true)
                                ordering(key, ids: draft.order, name: field.title) { draft.order.swapAt($0, $1) }
                            }
                        }
                    }
                    Divider()
                    Text("Buttons").font(.headline)
                    ForEach($draft.buttons) { $button in
                        let id = button.id
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                RecordCardField("Button name", text: $button.title)
                                ordering(button.id, ids: draft.buttons.map(\.id), name: button.title) { draft.buttons.swapAt($0, $1) }
                                remove(button.title) { draft.buttons.removeAll { $0.id == id } }
                            }
                            HStack {
                                DropMenu("Command", options: RecordButtonProperty.Command.allCases.map { .init(title: $0.rawValue, value: $0) },
                                         selection: $button.command)
                                DropMenu("Property", options: collection.properties.map { .init(title: $0.title, value: $0.id) },
                                         selection: $button.field)
                                if button.command == .set { RecordCardField("Value", text: $button.value) }
                            }
                        }
                    }
                    Button("Add button") { draft.buttons.append(.init(title: "", command: .copy, field: "name")) }
                        .buttonStyle(.yab(.secondary, .small))
                    Divider()
                    Text("Tabs").font(.headline)
                    ForEach(draft.tabs, id: \.self) { title in
                        HStack {
                            Text(title)
                            Spacer()
                            ordering(title, ids: draft.tabs, name: title) { draft.tabs.swapAt($0, $1) }
                            remove(title) { draft.tabs.removeAll { $0 == title } }.disabled(draft.tabs.count == 1)
                        }
                    }
                    addRow("Tab", name: $tabName, existing: draft.tabs) { draft.tabs.append($0) }
                }.padding(.horizontal, 2)
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.yab(.quiet, .small)).keyboardShortcut(.cancelAction)
                Button("Save template") {
                    for i in draft.buttons.indices where draft.buttons[i].command == .set {
                        if collection.properties.first(where: { $0.id == draft.buttons[i].field })?.numeric == true,
                           let number = try? Decimal(draft.buttons[i].value, format: .number) {
                            draft.buttons[i].value = NSDecimalNumber(decimal: number).stringValue
                        }
                    }
                    save(draft)
                }.buttonStyle(.yab(.primary, .small)).disabled(!valid)
            }
        }.padding().frame(width: 510, height: 520)
    }

    private func ordering<ID: Equatable>(_ id: ID, ids: [ID], name: String, move: @escaping (Int, Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach([-1, 1], id: \.self) { direction in
                let index = ids.firstIndex(of: id)
                let target = (index ?? 0) + direction
                RailButton("Move " + name + (direction < 0 ? " up" : " down"), icon: direction < 0 ? "arrow.up" : "arrow.down", doorSize: .header) {
                    if let index, ids.indices.contains(target) { move(index, target) }
                }.disabled(index == nil || !ids.indices.contains(target))
            }
        }
    }

    private func remove(_ name: String, action: @escaping () -> Void) -> some View {
        RailButton("Remove " + name, icon: "xmark", doorSize: .header, action: action)
    }

    private func addRow(_ type: String, name: Binding<String>, existing: [String], add: @escaping (String) -> Void) -> some View {
        let trimmed = name.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            RecordCardField(type + " name", text: name)
            Button("Add " + type.lowercased()) { add(trimmed); name.wrappedValue = "" }
                .buttonStyle(.yab(.secondary, .small))
                .disabled(trimmed.isEmpty || existing.contains { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame })
        }
    }
}

private struct RecordCardField: View {
    let title: String
    @Binding var text: String
    @FocusState private var typing: Bool

    init(_ title: String, text: Binding<String>) {
        self.title = title
        _text = text
    }

    var body: some View {
        TextField("", text: $text).textFieldStyle(.plain).focused($typing)
            .modifier(CardField(hint: title, empty: text.isEmpty, typing: typing))
            .accessibilityLabel(title)
    }
}
