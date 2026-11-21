import SwiftUI

struct CollectionSetup: View {
    let ground: Color
    let create: (PageCollection) -> Void
    let cancel: () -> Void
    @State private var template = CollectionTemplate.blank
    @State private var name = ""
    @State private var symbol = CollectionTemplate.blank.symbol
    @State private var draft: PageCollection?
    @State private var customizing = false
    @State private var newProperty = ""
    @State private var newType = CollectionPropertyType.text
    @State private var newRequired = false
    @State private var moving: String?
    @Environment(\.colorScheme) private var scheme
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
        .frame(width: customizing ? 756 : 502)
        .background(ground)
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
            resetProperty()
        }
    }

    private func propertyList(_ item: PageCollection) -> some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(trimmedName, systemImage: symbol).font(CardFrame.title)
                HStack {
                    Text("Property")
                    Spacer()
                    Text("Required")
                }.font(CardFrame.detail).foregroundStyle(Palette.muted)
                Divider()
                ThreadScrollView {
                    VStack(spacing: SideBar.gap) {
                        ForEach(item.properties) { property in
                            propertyRow(property, in: item)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("New property").font(CardFrame.title)
                Text("Name").font(CardFrame.detail)
                YabFormField("New property", text: $newProperty)
                Text("Type").font(CardFrame.detail)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(CollectionPropertyType.allCases, id: \.self) { type in
                        FormChoiceCard(title: type.rawValue, icon: type.symbol,
                                       selected: newType == type, tint: tint(type)) { newType = type }
                    }
                }
                HStack {
                    Toggle("Required", isOn: $newRequired)
                        .accessibilityLabel("New property required")
                    Spacer()
                    Button("Add property") {
                        draft?.properties.append(.init(id: UUID().uuidString, title: trimmedProperty,
                                                       required: newRequired, type: newType))
                        resetProperty()
                    }.buttonStyle(.yab(.secondary, .regular)).disabled(trimmedProperty.isEmpty)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.fixedSize(horizontal: false, vertical: true)
        .modifier(SidebarTypography())
        .toggleStyle(NetCheckboxStyle()).padding(20)
    }

    private func resetProperty() {
        newProperty = ""
        newType = .text
        newRequired = false
    }

    private func tint(_ type: CollectionPropertyType) -> Color {
        let tint: FolderTint = switch type {
        case .text: .blue
        case .number: .teal
        case .date: .orange
        case .select: .purple
        case .multiSelect: .pink
        case .relation: .red
        }
        return tint.ink(dark: scheme == .dark)
    }

    private func propertyRow(_ property: CollectionProperty, in item: PageCollection) -> some View {
        let fixed = property.id == "name"
        let included = !excluded.contains(property.id)
        return SidebarTabRow(editing: true) {
            if fixed {
                Symbol("lock", size: SideBar.mark).foregroundStyle(Palette.muted)
                    .frame(width: Door.Size.header.side)
            } else {
                RailButton("Reorder " + property.title, keyboard: true, doorSize: .header) {
                    moving = property.id
                } mark: { Door.Size.header.symbol("line.3.horizontal") }
                .draggable(item.id.uuidString + "/" + property.id)
                .popover(isPresented: Binding(get: { moving == property.id }, set: { if !$0 { moving = nil } })) {
                    VStack {
                        ForEach([-1, 1], id: \.self) { step in
                            let index = item.properties.firstIndex(where: { $0.id == property.id }) ?? 0
                            Button(step < 0 ? "Move up" : "Move down") {
                                move(property.id, to: index + step)
                                moving = nil
                            }.buttonStyle(.yab(.quiet, .regular))
                            .disabled(!(1..<item.properties.count).contains(index + step))
                        }
                    }.padding(CardFrame.inset)
                }
            }
            Toggle(isOn: Binding(get: { included }, set: { on in
                if on { excluded.remove(property.id) } else { excluded.insert(property.id) }
            })) { EmptyView() }.disabled(fixed).accessibilityLabel("Include " + property.title)
            SidebarTabLabel(title: property.title) {
                Symbol(property.type.symbol, size: SideBar.mark).foregroundStyle(tint(property.type))
            }.opacity(included ? 1 : 0.5)
            Spacer(minLength: 0)
            Text(property.type.rawValue).font(.caption).foregroundStyle(Palette.muted).lineLimit(1)
            Toggle(isOn: Binding(get: { property.required }, set: { required in
                guard let i = draft?.properties.firstIndex(where: { $0.id == property.id }) else { return }
                draft?.properties[i].required = required
            })) { EmptyView() }.disabled(fixed || !included).accessibilityLabel("Require " + property.title)
        }
        .dropDestination(for: String.self) { values, _ in
            guard !fixed, let token = values.first,
                  let source = item.properties.first(where: { item.id.uuidString + "/" + $0.id == token }),
                  let target = item.properties.firstIndex(where: { $0.id == property.id }) else { return false }
            return move(source.id, to: target)
        }
    }

    @discardableResult private func move(_ id: String, to index: Int) -> Bool {
        guard var item = draft, id != "name", (1..<item.properties.count).contains(index),
              let source = item.properties.firstIndex(where: { $0.id == id }) else { return false }
        let field = item.properties.remove(at: source)
        item.properties.insert(field, at: index)
        draft = item
        return true
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
