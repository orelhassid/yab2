import AppKit
import SwiftUI

// A chat flying out of its card on the column's list and back into it, as
// UIKit's zoom draws a chat out of its card on the iPhone's Chats page. The
// chat has a hosting view of its own (ChatZoomStage), so the whole of it,
// its AppKit scroll and field too, is scaled as one picture on the render
// server: one spring, sampled here, played there, no frame of it worked out
// on the main thread. The card's title flies into the head's capsule.
// docs/chat-zoom.md has the numbers and how it was filmed.

/// The chat's width, told to its own hosting view.
@MainActor
final class ChatPaneLook: ObservableObject {
    @Published var width: CGFloat
    init(width: CGFloat) { self.width = width }
}

/// The words in flight between a card and a chat's head are hidden in both
/// places while they fly, so the title is only ever in one place.
@MainActor
final class ChatZoomVeil: ObservableObject {
    static let shared = ChatZoomVeil()
    /// The card (a chat's id, or ChatCards.newChat) whose title is away.
    @Published var card: String?
    /// The head's name is away.
    @Published var head = false
}

/// A title the flight stands in for while it flies: the card's (`card`
/// its id) or, with none, the chat head's.
struct ChatZoomVeiled: ViewModifier {
    let card: String?
    @ObservedObject private var veil = ChatZoomVeil.shared

    func body(content: Content) -> some View {
        let away = card.map { veil.card == $0 } ?? veil.head
        content.opacity(away ? 0 : 1)
    }
}

/// A card pressed: in a little, as the iPhone's, and the chat it opens
/// built while the button is held (ChatZoom.press), so the flight starts
/// on the frame it is let go.
struct ChatCardPress: ButtonStyle {
    let browser: Browser
    let id: String

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.09), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, down in
                ChatZoom.press(id, down: down, in: browser)
            }
    }
}

/// One spring, critically damped, sampled a hundred and twenty times a
/// second: the same numbers for every layer that moves with it, and for
/// where it is when it is turned back.
enum ChatSpring {
    static let rate: Double = 120

    static func samples(from start: CGFloat, velocity: CGFloat, to end: CGFloat, response: Double) -> [CGFloat] {
        let omega = 2 * Double.pi / response
        let stiffness = omega * omega, damping = 2 * omega
        var x = Double(start), v = Double(velocity)
        var out = [start]
        let steps = 10, h = 1 / (rate * Double(steps))
        for _ in 0..<Int(rate * 2) {
            for _ in 0..<steps {
                let a = -stiffness * (x - Double(end)) - damping * v
                v += a * h
                x += v * h
            }
            out.append(CGFloat(x))
            // Half a point of the flight from its end: at rest.
            if abs(x - Double(end)) < 0.003, abs(v) < 0.05 { break }
        }
        out[out.count - 1] = end
        return out
    }

    /// Even, over `seconds`: with less motion the chat only fades.
    static func even(from start: CGFloat, to end: CGFloat, seconds: Double) -> [CGFloat] {
        let n = max(2, Int(seconds * rate))
        return (0...n).map { start + (end - start) * CGFloat($0) / CGFloat(n) }
    }
}

/// The list and the chat trading places in the column: which is up, and a
/// chat on its way out of its card or back.
@MainActor
final class ChatZoom: ObservableObject {
    /// The chats kept are up, at rest or under a chat on its way.
    @Published private(set) var listShown: Bool
    /// The chat is up, at rest or on its way.
    @Published private(set) var paneShown: Bool
    /// A file or a link over the chat, which takes the drop itself.
    @Published var dropping = false
    let look: ChatPaneLook
    let browser: Browser
    let feed: ChatFeed
    weak var stage: ChatZoomStage?

    /// Where the flight is: 0 the card, 1 the whole column.
    private(set) var progress: CGFloat
    private(set) var target: CGFloat
    /// The run under way, sampled (ChatSpring), and which run it is.
    private var samples: [CGFloat] = []
    private var run = 0
    /// A flight asked for before the stage could take it.
    private var waiting = false
    private var source = Source(id: ChatCards.newChat, card: nil, title: nil, words: "", headWords: "")
    /// The chat built under a held press, before the click lands.
    private(set) var warm: String?
    /// Let go of after a drag: where the chat was and how fast it went.
    private var released: (rect: CGRect, speed: CGFloat, dim: CGFloat)?

    struct Source {
        let id: String
        /// The card, in the column's space; nil when it isn't in sight.
        let card: CGRect?
        /// Its title, in the column's space.
        let title: CGRect?
        let words: String
        /// The same words as the head has them.
        let headWords: String
        /// The corner it starts from: a card's, or the pencil's round.
        var radius: CGFloat = Radius.card
        /// The title's type size: a card's, or New Chat's row's.
        @MainActor var type: CGFloat { id == ChatCards.newChat ? ChatZoomStage.headType : ChatZoomStage.cardType }
    }

    init(browser: Browser, feed: ChatFeed, list: Bool, width: CGFloat) {
        self.browser = browser
        self.feed = feed
        listShown = list
        paneShown = !list
        progress = list ? 0 : 1
        target = progress
        look = ChatPaneLook(width: width)
        Self.all[ObjectIdentifier(browser)] = Weak(self)
    }

    private final class Weak {
        weak var zoom: ChatZoom?
        init(_ zoom: ChatZoom) { self.zoom = zoom }
    }
    private static var all: [ObjectIdentifier: Weak] = [:]

    /// The column's, in `browser`'s window.
    static func of(_ browser: Browser) -> ChatZoom? { all[ObjectIdentifier(browser)]?.zoom }

    /// The head's name where it rests, in the chat's own space, by chat
    /// (ChatCards.newChat for a new one): where the card's title flies to.
    static var heads: [String: CGRect] = [:]

    private static func quietly(_ change: () -> Void) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still, change)
    }

    private var still: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: trading places

    /// The column goes to its list (`toList`) or to the chat the feed follows.
    func trade(toList: Bool) {
        warm = nil
        // The list coming up under the chat is laid out a turn after it is
        // put there: the chat waits for it, still over the column, and only
        // then looks for its card. Looked for before, a list not shown yet
        // in this window (a chat begun by ⌘J) had none, and the chat slid
        // away instead of going into it.
        let late = toList && !listShown
        if !late { find() }
        // The list goes under the chat now: the chat has its own ground at
        // once, or for the turn it waits the list showed through its words.
        if toList { stage?.holdGround() }
        Self.quietly {
            if toList { listShown = true } else { paneShown = true }
        }
        target = toList ? 0 : 1
        // Not asked for before the card is found: the stage's own layout
        // in this turn would start it from none.
        waiting = !late
        stage?.needsLayout = true
        if late {
            let run = run
            DispatchQueue.main.async { [weak self] in
                guard let self, self.run == run, self.target == 0 else { return }
                self.find()
                self.waiting = true
                self.start()
            }
        } else {
            start()
        }
    }

    /// The card of the chat the feed follows, and its title, where the list has them now.
    private func find() {
        let id = feed.chat?.id ?? ChatCards.newChat
        let words = feed.chat?.title ?? "New Chat"
        var card = ChatCards.card(id, width: look.width)
        var round = false
        // A new chat with New Chat's row out of sight: the pencil in the
        // list's head, always in sight, is where it comes from and goes.
        if card == nil, id == ChatCards.newChat, let pencil = ChatCards.frames[ChatCards.pencil],
           abs(ChatCards.width - look.width) < 0.5 {
            card = pencil
            round = true
        }
        source = Source(id: id, card: card, title: card == nil || round || words.isEmpty ? nil : ChatCards.titles[id], words: words,
                        headWords: feed.chat.map { $0.title.isEmpty ? "Chat" : $0.title } ?? "New chat",
                        radius: round ? (card?.height ?? 0) / 2 : Radius.card)
        if card == nil {
            StageView.mark("chat-zoom-no-card", ChatCards.why(id, width: look.width))
        }
    }

    /// The flight asked for, once the stage is there and laid out.
    func start() {
        guard waiting, let stage, stage.bounds.width > 0, stage.bounds.height > 0 else { return }
        waiting = false
        let (from, velocity) = now()
        let let_go = released
        released = nil
        let mode: ChatZoomStage.Mode = still ? .fade : source.card == nil ? .push : .zoom
        samples = mode == .fade
            ? ChatSpring.even(from: from, to: target, seconds: 0.15)
            : ChatSpring.samples(from: from, velocity: let_go.map { -min(5, $0.speed / max(1, Self.reach(from: $0.rect, to: source.card))) } ?? velocity,
                                 to: target, response: target == 1 ? 0.42 : 0.38)
        run += 1
        let mine = run
        // The title flies only between a card in sight and a head laid out
        // for this chat.
        let head = mode == .zoom ? Self.heads[source.id] : nil
        let titles = head != nil && source.title != nil
        if titles {
            ChatZoomVeil.shared.card = source.id
            ChatZoomVeil.shared.head = true
        }
        StageView.mark("chat-zoom", ["to": Double(target), "from": Double(from), "mode": "\(mode)", "frames": samples.count,
                                     "card": source.card != nil, "titles": titles, "warm": stage.warming])
        stage.fly(samples, mode: mode, source: source, head: titles ? head : nil,
                  full: let_go?.rect, dim: let_go?.dim) { [weak self] in self?.landed(mine) }
    }

    /// How far a chat let go of has to travel back to its card.
    private static func reach(from rect: CGRect, to card: CGRect?) -> CGFloat {
        guard let card else { return rect.width }
        return max(80, hypot(rect.midX - card.midX, rect.midY - card.midY))
    }

    /// Where the flight is now, and how fast it goes.
    private func now() -> (CGFloat, CGFloat) {
        if let released { return (1, -released.speed) }
        guard let stage, let at = stage.elapsed(), samples.count > 1 else { return (progress, 0) }
        let i = min(samples.count - 1, max(0, Int(at * ChatSpring.rate)))
        let j = min(samples.count - 1, i + 1)
        return (samples[i], (samples[j] - samples[i]) * CGFloat(ChatSpring.rate))
    }

    private func landed(_ mine: Int) {
        guard mine == run else { return }
        progress = target
        samples = []
        // The real titles back first; the flown ones go a turn later, once
        // those are drawn, so no frame has neither.
        ChatZoomVeil.shared.card = nil
        ChatZoomVeil.shared.head = false
        let open = target == 1
        if open { Self.quietly { listShown = false } }
        DispatchQueue.main.async { [weak self] in
            guard let self, mine == self.run else { return }
            if open {
                self.stage?.rest()
            } else {
                self.stage?.alphaValue = 0
                Self.quietly { self.paneShown = false }
            }
        }
        StageView.mark("chat-zoom-landed", ["to": Double(target)])
    }

    // MARK: a press

    static func press(_ id: String, down: Bool, in browser: Browser) {
        all[ObjectIdentifier(browser)]?.zoom?.press(id, down: down)
    }

    /// Held: the chat is built behind the list, unseen, so the click
    /// starts the flight on its own frame. Let go of without a click (the
    /// pointer dragged off), it goes again.
    private func press(_ id: String, down: Bool) {
        if down {
            guard listShown, !paneShown, target == 0, !still else { return }
            warm = id
            feed.follow(id == ChatCards.newChat ? nil : id)
            Self.quietly { paneShown = true }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.warm == id, self.target == 0 else { return }
            self.warm = nil
            Self.quietly { self.paneShown = false }
            self.feed.follow(self.browser.chatID)
        }
    }

    // MARK: two fingers

    /// The chat at rest over the column: it can be pulled back to its card.
    var swipeable: Bool { paneShown && !listShown && target == 1 && samples.isEmpty && !still }

    /// The pull began: the list comes up under the chat.
    func pullBegan() {
        Self.quietly { listShown = true }
    }

    /// Let go: back to the card (`away`) from `rect` at `speed` points a
    /// second, or back over the column.
    func pullEnded(away: Bool, rect: CGRect, speed: CGFloat, dim: CGFloat) {
        guard away else {
            stage?.settle { [weak self] in
                guard let self, self.target == 1, self.samples.isEmpty else { return }
                Self.quietly { self.listShown = false }
            }
            return
        }
        released = (rect, speed, dim)
        browser.chatHistory = true
    }
}

// MARK: - the stage

/// The chat's own hosting view, inside a clip that flies from the card's
/// rectangle to the column's, under the flown title and over a veil that
/// darkens the list.
final class ChatZoomStage: NSView {
    enum Mode: CustomStringConvertible {
        /// Out of its card and back.
        case zoom
        /// No card in sight: in from the right, as a pushed screen.
        case push
        /// Less motion: a fade where it is.
        case fade

        var description: String {
            switch self {
            case .zoom: "zoom"
            case .push: "push"
            case .fade: "fade"
            }
        }
    }

    let host: NSHostingView<ChatPane>
    private weak var zoom: ChatZoom?
    private let clip = Flipped()
    private let scaler = Flipped()
    private let veil = Flipped()
    private let under = Layers()
    private let over = Layers()
    private let cast = CALayer()
    private let titleA = CALayer()
    private let titleB = CALayer()
    /// Built unseen under a held press (ChatZoom.press).
    var warming = false {
        didSet { alphaValue = warming ? 0 : 1 }
    }
    private var flying = false
    private var monitor: Any?
    private var pull: Pull?

    override var isFlipped: Bool { true }

    init(root: ChatPane, zoom: ChatZoom) {
        host = NSHostingView(rootView: root)
        self.zoom = zoom
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        host.sizingOptions = []
        // A hosting view of its own is told the title bar's height as safe
        // area: the turns' scroll stood that far down, its fade and blur
        // with it, and the words above them went by under the head untouched.
        host.safeAreaRegions = []
        veil.wantsLayer = true
        veil.layer?.backgroundColor = NSColor.black.cgColor
        veil.alphaValue = 0
        clip.wantsLayer = true
        // AppKit keeps the layer's own clipping to this (macOS 14 on).
        clip.clipsToBounds = true
        scaler.wantsLayer = true
        scaler.addSubview(host)
        clip.addSubview(scaler)
        for view in [veil, under, clip, over] { addSubview(view) }
        cast.shadowColor = NSColor.black.cgColor
        cast.shadowRadius = 17
        cast.shadowOffset = CGSize(width: 0, height: 14)
        cast.shadowOpacity = 0
        under.layer?.addSublayer(cast)
        for title in [titleA, titleB] {
            title.anchorPoint = .zero
            title.opacity = 0
            title.actions = ["position": NSNull(), "bounds": NSNull(), "contents": NSNull(), "opacity": NSNull(), "transform": NSNull()]
            over.layer?.addSublayer(title)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        for view in [veil, under, clip, over] { view.frame = bounds }
        scaler.frame = clip.bounds
        host.frame = scaler.bounds
        cast.frame = under.bounds
        zoom?.start()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                MainActor.assumeIsolated { self?.heard(event) ?? event }
            }
        } else if window == nil, let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    /// Unseen while it is built under a press; while it flies it takes
    /// the clicks, which would land where the chat was laid out, not where
    /// it is drawn.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !warming, alphaValue > 0.01 else { return nil }
        if flying || pull != nil { return frame.contains(point) ? self : nil }
        return super.hitTest(point)
    }

    // MARK: flight

    struct Look {
        var rect: CGRect
        var scale: CGFloat
        var radius: CGFloat
        var opacity: Float
        var slide: CGFloat
        var dim: Float
        var shadow: Float
        var a: Title
        var b: Title
    }

    struct Title {
        var origin: CGPoint = .zero
        var scale: CGFloat = 1
        var opacity: Float = 0
    }

    /// The card's title, in the card's own type; the head's name, in its.
    static let cardType: CGFloat = 13.5 // a row's name (ChatListRowBody), as the head's
    static let headType: CGFloat = 13.5

    /// Where everything stands at `p` of the way from the card (0) to the
    /// column (`full`, the whole of it unless let go of mid-pull).
    private func look(_ p: CGFloat, mode: Mode, source: ChatZoom.Source, head: CGRect?, full: CGRect, dim: CGFloat) -> Look {
        let column = bounds
        func mix(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
        switch mode {
        case .fade:
            return Look(rect: column, scale: 1, radius: Radius.surface, opacity: Float(p), slide: 0, dim: 0, shadow: 0, a: Title(), b: Title())
        case .push:
            // The chat, its ground and all, comes in from the right and goes
            // back there: moved whole, never its words off its ground.
            let shown = max(0, min(1, p))
            return Look(rect: full.offsetBy(dx: (1 - p) * column.width, dy: 0), scale: full.width / column.width, radius: Radius.surface,
                        opacity: 1, slide: 0, dim: Float(dim * shown), shadow: Float(0.3 * shown), a: Title(), b: Title())
        case .zoom:
            guard let card = source.card else { return look(p, mode: .push, source: source, head: head, full: full, dim: dim) }
            let rect = CGRect(x: mix(card.minX, full.minX, p), y: mix(card.minY, full.minY, p),
                              width: mix(card.width, full.width, p), height: mix(card.height, full.height, p))
            let scale = rect.width / column.width
            var out = Look(rect: rect, scale: scale, radius: mix(source.radius, Radius.surface, min(1, max(0, p))),
                           opacity: Float(Self.smooth((p - 0.05) / 0.2)), slide: 0, dim: Float(dim * max(0, p)),
                           shadow: Float(0.45 * sin(Double.pi * Double(min(1, max(0, p))))), a: Title(), b: Title())
            if let head, let title = source.title {
                // In the flight's own frame, so the words keep with the head
                // and never lag behind it: from the card's title to the
                // head's name, into its size and place early, then riding.
                let q = Self.ease(min(1, max(0, p)))
                let local = CGPoint(x: mix(title.minX - card.minX, head.minX * scale, q),
                                    y: mix(title.minY - card.minY, head.minY * scale, q))
                let origin = CGPoint(x: rect.minX + local.x, y: rect.minY + local.y)
                let b = mix(source.type / Self.headType, scale, q)
                // Handed over quickly: the two copies break their lines
                // differently, so they are never long seen together.
                let hand = Float(Self.smooth((q - 0.35) / 0.2))
                out.a = Title(origin: origin, scale: b * Self.headType / source.type, opacity: 1 - hand)
                out.b = Title(origin: origin, scale: b, opacity: hand)
            }
            return out
        }
    }

    /// 0 to 1 over 0...1, eased at both ends.
    private static func smooth(_ t: CGFloat) -> CGFloat {
        let x = min(1, max(0, t))
        return x * x * (3 - 2 * x)
    }

    /// Fast out of the card and slow into the head: (0.25, 0.8, 0.3, 1).
    private static func ease(_ t: CGFloat) -> CGFloat {
        let x1 = 0.25, y1 = 0.8, x2 = 0.3, y2 = 1.0
        let cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx
        let cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by
        var u = Double(t)
        for _ in 0..<8 {
            let x = ((ax * u + bx) * u + cx) * u - Double(t)
            let dx = (3 * ax * u + 2 * bx) * u + cx
            if abs(x) < 1e-5 || abs(dx) < 1e-6 { break }
            u -= x / dx
        }
        u = min(1, max(0, u))
        return CGFloat(((ay * u + by) * u + cy) * u)
    }

    /// The titles as pictures, in the column's ink.
    private func picture(_ words: String, type: CGFloat, width: CGFloat, lines: Int) -> (CGImage, CGSize)? {
        let scale = window?.backingScaleFactor ?? 2
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        var made: (CGImage, CGSize)?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let text = Text(words)
                .font(.system(size: type, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(lines)
                .multilineTextAlignment(.leading)
                .frame(width: width, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: text)
            renderer.scale = scale
            if let image = renderer.cgImage {
                made = (image, CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale))
            }
        }
        return made
    }

    /// The run's samples played on the render server, every layer from the
    /// same numbers; `done` once the last frame is drawn.
    func fly(_ samples: [CGFloat], mode: Mode, source: ChatZoom.Source, head: CGRect?, full: CGRect?, dim: CGFloat?,
             done: @escaping () -> Void) {
        let full = full ?? bounds
        let dimTop = dim ?? 0.3
        let looks = samples.map { look($0, mode: mode, source: source, head: head, full: full, dim: dimTop) }
        flying = true
        warming = false
        if let head, let title = source.title {
            if let (image, size) = picture(source.words, type: source.type, width: title.width, lines: 2) {
                titleA.contents = image
                titleA.contentsScale = window?.backingScaleFactor ?? 2
                titleA.bounds = CGRect(origin: .zero, size: size)
            }
            if let (image, size) = picture(source.headWords, type: Self.headType, width: head.width, lines: 1) {
                titleB.contents = image
                titleB.contentsScale = window?.backingScaleFactor ?? 2
                titleB.bounds = CGRect(origin: .zero, size: size)
            }
        }
        let count = looks.count
        let duration = Double(count - 1) / ChatSpring.rate
        let times = (0..<count).map { NSNumber(value: Double($0) / Double(max(1, count - 1))) }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Set first: it covers only what is added after it.
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { done() } }
        func key(_ layer: CALayer?, _ path: String, _ values: [Any]) {
            guard let layer else { return }
            let move = CAKeyframeAnimation(keyPath: path)
            move.values = values
            move.keyTimes = times
            move.duration = max(duration, 1 / ChatSpring.rate)
            move.calculationMode = .linear
            move.fillMode = .both
            move.isRemovedOnCompletion = false
            layer.add(move, forKey: "zoom." + path)
        }
        // A pull let go of: the clip leaves its pulled transform for the
        // same rectangle drawn by position and bounds, in this commit.
        clip.layer?.transform = CATransform3DIdentity
        clip.layer?.removeAnimation(forKey: "zoom.settle")
        // Its own ground while it flies, so the list doesn't show through its words.
        grounded()
        veil.layer?.removeAnimation(forKey: "zoom.settle")
        key(clip.layer, "position", looks.map { NSValue(point: $0.rect.origin) })
        key(clip.layer, "bounds", looks.map { NSValue(rect: CGRect(origin: .zero, size: $0.rect.size)) })
        key(clip.layer, "cornerRadius", looks.map { $0.radius })
        key(clip.layer, "opacity", looks.map { $0.opacity })
        key(scaler.layer, "transform", looks.map {
            NSValue(caTransform3D: CATransform3DConcat(CATransform3DMakeScale($0.scale, $0.scale, 1), CATransform3DMakeTranslation($0.slide, 0, 0)))
        })
        key(veil.layer, "opacity", looks.map { $0.dim })
        key(cast, "shadowPath", looks.map { CGPath.rounded($0.rect.offsetBy(dx: $0.slide, dy: 0), corner: $0.radius) })
        key(cast, "shadowOpacity", looks.map { $0.shadow })
        if head != nil {
            key(titleA, "position", looks.map { NSValue(point: $0.a.origin) })
            key(titleA, "transform", looks.map { NSValue(caTransform3D: CATransform3DMakeScale($0.a.scale, $0.a.scale, 1)) })
            key(titleA, "opacity", looks.map { $0.a.opacity })
            key(titleB, "position", looks.map { NSValue(point: $0.b.origin) })
            key(titleB, "transform", looks.map { NSValue(caTransform3D: CATransform3DMakeScale($0.b.scale, $0.b.scale, 1)) })
            key(titleB, "opacity", looks.map { $0.b.opacity })
        } else {
            for title in [titleA, titleB] { Self.drop(title) }
        }
        CATransaction.commit()
        // What the render server has, a third of the way: for the bench's marks.
        DispatchQueue.main.asyncAfter(deadline: .now() + duration / 3) { [weak self] in
            guard let self, let clip = self.clip.layer?.presentation(), let scaler = self.scaler.layer?.presentation() else { return }
            StageView.mark("chat-zoom-drawn", ["clip": "\(clip.frame)", "clipModel": "\(self.clip.layer?.frame ?? .zero)",
                                               "scale": Double(scaler.transform.m11), "opacity": Double(clip.opacity),
                                               "masks": clip.masksToBounds, "keys": self.clip.layer?.animationKeys() ?? [],
                                               "a": "\(self.titleA.presentation()?.position ?? .zero)", "aOpacity": Double(self.titleA.presentation()?.opacity ?? -1),
                                               "offscreen": self.offscreen()])
        }
    }

    /// What in the flight the render server draws off screen for every
    /// frame of it (a mask, a filter, a backdrop, a shadow with no path, a
    /// rounded clip over sublayers), by kind and count, for the bench.
    private func offscreen() -> [String: Int] {
        var found: [String: Int] = [:]
        func walk(_ layer: CALayer) {
            let seen = layer.presentation() ?? layer
            let kind = layer.delegate.map { String(describing: type(of: $0)) } ?? String(describing: type(of: layer))
            if layer.mask != nil { found["mask " + kind, default: 0] += 1 }
            if !(layer.filters ?? []).isEmpty { found["filter " + kind, default: 0] += 1 }
            if !(layer.backgroundFilters ?? []).isEmpty || String(describing: type(of: layer)).contains("Backdrop") { found["backdrop " + kind, default: 0] += 1 }
            if seen.shadowOpacity > 0, seen.shadowPath == nil { found["shadow " + kind, default: 0] += 1 }
            if seen.masksToBounds, seen.cornerRadius > 0, !(layer.sublayers ?? []).isEmpty { found["rounded clip " + kind, default: 0] += 1 }
            layer.sublayers?.forEach(walk)
        }
        if let layer { walk(layer) }
        return found
    }

    /// How long the flight under way has run, by the render server's clock.
    func elapsed() -> Double? {
        guard flying, let layer = clip.layer, let move = layer.animation(forKey: "zoom.position") else { return nil }
        // Not drawn yet: it begins when this turn's changes are committed.
        guard move.beginTime > 0 else { return 0 }
        return max(0, layer.convertTime(CACurrentMediaTime(), from: nil) - move.beginTime)
    }

    /// Landed over the column: the flight's layers let go, at rest as AppKit lays them.
    func rest() {
        flying = false
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [clip.layer, scaler.layer, veil.layer, cast, titleA, titleB] as [CALayer?] {
            if let layer { Self.drop(layer) }
        }
        titleA.opacity = 0
        titleB.opacity = 0
        CATransaction.commit()
        unground()
    }

    /// At rest the column's own plate shows under the chat, its glass not
    /// the same as the flight's ground: crossed over, not swapped.
    private func unground() {
        CATransaction.begin()
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = clip.layer?.backgroundColor
        fade.toValue = nil
        fade.duration = 0.15
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        clip.layer?.add(fade, forKey: "zoom.ground")
        clip.layer?.backgroundColor = nil
        CATransaction.commit()
    }

    /// The flight's ground under the chat before it moves.
    func holdGround() { grounded() }

    /// The flight's own ground, the column's color, under the chat: at
    /// once, as faded in the list showed through the words.
    private func grounded() {
        guard let layer = clip.layer else { return }
        var ground: CGColor?
        effectiveAppearance.performAsCurrentDrawingAppearance { ground = Palette.NS.ground.cgColor }
        layer.removeAnimation(forKey: "zoom.ground")
        layer.backgroundColor = ground
    }

    private static func drop(_ layer: CALayer) {
        for key in layer.animationKeys() ?? [] where key.hasPrefix("zoom.") { layer.removeAnimation(forKey: key) }
    }

    // MARK: pulled back by two fingers

    private struct Pull {
        var began: Bool
        var x: CGFloat = 0
        var y: CGFloat = 0
        var moves: [(time: TimeInterval, x: CGFloat)] = []
        var shown: CGRect = .zero
        var dim: CGFloat = 0.3
    }

    /// Two fingers sideways over the chat at rest, to the right, as
    /// Safari's back: the chat follows them, smaller as it goes, and let
    /// go of far or fast enough it flies back into its card.
    private func heard(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, let zoom else { return event }
        let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        let rise = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        switch event.phase {
        case .began:
            let point = convert(event.locationInWindow, from: nil)
            guard zoom.swipeable, bounds.contains(point), !Self.scrollsSideways(window, at: event.locationInWindow) else {
                pull = nil
                return event
            }
            pull = Pull(began: false)
            StageView.mark("chat-pull", ["fingers": Double(fingers), "inverted": event.isDirectionInvertedFromDevice])
            return event
        case .changed:
            guard var pull else { return event }
            if !pull.began {
                pull.x += fingers
                pull.y += rise
                guard abs(pull.x) > 8 || abs(pull.y) > 8 else { self.pull = pull; return event }
                // Up, down or to the left: the turns' own scroll.
                guard pull.x > 0, abs(pull.x) > abs(pull.y) * 1.5 else { self.pull = nil; return event }
                pull.began = true
                zoom.pullBegan()
            } else {
                pull.x += fingers
                pull.y += rise
            }
            pull.moves.append((event.timestamp, pull.x))
            if pull.moves.count > 6 { pull.moves.removeFirst() }
            self.pull = pull
            follow()
            return nil
        case .ended, .cancelled:
            guard let pull, pull.began else { self.pull = nil; return event }
            let first = pull.moves.first, last = pull.moves.last
            let span = (last?.time ?? 0) - (first?.time ?? 0)
            let speed = span > 0.005 ? ((last?.x ?? 0) - (first?.x ?? 0)) / CGFloat(span) : 0
            let gone = pull.x / (bounds.width * 0.9)
            self.pull = nil
            zoom.pullEnded(away: event.phase == .ended && (gone > 0.33 || speed > 450), rect: pull.shown,
                           speed: max(0, speed), dim: pull.dim)
            return nil
        default:
            return pull?.began == true ? nil : event
        }
    }

    /// The chat where the fingers have it: along with them, smaller the
    /// farther it goes, the list lighter under it.
    private func follow() {
        guard var pull else { return }
        let column = bounds
        let gone = min(1, max(0, pull.x / (column.width * 0.9)))
        let scale = 1 - 0.2 * gone
        let width = column.width * scale, height = column.height * scale
        let rect = CGRect(x: max(0, pull.x) * 0.7 + (column.width - width) / 2 * 0.3,
                          y: (column.height - height) / 2 * 0.6 + max(-24, min(24, pull.y * 0.3)),
                          width: width, height: height)
        pull.shown = rect
        pull.dim = 0.3 * (1 - gone)
        self.pull = pull
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        grounded()
        clip.layer?.transform = CATransform3DConcat(CATransform3DMakeScale(scale, scale, 1),
                                                    CATransform3DMakeTranslation(rect.minX, rect.minY, 0))
        clip.layer?.cornerRadius = Radius.surface / scale
        veil.alphaValue = pull.dim
        cast.shadowPath = CGPath.rounded(rect, corner: Radius.surface)
        cast.shadowOpacity = Float(0.35 * gone)
        CATransaction.commit()
    }

    /// Not far enough: back over the column on the same spring.
    func settle(done: @escaping () -> Void) {
        guard let clip = clip.layer else { return }
        let from = clip.transform
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            MainActor.assumeIsolated {
                self?.unground()
                done()
            }
        }
        let spring = CASpringAnimation(perceptualDuration: 0.38, bounce: 0)
        spring.keyPath = "transform"
        spring.fromValue = NSValue(caTransform3D: from)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.duration = spring.settlingDuration
        clip.add(spring, forKey: "zoom.settle")
        clip.transform = CATransform3DIdentity
        clip.cornerRadius = 0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = veil.alphaValue
        fade.toValue = 0
        fade.duration = 0.25
        veil.layer?.add(fade, forKey: "zoom.settle")
        veil.alphaValue = 0
        cast.shadowOpacity = 0
        CATransaction.commit()
    }

    /// A table or a code block that scrolls sideways under the fingers keeps them.
    private static func scrollsSideways(_ window: NSWindow, at point: NSPoint) -> Bool {
        var view = window.contentView?.hitTest(point)
        while let at = view {
            if let scroll = at as? NSScrollView, scroll.hasHorizontalScroller || (scroll.documentView?.frame.width ?? 0) > scroll.contentSize.width + 1 {
                return true
            }
            view = at.superview
        }
        return false
    }
}

/// A plain view whose layer's origin is its top left, for the flight's
/// transforms and positions.
private final class Flipped: NSView {
    override var isFlipped: Bool { true }
}

/// Layers of the flight's own, over or under the chat: nothing to click.
private final class Layers: NSView {
    override var isFlipped: Bool { true }

    init() {
        super.init(frame: .zero)
        let root = CALayer()
        root.isGeometryFlipped = true
        layer = root
        wantsLayer = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// The stage in the column's SwiftUI: made once, its chat told nothing
/// after (ChatPane watches what it shows itself).
struct ChatZoomStageView: NSViewRepresentable {
    let browser: Browser
    let feed: ChatFeed
    let zoom: ChatZoom
    let more: ChatMore

    func makeNSView(context: Context) -> ChatZoomStage {
        let stage = ChatZoomStage(root: ChatPane(browser: browser, feed: feed, look: zoom.look, zoom: zoom, more: more), zoom: zoom)
        stage.warming = zoom.warm != nil && zoom.target == 0
        zoom.stage = stage
        return stage
    }

    func updateNSView(_ stage: ChatZoomStage, context: Context) {
        if zoom.stage !== stage { zoom.stage = stage }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatZoomStage, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
