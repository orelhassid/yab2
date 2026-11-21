import SwiftUI

struct RadialDropdownRow {
    let title: String
    let icon: String
    var spaceIcon = false
    var enabled = true
    var children = false
    var checked = false

    @MainActor static func commands(_ slots: [RadialItem], browser: Browser, editing: Bool = false) -> [Self] {
        slots.map { item in
            Self(title: item.title, icon: item.icon, enabled: editing || item.available(in: browser),
                 children: item.hasChildren)
        }
    }
}

struct RadialDropdown: View {
    static let width: CGFloat = 216
    static let rowHeight: CGFloat = 38
    static let inset: CGFloat = 6
    let rows: [RadialDropdownRow]
    let paint: SpacePaint
    var selected: Int?
    var maxHeight: CGFloat = .infinity
    var scrolled: ((CGFloat) -> Void)?
    let choose: (Int) -> Void
    @State private var hover: Int?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    var body: some View {
        let height = CGFloat(rows.count) * Self.rowHeight
        let shape = RoundedRectangle(cornerRadius: Radius.floating, style: .continuous)
        VStack(spacing: 0) {
            if height + 2 * Self.inset > maxHeight {
                ScrollView {
                    content.onGeometryChange(for: CGFloat.self) { -$0.frame(in: .named("dropdownScroll")).minY } action: { scrolled?($0) }
                }.coordinateSpace(name: "dropdownScroll")
            } else { content }
        }
        .padding(Self.inset)
        .frame(height: min(height + 2 * Self.inset, maxHeight))
        .background { shape.fill(.regularMaterial).overlay { shape.fill(Color(nsColor: SpaceWash.painted(paint).color).opacity(opaque ? 1 : 0.68)) } }
        .overlay { shape.strokeBorder(Palette.hairline).allowsHitTesting(false) } // design: the dropdown shares the wheel’s Space-tinted material.
        .environment(\.colorScheme, LookMode(rawValue: paint.mode)?.scheme ?? scheme)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                Button { choose(i) } label: {
                    HStack(spacing: 10) {
                        Group {
                            if row.spaceIcon { SpaceMark(icon: row.icon, size: 16) }
                            else { Symbol(row.icon, size: 16) }
                        }.frame(width: 22)
                        Text(row.title).lineLimit(1)
                        Spacer(minLength: 4)
                        if row.children { Image(systemName: "chevron.right") }
                        if row.checked || (scrolled == nil && selected == i) { Image(systemName: "checkmark") }
                    }
                    .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: Self.rowHeight)
                    .background { RoundedRectangle(cornerRadius: Radius.control).fill(Palette.ink.opacity(selected == i || (scrolled == nil && hover == i) ? 0.14 : 0)) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!row.enabled)
                .onHover { over in if over { hover = i } else if hover == i { hover = nil } }
            }
        }
    }
}

/// Reports actual layout bounds for native-tab eligibility and held-button tracking.
struct RadialMenuSurface: NSViewRepresentable {
    let register: (NSView) -> Void
    final class Marker: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    func makeNSView(context: Context) -> NSView {
        let view = Marker()
        register(view)
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { register(view) }
}

@MainActor
final class RadialDropdownHost: NSHostingView<RadialDropdown> {
    private var scrollOffset: CGFloat = 0
    func row(at location: CGPoint) -> Int? {
        let point = convert(location, from: nil)
        let inset = RadialDropdown.inset
        guard bounds.insetBy(dx: inset, dy: inset).contains(point) else { return nil }
        let fromTop = isFlipped ? point.y - bounds.minY : bounds.maxY - point.y
        let index = Int(floor((fromTop - inset + scrollOffset) / RadialDropdown.rowHeight))
        return rootView.rows.indices.contains(index) ? index : nil
    }
    func topOffset(of row: Int) -> CGFloat {
        RadialDropdown.inset + CGFloat(row) * RadialDropdown.rowHeight - scrollOffset
    }
    func highlight(_ row: Int?) {
        if rootView.selected != row { rootView.selected = row }
    }
    static func place(rows: [RadialDropdownRow], paint: SpacePaint, in root: NSView, near point: CGPoint,
                      parent: RadialDropdownHost? = nil, choose: @escaping (Int) -> Void) -> RadialDropdownHost {
        let height = min(root.bounds.height, CGFloat(rows.count) * RadialDropdown.rowHeight + 2 * RadialDropdown.inset)
        let width = min(RadialDropdown.width, root.bounds.width)
        let host = RadialDropdownHost(rootView: RadialDropdown(rows: rows, paint: paint, maxHeight: height, choose: choose))
        host.rootView.scrolled = { [weak host] value in host?.scrollOffset = value }
        host.sizingOptions = []
        let x = parent.map { $0.frame.maxX + width <= root.bounds.maxX ? $0.frame.maxX : $0.frame.minX - width } ?? point.x
        let y = root.isFlipped ? point.y : point.y - height
        host.frame = CGRect(x: max(root.bounds.minX, min(x, root.bounds.maxX - width)),
                            y: max(root.bounds.minY, min(y, root.bounds.maxY - height)), width: width, height: height)
        root.addSubview(host, positioned: .above, relativeTo: nil)
        host.layoutSubtreeIfNeeded()
        return host
    }
}
