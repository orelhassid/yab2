import SwiftUI

struct CollectionDataGrid: View {
    let properties: [CollectionProperty]
    let entries: [CollectionEntry]
    let start: Int
    let total: Int
    @Binding var selection: Set<UUID>
    @Binding var calculations: [String: CollectionCalculation]
    let matching: [CollectionEntry]

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
                            Toggle("Select page", isOn: Binding(get: { !entries.isEmpty && pageIDs.isSubset(of: selection) }, set: { all in
                                if all { selection.formUnion(pageIDs) } else { selection.subtract(pageIDs) }
                            }))
                            .labelsHidden().fixedSize().disabled(entries.isEmpty)
                            Text("#").foregroundStyle(.secondary)
                            ForEach(properties) { property in
                                Text(property.title).fontWeight(.medium)
                                    .frame(width: dataWidth, alignment: property.numeric ? .trailing : .leading)
                            }
                        }
                        .padding(.vertical, 6)
                        Divider().gridCellUnsizedAxes(.horizontal)
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            GridRow {
                                Toggle("Select row \(start + offset + 1)", isOn: Binding(get: { selection.contains(entry.id) }, set: { on in
                                    if on { selection.insert(entry.id) } else { selection.remove(entry.id) }
                                }))
                                .labelsHidden().fixedSize()
                                Text(String(start + offset + 1)).monospacedDigit().foregroundStyle(.secondary)
                                ForEach(properties) { property in
                                    Text(entry.values[property.id] ?? "")
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: property.numeric ? .trailing : .leading)
                                }
                            }
                            .padding(.vertical, 6)
                            Divider().gridCellUnsizedAxes(.horizontal)
                        }
                        GridRow {
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            ForEach(properties) { property in
                                footer(property)
                                    .frame(maxWidth: .infinity, alignment: property.numeric ? .trailing : .leading)
                            }
                        }.padding(.vertical, 6)
                    }
                    .toggleStyle(.checkbox).controlSize(.small)
                    if total == 0 {
                        Text("No records").foregroundStyle(.secondary)
                            .frame(width: room.size.width).padding(.vertical)
                    }
                }
                .frame(minWidth: room.size.width, alignment: .leading)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }

    private func footer(_ property: CollectionProperty) -> some View {
        let current = calculations[property.id]
        let options: [CollectionCalculation] = property.numeric ? CollectionCalculation.allCases : [.count, .unique]
        return Menu {
            Button("None") { calculations.removeValue(forKey: property.id) }
            ForEach(options, id: \.self) { operation in
                Button(operation.rawValue.capitalized) { calculations[property.id] = operation }
            }
        } label: {
            let title = current.map { op in
                op.rawValue.capitalized + " " + op.result(matching.map { $0.values[property.id] ?? "" })
            } ?? "Calculate"
            Text(title).font(.caption)
        }
        .menuStyle(.borderlessButton).fixedSize()
        .accessibilityLabel("Calculate " + property.title)
    }
}
