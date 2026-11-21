import SwiftUI

struct CollectionEntryForm: View {
    let collection: PageCollection
    let filters: [CollectionFilter]
    let save: (CollectionEntry) -> Void
    let cancel: () -> Void
    @Environment(\.tone) private var tone
    @State private var active = "Blank"
    @State private var drafts: [String: [String: String]] = [:]

    private var values: [String: String] {
        var defaults = active == "Blank" ? [:] : collection.creationDefaults
        for rule in filters { defaults[rule.property] = rule.value }
        return drafts[active] ?? defaults
    }

    private func field(_ id: String) -> Binding<String> {
        Binding(get: { values[id] ?? "" }, set: { value in
            var edited = values
            edited[id] = value
            drafts[active] = edited
        })
    }

    private var valid: Bool {
        collection.properties.allSatisfy { property in
            let value = (values[property.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return !property.required }
            return !property.numeric || (try? Decimal(value, format: .number)) != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Symbol(collection.symbol, size: SideBar.mark)
                Text("New Record").font(CardFrame.title)
                Spacer()
                RailButton("Close", icon: "xmark", doorSize: .header, action: cancel)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            HStack(spacing: SideBar.markGap) {
                ForEach(["Blank", collection.creationTemplateName].compactMap { $0 }, id: \.self) { title in
                    PageTabButton(title: title, symbol: title == "Blank" ? "doc" : collection.symbol,
                                  selected: title == active) { active = title }
                }
            }.padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ThreadScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(collection.properties) { property in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(property.title + (property.required ? " *" : "")).font(CardFrame.detail)
                            if property.type == .select || property.type == .multiSelect {
                                RecordOptionField(property: property, options: collection.options(for: property),
                                                  value: field(property.id))
                            } else {
                                YabFormField(property.title, text: field(property.id))
                            }
                        }
                    }
                }.padding(20)
            }.frame(height: min(365, CGFloat(collection.properties.count) * 70 + 32))
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.yab(.secondary, .regular)).keyboardShortcut(.cancelAction)
                Button("Create Record") {
                    var stored = values
                    for field in collection.properties where field.numeric {
                        if let number = try? Decimal(stored[field.id] ?? "", format: .number) {
                            stored[field.id] = NSDecimalNumber(decimal: number).stringValue
                        }
                    }
                    save(.init(values: stored))
                }.buttonStyle(.yab(.primary, .regular)).keyboardShortcut(.return, modifiers: .command).disabled(!valid)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }.frame(width: 500).background(tone?.color ?? Palette.ground)
    }
}

private struct RecordOptionField: View {
    let property: CollectionProperty
    let options: [String]
    @Binding var value: String
    @State private var open = false
    @State private var query = ""

    private var selected: [String] {
        property.type == .multiSelect ? value.components(separatedBy: ", ").filter { !$0.isEmpty } : [value]
    }

    var body: some View {
        Button { open.toggle() } label: {
            HStack {
                if value.isEmpty { Text("Choose " + property.title.lowercased()) }
                else { YabValueBadge(title: value, tint: .purple) }
                Spacer()
                Symbol("chevron.down", size: 10)
            }
        }.buttonStyle(.yab(.secondary, .regular)).accessibilityLabel(property.title)
        .popover(isPresented: $open) {
            VStack(alignment: .leading, spacing: 4) {
                ThemedSearchField("Find or add option", text: $query)
                let matches = Array(Set(options + selected)).filter {
                    !$0.isEmpty && (query.isEmpty || $0.localizedCaseInsensitiveContains(query))
                }.sorted()
                ThreadScrollView {
                    VStack(spacing: 0) {
                        ForEach(matches, id: \.self) { option in
                            TrailMenuRow(title: option, selected: selected.contains(option), action: { choose(option) }) {
                                Symbol(property.type.symbol, size: SideBar.mark)
                            }
                        }
                    }
                }.frame(height: CGFloat(min(6, matches.count)) * SideBar.row)
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !matches.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
                    TrailMenuRow(title: "Add " + trimmed, action: { choose(trimmed) }) { Symbol("plus", size: SideBar.mark) }
                }
            }.padding(8).frame(width: 250).onDisappear { query = "" }
        }
    }

    private func choose(_ option: String) {
        if property.type == .multiSelect {
            value = (selected.contains(option) ? selected.filter { $0 != option } : selected + [option]).joined(separator: ", ")
            query = ""
        } else {
            value = value == option ? "" : option
            open = false
        }
    }
}
