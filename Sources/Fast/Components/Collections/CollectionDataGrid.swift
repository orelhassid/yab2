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

    private struct Drag {
        let source: Int
        let target: Int
        let travel: CGFloat
    }

    @GestureState private var drag: Drag?
    @ScaledMetric(relativeTo: .body) private var contentHeight: CGFloat = 24
    private var height: CGFloat { max(contentHeight, view.compactRows == true ? 28 : 36) }
    private var sign: CGFloat { direction == .rightToLeft ? -1 : 1 }
    private var pageIDs: Set<UUID> { Set(entries.map(\.id)) }

    var body: some View {
        GeometryReader { room in
            let digits = String(max(1, start + entries.count)) as NSString
            let numberFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            let numberWidth = ceil(digits.size(withAttributes: [.font: numberFont]).width)
            let gutter: CGFloat = 28
            let indexWidth = numberWidth + 12
            let dataWidth = max(110, (room.size.width - gutter - indexWidth) / CGFloat(max(1, properties.count)))
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 0) {
                            Toggle(isOn: Binding(get: { !entries.isEmpty && pageIDs.isSubset(of: selection) }, set: { all in
                                if all { selection.formUnion(pageIDs) } else { selection.subtract(pageIDs) }
                            })) { EmptyView() }.accessibilityLabel("Select page").disabled(entries.isEmpty)
                                .frame(width: gutter, height: height)
                            Text("#").foregroundStyle(.secondary).frame(width: indexWidth)
                            columns(width: dataWidth) { index, property in
                                columnHeader(property, index: index, width: dataWidth)
                            }
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            HStack(spacing: 0) {
                                Toggle(isOn: Binding(get: { selection.contains(entry.id) }, set: { on in
                                    if on { selection.insert(entry.id) } else { selection.remove(entry.id) }
                                })) { EmptyView() }.accessibilityLabel("Select row \(start + offset + 1)")
                                    .frame(width: gutter, height: height)
                                Text(String(start + offset + 1)).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: indexWidth)
                                columns(width: dataWidth) { _, property in
                                    Button { openRecord(entry) } label: {
                                        valueCell(entry.values[property.id] ?? "", property: property)
                                            .lineLimit(1).padding(.horizontal, DropFace.inset)
                                            .frame(width: dataWidth, height: height, alignment: property.numeric ? .trailing : .leading)
                                            .clipped().contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                }
                            }
                            .background { if selection.contains(entry.id) { SelectionPlate(corner: 0, state: .selected) } }
                        }
                        if total > 0 {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: gutter + indexWidth, height: height)
                                columns(width: dataWidth) { _, property in footer(property) }
                            }
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

    @ViewBuilder private func valueCell(_ value: String, property: CollectionProperty) -> some View {
        if value.isEmpty {
            Color.clear
        } else {
            switch property.type {
            case .text: Text(value)
            case .number: Text(value).monospacedDigit()
            case .date, .relation:
                HStack(spacing: 6) {
                    Symbol(property.type.symbol, size: 12).foregroundStyle(Palette.muted)
                    Text(value)
                }
            case .select: YabValueBadge(title: value, tint: .purple)
            case .multiSelect:
                HStack(spacing: 4) {
                    ForEach(Array(value.components(separatedBy: ", ").enumerated()), id: \.offset) { _, tag in
                        YabValueBadge(title: tag, tint: .pink)
                    }
                }
            }
        }
    }

    private func columns<Content: View>(width: CGFloat, @ViewBuilder content: @escaping (Int, CollectionProperty) -> Content) -> some View {
        ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
            let held = drag?.source == index
            let shift = drag.map { ColumnHand.shift(index, from: $0.source, to: $0.target, rows: nil, step: width) } ?? 0
            ZStack(alignment: .leading) {
                if drag?.target == index {
                    Rectangle().fill(Color.accentColor.opacity(0.18))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 2) }
                }
                content(index, property)
                    .frame(width: width, height: height)
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.hairline).frame(width: 0.5).allowsHitTesting(false) }
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 0.5).allowsHitTesting(false) }
                    .background { if held { Rectangle().fill(.regularMaterial) } }
                    .opacity(held ? 0.8 : 1)
                    .offset(x: held ? drag?.travel ?? 0 : sign * shift)
                    .animation(held ? nil : Motion.settle, value: shift)
            }
            .frame(width: width, height: height)
            .zIndex(held ? 1 : 0)
        }
    }

    private func landing(_ travel: CGFloat, from index: Int, width: CGFloat) -> Int {
        min(properties.count - 1, max(1, index + Int((sign * travel / width).rounded())))
    }

    @ViewBuilder private func columnHeader(_ property: CollectionProperty, index: Int, width: CGFloat) -> some View {
        let fixed = property.id == schema.first?.id
        let header = HStack(spacing: 6) {
            Symbol(property.type.symbol, size: 12).foregroundStyle(Palette.muted)
            Text(property.title).fontWeight(.medium).lineLimit(1)
            if view.sortProperty == property.id {
                Symbol(view.descending == true ? "arrow.down" : "arrow.up", size: 10)
            }
            Spacer(minLength: 0)
            if !fixed && hovering == property.id { Symbol("line.3.horizontal", size: 10).foregroundStyle(Palette.muted) }
        }.padding(.horizontal, DropFace.inset).frame(width: width, height: height, alignment: .leading).contentShape(Rectangle())
            .background { if hovering == property.id { SelectionPlate(corner: 0, state: .hover) } }
            .onHover { if $0 { hovering = property.id } else if hovering == property.id { hovering = nil } }
            .accessibilityElement(children: .ignore).accessibilityLabel(property.title + " column")
        Group {
            if fixed { header }
            else {
                header.gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .updating($drag) { value, state, _ in
                        let travel = value.translation.width
                        state = Drag(source: index, target: landing(travel, from: index, width: width), travel: travel)
                    }
                    .onEnded { value in
                        let target = landing(value.translation.width, from: index, width: width)
                        guard properties.indices.contains(target) else { return }
                        view.moveColumn(property.id, to: properties[target].id, properties: schema)
                    })
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
                          selection: $view.calculations[property.id], trailing: property.numeric, faceTitle: title, cellHeight: height)
    }
}
