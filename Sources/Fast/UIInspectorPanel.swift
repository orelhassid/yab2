import SwiftUI

/// The dock reserves space between the page and any trailing sidebar.
struct UIInspectorDock: View {
    let browser: Browser
    let topInset: CGFloat
    private let inspector = BrowserUIInspector.shared

    var body: some View {
        if inspector.isOpen(for: browser), inspector.placement == .docked {
            UIInspectorPanel(inspector: inspector)
                .frame(idealWidth: 415, maxWidth: 415)
                .padding(Backdrop.inset)
                .padding(.top, topInset)
                .layoutPriority(1)
        }
    }
}

struct UIInspectorOverlay: View {
    let browser: Browser
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let inspector = BrowserUIInspector.shared

    var body: some View {
        GeometryReader { room in
            if inspector.isOpen(for: browser) {
                switch inspector.placement {
                case .drawer:
                    let leading = browser.leadingSidebarRoom + Backdrop.inset
                    let trailing = browser.trailingSidebarRoom + Backdrop.inset
                    UIInspectorPanel(inspector: inspector, split: room.size.width - leading - trailing >= 630)
                        .frame(height: min(355, room.size.height * 0.56))
                        .padding(EdgeInsets(top: 0, leading: leading, bottom: Backdrop.inset, trailing: trailing))
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                case .floating:
                    UIInspectorFloating(inspector: inspector, room: room.size)
                case .docked, .detached:
                    EmptyView()
                }
            }
        }
        .animation(reduceMotion ? nil : Motion.glide, value: inspector.placement)
    }
}

private struct UIInspectorFloating: View {
    let inspector: BrowserUIInspector
    let room: CGSize
    @State private var offset: CGSize?
    @GestureState private var drag = CGSize.zero

    var body: some View {
        let width = min(415, max(0, room.width - 24))
        let height = min(650, max(0, room.height - 54))
        let origin = offset ?? CGSize(width: room.width - width - 24, height: 35)
        let x = min(max(0, origin.width + drag.width), max(0, room.width - width))
        let y = min(max(0, origin.height + drag.height), max(0, room.height - height))
        UIInspectorPanel(inspector: inspector, moveHandle: AnyGesture(
            DragGesture(coordinateSpace: .global)
                .updating($drag) { value, drag, _ in drag = value.translation }
                .onEnded { value in
                    offset = CGSize(
                        width: min(max(0, origin.width + value.translation.width), max(0, room.width - width)),
                        height: min(max(0, origin.height + value.translation.height), max(0, room.height - height))
                    )
                }
        ))
        .frame(width: width, height: height)
        .shadow(color: .black.opacity(Double(Shadow.card.opacity)), radius: Shadow.card.radius, y: Shadow.card.y) // design: float the themed inspector over the page using the shared card shadow
        .offset(x: x, y: y)
    }
}

struct UIInspectorDetached: View {
    @ObservedObject var browser: Browser

    var body: some View {
        WorkspaceThemeReader(browser: browser) { _ in
            UIInspectorPanel(inspector: BrowserUIInspector.shared).padding(Backdrop.inset)
        }
    }
}

private struct UIInspectorTreeRow: Identifiable {
    let entry: UIInspectorEntry
    let level: Int
    var id: UIInspectorID { entry.id }
}

private struct UIInspectorPanel: View {
    let inspector: BrowserUIInspector
    var split = false
    var moveHandle: AnyGesture<DragGesture.Value>?
    @Environment(\.tone) private var tone
    @State private var openNodes: Set<UIInspectorID> = []
    @State private var previouslySelected: UIInspectorID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if split {
                HStack(spacing: 0) {
                    structure
                        .frame(minWidth: 265, idealWidth: 340, maxWidth: 415, maxHeight: .infinity, alignment: .top)
                    Divider()
                    styles
                }
            } else {
                VStack(spacing: 0) {
                    structure
                    Divider()
                    styles
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .background {
            RoundedRectangle(cornerRadius: Radius.control).fill(tone?.color ?? Palette.ground)
        }
        .background { UIInspectorPanelMarker() }
        .accessibilityIdentifier("browser-ui-inspector")
        .onChange(of: inspector.tree, initial: true) { _, _ in revealSelection() }
        .onChange(of: inspector.selected) { _, _ in revealSelection() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PageActionButton(title: "Pick Element", icon: "cursorarrow.rays",
                             state: inspector.picking ? .active : .ready, iconOnly: true) {
                inspector.startPicking()
            }
            Text("Browser UI Inspector")
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(moveHandle)
            Menu {
                ForEach(UIInspectorPlacement.allCases, id: \.self) { mode in
                    Button { inspector.move(to: mode) } label: {
                        if inspector.placement == mode { Label(mode.rawValue, systemImage: "checkmark") }
                        else { Text(mode.rawValue) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(inspector.placement.rawValue)
                    Symbol("chevron.down", size: 8)
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Inspector Placement")
            .accessibilityValue(inspector.placement.rawValue)

            PageActionButton(title: "Close Inspector", icon: "xmark", iconOnly: true) {
                inspector.close()
            }
        }
        .padding(12)
    }

    private var structure: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("Structure")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(rows(in: inspector.tree)) { row in
                            structureRow(row).id(row.id)
                        }
                    }
                    .padding(4)
                }
                .frame(minHeight: 68, idealHeight: 142, maxHeight: split ? .infinity : 155)
                .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.ink.opacity(0.04)))
                .onChange(of: inspector.selected, initial: true) { _, selected in
                    if let selected {
                        DispatchQueue.main.async { proxy.scrollTo(selected) }
                    }
                }
            }
            if let entry = selectedEntry {
                HStack(spacing: 8) {
                    Text(entry.node.source.display)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted(on: tone))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    PageActionButton(title: "Open in Code", icon: "chevron.left.forwardslash.chevron.right") {
                        inspector.openSource(entry.node.source)
                    }
                }
            }
        }
        .padding(12)
    }

    private func structureRow(_ row: UIInspectorTreeRow) -> some View {
        let entry = row.entry
        let selected = entry.id == inspector.selected
        return HStack(spacing: 4) {
            if entry.children.isEmpty {
                Color.clear.frame(width: 17, height: 22)
            } else {
                Button {
                    if openNodes.contains(entry.id) { openNodes.remove(entry.id) }
                    else { openNodes.insert(entry.id) }
                } label: {
                    Symbol(openNodes.contains(entry.id) ? "chevron.down" : "chevron.right", size: 8)
                        .frame(width: 17, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(openNodes.contains(entry.id) ? "Collapse \(entry.node.component)" : "Expand \(entry.node.component)")
            }
            Button {
                inspector.select(entry.id)
            } label: {
                HStack(spacing: 8) {
                    Text(entry.node.component)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .monospaced))
                    if let name = entry.node.label {
                        Text(name).font(.system(size: 12)).foregroundStyle(Palette.muted(on: tone))
                    }
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 23, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])
        }
        .padding(.leading, CGFloat(row.level) * 15)
        .background {
            if selected { SelectionPlate(corner: Radius.control, state: .selected) }
        }
    }

    private var styles: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                section("Styles")
                if let entry = selectedEntry {
                    sizeDiagram(entry.size)
                    values("Size", [UIInspectorStyle("Size", "Width / Height", UIInspectorStyle.size(entry.size))])
                    let groups = entry.node.styles.map(\.group).reduce(into: [String]()) { groups, name in
                        if !groups.contains(name) { groups.append(name) }
                    }
                    ForEach(groups, id: \.self) { name in
                        Divider()
                        values(name, entry.node.styles.filter { $0.group == name })
                    }
                } else {
                    Text(inspector.picking ? "Click a browser control to inspect it." : "No element selected")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.muted(on: tone))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.system(size: 13, weight: .semibold))
    }

    private func values(_ group: String, _ styles: [UIInspectorStyle]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group).font(.system(size: 12, weight: .semibold))
            Grid(alignment: .leading, horizontalSpacing: 15, verticalSpacing: 6) {
                ForEach(styles, id: \.name) { style in
                    GridRow {
                        Text(style.name).foregroundStyle(Palette.muted(on: tone))
                        HStack(spacing: 6) {
                            Text(style.value).fontDesign(.monospaced).textSelection(.enabled)
                            if let swatch = style.swatch {
                                RoundedRectangle(cornerRadius: Radius.small)
                                    .fill(Color(nsColor: swatch))
                                    .frame(width: 12, height: 12)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 12))
        }
    }

    private func sizeDiagram(_ size: CGSize) -> some View {
        Text(UIInspectorStyle.size(size))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(Color.accentColor.opacity(0.10))
                    .strokeBorder(Color.accentColor.opacity(0.65))
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: Radius.control).fill(Palette.ink.opacity(0.04)))
            .accessibilityHidden(true)
    }

    private var selectedEntry: UIInspectorEntry? {
        guard let id = inspector.selected else { return nil }
        return path(to: id, in: inspector.tree)?.last
    }

    private func path(to id: UIInspectorID, in entries: [UIInspectorEntry]) -> [UIInspectorEntry]? {
        for entry in entries {
            if entry.id == id { return [entry] }
            if let child = path(to: id, in: entry.children) { return [entry] + child }
        }
        return nil
    }

    private func revealSelection() {
        guard let id = inspector.selected, id != previouslySelected,
              let path = path(to: id, in: inspector.tree) else { return }
        openNodes.formUnion(path.map(\.id))
        previouslySelected = id
    }

    private func rows(in entries: [UIInspectorEntry], at level: Int = 0) -> [UIInspectorTreeRow] {
        entries.flatMap { entry in
            let row = UIInspectorTreeRow(entry: entry, level: level)
            return openNodes.contains(entry.id) ? [row] + rows(in: entry.children, at: level + 1) : [row]
        }
    }
}

private struct UIInspectorPanelMarker: NSViewRepresentable {
    func makeNSView(context: Context) -> UIInspectorProbe {
        let view = UIInspectorProbe()
        view.isPanel = true
        return view
    }

    func updateNSView(_ view: UIInspectorProbe, context: Context) {}
}
