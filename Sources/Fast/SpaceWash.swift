import AppKit
import SwiftUI

// The window's color as a space changes, in Core Animation over the
// backdrop: a layer in one space's color and grain, laid over the other's.
//
// ⌃N: the new space's color is worn at once, under a layer of the old one
// that clears in the switch's beat, so the room turns in the same frames as
// the rows and the capsule. Worn through SwiftUI's own animation, the color
// was a main-thread spring over the whole window, and with a busy window
// server it landed in one step some 180 ms after the rows.
//
// Two fingers sideways: the layer is the next space's color, as far over
// the old as the fingers have gone; let go past halfway, the space comes
// and the rest of the way is played out; short of it, the layer goes.

@MainActor
final class SpaceWash {
    /// Set while a switch puts its color on, so the window doesn't also
    /// animate it (App's backdrop).
    var turning = false

    /// The spring a wash lands on: the column's row's (SpacePager), or,
    /// while `onStrip`, the turn's across the top (StripTurn).
    static var onStrip = false
    static func landing(keyPath: String, from: Any, to: Any, velocity: CGFloat = 0) -> CASpringAnimation {
        onStrip ? StripTurn.caSpring(keyPath: keyPath, from: from, to: to, velocity: velocity)
            : SpacePaging.animation(keyPath: keyPath, from: from, to: to, velocity: velocity)
    }

    /// The old color over the new from `opacity`, cleared on the turn's
    /// spring across the top: the capsule's width and name ride the same
    /// one (StripTurn).
    func clearOnStrip(_ paint: Paint?, from opacity: Float, base: Paint? = nil) {
        Self.onStrip = true
        defer { Self.onStrip = false }
        clear(paint, from: opacity, spring: true, base: base)
    }

    fileprivate weak var view: WashView?
    weak var backdrop: WindowBackdropView?

    /// The grounds that wear the window's color on a surface of their own
    /// (CardGround: the column brought out over the page as a card, and its
    /// ground under the row of spaces while they slide). Each turns as the
    /// window does, in the same calls, so on the same curve and in the same
    /// frames. Worn through SwiftUI, the card's color eased over a third of
    /// a second on the main thread (Toned's animation), held still through
    /// the switch's own pass, out of step with the row and the window.
    private var mirrors: [Mirror] = []
    private struct Mirror { weak var view: CardGroundView? }

    fileprivate func mirror(_ view: CardGroundView) {
        mirrors.removeAll { $0.view == nil || $0.view === view }
        mirrors.append(Mirror(view: view))
    }

    fileprivate func unmirror(_ view: CardGroundView) {
        mirrors.removeAll { $0.view == nil || $0.view === view }
    }

    /// The grounds in the window this wash is over.
    var grounds: [CardGroundView] {
        let window = backdrop?.window ?? view?.window
        return mirrors.compactMap(\.view).filter { $0.window != nil && (window == nil || $0.window === window) }
    }

    /// A color and its grain, as the window wears them for a space now.
    struct Paint: Equatable {
        let color: NSColor
        let grain: Double
        var colors: [NSColor] = []
        var transparency: Double = 0
        /// On Liquid Glass, `transparency` the glass's tint
        /// (WindowGlassPolicy.transparency).
        var glass = false
        /// Drawings over the color (LookDrawings), nil for none.
        var drawings: LookDrawings.Set? = nil
        var drawingsStrength: Double = 0

        /// How opaque its coating is drawn (BackdropTransparency).
        var opacity: Float {
            Float(BackdropTransparency.opacity(transparency, reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        }
    }

    /// A ground's own color's opacity, `alpha` at rest, with `cover` of
    /// another color over it, that one `over` opaque itself: the two mixed
    /// as far as the row has gone, together as opaque as their mix. Under an
    /// opaque color the ground stays as it is and is covered as the color
    /// comes; under a see-through one it gives way only as much as the
    /// color covers. Given way by the cover alone, both were see-through at
    /// once mid-way and what is under them came up between them: the
    /// window's glass, the page under a card, a fifth of the way a tenth
    /// darker with the same color on either side.
    static func given(_ cover: Float, alpha: Float, over: Float) -> Float {
        guard over < 1 else { return alpha }
        return alpha * (1 - cover) / (1 - cover * over)
    }

    /// That opacity animated as the cover goes from `from` to `to`, by
    /// `given` all the way: on `timing` over `duration`, or with no
    /// duration on the row's spring (SpacePaging.animation). Animated
    /// between its two ends alone, the way was `alpha` × (1 − cover) again,
    /// and a switch by key or a let-go swipe went a tenth darker over a dark
    /// page halfway, and lighter over a light one.
    static func coverAnimation(alpha: Float, over: Float, from: Float, to: Float,
                               duration: CFTimeInterval = 0, timing: CAMediaTimingFunction? = nil,
                               velocity: CGFloat = 0) -> CAAnimation {
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        var times: [Double] = []
        var progress: [Double] = []
        if duration > 0 {
            // The cover's own curve on its way, this one's values along it.
            for step in 0...24 {
                times.append(Double(step) / 24)
                progress.append(Double(step) / 24)
            }
            animation.duration = duration
            animation.timingFunction = timing
        } else {
            // The spring's way from one end to the other, a frame at a time:
            // mass 1, as SpacePaging.animation has it, setting off at
            // `velocity` of the whole way a second, as the row does.
            let spring = SpaceWash.landing(keyPath: "opacity", from: 0, to: 1, velocity: velocity)
            let length = max(spring.duration, 1.0 / 60)
            let k = Double(spring.stiffness), c = Double(spring.damping)
            var x = 1.0, v = -Double(spring.initialVelocity), t = 0.0
            let dt = 1.0 / 1200
            var next = 0.0
            while t <= length + dt {
                if t >= next {
                    times.append(min(1, t / length))
                    progress.append(1 - x)
                    next += 1.0 / 120
                }
                v += (-k * x - c * v) * dt
                x += v * dt
                t += dt
            }
            times.append(1)
            progress.append(1)
            animation.duration = length
        }
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.values = progress.map { share in
            NSNumber(value: given(from + (to - from) * Float(share), alpha: alpha, over: over))
        }
        animation.calculationMode = .linear
        return animation
    }

    /// What the window wears for these preferences, or nil when it wears no
    /// swatch of its own: no backdrop, or the site's color. Edge to edge
    /// with the column docked, it wears the space's under the column
    /// (Preferences.edgeBackdrop).
    static func worn(_ prefs: Preferences) -> Paint? {
        guard prefs.backdrop == .color || prefs.edgeBackdrop else { return nil }
        return worn(SpacePaint(prefs), prefs: prefs)
    }

    static func worn(_ paint: SpacePaint?, prefs: Preferences) -> Paint? {
        guard prefs.backdrop == .color || prefs.edgeBackdrop, let paint else { return nil }
        return painted(paint)
    }

    /// What a card over the page, or edge to edge the column, wears for
    /// these preferences: the window's paint on a color; edge to edge,
    /// where the window wears none, the space's look all the same, color, gradient, grain and frost, as Arc's
    /// sidebar out over the page wears its space's theme with the sidebar
    /// hidden (feedback #165). Nil on the site's color.
    static func card(_ prefs: Preferences) -> Paint? {
        card(SpacePaint(prefs), prefs: prefs)
    }

    static func card(_ paint: SpacePaint?, prefs: Preferences) -> Paint? {
        guard prefs.backdrop != .site, let paint else { return nil }
        return painted(paint)
    }

    /// What the grounds wear for `paint`, the space on screen's when nil, in
    /// `browser`'s window: the window's paint, or edge to edge, while the
    /// column is docked or out over the page as a card, the column's, so a
    /// switch turns the column's color as it does on a color.
    static func grounded(_ paint: SpacePaint? = nil, in browser: Browser) -> Paint? {
        let prefs = browser.prefs
        if browser.windowPurpose == .privateOnly { return Paint(color: ContentView.privateBackdrop, grain: prefs.grain) }
        if let project = browser.developmentLook { return painted(paint ?? project) }
        let paint = paint ?? SpacePaint(prefs)
        return !prefs.sideShut || browser.sideCard ? card(paint, prefs: prefs) : worn(paint, prefs: prefs)
    }

    /// `paint` with Take the site's color's tint of `site`, as the window
    /// wears it on a color (LookCard.colors); as it is with no site color.
    static func sited(_ paint: Paint, prefs: Preferences, site: NSColor?) -> Paint {
        guard let site else { return paint }
        let look = SpacePaint(prefs)
        let dark = LookMode(rawValue: look.mode)?.scheme.map { $0 == .dark }
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        var sited = paint
        sited.colors = LookCard.colors(look, dark: dark, site: site)
        return sited
    }

    static func painted(_ paint: SpacePaint) -> Paint {
        // A space's own Light or Dark before the app's: a light space in a
        // dark app took the color's deep shade under its dark words.
        let dark = LookMode(rawValue: paint.mode)?.scheme.map { $0 == .dark }
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        return Paint(color: paint.color(dark: dark), grain: paint.grain,
                     colors: paint.colors.compactMap(NSColor.init(hex:)).map { dark ? $0.deepened : $0 },
                     transparency: paint.wornTransparency(dark: dark), glass: paint.glass && WindowGlassPolicy.supported,
                     drawings: LookDrawings.Set(rawValue: paint.drawings), drawingsStrength: paint.drawingsStrength)
    }

    /// Over the window at `opacity`, now, with nothing animated: the
    /// fingers' own pace.
    func show(_ paint: Paint, opacity: Float) {
        grounds.forEach { $0.show(paint, opacity: opacity) }
        guard let view else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.wear(paint)
        view.layer?.removeAnimation(forKey: "wash")
        view.layer?.opacity = opacity
        backdrop?.overOpacity = paint.opacity
        backdrop?.setCover(opacity)
        CATransaction.commit()
    }

    /// The rest of the way over the window, from `opacity` to all of it,
    /// in the render server: the fingers let go, and the new color comes
    /// before the space does.
    func fill(from opacity: Float, duration: CFTimeInterval) {
        grounds.forEach { $0.fill(from: opacity, duration: duration) }
        guard let layer = view?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = 1
        backdrop?.setCover(1, from: opacity, duration: duration,
                           timing: CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1))
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 1
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        layer.add(fade, forKey: "wash")
        CATransaction.commit()
    }

    /// Off the window at once: the window wears the same color under it now.
    func hide() {
        grounds.forEach { $0.hide() }
        backdrop?.setCover(0)
        guard let layer = view?.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.removeAnimation(forKey: "wash")
        layer.opacity = 0
        CATransaction.commit()
    }

    /// Over the window from `opacity` and cleared over `duration`, in the
    /// render server. `base`: what the window wears under it now, the
    /// space just changed; the grounds put it on in this same frame rather
    /// than with SwiftUI's next pass.
    func clear(_ paint: Paint? = nil, from opacity: Float, duration: CFTimeInterval, base: Paint? = nil) {
        grounds.forEach { $0.clear(paint, from: opacity, spring: false, duration: duration, base: base) }
        if let paint { backdrop?.overOpacity = paint.opacity }
        backdrop?.setCover(0, from: opacity, duration: duration, timing: CAMediaTimingFunction(name: .linear))
        guard let view, let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let paint { view.wear(paint) }
        layer.opacity = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = opacity
        fade.toValue = 0
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .linear)
        layer.add(fade, forKey: "wash")
        CATransaction.commit()
    }

    /// Cleared on the spring the column's spaces land on (SpacePager), so
    /// the color turns as far as the row has slid, as Arc's does. `began`:
    /// when that spring set off (the row's, on the render server's clock),
    /// for a clear that takes over from `go` part way, at `velocity` of
    /// the whole way a second as the row set off.
    func clear(_ paint: Paint? = nil, from opacity: Float, spring: Bool, base: Paint? = nil,
               began: CFTimeInterval? = nil, velocity: CGFloat = 0) {
        guard spring else { return clear(paint, from: opacity, duration: SpaceTurn.duration, base: base) }
        grounds.forEach { $0.clear(paint, from: opacity, spring: true, duration: 0, base: base, began: began, velocity: velocity) }
        if let paint { backdrop?.overOpacity = paint.opacity }
        backdrop?.setCover(0, from: opacity, spring: true, began: began, velocity: velocity)
        guard let view, let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let paint { view.wear(paint) }
        layer.opacity = 0
        layer.add(Self.since(began, SpaceWash.landing(keyPath: "opacity", from: opacity, to: Float(0), velocity: velocity), in: layer),
                  forKey: "wash")
        CATransaction.commit()
    }

    /// The fingers let go past halfway: the next space's color the rest of
    /// the way over, from `opacity`, on the spring the row lands on and at
    /// its `velocity` of the whole way a second, sent with the row before
    /// the switch is laid out. Played after the switch, it stood where the
    /// fingers had left it while the row landed, and came 100 to 200 ms
    /// after it (wash_matrix.py, Mail to a space). The switch hands it to
    /// `clear` on the same spring (`began`): the old color over the new
    /// clearing as the new one over the old was coming, the same mix all
    /// the way.
    func go(_ paint: Paint, from opacity: Float, velocity: CGFloat) {
        grounds.forEach { $0.go(paint, from: opacity, velocity: velocity) }
        backdrop?.overOpacity = paint.opacity
        backdrop?.setCover(1, from: opacity, spring: true, velocity: velocity)
        guard let view, let layer = view.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.wear(paint)
        layer.opacity = 1
        layer.add(SpaceWash.landing(keyPath: "opacity", from: opacity, to: Float(1), velocity: velocity), forKey: "wash")
        CATransaction.commit()
    }

    /// `animation` as if it had set off at `began` (CACurrentMediaTime),
    /// part of its way already gone; as it is with none.
    static func since(_ began: CFTimeInterval?, _ animation: CAAnimation, in layer: CALayer) -> CAAnimation {
        guard let began else { return animation }
        animation.beginTime = layer.convertTime(began, from: nil)
        animation.fillMode = .backwards
        return animation
    }
}

/// The layer itself, laid over the backdrop. Takes no clicks.
struct SpaceWashLayer: NSViewRepresentable {
    @Environment(Browser.self) private var browser: Browser?
    func makeNSView(context: Context) -> WashView {
        let view = WashView()
        view.bind(to: browser?.spaceWash)
        return view
    }

    func updateNSView(_ view: WashView, context: Context) {
        view.bind(to: browser?.spaceWash)
    }

    static func dismantleNSView(_ view: WashView, coordinator: ()) {
        view.bind(to: nil)
    }
}

final class WashView: NSView {
    private weak var wash: SpaceWash?

    func bind(to wash: SpaceWash?) {
        guard self.wash !== wash else { return }
        if self.wash?.view === self { self.wash?.view = nil }
        self.wash = wash
        wash?.view = self
    }

    private let coating = BackdropCoatingView(frame: .zero)
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.opacity = 0
        coating.frame = bounds
        coating.autoresizingMask = [.width, .height]
        addSubview(coating)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        coating.frame = bounds
    }

    fileprivate func wear(_ paint: SpaceWash.Paint) {
        coating.wear(paint)
    }
}

/// A card's ground in the window's color, gradient, grain and frost, as
/// `BackdropFill` draws it, but in Core Animation, so it turns with the
/// window when the space changes (SpaceWash's grounds): the column brought
/// out over the page, and its ground under the row of spaces while they
/// slide (SpacePager).
struct CardGround: View {
    let paint: SpaceWash.Paint
    /// How many steps its colors have turned (Shift with tabs, LookCard).
    var step = 0

    var body: some View {
        CardGroundLayer(paint: paint, step: step)
            .background {
                if paint.transparency > 0 {
                    BackdropVeil.Frost(color: paint.color, card: true, colors: paint.colors, transparency: paint.transparency)
                }
            }
    }
}

private struct CardGroundLayer: NSViewRepresentable {
    @Environment(Browser.self) private var browser: Browser?
    let paint: SpaceWash.Paint
    var step = 0

    func makeNSView(context: Context) -> CardGroundView { CardGroundView(frame: .zero) }

    func updateNSView(_ view: CardGroundView, context: Context) {
        view.bind(to: browser?.spaceWash)
        view.given(paint)
        view.turn(to: step)
    }

    static func dismantleNSView(_ view: CardGroundView, coordinator: ()) {
        view.bind(to: nil)
    }
}

/// The window's coating and its wash in one view (WindowBackdropView,
/// WashView), for a surface wearing the window's color on a ground of its
/// own. The frost, when there is one, is SwiftUI's, under it (CardGround).
final class CardGroundView: NSView {
    private weak var wash: SpaceWash?

    func bind(to wash: SpaceWash?) {
        guard self.wash !== wash else { return }
        self.wash?.unmirror(self)
        self.wash = wash
        if window != nil { wash?.mirror(self) }
    }

    private let base = BackdropCoatingView(frame: .zero)
    /// The other space's color over it while a switch turns it.
    private let over = NSView(frame: .zero)
    private let overCoating = BackdropCoatingView(frame: .zero)
    private var paint: SpaceWash.Paint?
    /// The last paint SwiftUI gave: a pass that gives the same again
    /// leaves what a switch has put on since.
    private var lastGiven: SpaceWash.Paint?
    private var cover: Float = 0
    override var isOpaque: Bool { false }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        base.autoresizingMask = [.width, .height]
        base.upsideDown = true
        overCoating.upsideDown = true
        addSubview(base)
        over.wantsLayer = true
        over.layer?.opacity = 0
        over.autoresizingMask = [.width, .height]
        overCoating.autoresizingMask = [.width, .height]
        over.addSubview(overCoating)
        addSubview(over)
        base.frame = bounds
        over.frame = bounds
        overCoating.frame = over.bounds
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        base.frame = bounds
        over.frame = bounds
        overCoating.frame = over.bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { wash?.mirror(self) } else { wash?.unmirror(self) }
    }

    /// Its colors turned to `step`, as the window's (BackdropCoatingView.turn).
    func turn(to step: Int) { base.turn(to: step) }

    /// The paint SwiftUI has for it.
    func given(_ paint: SpaceWash.Paint) {
        guard paint != lastGiven else { return }
        lastGiven = paint
        self.paint = paint
        base.wear(paint)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.layer?.opacity = baseOpacity(cover)
        CATransaction.commit()
    }

    private var alpha: Float {
        Float(BackdropTransparency.opacity(paint?.transparency ?? 0,
                                                 reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
    }

    /// How opaque the color over it is (WindowBackdropView.overOpacity).
    private var overOpacity: Float = 1

    /// The ground under the wash, with `cover` of the other color over it:
    /// by the window's rule (SpaceWash.given), so the two mix as the
    /// window's do.
    private func baseOpacity(_ cover: Float) -> Float {
        SpaceWash.given(cover, alpha: alpha, over: overOpacity)
    }

    // The same steps as the window's, called with them (SpaceWash).

    func show(_ paint: SpaceWash.Paint, opacity: Float) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overCoating.wear(paint)
        overOpacity = paint.opacity
        over.layer?.removeAnimation(forKey: "wash")
        over.layer?.opacity = opacity
        cover = opacity
        base.layer?.removeAnimation(forKey: "space-cover")
        base.layer?.opacity = baseOpacity(opacity)
        CATransaction.commit()
    }

    func go(_ paint: SpaceWash.Paint, from opacity: Float, velocity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        overCoating.wear(paint)
        overOpacity = paint.opacity
        over.layer?.opacity = 1
        over.layer?.add(SpaceWash.landing(keyPath: "opacity", from: opacity, to: Float(1), velocity: velocity), forKey: "wash")
        cover = 1
        base.layer?.opacity = baseOpacity(1)
        base.layer?.removeAnimation(forKey: "space-cover")
        if baseOpacity(opacity) != baseOpacity(1) {
            base.layer?.add(SpaceWash.coverAnimation(alpha: alpha, over: overOpacity, from: opacity, to: 1, velocity: velocity),
                            forKey: "space-cover")
        }
        CATransaction.commit()
    }

    func fill(from opacity: Float, duration: CFTimeInterval) {
        let timing = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        over.layer?.opacity = 1
        over.layer?.add(Self.fade(from: opacity, to: 1, duration: duration, timing: timing), forKey: "wash")
        cover = 1
        base.layer?.opacity = baseOpacity(1)
        base.layer?.add(SpaceWash.coverAnimation(alpha: alpha, over: overOpacity, from: opacity, to: 1, duration: duration, timing: timing),
                        forKey: "space-cover")
        CATransaction.commit()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        over.layer?.removeAnimation(forKey: "wash")
        over.layer?.opacity = 0
        cover = 0
        base.layer?.removeAnimation(forKey: "space-cover")
        base.layer?.opacity = baseOpacity(0)
        CATransaction.commit()
    }

    /// `paint` over it from `opacity` to none, on the row's spring or
    /// linearly over `duration`; `worn`, the new space's, under it at once.
    func clear(_ paint: SpaceWash.Paint?, from opacity: Float, spring: Bool, duration: CFTimeInterval, base worn: SpaceWash.Paint?,
               began: CFTimeInterval? = nil, velocity: CGFloat = 0) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let worn {
            self.paint = worn
            base.wear(worn)
        }
        if let paint {
            overCoating.wear(paint)
            overOpacity = paint.opacity
        }
        let linear = CAMediaTimingFunction(name: .linear)
        func curve(_ from: Float, _ to: Float) -> CAAnimation {
            spring ? SpaceWash.landing(keyPath: "opacity", from: from, to: to, velocity: velocity)
                   : Self.fade(from: from, to: to, duration: duration, timing: linear)
        }
        cover = 0
        base.layer?.opacity = baseOpacity(0)
        base.layer?.removeAnimation(forKey: "space-cover")
        if baseOpacity(opacity) != baseOpacity(0), let layer = base.layer {
            layer.add(SpaceWash.since(began, SpaceWash.coverAnimation(alpha: alpha, over: overOpacity, from: opacity, to: 0,
                                                                      duration: spring ? 0 : duration, timing: spring ? nil : linear,
                                                                      velocity: velocity), in: layer),
                      forKey: "space-cover")
        }
        over.layer?.opacity = 0
        if let layer = over.layer { layer.add(SpaceWash.since(began, curve(opacity, 0), in: layer), forKey: "wash") }
        CATransaction.commit()
    }

    private static func fade(from: Float, to: Float, duration: CFTimeInterval, timing: CAMediaTimingFunction) -> CABasicAnimation {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = duration
        fade.timingFunction = timing
        return fade
    }
}
