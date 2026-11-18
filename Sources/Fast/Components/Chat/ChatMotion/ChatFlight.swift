import AppKit
import SwiftUI

// An answer taken into the chat column in one motion: the card it was in
// (the ⌘J field's answer, a command's answer over the page) becomes a
// plate, its picture on it, that grows from where the card was into the
// column's place while the column comes out under it; landed, the plate
// goes and the column is there. Drawn by Core Animation on a layer over
// the window, so the flight costs the main thread one picture of the card
// and nothing a frame.

/// A view's place in its window, kept for a flight to start or land there.
struct FlightMark: NSViewRepresentable {
    enum Kind { case answer, room }
    let kind: Kind
    /// The corner of what it marks, for the plate to start or land with.
    var corner: CGFloat = Radius.card
    /// A room's air around the column (DevRoom.Rim.inset), to find the column in it.
    var inset: CGFloat = 0

    func makeNSView(context: Context) -> MarkView { MarkView() }

    func updateNSView(_ view: MarkView, context: Context) {
        view.corner = corner
        view.inset = inset
        switch kind {
        case .answer: ChatFlight.answer = Weak(view)
        case .room: ChatFlight.rooms.removeAll { $0.view == nil || $0.view === view }; ChatFlight.rooms.append(Weak(view))
        }
    }

    final class MarkView: NSView {
        var corner: CGFloat = 0
        var inset: CGFloat = 0
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        /// Where it is, in its window's own points.
        var place: CGRect { convert(bounds, to: nil) }
    }

    struct Weak {
        weak var view: MarkView?
        init(_ view: MarkView) { self.view = view }
    }
}

@MainActor
enum ChatFlight {
    static var answer: FlightMark.Weak?
    static var rooms: [FlightMark.Weak] = []

    /// Where the card marked as the answer is, with its picture, taken
    /// before it goes: nil when there is none on screen.
    static func takeOff() -> Takeoff? {
        guard let mark = answer?.view, let window = mark.window, window.isVisible,
              let host = window.contentView?.layer, let root = window.contentView?.superview?.layer ?? window.contentView?.layer else { return nil }
        let place = mark.place
        guard place.width > 20, place.height > 20 else { return nil }
        return Takeoff(window: window, place: place, corner: mark.corner,
                       picture: picture(of: host, in: root, at: place, scale: window.backingScaleFactor))
    }

    struct Takeoff {
        let window: NSWindow
        let place: CGRect
        let corner: CGFloat
        let picture: CGImage?
    }

    /// The card's layers, drawn once: from the first that lies within
    /// `place` (the card's own ground) up, each within its own frame. The
    /// window's whole tree drawn into the card's place cost 60 ms of main
    /// thread before anything moved: Core Animation draws a layer that
    /// isn't opaque through a transparency layer as big as the clip it is
    /// given, so a 14 pt key glyph at 0.6 cost a card-sized one, 4 ms, and
    /// the layers under the card came too, the backdrop's grain, the
    /// paper, the page (which draws nothing here). `place` is in `root`'s
    /// space, the window's; the card's layers are `host`'s.
    static func picture(of host: CALayer, in root: CALayer, at place: CGRect, scale: CGFloat) -> CGImage? {
        let width = Int(place.width * scale), height = Int(place.height * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -place.minX, y: -place.minY)
        let layers = (host.sublayers ?? []).filter { !$0.isHidden && $0.opacity > 0 }
        let near = place.insetBy(dx: -1, dy: -1)
        let card = layers.firstIndex { near.contains(root.convert($0.bounds, from: $0)) } ?? 0
        for layer in layers[card...] {
            let shown = root.convert(layer.bounds, from: layer).intersection(place)
            guard !shown.isNull, shown.width > 0.5, shown.height > 0.5 else { continue }
            // Into the layer's own space, as its parent would take it there.
            let origin = root.convert(CGPoint.zero, from: layer)
            let across = root.convert(CGPoint(x: 1, y: 0), from: layer)
            let down = root.convert(CGPoint(x: 0, y: 1), from: layer)
            context.saveGState()
            context.clip(to: shown)
            context.concatenate(CGAffineTransform(a: across.x - origin.x, b: across.y - origin.y,
                                                  c: down.x - origin.x, d: down.y - origin.y,
                                                  tx: origin.x, ty: origin.y))
            layer.render(in: context)
            context.restoreGState()
        }
        return context.makeImage()
    }

    /// The column's place once it is out: the room's, less its air, the
    /// column as wide as it is set.
    static func landing(in window: NSWindow, width: CGFloat, leading: Bool = false) -> CGRect? {
        guard let mark = rooms.first(where: { $0.view?.window === window })?.view else { return nil }
        let room = mark.place
        let inset = mark.inset
        let x = leading ? room.minX + inset : room.maxX - inset - width
        return CGRect(x: x, y: room.minY + inset, width: width, height: room.height - 2 * inset)
    }

    /// The plate, from the card to the column.
    static func fly(_ takeoff: Takeoff, to landing: CGRect, corner: CGFloat) {
        let window = takeoff.window
        // Over the content, beside it in the frame: a view added inside
        // SwiftUI's host never gets its layer into the window's tree.
        guard let content = window.contentView, let frame = content.superview else { return }
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let sky = FlightSky(frame: content.frame)
        sky.autoresizingMask = [.width, .height]
        frame.addSubview(sky, positioned: .above, relativeTo: content)
        guard let layer = sky.layer else { sky.removeFromSuperview(); return }

        let from = sky.convert(takeoff.place, from: nil)
        let to = sky.convert(landing, from: nil)
        var ground = NSColor.white
        sky.effectiveAppearance.performAsCurrentDrawingAppearance { ground = Palette.NS.ground.usingColorSpace(.sRGB) ?? .white }

        let plate = CALayer()
        plate.anchorPoint = .zero
        plate.frame = from
        plate.cornerRadius = takeoff.corner
        plate.cornerCurve = .continuous
        plate.backgroundColor = ground.cgColor
        plate.masksToBounds = true
        let shade = CALayer()
        shade.anchorPoint = .zero
        shade.frame = from
        shade.cornerRadius = takeoff.corner
        shade.cornerCurve = .continuous
        shade.backgroundColor = ground.cgColor
        shade.shadowColor = NSColor.black.cgColor
        shade.shadowOpacity = 0.14
        shade.shadowRadius = 18
        shade.shadowOffset = CGSize(width: 0, height: -6)
        // The card's picture, pinned at its top left as the plate grows.
        let picture = CALayer()
        picture.contents = takeoff.picture
        picture.contentsScale = window.backingScaleFactor
        picture.anchorPoint = .zero
        picture.frame = CGRect(x: 0, y: from.height - takeoff.place.height, width: takeoff.place.width, height: takeoff.place.height)
        plate.addSublayer(picture)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.addSublayer(shade)
        layer.addSublayer(plate)
        CATransaction.commit()

        let span: CFTimeInterval = still ? 0.15 : 0.3
        let curve = CAMediaTimingFunction(controlPoints: 0.19, 1, 0.22, 1)
        func move<T>(_ layer: CALayer, _ key: String, _ from: T, _ to: T, duration: CFTimeInterval = span,
                     timing: CAMediaTimingFunction = curve) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            layer.add(animation, forKey: key)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Near the end, the plate gives way to the column already under it.
        let yield = CABasicAnimation(keyPath: "opacity")
        yield.fromValue = 1
        yield.toValue = 0
        yield.beginTime = CACurrentMediaTime() + span * 0.6
        yield.duration = 0.15
        yield.fillMode = .backwards
        yield.timingFunction = CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1)
        for part in [plate, shade] {
            part.opacity = 0
            part.add(yield, forKey: "yield")
        }
        CATransaction.setCompletionBlock { sky.removeFromSuperview() }
        // The model where it lands, the animations from where it was.
        for part in [plate, shade] {
            part.position = to.origin
            part.bounds = CGRect(origin: .zero, size: to.size)
            part.cornerRadius = corner
            if !still {
                move(part, "position", NSValue(point: from.origin), NSValue(point: to.origin))
                move(part, "bounds.size", NSValue(size: from.size), NSValue(size: to.size))
                move(part, "cornerRadius", takeoff.corner, corner)
            }
        }
        shade.shadowOpacity = 0
        move(shade, "shadowOpacity", 0.14, 0)
        // Its words go as it grows, their top with the plate's; the
        // column's own come in under it.
        picture.opacity = 0
        move(picture, "opacity", 1, 0, duration: span * 0.6, timing: CAMediaTimingFunction(name: .easeOut))
        let top = to.height - takeoff.place.height
        move(picture, "position.y", picture.position.y, top)
        picture.position.y = top
        CATransaction.commit()
    }
}

/// The layer the plate flies on: over everything, taking no clicks.
private final class FlightSky: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
