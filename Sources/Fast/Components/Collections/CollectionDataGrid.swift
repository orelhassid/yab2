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
    let collection: PageCollection
    let update: (UUID, String, String) -> Void
    let collectionName: String
    let filteredEmpty: Bool
    let create: () -> Void
    let clear: () -> Void
    @Environment(\.tone) private var tone
    @Environment(\.layoutDirection) private var direction
    let openRecord: (CollectionEntry) -> Void

    @State private var hovering: String?

    @State private var columnMenu: String?
    @State private var resizeHover: String?
    @GestureState private var resizing: Resize?
    private struct Resize {
        let key: String
        let width: CGFloat
    }

    private func columnWidth(_ id: String, fallback: CGFloat) -> CGFloat {
        if resizing?.key == id, let resizing { return resizing.width }
        return max(96, min(1200, view.columnWidths?[id] ?? fallback))
    }

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
                                columnHeader(property, index: index, fallback: dataWidth)
                            }
                        }
                        ForEach(Array(entries.enumerated()), id: \.element.id) { offset, entry in
                            groupLabels(entry, previous: offset > 0 ? entries[offset - 1] : nil)
                            HStack(spacing: 0) {
                                Toggle(isOn: Binding(get: { selection.contains(entry.id) }, set: { on in
                                    if on { selection.insert(entry.id) } else { selection.remove(entry.id) }
                                })) { EmptyView() }.accessibilityLabel("Select row \(start + offset + 1)")
                                    .frame(width: gutter, height: height)
                                Text(String(start + offset + 1)).monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: indexWidth)
                                columns(width: dataWidth) { _, property in
                                    CollectionEditableCell(property: property, entry: entry, primary: property.id == schema.first?.id,
                                                           height: height, collection: collection, save: { update(entry.id, property.id, $0) },
                                                           open: { openRecord(entry) }) {
                                        valueCell(entry.values[property.id] ?? "", property: property)
                                    }
                                }
                            }
                            .background { if selection.contains(entry.id) { SelectionPlate(corner: 0, state: .selected) } }
                        }
                        Button(action: create) {
                            HStack(spacing: 6) {
                                Symbol("plus", size: 12)
                                Text("New Record")
                            }.font(CardFrame.detail).foregroundStyle(Palette.muted)
                                .padding(.horizontal, DropFace.inset)
                                .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                                .contentShape(Rectangle())
                        }.buttonStyle(CollectionCellPress()).accessibilityLabel("Add record in table")
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

    @ViewBuilder private func groupLabels(_ entry: CollectionEntry, previous: CollectionEntry?) -> some View {
        let groups = view.groupRules ?? []
        ForEach(Array(groups.enumerated()), id: \.element.id) { level, rule in
            if previous == nil || groups.prefix(level + 1).contains(where: { (entry.values[$0.property] ?? "") != (previous?.values[$0.property] ?? "") }) {
                let name = schema.first { $0.id == rule.property }?.title ?? rule.property
                let value = entry.values[rule.property] ?? ""
                HStack(spacing: 6) {
                    Symbol("rectangle.3.group", size: 12)
                    Text(name).foregroundStyle(Palette.muted)
                    Text(value.isEmpty ? "Empty" : value)
                }.font(CardFrame.detail).padding(.leading, 8 + CGFloat(level) * 12)
                    .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
                    .background(Palette.hairline.opacity(0.35))
            }
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

    private func columns<Content: View>(width fallback: CGFloat, @ViewBuilder content: @escaping (Int, CollectionProperty) -> Content) -> some View {
        ForEach(Array(properties.enumerated()), id: \.element.id) { index, property in
            let width = columnWidth(property.id, fallback: fallback)
            let held = drag?.source == index
            let shift = drag.map { ColumnHand.shift(index, from: $0.source, to: $0.target, rows: nil, step: columnWidth(properties[$0.source].id, fallback: fallback)) } ?? 0
            ZStack(alignment: .leading) {
                if drag?.target == index {
                    Rectangle().fill(Color.accentColor.opacity(0.18))
                        .overlay(alignment: .leading) { Rectangle().fill(Color.accentColor).frame(width: 2) }
                }
                content(index, property)
                    .frame(width: width, height: height)
                    .overlay(alignment: .trailing) {
                        let highlighted = resizeHover == property.id || resizing?.key == property.id
                        Rectangle().fill(highlighted ? Color.accentColor : Palette.hairline)
                            .frame(width: highlighted ? 2 : 0.5).allowsHitTesting(false)
                    }
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

    private func landing(_ travel: CGFloat, from index: Int, fallback: CGFloat) -> Int {
        let widths = properties.map { columnWidth($0.id, fallback: fallback) }
        let center = widths.prefix(index).reduce(0, +) + widths[index] / 2 + sign * travel
        var edge: CGFloat = 0
        for (i, width) in widths.enumerated() {
            edge += width
            if center < edge { return max(1, i) }
        }
        return widths.count - 1
    }

    @ViewBuilder private func columnHeader(_ property: CollectionProperty, index: Int, fallback: CGFloat) -> some View {
        let width = columnWidth(property.id, fallback: fallback)
        let fixed = property.id == schema.first?.id
        let header = HStack(spacing: 6) {
            Symbol(property.type.symbol, size: 12).foregroundStyle(Palette.muted)
            Text(property.title).fontWeight(.medium).lineLimit(1)
            if let sort = view.sorts.first(where: { $0.property == property.id }) {
                Symbol(sort.value == "Descending" ? "arrow.down" : "arrow.up", size: 10)
            }
            Spacer(minLength: 0)
            if !fixed && hovering == property.id { Symbol("line.3.horizontal", size: 10).foregroundStyle(Palette.muted) }
        }.padding(.horizontal, DropFace.inset).frame(width: width, height: height, alignment: .leading).contentShape(Rectangle())
            .background { if hovering == property.id { SelectionPlate(corner: 0, state: .hover) } }
            .onHover { if $0 { hovering = property.id } else if hovering == property.id { hovering = nil } }
            .accessibilityElement(children: .ignore).accessibilityLabel(property.title + " column")
        let menuHeader = header.onTapGesture { columnMenu = property.id }
            .accessibilityAddTraits(.isButton).accessibilityAction { columnMenu = property.id }
        Group {
            if fixed { menuHeader }
            else {
                menuHeader.simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .updating($drag) { value, state, _ in
                        let travel = value.translation.width
                        state = Drag(source: index, target: landing(travel, from: index, fallback: fallback), travel: travel)
                    }
                    .onEnded { value in
                        let target = landing(value.translation.width, from: index, fallback: fallback)
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
        .popover(isPresented: Binding(get: { columnMenu == property.id }, set: { if !$0 { columnMenu = nil } })) {
            VStack(spacing: 0) {
                ForEach(CollectionColumnAction.allCases, id: \.self) { action in
                    TrailMenuRow(title: action.title(rtl: direction == .rightToLeft), action: {
                        columnMenu = nil
                        view.apply(action, column: property.id, properties: schema)
                    }) { Symbol(action.symbol, size: 12) }
                    .disabled(!view.supports(action, column: property.id, properties: schema))
                }
            }.padding(4).frame(width: 190).toned(tone)
        }
        .overlay(alignment: .trailing) {
            Rectangle().fill(resizeHover == property.id || resizing?.key == property.id ? Color.accentColor : .clear)
                .frame(width: 2).frame(width: 8).contentShape(Rectangle())
                .onHover { inside in
                    if inside { resizeHover = property.id; NSCursor.resizeLeftRight.set() }
                    else if resizeHover == property.id { resizeHover = nil; NSCursor.arrow.set() }
                }
                .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .updating($resizing) { value, state, _ in
                        let initial = view.columnWidths?[property.id] ?? fallback
                        state = Resize(key: property.id, width: min(1200, max(96, initial + sign * value.translation.width)))
                    }
                    .onEnded { value in
                        setWidth((view.columnWidths?[property.id] ?? fallback) + sign * value.translation.width, for: property.id)
                    })
                .accessibilityElement().accessibilityLabel("Resize " + property.title)
                .accessibilityValue(String(Int(width)))
                .accessibilityAdjustableAction { setWidth(width + ($0 == .increment ? 16 : -16), for: property.id) }
                .focusable().onMoveCommand { move in
                    if move == .left || move == .right { setWidth(width + (move == .right ? sign : -sign) * 16, for: property.id) }
                }
        }
    }

    private func setWidth(_ width: CGFloat, for key: String) {
        var widths = view.columnWidths ?? [:]
        widths[key] = max(96, min(1200, width))
        view.columnWidths = widths
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
