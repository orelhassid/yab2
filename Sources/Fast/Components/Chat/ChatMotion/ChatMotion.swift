import AppKit
import SwiftUI

// Your words sent, and the answer coming, drawn the same wherever a chat
// is had: the ⌘J field's answer (FieldAnswer) and the column (ChatColumn)
// take their pieces from here, so the two never drift apart
// (docs/chat-motion.md).
//
// - The words you sent go up from the field into your line (SendFlight),
//   the line's ground coming up around them; the field stays and empties.
// - What it does now is one line of words (MorphWords): a new state's
//   words change in place, the letters the two share standing still.
// - Its answer comes in as it is written, each new stretch of words fading
//   in over the ones already there (FreshText).
//
// All of it cheap on purpose, as sending and answering are the path most
// worn: the flight is Core Animation over the window, drawn once; a
// stretch's fade is one text's draw a frame for 150 ms, and only the text
// still being written has one.

// MARK: - your words, sent

/// The words in the field go up into the line they become. A layer over
/// the window carries them, their picture taken from the field's own
/// text as it stood, and flies them to where the line comes out; landed,
/// the line shows and the layer goes in the same beat, so nothing is ever
/// drawn twice or missing.
@MainActor
enum SendFlight {
    /// How long the words travel: the column's own curve (Motion.chatIn),
    /// most of the way in the first third, then settling.
    static let span: CFTimeInterval = 0.3
    private static let curve = CAMediaTimingFunction(controlPoints: 0.19, 1, 0.22, 1)
    /// Where the words wait for their line to come out before they give up.
    private static let patience: TimeInterval = 0.7

    private static var flight: Flight?

    private final class Flight {
        let text: String
        let bubble: Bool
        let sky: SendSky
        let plate = CALayer()
        let words = CALayer()
        let landed = CALayer()
        /// The words' place in the sky, and their size there.
        let from: CGRect
        let size: CGFloat
        let ink: NSColor
        let ground: NSColor
        let scale: CGFloat
        var target: CGRect?
        /// Where the line is now, asked again as the column scrolls.
        var place: (() -> CGRect?)?
        var settling = false
        /// Every line waiting on these words: all show as they land.
        var reveals: [() -> Void] = []
        var done = false

        init(text: String, bubble: Bool, sky: SendSky, from: CGRect, size: CGFloat, ink: NSColor, ground: NSColor, scale: CGFloat) {
            self.text = text
            self.bubble = bubble
            self.sky = sky
            self.from = from
            self.size = size
            self.ink = ink
            self.ground = ground
            self.scale = scale
        }
    }

    /// Whether a line with these words is the one the words are on their
    /// way to: it comes out hidden, and shows when they land.
    static func awaits(_ text: String) -> Bool {
        guard let flight, !flight.done else { return false }
        return flight.text == text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The words in the field that has the keys in `window`, taken where
    /// they stand, before the field empties. Nothing with Reduce Motion:
    /// the line then just shows where it goes.
    static func takeOff(_ text: String, in window: NSWindow?, bubble: Bool = false) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        abandon()
        guard !text.isEmpty, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let window, let editor = window.firstResponder as? NSTextView,
              editor.string.trimmingCharacters(in: .whitespacesAndNewlines) == text,
              let manager = editor.layoutManager, let container = editor.textContainer,
              let content = window.contentView, let frame = content.superview else { return }
        let glyphs = manager.glyphRange(for: container)
        var used = manager.boundingRect(forGlyphRange: glyphs, in: container)
        used.origin.x += editor.textContainerOrigin.x
        used.origin.y += editor.textContainerOrigin.y
        // A line longer than its field is scrolled: only what shows goes.
        let shown = used.intersection(editor.visibleRect).integral
        guard shown.width > 2, shown.height > 2 else { return }
        let scale = window.backingScaleFactor
        guard let picture = draw(size: shown.size, scale: scale, { context in
            context.translateBy(x: -shown.minX, y: -shown.minY)
            editor.effectiveAppearance.performAsCurrentDrawingAppearance {
                manager.drawGlyphs(forGlyphRange: glyphs, at: editor.textContainerOrigin)
            }
        }) else { return }

        let sky = SendSky(frame: content.frame)
        sky.autoresizingMask = [.width, .height]
        frame.addSubview(sky, positioned: .above, relativeTo: content)
        let from = sky.convert(editor.convert(shown, to: nil), from: nil)
        var ink = NSColor.black, ground = NSColor.black.withAlphaComponent(0.05)
        editor.effectiveAppearance.performAsCurrentDrawingAppearance {
            let resolved = Palette.NS.ink.usingColorSpace(.sRGB) ?? .black
            ink = bubble ? .white : resolved
            ground = bubble ? NSColor.controlAccentColor : resolved.withAlphaComponent(0.05)
        }
        let flight = Flight(text: text, bubble: bubble, sky: sky, from: from, size: editor.font?.pointSize ?? 13.5, ink: ink, ground: ground, scale: scale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let plate = flight.plate
        plate.anchorPoint = .zero
        plate.frame = from.insetBy(dx: -12, dy: -8)
        plate.cornerRadius = Radius.floating
        plate.cornerCurve = .continuous
        plate.backgroundColor = ground.cgColor
        plate.opacity = 0
        // Top left pinned, as words are set: y up in the sky, so the anchor's top is 1.
        for layer in [flight.words, flight.landed] {
            layer.anchorPoint = CGPoint(x: 0, y: 1)
            layer.contentsScale = scale
            layer.contentsGravity = .topLeft
        }
        flight.words.contents = picture
        flight.words.bounds = CGRect(origin: .zero, size: from.size)
        flight.words.position = CGPoint(x: from.minX, y: from.maxY)
        flight.landed.position = flight.words.position
        flight.landed.opacity = 0
        sky.layer?.addSublayer(plate)
        sky.layer?.addSublayer(flight.words)
        sky.layer?.addSublayer(flight.landed)
        CATransaction.commit()
        // The words leave the field in the beat their picture shows over
        // it: the field's own emptying comes a pass or two later, so it is
        // out of sight until then, never both drawn a pixel apart, never
        // neither.
        let field = (editor.delegate as? NSView) ?? editor
        field.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { field.alphaValue = 1 }
        self.flight = flight
        // The line never came (a message queued, a chat that went): the
        // words go where they stand.
        DispatchQueue.main.asyncAfter(deadline: .now() + patience) { [weak flight] in
            guard let flight, flight === self.flight, flight.target == nil else { return }
            abandon()
        }
    }

    /// The line the words go to, laid out (hidden) in its place: they fly
    /// there, and `reveal` shows it as they land. A line that replaces it
    /// (the same words heard back) only waits with it.
    static func land(window: NSWindow, place: @escaping () -> CGRect?, reveal: @escaping () -> Void) {
        guard let flight, !flight.done, flight.sky.window === window else { reveal(); return }
        flight.reveals.append(reveal)
        flight.place = place
        guard !flight.settling, flight.target == nil else { return }
        flight.settling = true
        follow(flight, tries: 0)
    }

    /// Off at once to where the line stands, then its place read again a
    /// frame at a time while the column settles around it (scrolled to its
    /// foot, a head come in): moved, the words turn toward it on the way.
    private static func follow(_ flight: Flight, tries: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) {
            guard !flight.done, flight === self.flight else { return }
            guard let here = flight.place?() else {
                if flight.target == nil { abandon() }
                return
            }
            let to = flight.sky.convert(here, from: nil)
            if let target = flight.target {
                if abs(target.minX - to.minX) > 0.5 || abs(target.minY - to.minY) > 0.5 {
                    flight.target = to
                    turn(flight, to: to)
                }
            } else {
                flight.target = to
                fly(flight, to: to)
            }
            if tries < 12 { follow(flight, tries: tries + 1) }
        }
    }

    /// The words on their way, sent on to the line's new place.
    private static func turn(_ flight: Flight, to: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { finish(flight) }
        let plate = flight.plate
        let was = plate.presentation()?.frame ?? plate.frame
        plate.position = to.origin
        plate.bounds = CGRect(origin: .zero, size: to.size)
        glide(plate, "position", NSValue(point: was.origin), NSValue(point: to.origin), bubble: flight.bubble)
        glide(plate, "bounds.size", NSValue(size: was.size), NSValue(size: to.size), bubble: flight.bubble)
        let end = CGPoint(x: to.minX + 12, y: to.maxY - 8)
        for layer in [flight.words, flight.landed] {
            let here = layer.presentation()?.position ?? layer.position
            layer.position = end
            glide(layer, "position", NSValue(point: here), NSValue(point: end), bubble: flight.bubble)
        }
        CATransaction.commit()
    }

    private static func glide(_ layer: CALayer, _ key: String, _ from: Any, _ to: Any, bubble: Bool = false) {
        let animation: CABasicAnimation
        if bubble {
            let spring = CASpringAnimation(keyPath: key)
            spring.mass = 1
            spring.stiffness = 360
            spring.damping = 32
            spring.initialVelocity = 0
            animation = spring
        } else {
            animation = CABasicAnimation(keyPath: key)
            animation.timingFunction = curve
        }
        animation.fromValue = from
        animation.toValue = to
        animation.duration = bubble ? 0.42 : span
        layer.add(animation, forKey: key)
    }

    private static func fly(_ flight: Flight, to: CGRect) {
        // The line's own words, as the line sets them: what the field's
        // picture turns into on the way, so it lands on the line exactly.
        let wide = max(10, to.width - 24 - (flight.bubble ? MessageBubble.tailRoom : 0))
        let font = NSFont.systemFont(ofSize: 13.5)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        let words = NSAttributedString(string: flight.text, attributes: [.font: font, .foregroundColor: flight.ink, .paragraphStyle: style])
        let box = words.boundingRect(with: CGSize(width: wide, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: ceil(box.width), height: min(ceil(box.height), to.height - 16))
        let picture = draw(size: size, scale: flight.scale) { _ in
            words.draw(with: CGRect(origin: .zero, size: CGSize(width: wide, height: size.height)), options: [.usesLineFragmentOrigin, .usesFontLeading])
        }
        let start = CGPoint(x: flight.from.minX, y: flight.from.maxY)
        let end = CGPoint(x: to.minX + 12, y: to.maxY - 8)
        // The field's words may be set larger (⌘J's own 20): they come down to the line's size.
        let shrink = 13.5 / max(flight.size, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { finish(flight) }
        let now = CACurrentMediaTime()
        let duration = flight.bubble ? 0.42 : span
        func move(_ layer: CALayer, _ key: String, _ from: Any, _ to: Any) {
            glide(layer, key, from, to, bubble: flight.bubble)
        }
        func fade(_ layer: CALayer, _ values: [Float], _ times: [NSNumber]) {
            let animation = CAKeyframeAnimation(keyPath: "opacity")
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.beginTime = now
            layer.add(animation, forKey: "opacity")
            layer.opacity = values.last ?? 1
        }
        let plate = flight.plate
        let was = plate.presentation()?.frame ?? plate.frame
        // The bubble's tail hangs under its foot: the plate is that much taller.
        let landed = flight.bubble ? CGSize(width: to.size.width, height: to.size.height + MessageBubble.tailDrop) : to.size
        if flight.bubble {
            // Draw the landed bubble once, including its tail. The flight
            // scales this same picture, so landing cannot change its skin.
            plate.contents = draw(size: landed, scale: flight.scale) { context in
                context.setFillColor(flight.ground.cgColor)
                context.addPath(MessageBubble(mine: true).path(in: CGRect(origin: .zero, size: to.size)).cgPath)
                context.fillPath()
            }
            plate.contentsScale = flight.scale
            plate.contentsGravity = .resize
            plate.backgroundColor = nil
            plate.cornerRadius = 0
        }
        // y is up in the sky: the extra height goes under the bubble's foot.
        let foot = CGPoint(x: to.origin.x, y: to.origin.y - (landed.height - to.size.height))
        plate.position = foot
        plate.bounds = CGRect(origin: .zero, size: landed)
        move(plate, "position", NSValue(point: was.origin), NSValue(point: foot))
        move(plate, "bounds.size", NSValue(size: was.size), NSValue(size: landed))
        // The ground comes up around the words as they rise.
        fade(plate, [Float(plate.presentation()?.opacity ?? 0), 1, 1], flight.bubble ? [0, 0.17, 1] : [0, 0.45, 1])

        flight.landed.contents = picture
        flight.landed.bounds = CGRect(origin: .zero, size: size)
        for layer in [flight.words, flight.landed] {
            let here = layer.presentation()?.position ?? start
            layer.position = end
            move(layer, "position", NSValue(point: here), NSValue(point: end))
        }
        flight.words.transform = CATransform3DMakeScale(shrink, shrink, 1)
        move(flight.words, "transform", NSValue(caTransform3D: CATransform3DIdentity), NSValue(caTransform3D: flight.words.transform))
        flight.landed.transform = CATransform3DIdentity
        move(flight.landed, "transform", NSValue(caTransform3D: CATransform3DMakeScale(1 / shrink, 1 / shrink, 1)), NSValue(caTransform3D: CATransform3DIdentity))
        if flight.bubble {
            // The field's ink gives way to white as the accent fill comes
            // up, before differently wrapped letters can overlap.
            fade(flight.landed, [0, 1, 1], [0, 0.17, 1])
            fade(flight.words, [1, 0, 0], [0, 0.17, 1])
        } else if abs(shrink - 1) < 0.01 {
            // The same words at the same size: the line's come in over the
            // field's, then the field's go, never both half there, which
            // would thin the words mid-way.
            fade(flight.landed, [0, 0, 1, 1], [0, 0.2, 0.55, 1])
            fade(flight.words, [1, 1, 0, 0], [0, 0.55, 0.75, 1])
        } else {
            // Set at another size (⌘J's 20), their letters never line up:
            // one gives way to the other early, while they move fastest.
            fade(flight.landed, [0, 0, 1, 1], [0, 0.1, 0.35, 1])
            fade(flight.words, [1, 1, 0, 0], [0, 0.1, 0.35, 1])
        }
        CATransaction.commit()
    }

    private static func finish(_ flight: Flight) {
        // A turn of the flight replaced this run's animations: its own
        // completion comes later.
        guard !flight.done, flight.plate.animation(forKey: "position") == nil else { return }
        flight.done = true
        // The line and the layer change places in one beat.
        flight.reveals.forEach { $0() }
        flight.sky.removeFromSuperview()
        if self.flight === flight { self.flight = nil }
    }

    /// A flight nobody lands: its words go where they are.
    private static func abandon() {
        guard let flight else { return }
        self.flight = nil
        flight.done = true
        flight.reveals.forEach { $0() }
        CATransaction.begin()
        CATransaction.setCompletionBlock { flight.sky.removeFromSuperview() }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.duration = 0.15
        flight.sky.layer?.opacity = 0
        flight.sky.layer?.add(fade, forKey: "opacity")
        CATransaction.commit()
    }

    /// Words drawn once into a picture, top down as text is set.
    private static func draw(size: CGSize, scale: CGFloat, _ body: (CGContext) -> Void) -> CGImage? {
        let width = Int(ceil(size.width * scale)), height = Int(ceil(size.height * scale))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        body(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// Where a line that may be the words' landing is: it tells the
    /// flight once it is laid out.
    struct Landing: NSViewRepresentable {
        let text: String
        /// The line is hidden, waiting for the words.
        let waiting: Bool
        let reveal: () -> Void

        func makeNSView(context: Context) -> MarkView { MarkView() }

        func updateNSView(_ view: MarkView, context: Context) {
            view.reveal = reveal
            guard waiting, !view.asked else { return }
            view.asked = true
            view.tell()
        }

        final class MarkView: NSView {
            var reveal: (() -> Void)?
            /// Its line waits for the words: tell the flight where it is.
            var asked = false
            private var told = false

            override func hitTest(_ point: NSPoint) -> NSView? { nil }

            override func viewDidMoveToWindow() {
                super.viewDidMoveToWindow()
                tell()
            }

            /// Once in its window, laid out and scrolled into its place.
            func tell() {
                guard asked, !told, window != nil else { return }
                told = true
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    guard let window = self.window else { self.reveal?(); return }
                    SendFlight.land(window: window, place: { [weak self] in
                        guard let self, self.window != nil else { return nil }
                        return self.convert(self.bounds, to: nil)
                    }) { [weak self] in self?.reveal?() }
                }
            }
        }
    }
}

/// The layer the words fly on: over everything, taking no clicks.
private final class SendSky: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Your words as sent, on their ground at the right: the line a message
/// becomes in the column and in the ⌘J field alike. Hidden while the
/// words are still on their way to it (SendFlight). In the column they
/// are a message as Messages draws one: on the accent, with its tail.
struct SentWords: View {
    let text: String
    var lines = 14
    var bubble = false
    @State private var hidden: Bool

    init(_ text: String, lines: Int = 14, bubble: Bool = false) {
        self.text = text
        self.lines = lines
        self.bubble = bubble
        _hidden = State(initialValue: SendFlight.awaits(text))
    }

    var body: some View {
        Group {
            if bubble {
                Text(text)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .padding(.trailing, MessageBubble.tailRoom) // design: the tail's room, on its side only
                    .background(MessageBubble(mine: true).fill(Color.accentColor))
            } else {
                Text(text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
            }
        }
        .font(.system(size: 13.5))
        .lineSpacing(2)
        .lineLimit(lines)
        .textSelection(.enabled)
        .background(SendFlight.Landing(text: text, waiting: hidden) { hidden = false })
        .opacity(hidden ? 0 : 1)
        .padding(.bottom, bubble ? MessageBubble.tailDrop : 0) // design: its tail hangs under the foot
    }
}

/// A message's ground as Messages (iOS 26) draws it, and as Yab for
/// iPhone does (its MessageBubble): round, its tail a hook hanging under
/// the foot corner of the side it is said from, yours at the right, the
/// agent's at the left. The tail stays inside the bubble's width and drops
/// `tailDrop` under it, so a bubble's edge is on the turns' line with or
/// without one; only the last of a run has it.
struct MessageBubble: Shape {
    var mine: Bool
    var tail = true
    /// Room kept beside a bubble for its tail: none, it hangs under.
    static let tailRoom: CGFloat = 0
    static let tailDrop: CGFloat = 5
    /// Where the agent's words stand in from the turns' edge: the bubble's
    /// 12. The turn's own rows (Worked for, a step, the answer's buttons)
    /// stand on this line too; cards and plates of its stand on the
    /// bubbles' body.
    static let words: CGFloat = tailRoom + 12

    func path(in rect: CGRect) -> Path {
        let width = rect.width, height = rect.height, edge = width
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: edge, height: height),
                        cornerRadius: min(Radius.window, height / 2), style: .continuous)
        if tail {
            // The hook from the body's foot corner, curling down to a point
            // `tailDrop` under it and just inside its edge (the iPhone's).
            let drop = Self.tailDrop
            func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: edge + x, y: height + y) }
            var hook = Path()
            hook.move(to: at(-22, -2))
            hook.addCurve(to: at(-1, drop), control1: at(-13, 1.5), control2: at(-6, drop))
            hook.addCurve(to: at(-2.5, -12), control1: at(-1.5, drop - 6), control2: at(-2.5, -5))
            hook.closeSubpath()
            path = path.union(hook)
        }
        let turned = mine ? CGAffineTransform.identity : CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        return path.applying(turned.concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

// MARK: - what it does now, in words

/// Words that change in place, as a state's words do: the letters the old
/// and the new begin with stand still, the rest of the old goes up and out
/// as the rest of the new comes up in. Only when the first
/// word changes ("Working" to "Worked", "Thinking" to "Reading"): a clock's
/// seconds just change.
struct MorphWords: View {
    let text: String
    @State private var keep = ""
    @State private var shown: String
    @Environment(\.accessibilityReduceMotion) private var still

    init(_ text: String) {
        self.text = text
        _shown = State(initialValue: text)
    }

    var body: some View {
        HStack(spacing: 0) {
            if !keep.isEmpty { Text(keep) }
            Text(String(shown.dropFirst(keep.count)))
                .id(shown)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 5)),
                                        removal: .opacity.combined(with: .offset(y: -5))))
        }
        .onChange(of: text) { _, new in
            guard new != shown else { return }
            guard !still, let shared = MorphWords.shared(shown, new) else {
                keep = ""
                shown = new
                return
            }
            // What the two share, split off first, drawn as it stands; then
            // the rest changes.
            keep = shared
            withAnimation(Motion.morphWords) { shown = new }
        }
    }

    /// The letters `old` and `new` begin with, when they are different
    /// words to change between; nil when only what follows the first word
    /// changed (a clock's seconds), which just changes.
    static func shared(_ old: String, _ new: String) -> String? {
        func first(_ words: String) -> Substring { words.split(separator: " ").first ?? Substring(words) }
        guard old != new, first(old) != first(new) else { return nil }
        return String(zip(old, new).prefix { $0 == $1 }.map(\.0))
    }
}

extension Motion {
    /// A field's hint coming back once your words have left it.
    static let hintBack = Animation.easeOut(duration: 0.13).delay(0.12)
    /// A state's words changing in place (MorphWords).
    static let morphWords = Animation.timingCurve(0.19, 1, 0.22, 1, duration: 0.26)
}

// MARK: - the answer, as it is written

/// Words still being written come in as ink soaking in: each new stretch
/// at a third, a step darker when the next comes, then in full, so the
/// newest words are always the lightest and the fade runs a beat behind
/// the writing (never an empty frame, the old and the new at
/// once). The steps ride the answer's own updates, ten a second
/// (ChatFeed, SelectionCommands), so the fade costs no frame of its own;
/// when the words stop coming, one more draw sets them in full. The ink is
/// the words' own color, so the text is drawn as any other, no renderer
/// of its own.
struct FreshText: View {
    let rich: AttributedString
    /// The words' size, for math and links' icons (RichMemo.text).
    var size: CGFloat = 13.5
    @State private var seen = Seen()
    @State private var rested = 0
    @Environment(\.accessibilityReduceMotion) private var still

    /// What was drawn: how many characters, and where the two newest
    /// stretches begin.
    final class Seen {
        var count = 0
        var newer = 0
        var newest = 0
        var rest: DispatchWorkItem?

        /// The words now `count` long: the newest stretch a step darker,
        /// the rest behind it in full. False when nothing came.
        @discardableResult func advance(to count: Int) -> Bool {
            guard count != self.count else { return false }
            if count < self.count {
                // Words held back (a mark not closed yet): nothing fresh past them.
                newer = min(newer, count)
                newest = min(newest, count)
            } else {
                newer = newest
                newest = self.count
            }
            self.count = count
            return true
        }

        /// The words stopped coming: all in full.
        func settle() {
            newer = count
            newest = count
        }
    }

    var body: some View {
        let count = rich.characters.count
        let seen = seen
        if seen.advance(to: count) {
            seen.rest?.cancel()
            let rest = DispatchWorkItem { [rested] in
                seen.settle()
                self.rested = rested + 1
            }
            seen.rest = rest
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: rest)
        }
        guard !still, seen.newer < count else { return RichMemo.text(rich, size: size) }
        var inked = rich
        let newer = inked.characters.index(inked.startIndex, offsetBy: seen.newer)
        let newest = inked.characters.index(inked.startIndex, offsetBy: max(seen.newer, seen.newest))
        FreshText.ink(&inked, newer..<newest, 0.66)
        FreshText.ink(&inked, newest..<inked.endIndex, 0.33)
        return RichMemo.text(inked, size: size)
    }

    /// Words at part of their ink; a link keeps its own.
    private static func ink(_ text: inout AttributedString, _ range: Range<AttributedString.Index>, _ ink: Double) {
        guard !range.isEmpty else { return }
        for run in text[range].runs where run.link == nil {
            text[run.range].foregroundColor = Palette.ink.opacity(ink)
        }
    }
}
