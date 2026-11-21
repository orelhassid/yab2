import SwiftUI

struct CollectionDataGrid: View {
    let properties: [CollectionProperty]
    let entries: [CollectionEntry]
    let start: Int
    let total: Int
    @Binding var selection: Set<UUID>
    @Binding var view: CollectionTableView
    let schema: [CollectionProperty]
    let matching: [CollectionEntry]
    let collectionName: String
    let filteredEmpty: Bool
    let create: () -> Void
    let clear: () -> Void
    @Environment(\.tone) private var tone
    @Environment(\.layoutDirection) private var direction
    let openRecord: (CollectionEntry) -> Void

    @State private var hovering: String?

    private var pageIDs: Set<UUID> { Set(entries.map(\.id)) }

    var body: some View {
        GeometryReader { room in
            let digits = String(max(1, start + entries.count)) as NSString
            let numberFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let numberWidth = ceil(digits.size(withAttributes: [.font: numberFont]).width)
            let gaps = CGFloat(properties.count + 1) * 8
            let dataWidth = max(100, (room.size.width - 16 - numberWidth - gaps) / CGFloat(max(1, properties.count)))
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 0) {
                        GridRow {
                            Toggle(isOn: Binding(get: { !entries.isEmpty && pageIDs.isSubset(of: selection) }, set: { all in
                                if all { selection.formUnion(pageIDs) } else { selection.subtract(pageIDs) }
                            })) { EmptyView() }.accessibilityLabel("Select page").fixedSize().disabled(entries.isEmpty)
                            Text("#").foregroundStyle(.secondary)
                            ForEach(properties) { property in
                                columnHeader(property, width: dataWidth)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            GridRow {
                                Toggle(isOn: Binding(get: { selection.contains(entry.id) }, set: { on in
                                    if on { selection.insert(entry.id) } else { selection.remove(entry.id) }
                                })) { EmptyView() }.accessibilityLabel("Select row \(start + offset + 1)").fixedSize()
                                Text(String(start + offset + 1)).monospacedDigit().foregroundStyle(.secondary)
                                ForEach(properties) { property in
                                    Button { openRecord(entry) } label: {
                                        let value = entry.values[property.id] ?? ""
                                        Group {
                                            if !value.isEmpty && (property.type == .select || property.type == .multiSelect) {
                                                YabValueBadge(title: value, tint: .purple)
                                            } else { Text(value).lineLimit(1) }
                                        }
                                            .frame(width: dataWidth, alignment: property.numeric ? .trailing : .leading)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 6)
                            .background { if selection.contains(entry.id) { SelectionPlate(corner: Radius.control, state: .selected) } }
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                        if total > 0 {
                            GridRow {
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                                ForEach(properties) { property in
                                    footer(property)
                                        .frame(maxWidth: .infinity, alignment: property.numeric ? .trailing : .leading)
                                }
                            }.padding(.vertical, 6)
                        }
                    }
                    .toggleStyle(NetCheckboxStyle())
                    if total == 0 {
                        VStack(spacing: 12) {
                            Symbol(filteredEmpty ? "line.3.horizontal.decrease" : "doc.text", size: 28)
                                .foregroundStyle(Palette.muted)
                            Text(filteredEmpty ? "No matching records" : "No " + collectionName.lowercased() + " yet")
                                .font(CardFrame.title)
                            Text(filteredEmpty ? "Clear the filters to see the records in this collection." : "Create your first record to get started.")
                                .font(CardFrame.detail).foregroundStyle(Palette.muted)
                            Button(action: filteredEmpty ? clear : create) {
                                Label(filteredEmpty ? "Clear filters" : "New Record", systemImage: filteredEmpty ? "xmark" : "plus")
                            }.buttonStyle(.yab(.primary, .regular))
                        }.frame(width: room.size.width, height: max(180, room.size.height - 44))

                    }
                }
                .frame(minWidth: room.size.width, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }

    @ViewBuilder private func columnHeader(_ property: CollectionProperty, width: CGFloat) -> some View {
        let fixed = property.id == schema.first?.id
        let header = HStack(spacing: 6) {
            Symbol(property.type.symbol, size: 12).foregroundStyle(Palette.muted)
            Text(property.title).fontWeight(.medium).lineLimit(1)
            if view.sortProperty == property.id {
                Symbol(view.descending == true ? "arrow.down" : "arrow.up", size: 10)
            }
            Spacer(minLength: 0)
            if !fixed && hovering == property.id { Symbol("line.3.horizontal", size: 10).foregroundStyle(Palette.muted) }
        }.frame(width: width, alignment: .leading).contentShape(Rectangle())
            .background { if hovering == property.id { SelectionPlate(corner: SideBar.radius, state: .hover) } }
            .onHover { if $0 { hovering = property.id } else if hovering == property.id { hovering = nil } }
            .accessibilityElement(children: .ignore).accessibilityLabel(property.title + " column")
        Group {
            if fixed { header }
            else {
                header.draggable(view.id.uuidString + "/" + property.id)
                    .dropDestination(for: String.self) { values, _ in
                        guard let source = properties.first(where: { view.id.uuidString + "/" + $0.id == values.first }),
                              source.id != property.id else { return false }
                        view.moveColumn(source.id, to: property.id, properties: schema)
                        return true
                    }
            }
        }
        .steadyMenu(actions: true, tone: tone) {
            ForEach(CollectionColumnAction.allCases, id: \.self) { action in
                Button(action.title(rtl: direction == .rightToLeft)) {
                    view.apply(action, column: property.id, properties: schema)
                }.disabled(!view.supports(action, column: property.id, properties: schema))
            }
        }
    }

    private func footer(_ property: CollectionProperty) -> some View {
        let current = view.calculations[property.id]
        let options: [CollectionCalculation] = property.numeric ? CollectionCalculation.allCases : [.count, .unique]
        let title = current.map { op in
            op.rawValue.capitalized + " " + op.result(matching.map { $0.values[property.id] ?? "" })
        } ?? "Calculate"
        return DropMenu("Calculate " + property.title,
                          options: [DropOption(title: "None", value: Optional<CollectionCalculation>.none)] +
                            options.map { DropOption(title: $0.rawValue.capitalized, value: Optional($0)) },
                          selection: $view.calculations[property.id], faceTitle: title)
    }
}
