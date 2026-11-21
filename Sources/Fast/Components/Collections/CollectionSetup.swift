import SwiftUI

struct CollectionSetup: View {
    let create: (PageCollection) -> Void
    let cancel: () -> Void
    @State private var template = CollectionTemplate.blank
    @State private var name = ""
    @State private var symbol = CollectionTemplate.blank.symbol
    @State private var draft: PageCollection?
    @State private var customizing = false
    @State private var newProperty = ""
    @State private var excluded: Set<String> = []
    @State private var choosingIcon = false

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedProperty: String { newProperty.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(customizing ? "Customize properties" : "New Collection").font(CardFrame.title)
                Spacer()
                RailButton("Close", icon: "xmark", doorSize: .header, action: cancel)
            }.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            if customizing, let draft { propertyList(draft) } else { details }
            Divider()
            HStack {
                if customizing {
                    Button("Back") { customizing = false }.buttonStyle(.yab(.quiet, .regular))
                }
                Spacer()
                Button("Cancel", action: cancel).buttonStyle(.yab(.secondary, .regular)).keyboardShortcut(.cancelAction)
                Button(customizing || template == .blank ? "Create Collection" : "Customize", action: advance)
                    .buttonStyle(.yab(.primary, .regular)).keyboardShortcut(.return, modifiers: .command)
                    .disabled(trimmedName.isEmpty)
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 502)
        .background(Palette.ground)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Template").font(CardFrame.detail)
            choice(.blank)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(CollectionTemplate.allCases.filter { $0 != .blank }, id: \.self) { choice($0) }
            }
            Text("Collection name").font(CardFrame.detail).padding(.top, 8)
            HStack {
                RailButton("Choose collection icon", icon: symbol, selected: choosingIcon, doorSize: .header) { choosingIcon.toggle() }
                    .keyTip("Choose collection icon")
                    .popover(isPresented: $choosingIcon) {
                        HStack {
                            ForEach(CollectionTemplate.allCases, id: \.self) { item in
                                RailButton(item.rawValue + " icon", icon: item.symbol, selected: item.symbol == symbol, doorSize: .header) {
                                    symbol = item.symbol
                                    choosingIcon = false
                                }
                            }
                        }.padding(CardFrame.inset)
                    }
                YabFormField("Collection name", text: $name)
            }
        }.padding(20)
    }

    private func choice(_ item: CollectionTemplate) -> some View {
        let detail = item == .blank ? "Name only" : item.fieldTitles.joined(separator: " · ")
        return FormChoiceCard(title: item == .blank ? "Start blank" : item.rawValue, detail: detail, icon: item.symbol,
                              selected: template == item) {
            guard template != item else { return }
            if name.isEmpty || name == template.rawValue { name = item == .blank ? "" : item.rawValue }
            template = item
            symbol = item.symbol
            draft = nil
            excluded.removeAll()
            newProperty = ""
        }
    }

    private func propertyList(_ item: PageCollection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(trimmedName, systemImage: symbol).font(.headline)
                Spacer()
                Text("Required").font(.caption).foregroundStyle(Palette.muted)
            }
            Divider()
            ThreadScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.properties) { property in
                        HStack {
                            Toggle(property.title, isOn: Binding(get: { !excluded.contains(property.id) }, set: { on in
                                if on { excluded.remove(property.id) } else { excluded.insert(property.id) }
                            }))
                            .accessibilityLabel("Include " + property.title)
                            .disabled(property.id == "name")
                            Spacer()
                            Toggle(isOn: Binding(get: { property.required }, set: { required in
                                guard let i = draft?.properties.firstIndex(where: { $0.id == property.id }) else { return }
                                draft?.properties[i].required = required
                            })) { EmptyView() }
                            .accessibilityLabel("Require " + property.title)
                            .disabled(property.id == "name" || excluded.contains(property.id))
                        }
                        Divider()
                    }
                }
            }.frame(height: min(200, CGFloat(item.properties.count) * 34))
            HStack {
                YabFormField("New property", text: $newProperty)
                Button("Add property") {
                    draft?.properties.append(.init(id: UUID().uuidString, title: trimmedProperty))
                    newProperty = ""
                }.buttonStyle(.yab(.secondary, .regular)).disabled(trimmedProperty.isEmpty)
            }
        }.toggleStyle(NetCheckboxStyle()).padding(20)
    }

    private func advance() {
        let base = template.make(name: trimmedName)
        var result = draft ?? base
        result.name = trimmedName
        result.symbol = symbol
        result.views = base.views
        if draft != nil { result.properties[0] = base.properties[0] }
        if template != .blank && !customizing {
            draft = result
            customizing = true
            return
        }
        result.properties.removeAll { excluded.contains($0.id) }
        for i in result.views.indices {
            result.views[i].filters.removeAll { excluded.contains($0.property) }
        }
        create(result)
    }
}
