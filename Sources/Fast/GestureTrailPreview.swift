import SwiftUI

struct GestureTrailPreview: View {
    let points: [CGPoint]
    let label: String?
    var replay = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        GeometryReader { box in
            if let end = points.last {
                ZStack(alignment: .topLeading) {
                    let path = Path { $0.addLines(points) }
                    if replay && !reducedMotion {
                        TimelineView(.animation(minimumInterval: 1 / 30)) { tick in
                            let phase = tick.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2)
                            line(path.trimmedPath(from: 0, to: min(1, phase / 1.3)))
                        }
                    } else { line(path) }
                    if let label {
                        Text(label).font(.callout.weight(.medium)).lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .frame(maxWidth: min(200, box.size.width))
                            .position(x: min(max(min(100, box.size.width / 2), end.x), max(box.size.width / 2, box.size.width - 100)),
                                      y: end.y + 26 < box.size.height ? max(14, end.y + 20) : max(14, end.y - 20))
                    }
                }.frame(width: box.size.width, height: box.size.height, alignment: .topLeading)
            }
        }.clipped().allowsHitTesting(false)
    }

    private func line(_ path: Path) -> some View {
        let style = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
        return ZStack(alignment: .topLeading) {
            path.stroke(.background.opacity(0.8), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            path.stroke(Color.accentColor, style: style)
            if let tip = path.currentPoint {
                Circle().fill(Color.accentColor).frame(width: 6, height: 6).position(tip)
            }
        }
    }

    static func example(_ directions: String, in size: CGSize) -> [CGPoint] {
        var points = [CGPoint.zero]
        for letter in directions {
            var p = points[points.count - 1]
            switch letter {
            case "U": p.y -= 1
            case "D": p.y += 1
            case "R": p.x += 1
            case "L": p.x -= 1
            default: continue
            }
            points.append(p)
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        let left = xs.min() ?? 0, top = ys.min() ?? 0
        let w = (xs.max() ?? 0) - left, h = (ys.max() ?? 0) - top
        let scale = min(size.width * 0.58 / max(1,w), size.height * 0.52 / max(1,h))
        return points.map { CGPoint(x: size.width / 2 + ($0.x - left - w / 2) * scale,
                                    y: size.height * 0.44 + ($0.y - top - h / 2) * scale) }
    }
}

final class MouseTrailHost: NSHostingView<GestureTrailPreview> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
