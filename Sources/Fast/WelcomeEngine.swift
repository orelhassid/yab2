import SwiftUI
import AppKit
import QuartzCore

// The welcome's stage: Yab's own parts, the row of tabs, the column, the
// page, the box, the dock and the chat, laid out at their own sizes in one
// space the size of the default window, a little apart, as an exploded view
// of the app. Each beat of a chapter says what is on the stage and where
// (a board of parts, each with a key); the stage works out what came, what
// went and what moved, and moves them with Core Animation alone, as the
// prototype's FLIP did: a part that stays glides from where it was, a new
// one comes in its own way, one that goes leaves its own way. Nothing here
// is animated by SwiftUI: each part is drawn once, by SwiftUI or as a
// layer, and only its layer's transform and opacity move, on the render
// server. A window of another size changes one transform, the stage's
// scale, and nothing is laid out again.

// MARK: - the space

/// The stage's own points: the 1180 × 780 window it was composed for.
enum StageSpace {
    static let size = CGSize(width: 1180, height: 780)
    /// Where the stage scales about: the middle of the header's line.
    static let pivot = CGPoint(x: 590, y: 52)

    /// The stage's scale in a window of this size, as one piece: 1 at
    /// 1180 × 780, 0.736 at 900 × 600, 1.2 at full screen on a 1512 × 982.
    static func scale(for window: CGSize) -> CGFloat {
        guard window.width > 0, window.height > 0 else { return 1 }
        return min(1.2, max(0.72, min(window.width / size.width, (window.height - 98) / 682)))
    }

    /// A stage point in the window's points, top-left origin.
    static func toWindow(_ point: CGPoint, in window: CGSize) -> CGPoint {
        let s = scale(for: window)
        return CGPoint(x: window.width / 2 + (point.x - pivot.x) * s, y: pivot.y + (point.y - pivot.y) * s)
    }

    static func toWindow(_ rect: CGRect, in window: CGSize) -> CGRect {
        let s = scale(for: window)
        let origin = toWindow(rect.origin, in: window)
        return CGRect(x: origin.x, y: origin.y, width: rect.width * s, height: rect.height * s)
    }

    /// A rect in the window's points as stage points: the real window's
    /// own rect, for Finish to grow into.
    static func toStage(_ rect: CGRect, in window: CGSize) -> CGRect {
        let s = scale(for: window)
        return CGRect(x: pivot.x + (rect.minX - window.width / 2) / s, y: pivot.y + (rect.minY - pivot.y) / s,
                      width: rect.width / s, height: rect.height / s)
    }
}

/// The welcome's own sizes of type, where they are off the app's scale:
/// its words are display words, set once per screen.
enum WelcomeType {
    /// A chapter's title: SF Pro Display 28 on a 34 line, medium.
    static let title: CGFloat = 28
    static let titleLine: CGFloat = 34
    /// The welcome's one display tracking, in ems.
    static let tracking: CGFloat = -0.015
    /// The line under the title: 15 on 20, muted.
    static let sub: CGFloat = 15
    static let subLine: CGFloat = 20
    /// "yet another browser.": 44 on a 52 line.
    static let name: CGFloat = 44
    /// Welcome's lede: 17 on 24, muted.
    static let lede: CGFloat = 17
}

// MARK: - curves

/// The curves of the welcome's motion (final-spec §3), as Core Animation
/// takes them.
enum WelcomeCurve: Equatable {
    case linear, easeOut
    /// (.2, .8, .2, 1): coming in.
    case arrive
    /// (.4, 0, .8, .4): going, quicker than coming.
    case depart
    /// (.2, .9, .2, 1): the rise into the header, a box rising.
    case rise
    /// (.19, 1, .22, 1): words changing, MorphText's.
    case morph
    /// (.2, .9, .25, 1): the dashes.
    case dash
    /// (.3, .6, .3, 1): a thing traveling on an arc.
    case travel
    /// A spring by its response and damping, Motion's; it sets its own length.
    case spring(response: Double, damping: Double)

    /// Motion.glide: things that move between two places.
    static let glide = WelcomeCurve.spring(response: 0.34, damping: 0.82)
    /// Motion.settle: things that arrive.
    static let settle = WelcomeCurve.spring(response: 0.30, damping: 0.86)
    /// The chapter's step: 0.34 and no bounce.
    static let step = WelcomeCurve.spring(response: 0.34, damping: 1)

    var function: CAMediaTimingFunction {
        switch self {
        case .linear, .spring: return CAMediaTimingFunction(name: .linear)
        case .easeOut: return CAMediaTimingFunction(name: .easeOut)
        case .arrive: return CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
        case .depart: return CAMediaTimingFunction(controlPoints: 0.4, 0, 0.8, 0.4)
        case .rise: return CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1)
        case .morph: return CAMediaTimingFunction(controlPoints: 0.19, 1, 0.22, 1)
        case .dash: return CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
        case .travel: return CAMediaTimingFunction(controlPoints: 0.3, 0.6, 0.3, 1)
        }
    }
}

@MainActor
enum WelcomeMotion {
    /// Every length and wait multiplied by this: 5 for the bench's slow
    /// motion (`./bench welcome slow=1`), to see a move frame by frame.
    static var pace: Double = 1

    /// One property from one value to another, on a curve, `delay`
    /// seconds from now (both scaled by the pace). A spring takes its own
    /// length; `duration` is for the rest.
    static func animation(_ keyPath: String, from: Any?, to: Any?, curve: WelcomeCurve, duration: Double,
                          delay: Double = 0, on layer: CALayer, fill: CAMediaTimingFillMode = .backwards) -> CABasicAnimation {
        let animation: CABasicAnimation
        if case .spring(let response, let damping) = curve {
            let spring = CASpringAnimation(keyPath: keyPath)
            spring.mass = 1
            spring.stiffness = pow(2 * .pi / response, 2)
            spring.damping = 4 * .pi * damping / response
            spring.duration = spring.settlingDuration
            animation = spring
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = duration
            animation.timingFunction = curve.function
        }
        animation.fromValue = from
        animation.toValue = to
        timed(animation, delay: delay, on: layer, fill: fill)
        return animation
    }

    /// Keyframes over `duration`, at the given moments (0 to 1).
    static func keyframes(_ keyPath: String, values: [Any], times: [Double], duration: Double, curve: WelcomeCurve,
                          delay: Double = 0, on layer: CALayer, fill: CAMediaTimingFillMode = .backwards) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.keyTimes = times.map { NSNumber(value: $0) }
        animation.duration = duration
        animation.timingFunctions = Array(repeating: curve.function, count: max(values.count - 1, 1))
        timed(animation, delay: delay, on: layer, fill: fill)
        return animation
    }

    /// The pace and the start, in the layer's own time.
    static func timed(_ animation: CAAnimation, delay: Double, on layer: CALayer, fill: CAMediaTimingFillMode) {
        animation.speed = Float(1 / pace)
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime() + delay * pace, from: nil)
        }
        animation.fillMode = fill
        if fill == .forwards || fill == .both { animation.isRemovedOnCompletion = false }
    }

    /// How long an animation runs, pace included, for what waits on it.
    static func length(_ animation: CAAnimation) -> Double {
        (animation as? CASpringAnimation).map { $0.settlingDuration * pace } ?? animation.duration * pace
    }
}

// MARK: - a part

/// One thing on the stage at its place: a part of Yab, a card, a line of
/// words. Its key is who it is from one board to the next, across the whole
/// tree: the same key on the next board glides there, a new key comes in,
/// a key that is gone leaves. A part can hold parts of its own (a row its
/// tabs), placed in its own points, which move with it and on their own.
struct StagePart {
    /// How a part comes in (the prototype's data-in).
    enum Enter: Equatable {
        /// Opacity, and 0.96 to 1, 0.22 arrive: the default.
        case fade
        /// Opacity alone, 0.22 arrive (xfade).
        case crossfade
        /// A title or a sub: opacity, and 0.98 to 1, 0.22 arrive.
        case words
        /// Up from 8 below, 0.96 to 1, with opacity, 0.26 rise: the box.
        case rise
        /// 0.6 to 1 on settle, opacity in 0.12: an agent's folder and tabs.
        case pop
        /// 0.6 to 1.06 to 1 with opacity, 0.36: a pin poured in.
        case pour
        /// From 24 to the left, with opacity, settle: a folder's tab coming out.
        case slideX
        /// From 28 up, with opacity, settle: a row of the column dropping in.
        case slideY
        /// From 6 below, with opacity, 0.22 arrive: an answer's row.
        case up6
        /// From 12 below, with opacity, settle: the dock.
        case up12
        /// 0.9 to 1 on settle, opacity in 0.15: a mark.
        case drop
        /// 0.85 to 1: a browser's icon.
        case drop85
        /// 0.94 to 1 on settle, opacity in 0.18: the window-to-be.
        case grow94
        /// From 24 to the right, with opacity, settle: the chat column.
        case chat
        /// Opacity in 0.12: the waiting ring.
        case ring
        /// 0.9 to 1 on a 0.42 spring with a little bounce, opacity in 0.12:
        /// the chosen mark's ring, out of its icon.
        case pick
        /// 0.4 to 1.08 to 1 in 0.5, opacity in 0.09: DoneTick.
        case tick
        /// From 8 below with opacity, on a 0.5 spring with no bounce: Welcome's lede.
        case lede
        /// Out of another part's rect (a key on this board or the last), on
        /// glide, opacity in 0.12: the Peek out of its link.
        case grow(from: String)
        /// There at once.
        case none
    }

    /// How a part leaves (the prototype's data-out, or a board's exits).
    enum Exit: Equatable {
        /// 0.98 and out, 0.15 depart: the default.
        case shrink
        /// Out in 0.12, linear.
        case fastFade
        /// Out in 0.15, linear, where it stands.
        case crossfade
        /// 14 down and out, 0.20 depart: the dock sinking into the page.
        case sink
        /// Up 330, 0.45 and out, 0.30 rise.
        case fold
        /// 40% of the way to another part on the new board, 0.9 and out, 0.19 depart.
        case toward(String)
        /// 0.9 and out, 0.18 depart: a ring back into its icon.
        case tuck
        /// Gone at once.
        case none
    }

    /// How what is drawn follows a change of the part's size.
    enum Resize {
        /// Scaled with it for the move, laid out at the new size underneath.
        case stretch
        /// Pinned to the top-left at the new size while the plate reshapes
        /// under it on Core Animation: a page going to half width, the
        /// window-to-be growing into the window.
        case pin
    }

    enum Drawing {
        case none
        /// Drawn by SwiftUI, at the part's size, top-left.
        case view(AnyView)
        /// A layer of its own, made once, sized to the part.
        case layer(@MainActor () -> CALayer)
    }

    var key: String
    /// In the parent's points: the stage's for a part on its own.
    var frame: CGRect
    var drawing: Drawing = .none
    /// A ground drawn by Core Animation under the drawing, which can
    /// reshape on the render server.
    var plate: StagePlate?
    /// nil: `.fade` coming in on its own, and nothing of its own when its
    /// parent is coming in too.
    var enter: Enter?
    /// Seconds after the board is shown; nil as 0.
    var delay: Double?
    var exit: Exit = .shrink
    /// Moving, it travels on an arc this far above the straight line. An
    /// arc always rises, whichever sign it is given (the prototype's -70).
    var arc: CGFloat = 0
    var resize: Resize = .stretch
    /// Its drawing answers the pointer (buttons, a picker, a drag).
    var takesClicks = false
    /// The drawing is the same as the last board's while this is: SwiftUI
    /// isn't asked again. nil: always asked.
    var version: AnyHashable?
    var children: [StagePart] = []

    init(_ key: String, _ frame: CGRect, drawing: Drawing = .none, plate: StagePlate? = nil,
         enter: Enter? = nil, delay: Double? = nil, exit: Exit = .shrink, arc: CGFloat = 0,
         resize: Resize = .stretch, takesClicks: Bool = false, version: AnyHashable? = nil, children: [StagePart] = []) {
        self.key = key
        self.frame = frame
        self.drawing = drawing
        self.plate = plate
        self.enter = enter
        self.delay = delay
        self.exit = exit
        self.arc = arc
        self.resize = resize
        self.takesClicks = takesClicks
        self.version = version
        self.children = children
    }

    /// A part drawn by SwiftUI.
    static func view<V: View>(_ key: String, _ frame: CGRect, enter: Enter? = nil, delay: Double? = nil, exit: Exit = .shrink,
                              takesClicks: Bool = false, @ViewBuilder _ content: () -> V) -> StagePart {
        StagePart(key, frame, drawing: .view(AnyView(content())), enter: enter, delay: delay, exit: exit, takesClicks: takesClicks)
    }
}

/// A part's ground, drawn by Core Animation: its fill, corner, ring and
/// shadow (cast from its outline, never from its pixels).
struct StagePlate {
    var fill: NSColor
    var corner: CGFloat
    /// A ring inside its edge.
    var ring: NSColor?
    var ringWidth: CGFloat = 1
    var shadow: Shadow.Cast?

    init(fill: NSColor, corner: CGFloat, ring: NSColor? = nil, ringWidth: CGFloat = 1, shadow: Shadow.Cast? = nil) {
        self.fill = fill
        self.corner = corner
        self.ring = ring
        self.ringWidth = ringWidth
        self.shadow = shadow
    }
}

/// What a beat puts on the stage.
struct WelcomeBoard {
    var parts: [StagePart] = []
    /// How parts of the board before leave, where this board says
    /// otherwise than they do: the box toward the row as the agent starts.
    var exits: [String: StagePart.Exit] = [:]

    init(_ parts: [StagePart] = [], exits: [String: StagePart.Exit] = [:]) {
        self.parts = parts
        self.exits = exits
    }

    static func + (lhs: WelcomeBoard, rhs: WelcomeBoard) -> WelcomeBoard {
        WelcomeBoard(lhs.parts + rhs.parts, exits: lhs.exits.merging(rhs.exits) { $1 })
    }
}

/// What is typed into a field on the stage, letter by letter: the box's
/// line, the terminal's. Its own object, so a letter draws that field and
/// nothing else. A field shows its board's words until something is typed.
@MainActor
final class WelcomeTyping: ObservableObject {
    static let shared = WelcomeTyping()
    @Published private(set) var typed: [String: String] = [:]

    func set(_ text: String?, for field: String) {
        guard typed[field] != text else { return }
        typed[field] = text
    }

    func clear() { if !typed.isEmpty { typed = [:] } }
}

// MARK: - the stage's view

/// The stage in the window: a canvas of stage points scaled to fit, the
/// parts on it, each a layer-backed view.
@MainActor
final class WelcomeStageView: NSView {
    /// The 1180 × 780 space, scaled by its bounds so the pointer finds
    /// what it's over.
    let canvas = WelcomeFlippedView()
    /// Portion of a chapter's artwork to fit in this column.
    var viewport: CGRect? { didSet { if viewport != oldValue { needsLayout = true } } }
    var alignsLeading = false
    private var nodes: [String: WelcomePartView] = [:]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        canvas.wantsLayer = true
        addSubview(canvas)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Only the parts that take the pointer: the stage itself lets it through.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self || hit === canvas ? nil : hit
    }

    override func layout() {
        super.layout()
        if let rect = viewport, rect.width > 0, rect.height > 0 {
            let scale = min(bounds.width / rect.width, bounds.height / rect.height, alignsLeading ? 1 : 1.3)
            guard scale > 0 else { return }
            let x = alignsLeading ? CGFloat.zero : (bounds.width - rect.width * scale) / 2
            let y = alignsLeading ? CGFloat.zero : (bounds.height - rect.height * scale) / 2
            canvas.frame = CGRect(x: x - rect.minX * scale, y: y - rect.minY * scale,
                                  width: StageSpace.size.width * scale, height: StageSpace.size.height * scale)
            canvas.bounds = CGRect(origin: .zero, size: StageSpace.size)
            return
        }
        let s = StageSpace.scale(for: bounds.size)
        let frame = CGRect(x: bounds.midX - StageSpace.pivot.x * s, y: StageSpace.pivot.y - StageSpace.pivot.y * s,
                           width: StageSpace.size.width * s, height: StageSpace.size.height * s)
        guard canvas.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = frame
        canvas.bounds = CGRect(origin: .zero, size: StageSpace.size)
        CATransaction.commit()
    }

    // MARK: finding

    /// A part's layer, for a move of a chapter's own.
    func layer(for key: String) -> CALayer? { nodes[key]?.layer }

    /// Where a part is on screen now, in stage points, mid-move included.
    func visualFrame(for key: String) -> CGRect? { nodes[key].map(visualFrame) }

    /// The keys on the stage now, parts in parts included, for the bench.
    var keys: [String] { nodes.keys.sorted() }

    /// A part's plate in another fill at once, with no board: the backdrop
    /// following the Color editor's dot while it is dragged. The next board
    /// says the same, or the plate takes the board's.
    func paint(_ key: String, fill: NSColor) {
        nodes[key]?.paint(fill)
    }

    /// A press on a part: in to `scale` about its middle and back, 0.26 s.
    func press(_ key: String, to scale: CGFloat) {
        guard let node = nodes[key], let layer = node.layer else { return }
        let size = node.bounds.size
        let squeeze = Self.transform(size: size, anchor: layer.anchorPoint, scale: CGSize(width: scale, height: scale),
                                     about: CGPoint(x: size.width / 2, y: size.height / 2))
        let animation = WelcomeMotion.keyframes("transform", values: [CATransform3DIdentity, squeeze, CATransform3DIdentity].map { NSValue(caTransform3D: $0) },
                                                times: [0, 0.4, 1], duration: 0.26, curve: .easeOut, on: layer)
        animation.isAdditive = true
        layer.add(animation, forKey: "press")
    }

    // MARK: showing a board

    /// Puts the board on the stage. Animated, what stays glides from where
    /// it is now to where it now goes, what's new comes in and what's gone
    /// leaves, each in its own way; still (a jump, the bench), it simply is.
    /// With Reduce Motion, every move is one 0.20 crossfade, in the same order.
    func show(_ board: WelcomeBoard, animated: Bool, reduceMotion: Bool) {
        // Where everything is on screen before anything changes.
        var before: [String: CGRect] = [:]
        for (key, node) in nodes { before[key] = visualFrame(node) }

        // The new tree, parents first, each with its place in stage points.
        struct Entry { let part: StagePart; let parent: String? }
        var entries: [Entry] = []
        var newFrames: [String: CGRect] = [:]
        func walk(_ parts: [StagePart], parent: String?, origin: CGPoint) {
            for part in parts {
                let absolute = part.frame.offsetBy(dx: origin.x, dy: origin.y)
                entries.append(Entry(part: part, parent: parent))
                newFrames[part.key] = absolute
                walk(part.children, parent: part.key, origin: absolute.origin)
            }
        }
        walk(board.parts, parent: nil, origin: .zero)

        let old = nodes
        var kept: Set<String> = []
        var fresh: Set<String> = []
        var next: [String: WelcomePartView] = [:]
        var order: [String: [WelcomePartView]] = [:]
        var newTops: [WelcomePartView] = []

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for entry in entries {
            let part = entry.part
            let parentNode = entry.parent.flatMap { next[$0] }
            let host: NSView = parentNode ?? canvas
            let node: WelcomePartView
            if let found = old[part.key], next[part.key] == nil {
                node = found
                kept.insert(part.key)
                let oldSize = node.frame.size
                if node.superview !== host || node.parentNode !== parentNode {
                    node.removeFromSuperview()
                    host.addSubview(node)
                    node.parentNode = parentNode
                }
                node.update(part)
                node.frame = part.frame
                node.fit(from: oldSize, animated: animated && !reduceMotion)
            } else {
                node = WelcomePartView(part)
                node.parentNode = parentNode
                host.addSubview(node)
                node.frame = part.frame
                node.fit(from: part.frame.size, animated: false)
                fresh.insert(part.key)
            }
            next[part.key] = node
            if let parentNode { order[parentNode.key, default: []].append(node) } else { newTops.append(node) }
        }

        // What's gone leaves: on its own, or with its parent, or as a ghost
        // of itself inside a parent that stays.
        var leaving: [WelcomePartView] = []
        for (key, node) in old where next[key] == nil {
            node.leaving = true
            leaving.append(node)
        }

        // Order, by each layer's place among its siblings rather than by
        // moving views about (a view taken out loses its moves): what
        // leaves under what stays, the rest as the board has it.
        for node in leaving { node.layer?.zPosition = -1 }
        for (index, node) in newTops.enumerated() { node.layer?.zPosition = CGFloat(index) }
        for (_, children) in order {
            for (index, node) in children.enumerated() { node.layer?.zPosition = CGFloat(index) }
        }
        nodes = next

        CATransaction.commit()

        guard animated else {
            for node in leaving { node.removeFromSuperview() }
            return
        }

        // Moves, in and out.
        var jumped = false
        for entry in entries {
            let part = entry.part
            guard let node = next[part.key] else { continue }
            if kept.contains(part.key) {
                guard let was = before[part.key] else { continue }
                // With Reduce Motion it is at its new place at once, and
                // the stage crossfades from how it looked (below).
                if reduceMotion {
                    if let now = newFrames[part.key], !Self.same(was, now) { jumped = true }
                    continue
                }
                // Relative to the parent: where it was inside it, if the
                // parent moves too; else where it was on the stage.
                var from = was
                if let parent = entry.parent, let parentWas = before[parent], kept.contains(parent) {
                    from = was.offsetBy(dx: -parentWas.minX, dy: -parentWas.minY)
                } else if let parent = entry.parent, let parentNow = newFrames[parent] {
                    from = was.offsetBy(dx: -parentNow.minX, dy: -parentNow.minY)
                }
                node.flip(from: from, to: part.frame, arc: part.arc)
            } else if fresh.contains(part.key) {
                let parentComing = entry.parent.map { fresh.contains($0) } ?? false
                if parentComing && part.enter == nil && part.delay == nil { continue }
                let kind = part.enter ?? .fade
                let delay = part.delay ?? 0
                if reduceMotion {
                    // There at once stays there at once: a grain that comes
                    // with its window isn't seen fading past its amount.
                    if kind != .none { node.enter(.crossfade, delay: delay, source: nil, reduced: true) }
                    continue
                }
                var source: CGRect?
                if case .grow(let key) = kind, let rect = before[key] ?? newFrames[key] {
                    let parentOrigin = entry.parent.flatMap { newFrames[$0]?.origin } ?? .zero
                    source = rect.offsetBy(dx: -parentOrigin.x, dy: -parentOrigin.y)
                }
                node.enter(kind, delay: delay, source: source, reduced: false)
            }
        }

        // Reduce Motion: what moved or changed size is not seen moving. The
        // stage as it was fades out over the stage as it is, one 0.20
        // crossfade on the render server: a fading copy at the old place,
        // the part appearing at the new.
        if jumped, let layer = canvas.layer {
            let crossfade = CATransition()
            crossfade.type = .fade
            crossfade.duration = 0.2 * WelcomeMotion.pace
            crossfade.timingFunction = WelcomeCurve.linear.function
            layer.add(crossfade, forKey: "reduced")
        }

        for node in leaving {
            if let parent = node.parentNode, parent.leaving {
                // Goes with its parent.
                continue
            }
            let exit: StagePart.Exit
            if node.parentNode != nil {
                exit = .crossfade
            } else {
                exit = reduceMotion ? .crossfade : board.exits[node.key] ?? node.part.exit
            }
            var target: CGRect?
            if case .toward(let key) = exit { target = newFrames[key] }
            let length = node.leave(exit, was: before[node.key], toward: target, reduced: reduceMotion)
            DispatchQueue.main.asyncAfter(deadline: .now() + length + 0.05) { [weak node] in
                guard let node, node.leaving else { return }
                node.removeFromSuperview()
            }
        }
    }

    // MARK: geometry

    /// Two places the eye can't tell apart.
    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5 && abs(a.width - b.width) < 0.5 && abs(a.height - b.height) < 0.5
    }

    /// Where a node is on screen now in stage points: its frame, through
    /// its own and every parent's transform as the render server has it.
    func visualFrame(_ node: WelcomePartView) -> CGRect {
        var rect = CGRect(origin: .zero, size: node.frame.size)
        var current: WelcomePartView? = node
        while let n = current {
            rect = n.presented(rect)
            current = n.parentNode
        }
        return rect
    }

    /// A scale about a point of a layer and a move, as a transform about
    /// the layer's own anchor.
    static func transform(size: CGSize, anchor: CGPoint, scale: CGSize = CGSize(width: 1, height: 1),
                          about center: CGPoint = .zero, move: CGPoint = .zero) -> CATransform3D {
        let a = CGPoint(x: anchor.x * size.width, y: anchor.y * size.height)
        let c = CGPoint(x: center.x - a.x, y: center.y - a.y)
        var t = CATransform3DMakeTranslation(-c.x, -c.y, 0)
        t = CATransform3DConcat(t, CATransform3DMakeScale(scale.width, scale.height, 1))
        t = CATransform3DConcat(t, CATransform3DMakeTranslation(c.x + move.x, c.y + move.y, 0))
        return t
    }
}

/// A view whose points run down, as the stage's do.
final class WelcomeFlippedView: NSView {
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

// MARK: - SwiftUI under the stage's scale

/// SwiftUI takes its view's place in the window as a move alone: under the
/// canvas's bounds, scaled to the window (1:1 only at 1180 × 780), it lays
/// out and hit-tests as if nothing were scaled, off from where it is drawn
/// by the scale, growing from the view's corner. A press on a switch or a
/// button drawn under the pointer went nowhere (Keep its spaces and Get
/// Started in a MacBook Air's window, 2026-10-18). So an AppKit control in
/// it (a switch is an NSSwitch) is found by AppKit's frames, which know the
/// scale, and a press on SwiftUI's own is handed to it at the point it lays
/// that spot out at (WelcomePointer). YAB_NARROW_WELCOME_HOSTING=0 leaves it
/// all as it was, for a before and after (evals/welcome-keep).
private let welcomeHostingHears = Narrow.on("WELCOME_HOSTING")

/// SwiftUI hosted under the stage's scale, that a press can be handed to.
@MainActor
protocol WelcomeScaledHost: NSView {
    var scaled: Bool { get }
    func unscaled(_ window: NSPoint) -> NSPoint
}

final class WelcomeHostingView<Content: View>: NSHostingView<Content>, WelcomeScaledHost {
    /// Drawn at another size than its own: something above it is scaled.
    var scaled: Bool {
        guard welcomeHostingHears, window != nil else { return false }
        let unit = convert(NSSize(width: 1, height: 1), to: nil)
        return abs(abs(unit.width) - 1) > 0.001 || abs(abs(unit.height) - 1) > 0.001
    }

    /// A window point as SwiftUI takes it: the same spot of this view, laid
    /// out unscaled from where its corner is.
    func unscaled(_ window: NSPoint) -> NSPoint {
        let local = convert(window, from: nil)
        let corner = convert(NSPoint.zero, to: nil)
        return NSPoint(x: corner.x + local.x, y: isFlipped ? corner.y - local.y : corner.y + local.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard scaled, !isHidden, let superview, frame.contains(point) else { return super.hitTest(point) }
        return control(at: convert(point, from: superview), in: self) ?? super.hitTest(point)
    }

    /// The AppKit control drawn at a point of `view`, by frames alone:
    /// SwiftUI's own boxes around one can be empty, the control hanging out.
    private func control(at point: NSPoint, in view: NSView) -> NSView? {
        for child in view.subviews.reversed() where !child.isHidden {
            let inside = child.convert(point, from: view)
            if let found = control(at: inside, in: child) { return found }
            if child is NSControl, child.bounds.contains(inside) { return child }
        }
        return nil
    }
}

/// A press on SwiftUI under the stage's scale, moved before the window sends
/// it: the event itself, so SwiftUI's gestures, which read it before the
/// view does, have the point SwiftUI lays that spot out at; the view it was
/// over pinned as the one a moved press finds (WelcomeOverlayView.hitTest);
/// its drags and its let go moved the same way. On while the welcome is in
/// a window.
@MainActor
enum WelcomePointer {
    private static var monitor: Any?
    /// The view the press in hand is for.
    private static weak var held: (any WelcomeScaledHost)?
    /// The view the moved press's hit test finds, until it is sent.
    private(set) static weak var pinned: NSView?

    static func start() {
        guard monitor == nil, welcomeHostingHears else { return }
        let kinds: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: kinds) { event in
            MainActor.assumeIsolated { hand(event) }
        }
    }

    static func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        held = nil
        pinned = nil
    }

    private static func hand(_ event: NSEvent) -> NSEvent {
        switch event.type {
        case .leftMouseDown, .rightMouseDown:
            held = nil
            guard let window = event.window, let top = window.contentView?.superview,
                  let hit = top.hitTest(top.convert(event.locationInWindow, from: nil)),
                  !(hit is NSControl), let host = host(of: hit), host.scaled else { return event }
            held = host
            pinned = host
            DispatchQueue.main.async { MainActor.assumeIsolated { pinned = nil } }
            return moved(event, host)
        case .leftMouseDragged, .rightMouseDragged:
            guard let held, held.window === event.window else { return event }
            return moved(event, held)
        case .leftMouseUp, .rightMouseUp:
            guard let host = held, host.window === event.window else { return event }
            held = nil
            return moved(event, host)
        default:
            return event
        }
    }

    private static func host(of view: NSView) -> (any WelcomeScaledHost)? {
        var node: NSView? = view
        while let at = node {
            if let host = at as? any WelcomeScaledHost { return host }
            node = at.superview
        }
        return nil
    }

    private static func moved(_ event: NSEvent, _ host: any WelcomeScaledHost) -> NSEvent {
        NSEvent.mouseEvent(with: event.type, location: host.unscaled(event.locationInWindow), modifierFlags: event.modifierFlags,
                           timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil, eventNumber: event.eventNumber,
                           clickCount: event.clickCount, pressure: event.pressure) ?? event
    }
}

// MARK: - a part's view

@MainActor
final class WelcomePartView: NSView {
    let key: String
    private(set) var part: StagePart
    weak var parentNode: WelcomePartView?
    var leaving = false
    private var plateView: WelcomePlateView?
    private var host: WelcomeHostingView<AnyView>?
    private var drawn: CALayer?
    private var drawnHost: NSView?

    init(_ part: StagePart) {
        self.key = part.key
        self.part = part
        super.init(frame: part.frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !leaving, !isHidden else { return nil }
        guard let hit = super.hitTest(point) else { return nil }
        if hit === self || hit === plateView || hit === drawnHost { return nil }
        if let host, hit.isDescendant(of: host), !part.takesClicks { return nil }
        return hit
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (drawn as? WelcomeRingLayer)?.paint(effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        (drawn as? WelcomeRingLayer)?.paint(effectiveAppearance)
    }

    private func build() {
        if let plate = part.plate {
            let view = WelcomePlateView(plate)
            addSubview(view, positioned: .below, relativeTo: nil)
            plateView = view
        }
        switch part.drawing {
        case .none: break
        case .view(let content):
            let hosting = WelcomeHostingView(rootView: content)
            hosting.sizingOptions = []
            hosting.safeAreaRegions = []
            hosting.translatesAutoresizingMaskIntoConstraints = true
            addSubview(hosting)
            host = hosting
        case .layer(let make):
            let view = WelcomeFlippedView()
            view.wantsLayer = true
            let layer = make()
            view.layer?.addSublayer(layer)
            addSubview(view)
            drawn = layer
            drawnHost = view
            (layer as? WelcomeRingLayer)?.paint(effectiveAppearance)
        }
    }

    /// The same key on a new board: its drawing and plate brought up to
    /// date, in place.
    func update(_ part: StagePart) {
        let before = self.part
        self.part = part
        leaving = false
        if let plate = part.plate {
            if let plateView { plateView.plate = plate } else {
                let view = WelcomePlateView(plate)
                addSubview(view, positioned: .below, relativeTo: nil)
                plateView = view
            }
        } else if let plateView {
            plateView.removeFromSuperview()
            self.plateView = nil
        }
        switch part.drawing {
        case .view(let content):
            if let host {
                if part.version == nil || part.version != before.version { host.rootView = content }
            } else {
                drawnHost?.removeFromSuperview(); drawnHost = nil; drawn = nil
                let hosting = WelcomeHostingView(rootView: content)
                hosting.sizingOptions = []
                hosting.safeAreaRegions = []
                addSubview(hosting)
                host = hosting
            }
        case .layer(let make):
            if drawn == nil {
                host?.removeFromSuperview(); host = nil
                let view = WelcomeFlippedView()
                view.wantsLayer = true
                let layer = make()
                view.layer?.addSublayer(layer)
                addSubview(view)
                drawn = layer
                drawnHost = view
                (layer as? WelcomeRingLayer)?.paint(effectiveAppearance)
            }
        case .none:
            host?.removeFromSuperview(); host = nil
            drawnHost?.removeFromSuperview(); drawnHost = nil; drawn = nil
        }
    }

    /// The plate and the drawing at the part's size. From another size,
    /// animated and pinned: the plate reshapes on the render server.
    func fit(from old: CGSize, animated: Bool) {
        let bounds = CGRect(origin: .zero, size: frame.size)
        plateView?.frame = bounds
        host?.frame = bounds
        drawnHost?.frame = bounds
        drawn?.frame = bounds
        if animated, part.resize == .pin, old != frame.size, let plateView {
            plateView.reshape(from: old)
        }
    }

    /// Its plate in another fill, now.
    func paint(_ fill: NSColor) {
        guard var plate = part.plate, let plateView else { return }
        plate.fill = fill
        part.plate = plate
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plateView.plate = plate
        CATransaction.commit()
    }

    // MARK: moving

    /// A rect in this part's points, in its parent's, as it is on screen now.
    func presented(_ rect: CGRect) -> CGRect {
        guard let layer else { return rect.offsetBy(dx: frame.minX, dy: frame.minY) }
        let shown = layer.presentation() ?? layer
        let transform = shown.transform
        let a = CGPoint(x: layer.anchorPoint.x * frame.width, y: layer.anchorPoint.y * frame.height)
        let affine = CATransform3DIsAffine(transform) ? CATransform3DGetAffineTransform(transform) : .identity
        let local = rect.offsetBy(dx: -a.x, dy: -a.y).applying(affine)
        return local.offsetBy(dx: frame.minX + a.x, dy: frame.minY + a.y)
    }

    /// From where it was (in its parent's points now) to where it is, on
    /// glide, or on an arc.
    func flip(from old: CGRect, to new: CGRect, arc: CGFloat) {
        guard let layer else { return }
        let moved = abs(old.minX - new.minX) > 0.5 || abs(old.minY - new.minY) > 0.5
        let resized = abs(old.width - new.width) > 0.5 || abs(old.height - new.height) > 0.5
        guard moved || resized else { return }
        let scale = part.resize == .stretch && resized
            ? CGSize(width: old.width / max(new.width, 1), height: old.height / max(new.height, 1))
            : CGSize(width: 1, height: 1)
        let start = WelcomeStageView.transform(size: new.size, anchor: layer.anchorPoint, scale: scale, about: .zero,
                                        move: CGPoint(x: old.minX - new.minX, y: old.minY - new.minY))
        layer.removeAnimation(forKey: "flip")
        if arc != 0 {
            let mid = WelcomeStageView.transform(size: new.size, anchor: layer.anchorPoint,
                                          scale: CGSize(width: (scale.width + 1) / 2, height: (scale.height + 1) / 2), about: .zero,
                                          move: CGPoint(x: (old.minX - new.minX) / 2, y: min(old.minY, new.minY) - new.minY - abs(arc)))
            let animation = WelcomeMotion.keyframes("transform", values: [start, mid, CATransform3DIdentity].map { NSValue(caTransform3D: $0) },
                                                    times: [0, 0.5, 1], duration: 0.43, curve: .travel, on: layer)
            layer.add(animation, forKey: "flip")
        } else {
            let animation = WelcomeMotion.animation("transform", from: NSValue(caTransform3D: start), to: NSValue(caTransform3D: CATransform3DIdentity),
                                                    curve: .glide, duration: 0.34, on: layer)
            layer.add(animation, forKey: "flip")
        }
    }

    /// Comes in its own way, `delay` seconds from now.
    func enter(_ kind: StagePart.Enter, delay: Double, source: CGRect?, reduced: Bool) {
        guard let layer else { return }
        let size = frame.size
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        // Clear to its own opacity: a part whose opacity says how much of
        // it shows (the grain) comes in to that, not past it.
        let opaque = layer.opacity
        func fade(_ curve: WelcomeCurve, _ duration: Double) {
            layer.add(WelcomeMotion.animation("opacity", from: 0, to: opaque, curve: curve, duration: duration, delay: delay, on: layer), forKey: "enter.opacity")
        }
        func move(_ from: CATransform3D, _ curve: WelcomeCurve, _ duration: Double) {
            layer.add(WelcomeMotion.animation("transform", from: NSValue(caTransform3D: from), to: NSValue(caTransform3D: CATransform3DIdentity),
                                              curve: curve, duration: duration, delay: delay, on: layer), forKey: "enter.transform")
        }
        func t(dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) -> CATransform3D {
            WelcomeStageView.transform(size: size, anchor: layer.anchorPoint, scale: CGSize(width: scale, height: scale), about: middle, move: CGPoint(x: dx, y: dy))
        }
        if reduced {
            fade(.linear, 0.2)
            return
        }
        switch kind {
        case .none: return
        case .fade: move(t(scale: 0.96), .arrive, 0.22); fade(.arrive, 0.22)
        case .crossfade: fade(.arrive, 0.22)
        case .words: move(t(scale: 0.98), .arrive, 0.22); fade(.arrive, 0.22)
        case .rise: move(t(dy: 8, scale: 0.96), .rise, 0.26); fade(.rise, 0.26)
        case .pop: move(t(scale: 0.6), .settle, 0.3); fade(.linear, 0.12)
        case .slideX: move(t(dx: -24), .settle, 0.3); fade(.settle, 0.3)
        case .slideY: move(t(dy: -28), .settle, 0.3); fade(.settle, 0.3)
        case .up6: move(t(dy: 6), .arrive, 0.22); fade(.arrive, 0.22)
        case .up12: move(t(dy: 12), .settle, 0.3); fade(.settle, 0.3)
        case .drop: move(t(scale: 0.9), .settle, 0.3); fade(.linear, 0.15)
        case .drop85: move(t(scale: 0.85), .settle, 0.3); fade(.linear, 0.15)
        case .grow94: move(t(scale: 0.94), .settle, 0.3); fade(.linear, 0.18)
        case .chat: move(t(dx: 24), .settle, 0.3); fade(.settle, 0.3)
        case .ring: fade(.linear, 0.12)
        case .pick: move(t(scale: 0.9), .spring(response: 0.42, damping: 0.72), 0.42); fade(.linear, 0.12)
        case .lede: move(t(dy: 8), .spring(response: 0.5, damping: 1), 0.5); fade(.spring(response: 0.5, damping: 1), 0.5)
        case .pour:
            let values = [t(scale: 0.6), t(scale: 0.8), t(scale: 1.06), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            layer.add(WelcomeMotion.keyframes("transform", values: values, times: [0, 0.3, 0.6, 1], duration: 0.36, curve: .easeOut, delay: delay, on: layer), forKey: "enter.transform")
            layer.add(WelcomeMotion.keyframes("opacity", values: [0, 1, 1], times: [0, 0.3, 1], duration: 0.36, curve: .easeOut, delay: delay, on: layer), forKey: "enter.opacity")
        case .tick:
            let values = [t(scale: 0.4), t(scale: 1.08), CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            let tick = WelcomeMotion.keyframes("transform", values: values, times: [0, 0.55, 1], duration: 0.5, curve: .linear, delay: delay, on: layer)
            tick.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.3, 1.2, 0.5, 1), CAMediaTimingFunction(controlPoints: 0.3, 1.2, 0.5, 1)]
            layer.add(tick, forKey: "enter.transform")
            fade(.linear, 0.09)
        case .grow:
            if let source {
                let scale = CGSize(width: source.width / max(size.width, 1), height: source.height / max(size.height, 1))
                let from = WelcomeStageView.transform(size: size, anchor: layer.anchorPoint, scale: scale, about: .zero,
                                               move: CGPoint(x: source.minX - frame.minX, y: source.minY - frame.minY))
                move(from, .glide, 0.34)
                fade(.linear, 0.12)
            } else {
                move(t(scale: 0.96), .arrive, 0.22); fade(.arrive, 0.22)
            }
        }
    }

    /// Leaves its own way; how long that takes.
    func leave(_ kind: StagePart.Exit, was: CGRect?, toward target: CGRect?, reduced: Bool) -> Double {
        guard let layer else { return 0 }
        let size = frame.size
        let middle = CGPoint(x: size.width / 2, y: size.height / 2)
        // Out from wherever it is now: a move under way stops there.
        let now = layer.presentation()?.transform ?? CATransform3DIdentity
        layer.removeAllAnimations()
        layer.transform = now
        func t(dx: CGFloat = 0, dy: CGFloat = 0, scale: CGFloat = 1) -> CATransform3D {
            CATransform3DConcat(now, WelcomeStageView.transform(size: size, anchor: layer.anchorPoint, scale: CGSize(width: scale, height: scale),
                                                         about: middle, move: CGPoint(x: dx, y: dy)))
        }
        var longest = 0.0
        func go(_ to: CATransform3D?, _ curve: WelcomeCurve, _ duration: Double) {
            if let to {
                let move = WelcomeMotion.animation("transform", from: NSValue(caTransform3D: now), to: NSValue(caTransform3D: to),
                                                   curve: curve, duration: duration, on: layer, fill: .forwards)
                layer.add(move, forKey: "leave.transform")
                longest = max(longest, WelcomeMotion.length(move))
            }
            let fade = WelcomeMotion.animation("opacity", from: layer.presentation()?.opacity ?? 1, to: 0, curve: curve, duration: duration, on: layer, fill: .forwards)
            layer.add(fade, forKey: "leave.opacity")
            longest = max(longest, WelcomeMotion.length(fade))
        }
        if reduced {
            go(nil, .linear, 0.2)
            return longest
        }
        switch kind {
        case .none:
            isHidden = true
            return 0
        case .shrink: go(t(scale: 0.98), .depart, 0.15)
        case .fastFade: go(nil, .linear, 0.12)
        case .crossfade: go(nil, .linear, 0.15)
        case .sink: go(t(dy: 14), .depart, 0.2)
        case .fold: go(t(dy: -330, scale: 0.45), .rise, 0.3)
        case .tuck: go(t(scale: 0.9), .depart, 0.18)
        case .toward:
            if let target, let was {
                let dx = (target.midX - was.midX) * 0.4, dy = (target.midY - was.midY) * 0.4
                go(t(dx: dx, dy: dy, scale: 0.9), .depart, 0.19)
            } else {
                go(t(scale: 0.98), .depart, 0.15)
            }
        }
        return longest
    }
}

// MARK: - a plate

/// A part's ground in Core Animation: resolved against the window's look
/// each time it changes, its shadow cast from its outline.
@MainActor
final class WelcomePlateView: NSView {
    var plate: StagePlate { didSet { needsDisplay = true; updateLayer() } }

    init(_ plate: StagePlate) {
        self.plate = plate
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Light or dark: its fill, ring and shadow resolved again.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func updateLayer() {
        guard let layer else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer.backgroundColor = plate.fill.cgColor
            layer.cornerRadius = plate.corner
            layer.cornerCurve = .continuous
            layer.borderWidth = plate.ring == nil ? 0 : plate.ringWidth
            layer.borderColor = plate.ring?.cgColor
            if let shadow = plate.shadow {
                layer.shadowColor = NSColor.black.cgColor
                layer.shadowOpacity = shadow.opacity
                layer.shadowRadius = shadow.radius
                // Down the screen, whichever way the layer's points run.
                layer.shadowOffset = CGSize(width: 0, height: layer.contentsAreFlipped() ? shadow.y : -shadow.y)
                layer.shadowPath = CGPath.rounded(bounds, corner: plate.corner)
            } else {
                layer.shadowOpacity = 0
                layer.shadowPath = nil
            }
        }
    }

    override func layout() {
        super.layout()
        guard let layer, plate.shadow != nil else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.shadowPath = CGPath.rounded(bounds, corner: plate.corner)
        CATransaction.commit()
    }

    /// From another size to its own, on glide: its bounds, its shadow's
    /// outline and its corner, on the render server.
    func reshape(from old: CGSize) {
        guard let layer else { return }
        let was = CGRect(origin: .zero, size: old), now = CGRect(origin: .zero, size: bounds.size)
        let anchor = layer.anchorPoint
        let bounds = WelcomeMotion.animation("bounds", from: NSValue(rect: was), to: NSValue(rect: now), curve: .glide, duration: 0.34, on: layer)
        layer.add(bounds, forKey: "reshape.bounds")
        // The anchor stays where it is: the position follows the size.
        let from = CGPoint(x: frame.minX + anchor.x * old.width, y: frame.minY + anchor.y * old.height)
        let to = CGPoint(x: frame.minX + anchor.x * now.width, y: frame.minY + anchor.y * now.height)
        if from != to {
            layer.add(WelcomeMotion.animation("position", from: NSValue(point: from), to: NSValue(point: to), curve: .glide, duration: 0.34, on: layer),
                      forKey: "reshape.position")
        }
        if plate.shadow != nil {
            layer.add(WelcomeMotion.animation("shadowPath", from: CGPath.rounded(was, corner: plate.corner),
                                              to: CGPath.rounded(now, corner: plate.corner),
                                              curve: .glide, duration: 0.34, on: layer), forKey: "reshape.shadow")
        }
    }
}
