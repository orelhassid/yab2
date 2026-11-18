import SwiftUI

/// Angles increase clockwise in the wheel's flipped view.
struct RadialSelection {
    static let commands: [Command?] = [.forward, .downloads, .newTab, .back, .reload, nil]
    static let hub: CGFloat = 58
    static let rim: CGFloat = 136
    static let outer: CGFloat = 183
    var wedge: Int?
    var space: Int?
    var showsSpaces: Bool { wedge == Self.commands.count - 1 }

    mutating func move(_ delta: CGPoint, spaceCount: Int) {
        let radius = hypot(delta.x, delta.y)
        let angle = atan2(delta.y, delta.x)
        func sector(_ count: Int, start: Double = 0) -> Int {
            let turn = (angle - start) / (2 * .pi)
            return (Int(floor(turn * Double(count) + 0.5)) + count * 2) % count
        }
        space = nil
        if radius < Self.hub || radius > Self.outer {
            wedge = nil
        } else if radius <= Self.rim {
            wedge = sector(Self.commands.count)
        } else if showsSpaces, spaceCount > 0 {
            space = sector(spaceCount, start: -.pi / 3)
        } else {
            wedge = nil
        }
    }
}

@MainActor
struct RadialMenu: View {
    let spaces: [Space]
    let available: [Bool]
    var selection = RadialSelection()
    static let side = RadialSelection.outer * 2
    private let center = CGPoint(x: RadialSelection.outer, y: RadialSelection.outer)

    private func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
        CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func sector(_ inner: CGFloat, _ outer: CGFloat, _ angle: Double, _ half: Double) -> Path {
        Path { path in
            path.addArc(center: center, radius: outer, startAngle: .radians(angle - half),
                        endAngle: .radians(angle + half), clockwise: false)
            path.addArc(center: center, radius: inner, startAngle: .radians(angle + half),
                        endAngle: .radians(angle - half), clockwise: true)
            path.closeSubpath()
        }
    }

    private var title: String {
        if let index = selection.space { return spaces[index].name }
        guard let index = selection.wedge else { return "" }
        switch RadialSelection.commands[index] {
        case .reload: return "Reload"
        case .back: return "Back"
        case .forward: return "Forward"
        case let command?: return command.title
        case nil: return "Spaces"
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(Palette.ground) // design: circular gesture target sized to the pointer hit regions.
                .frame(width: 272, height: 272)
            ForEach(RadialSelection.commands.indices, id: \.self) { index in
                let angle = Double(index) * .pi / 3
                let selected = selection.wedge == index
                let shape = sector(62, 124, angle, .pi / 6)
                shape.fill(selected ? Palette.wash : Palette.hover)
                shape.stroke(Palette.hairline, lineWidth: 0.65)
                sector(128, RadialSelection.rim, angle, .pi / 6)
                    .fill(selected ? Palette.faint.opacity(0.7) : Palette.hover)
                Symbol(RadialSelection.commands[index]?.symbol ?? "square.stack.3d.up", size: 17)
                    .foregroundStyle(selected ? Palette.ink : Palette.muted)
                    .opacity(available[index] ? 1 : 0.35)
                    .position(point(94, angle))
            }
            Circle().stroke(Palette.hairline, lineWidth: 1)
                .frame(width: 114, height: 114)
            Text(title).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center).lineLimit(2).frame(width: 98)
            if selection.showsSpaces && !spaces.isEmpty {
                ForEach(spaces.indices, id: \.self) { index in
                    let step = 2 * Double.pi / Double(spaces.count)
                    let angle = -.pi / 3 + Double(index) * step
                    let shape = sector(141, RadialSelection.outer, angle, step / 2)
                    shape.fill(selection.space == index ? Palette.wash : Palette.hover)
                    shape.stroke(Palette.hairline, lineWidth: 0.65)
                    VStack(spacing: 2) {
                        SpaceMark(icon: spaces[index].icon, size: min(16, 150 * step))
                        if spaces.count <= 9 {
                            Text(spaces[index].name).font(.system(size: 10, weight: .medium))
                                .lineLimit(1).frame(maxWidth: 56)
                        }
                    }
                    .foregroundStyle(Palette.muted)
                    .position(point(162, angle))
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .allowsHitTesting(false)
    }
}

final class RadialMenuHost: NSHostingView<RadialMenu> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func track(_ location: CGPoint) {
        let local = convert(location, from: nil)
        let delta = CGPoint(x: local.x - bounds.midX,
                            y: (local.y - bounds.midY) * (isFlipped ? 1 : -1))
        var menu = rootView
        menu.selection.move(delta, spaceCount: menu.spaces.count)
        rootView = menu
    }
}
