import SwiftUI
import AppKit

// The first time: "Exploded Yab". No drawn miniature of Yab: its own parts,
// the row of tabs, the column, the page, the ⌘T box, the agent's dock and
// chat, at their real size, pulled a little apart (WelcomeEngine,
// WelcomeParts). Welcome is the glass mark, its light coming on under it,
// "yet another browser." and one line (WelcomeHero); leaving it, the mark
// rises into the header and the name folds into "yab" beside it. Then the
// chapters, one frame for all of them that never moves: the title and its
// line at one height, the parts under them, Back and the dashes in one
// bottom corner, the quiet word and the one glass button in the other,
// their corners concentric with the window's. Chapters 1 and 2 show sample
// parts; from Make it yours the parts hold only what is yours; at Start
// Browsing the gaps close into the real window (onb-work/final-spec.md).
//
// All of it is AppKit and Core Animation under one view: the ground and
// the header (HeroView), the stage (WelcomeStageView) and the frame's
// buttons (WelcomeChromeView), each button a small SwiftUI island of its
// own. What moves is a layer's transform or opacity, played by the render
// server; SwiftUI draws the buttons and their words, and nothing more.

/// The welcome over the whole window, lights and all.
struct WelcomePanel: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences

    @ObservedObject private var stage = WelcomeStage.shared

    var body: some View {
        WelcomeOverlay(stage: stage, chrome: chrome, fromDisk: stage.arrival(prefs) == .disk)
            .transition(.opacity)
            .onAppear { stage.attach(browser) }
            .onDisappear { stage.detach(browser) }
    }

    /// What the frame shows now.
    private var chrome: WelcomeChrome {
        WelcomeChrome(words: stage.words, dashes: stage.dashes, back: stage.canGoBack, toast: stage.toast,
                      skip: stage.arrival(prefs) == .replay, lights: !browser.titleLights, menuDown: browser.menuDown, reduceMotion: stage.reduceMotion)
    }
}

/// What the frame around the stage shows: the footer's words and buttons,
/// the dashes, the toast and the window's lights.
struct WelcomeChrome: Equatable {
    var words = WelcomeWords(frame: .welcome, primary: "Get Started")
    var dashes = WelcomeDashes()
    /// Back is there: past the path's first beat, before Finish.
    var back = false
    var toast: String?
    /// Every beat of a manual replay can hand the window back at once.
    var skip = false
    /// The overlay brings its own traffic lights: the title bar's are under it.
    var lights = true
    var menuDown: CGFloat = 0
    var reduceMotion = false
}

private struct WelcomeOverlay: NSViewRepresentable {
    let stage: WelcomeStage
    let chrome: WelcomeChrome
    let fromDisk: Bool

    func makeNSView(context: Context) -> WelcomeOverlayView { WelcomeOverlayView(stage: stage, fromDisk: fromDisk) }

    func updateNSView(_ view: WelcomeOverlayView, context: Context) { view.show(chrome) }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: WelcomeOverlayView, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}

// MARK: - the overlay

/// The whole welcome, one view over the whole window: the ground and the
/// header under the stage, the frame's buttons over it. Its own layer is
/// what steps aside for a sign-in and what fades at the very end.
@MainActor
final class WelcomeOverlayView: NSView {
    private weak var stage: WelcomeStage?
    private let hero: HeroView
    private let chrome = WelcomeChromeView()
    private let panel = WelcomeFlippedView()
    private let wash = CAGradientLayer()
    private let inputScroll = NSScrollView()
    private let headingHost = NSHostingController(rootView: WelcomeHeading(words: WelcomeWords()))
    private var heading: NSView { headingHost.view }
    private var shown = WelcomeWords()

    private var arrived = false
    /// Bumped by each wait for the button, so an old one lets it be.
    private var clock = 0

    init(stage: WelcomeStage, fromDisk: Bool) {
        self.stage = stage
        let hero = HeroView(risen: stage.words.frame != .welcome, animated: !stage.reduceMotion, fromDisk: fromDisk)
        // Shown at rest by the bench, Welcome is already settled: no intro.
        hero.plays = !stage.buttonIn
        self.hero = hero
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(hero)
        panel.wantsLayer = true
        panel.layer?.cornerRadius = Radius.window
        panel.layer?.cornerCurve = .continuous
        panel.layer?.masksToBounds = true
        wash.type = .radial
        wash.startPoint = CGPoint(x: 0.18, y: 0.78)
        wash.endPoint = CGPoint(x: 1.2, y: -0.15)
        panel.layer?.addSublayer(wash)
        addSubview(panel)
        panel.addSubview(stage.view)
        stage.inputs.alignsLeading = true
        inputScroll.drawsBackground = false
        inputScroll.hasVerticalScroller = true
        inputScroll.scrollerStyle = .overlay
        inputScroll.autohidesScrollers = true
        inputScroll.documentView = stage.inputs
        addSubview(inputScroll)
        headingHost.sizingOptions = []
        addSubview(heading)
        addSubview(chrome)
        chrome.actions.back = { [weak stage] in stage?.back() }
        chrome.actions.primary = { [weak stage] in stage?.pressPrimary() }
        chrome.actions.quiet = { [weak stage] in stage?.pressQuiet() }
        chrome.actions.skip = { [weak stage] in stage?.skipReplay() }
        chrome.onDash = { [weak stage] in stage?.jump(toChapter: $0) }
        stage.overlay = self
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { WelcomePointer.start() } else { WelcomePointer.stop() }
        keyWatch.forEach(NotificationCenter.default.removeObserver)
        keyWatch = []
        guard let window else { return }
        // Chapter 1's run holds while the window isn't the one in front.
        for (name, unfocused) in [(NSWindow.didBecomeKeyNotification, false), (NSWindow.didResignKeyNotification, true)] {
            keyWatch.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stage?.hold(unfocused: unfocused) }
            })
        }
        stage?.hold(unfocused: !window.isKeyWindow)
    }

    private var keyWatch: [NSObjectProtocol] = []

    /// A press handed to SwiftUI under the stage's scale (WelcomePointer)
    /// goes to the view it was over, wherever its moved point falls.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if let pinned = WelcomePointer.pinned, pinned.isDescendant(of: self) { return pinned }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        guard let stage else { return }
        let width = WelcomeColumns.leftWidth(bounds.width)
        let finish = shown.frame == .finish
        let intro = shown.frame == .welcome
        let inset = min(48, width * 0.085)
        hero.frame = bounds
        hero.contentWidth = width
        panel.frame = finish ? bounds : CGRect(x: width, y: 8, width: max(1, bounds.width - width - 8), height: max(1, bounds.height - 16))
        wash.frame = panel.bounds
        wash.isHidden = finish
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        wash.colors = [Swatch.peach, .rose, .lavender, .sky].map { $0.color(dark: dark, custom: .clear).cgColor }
        stage.view.frame = finish ? panel.bounds : panel.bounds.insetBy(dx: 16, dy: 24)
        heading.isHidden = intro || finish
        let formWidth = max(1, width - 2 * inset)
        let textHeight = headingHost.sizeThatFits(in: CGSize(width: formWidth, height: 1000)).height
        let area = max(1, bounds.height - 152)
        let rect = stage.inputs.viewport ?? .null
        let formScale = rect.isNull ? 0 : min(1, formWidth / max(1, rect.width))
        let formHeight = rect.isNull ? 0 : rect.height * formScale
        let visibleHeight = min(formHeight, max(1, area - textHeight - 24))
        let block = textHeight + (formHeight > 0 ? 24 + visibleHeight : 0)
        let top = 76 + max(0, (area - block) / 2)
        heading.frame = CGRect(x: inset, y: top, width: formWidth, height: textHeight)
        inputScroll.frame = intro ? CGRect(x: 0, y: HeroLayout.openingOffset(in: CGSize(width: width, height: bounds.height)), width: width, height: bounds.height)
            : CGRect(x: inset, y: heading.frame.maxY + 24, width: formWidth, height: visibleHeight)
        stage.inputs.frame = CGRect(origin: .zero, size: CGSize(width: inputScroll.contentSize.width, height: intro ? bounds.height : formHeight))
        inputScroll.isHidden = !intro && formHeight == 0
        chrome.frame = bounds
        if !arrived, bounds.width > 0, bounds.height > 0 {
            arrived = true
            firstFrame(stage)
        }
    }

    /// The frame's button and its words, in `view`'s points, for the bench.
    func cluster(in view: NSView) -> CGRect { chrome.cluster(in: view) }

    var skipFrame: CGRect? { chrome.skipFrame }

    /// The current dash's fill, for the bench.
    var dashState: [String: Any] { chrome.dashState }

    func show(_ state: WelcomeChrome) {
        if shown != state.words {
            if shown.title != state.words.title { inputScroll.contentView.scroll(to: .zero) }
            shown = state.words
            headingHost.rootView = WelcomeHeading(words: shown) { [weak stage] in stage?.selectScene($0) }
            needsLayout = true
        }
        hero.animated = !state.reduceMotion
        hero.set(risen: state.words.frame != .welcome)
        hero.set(finished: state.words.frame == .finish)
        chrome.show(state, animated: arrived)
    }

    /// The first frame on screen: the button as the welcome needs it, and
    /// back from a sign-in, the overlay coming back as it went.
    private func firstFrame(_ stage: WelcomeStage) {
        if stage.returning {
            stage.returning = false
            chrome.bringButton(after: 0, reduced: true, animated: false)
            stage.buttonIn = true
            if !stage.reduceMotion { comeBack() }
        } else if stage.words.frame == .welcome, !stage.buttonIn {
            awaitButton(stage)
        } else {
            chrome.bringButton(after: 0, reduced: true, animated: false)
            stage.buttonIn = true
        }
    }

    /// The button comes in 3.2 s into the intro, on a spring, and only then
    /// takes a press; with Reduce Motion, at once, in the one crossfade.
    private func awaitButton(_ stage: WelcomeStage) {
        clock += 1
        let clock = clock
        let reduced = stage.reduceMotion
        let delay = reduced ? 0 : HeroView.buttonAt
        chrome.bringButton(after: delay, reduced: reduced, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay * WelcomeMotion.pace) { [weak self] in
            guard let self, self.clock == clock else { return }
            self.stage?.buttonIn = true
        }
    }

    /// Welcome's intro from its first frame again (the bench's `welcome
    /// play=1`), the button waiting for it as the first time.
    func replayIntro() {
        guard let stage, stage.words.frame == .welcome else { return }
        stage.buttonIn = false
        hero.fromDisk = stage.coming == .disk
        hero.replay()
        chrome.dropButton()
        awaitButton(stage)
    }

    // MARK: the whole overlay

    /// The overlay out: for a sign-in's tab (`stepping`: 0.15 depart and a
    /// little smaller, or at once with Reduce Motion), or at the very end
    /// (a 0.12 crossfade to the real window, already laid out under it).
    /// Then `done`, which takes the panel away.
    func leave(fade seconds: Double, stepping: Bool, then done: @escaping () -> Void) {
        let reduced = stage?.reduceMotion ?? false
        let duration = stepping && reduced ? 0 : seconds
        guard let layer, duration > 0 else { done(); return }
        let from = layer.presentation()?.opacity ?? layer.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        alphaValue = 0
        CATransaction.commit()
        layer.add(WelcomeMotion.animation("opacity", from: from, to: 0, curve: stepping ? .depart : .linear, duration: duration, on: layer),
                  forKey: "leave.opacity")
        if stepping {
            let smaller = WelcomeStageView.transform(size: bounds.size, anchor: layer.anchorPoint, scale: CGSize(width: 0.98, height: 0.98),
                                                     about: CGPoint(x: bounds.midX, y: bounds.midY))
            layer.add(WelcomeMotion.animation("transform", from: NSValue(caTransform3D: CATransform3DIdentity), to: NSValue(caTransform3D: smaller),
                                              curve: .depart, duration: duration, on: layer, fill: .forwards), forKey: "leave.transform")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * WelcomeMotion.pace) { done() }
    }

    /// Back from a sign-in's tab: from 0.98 and clear to where it was, on settle.
    private func comeBack() {
        guard let layer else { return }
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        let smaller = WelcomeStageView.transform(size: bounds.size, anchor: layer.anchorPoint, scale: CGSize(width: 0.98, height: 0.98), about: middle)
        layer.add(WelcomeMotion.animation("transform", from: NSValue(caTransform3D: smaller), to: NSValue(caTransform3D: CATransform3DIdentity),
                                          curve: .settle, duration: 0.3, on: layer), forKey: "back.transform")
        layer.add(WelcomeMotion.animation("opacity", from: 0, to: 1, curve: .settle, duration: 0.3, on: layer), forKey: "back.opacity")
    }
}

private enum WelcomeColumns {
    static func leftWidth(_ width: CGFloat) -> CGFloat { width * 0.44 }
}

private struct WelcomeHeading: View {
    let words: WelcomeWords
    var select: (WelcomeStage.Beat) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(words.title).font(.system(size: WelcomeType.title, weight: .bold, design: .rounded))
                .tracking(WelcomeType.title * WelcomeType.tracking)
                .foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Text(words.sub).font(.system(size: WelcomeType.sub)).foregroundStyle(Palette.muted)
            if let scene = words.scene {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(WelcomeSample.scenes, id: \.beat) { step in
                        Button { select(step.beat) } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    Rectangle().fill(Palette.hairline).frame(width: 2)
                                    Circle().fill(Palette.ground).frame(width: 18, height: 18) // design: masks the timeline behind its marker
                                    Circle().strokeBorder(Palette.muted, lineWidth: 1).frame(width: 12, height: 12)
                                    if scene == step.beat { Circle().fill(Palette.ink).frame(width: 8, height: 8) }
                                }
                                .frame(width: 20, height: 40)
                                Text(step.label).font(.system(size: 17, weight: scene == step.beat ? .semibold : .regular))
                            }
                            .foregroundStyle(scene == step.beat ? Palette.ink : Palette.muted)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(scene == step.beat ? .isSelected : [])
                    }
                }
                .padding(.top, 10)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - the frame's buttons

/// What the frame's SwiftUI buttons do, set once the stage is known.
final class WelcomeFootActions {
    var back: () -> Void = {}
    var primary: () -> Void = {}
    var quiet: () -> Void = {}
    var skip: () -> Void = {}
}

/// Where the footer's SwiftUI put its buttons, in its own points: the one
/// button, for Welcome's place, and all of them, for the pointer.
final class WelcomeFootMeasure {
    var primary: CGRect = .zero { didSet { if primary != oldValue { changed?() } } }
    var cluster: CGRect = .zero
    var changed: (() -> Void)?
}

/// The frame that never moves, over the stage: the traffic lights, Back and
/// the dashes in one bottom corner, the failure's words, the quiet word and
/// the one button in the other, and the toast at the top right. All at 1:1
/// in their corners, 10 in, so each corner of 8 shares its center with the
/// window's 18; except the one button on Welcome, which stands under the
/// name at the stage's scale and glides from there to its corner.
@MainActor
final class WelcomeChromeView: NSView {
    let actions: WelcomeFootActions
    var onDash: (Int) -> Void = { _ in }

    /// The buttons' distance from the window's edges: the window's corner
    /// less a button's, so the two corners share one center.
    static let corner = Radius.window - Radius.control
    static let side = ButtonSize.large.height
    /// Room enough for a failure's words, the quiet word and the button,
    /// right-aligned in it; only what is drawn takes the pointer.
    static let room: CGFloat = 640
    /// Where the button stands on Welcome: its top, in stage points.
    static let welcomeTop: CGFloat = 486
    /// The close button's middle, from the window's leading edge.
    static let lightsAt: CGFloat = 26

    private let lightsBox = WelcomeFlippedView()
    private let lights = LightsRow()
    private let back: NSHostingView<WelcomeBack>
    private let dashes = DashesView()
    /// The one button and the words before it, in a box of their own:
    /// scaled with the stage on Welcome, 1:1 in the corner after.
    private let rightBox = WelcomeFlippedView()
    private let right: WelcomeHostingView<WelcomeFootRight>
    private let toast: NSHostingView<WelcomeToast>
    private let skip: NSHostingView<WelcomeSkip>
    private let measure: WelcomeFootMeasure

    private var shown = WelcomeChrome()
    private var first = true
    /// The button is there (it may still be on its way in).
    private var buttonIn = false
    /// When it may be pressed.
    private var liveAt: CFTimeInterval = .infinity
    /// Where the button stands: its middle on screen and its scale.
    private var placed: (center: CGPoint, scale: CGFloat)?

    init() {
        let actions = WelcomeFootActions(), measure = WelcomeFootMeasure()
        self.actions = actions
        self.measure = measure
        back = NSHostingView(rootView: WelcomeBack(actions: actions))
        right = WelcomeHostingView(rootView: WelcomeFootRight(words: WelcomeWords(frame: .welcome, primary: "Get Started"), measure: measure, actions: actions))
        toast = NSHostingView(rootView: WelcomeToast(words: ""))
        skip = NSHostingView(rootView: WelcomeSkip(actions: actions))
        super.init(frame: .zero)
        wantsLayer = true
        for host in [back, right, toast, skip] as [NSView] {
            host.wantsLayer = true
        }
        for host in [back, toast] as [NSView] { host.alphaValue = 0 }
        back.sizingOptions = []
        right.sizingOptions = []
        toast.sizingOptions = []
        back.safeAreaRegions = []
        right.safeAreaRegions = []
        toast.safeAreaRegions = []
        skip.safeAreaRegions = []
        // This island sizes to its label; the footer islands have fixed frames.
        skip.sizingOptions = [.intrinsicContentSize]
        skip.isHidden = true
        lightsBox.wantsLayer = true
        rightBox.wantsLayer = true
        rightBox.alphaValue = 0
        dashes.alphaValue = 0
        rightBox.addSubview(right)
        addSubview(lightsBox)
        addSubview(back)
        addSubview(dashes)
        addSubview(rightBox)
        addSubview(toast)
        addSubview(skip)
        dashes.onSelect = { [weak self] in self?.onDash($0) }
        measure.changed = { [weak self] in self?.needsLayout = true }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The button and the words before it, in `view`'s points, for the bench.
    func cluster(in view: NSView) -> CGRect { view.convert(measure.cluster, from: right) }

    /// The current dash's fill, for the bench.
    var dashState: [String: Any] { dashes.state }

    /// The pinned replay control, in window coordinates, for acceptance probes.
    var skipFrame: CGRect? { skip.isHidden ? nil : skip.frame }

    /// Only the buttons take the pointer, and only while they are there.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point), hit !== self else { return nil }
        if hit === rightBox || hit.isDescendant(of: rightBox) {
            guard buttonIn, rightBox.alphaValue > 0, CACurrentMediaTime() >= liveAt else { return nil }
            return measure.cluster.contains(right.convert(point, from: superview)) ? hit : nil
        }
        if hit === skip || hit.isDescendant(of: skip) { return skip.isHidden ? nil : hit }
        if hit.isDescendant(of: back) { return back.alphaValue > 0 ? hit : nil }
        if hit.isDescendant(of: dashes) { return dashes.alphaValue > 0 ? hit : nil }
        if hit.isDescendant(of: lightsBox) { return lightsBox.alphaValue > 0 ? hit : nil }
        // The toast only says.
        return nil
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let corner = Self.corner, side = Self.side
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lightsBox.frame = CGRect(x: Self.lightsAt - Lights.lead, y: shown.menuDown, width: Lights.run, height: Metrics.strip)
        lights.frame = lightsBox.bounds
        back.frame = CGRect(x: corner, y: size.height - corner - side, width: side, height: side)
        // 12 right of Back, on the footer's line.
        let dash = dashes.intrinsicContentSize
        dashes.frame = CGRect(x: WelcomeColumns.leftWidth(size.width) - corner - dash.width, y: shown.menuDown + HeroLayout.headerY - dash.height / 2, width: dash.width, height: dash.height)
        let skipSize = skip.fittingSize
        skip.frame = CGRect(x: size.width - (Self.lightsAt - Lights.lead) - skipSize.width,
                            y: shown.menuDown + Metrics.strip / 2 - skipSize.height / 2,
                            width: skipSize.width, height: skipSize.height)
        let plate = toast.fittingSize
        toast.frame = CGRect(x: size.width - 12 - plate.width, y: 12, width: plate.width, height: plate.height)
        CATransaction.commit()
        placeRight(animated: false)
    }

    // MARK: showing

    func show(_ new: WelcomeChrome, animated: Bool) {
        guard first || new != shown else { return }
        let old = shown
        shown = new
        let animate = animated && !first
        first = false
        let frame = new.words.frame
        let reduced = new.reduceMotion
        skip.isHidden = !new.skip
        // Out of Welcome, Back and the dashes come a beat after the button leaves.
        let lead = old.words.frame == .welcome && frame == .chapter ? 0.2 : 0
        let fades = animate && !reduced

        if new.lights != (lights.superview != nil) {
            if new.lights { lightsBox.addSubview(lights) } else { lights.removeFromSuperview() }
        }
        fade(lightsBox, new.lights && frame != .finish, fades)
        fade(back, frame == .chapter && new.back, fades, after: lead)
        dashes.show(new.dashes)
        fade(dashes, frame == .chapter, fades, after: lead)
        // Finish keeps the last words while the button goes.
        if frame != .finish {
            right.rootView = WelcomeFootRight(words: new.words, measure: measure, actions: actions)
        }
        fade(rightBox, buttonIn && frame != .finish && new.words.primary != nil, fades)
        if let words = new.toast { toast.rootView = WelcomeToast(words: words) }
        fade(toast, new.toast != nil, fades)
        needsLayout = true
        placeRight(animated: fades)
        // Reduce Motion: what changed in the frame, in one 0.20 crossfade.
        if animate, reduced, let layer {
            let crossfade = CATransition()
            crossfade.type = .fade
            crossfade.duration = 0.2 * WelcomeMotion.pace
            layer.add(crossfade, forKey: "reduced")
        }
    }

    /// The button comes in `delay` seconds from now: 0.94 to 1 and clear on
    /// a spring (0.5, a little give); `reduced`, only its opacity in 0.20.
    func bringButton(after delay: Double, reduced: Bool, animated: Bool) {
        buttonIn = true
        liveAt = CACurrentMediaTime() + delay * WelcomeMotion.pace
        let visible = shown.words.frame != .finish && shown.words.primary != nil
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rightBox.alphaValue = visible ? 1 : 0
        CATransaction.commit()
        guard visible, animated, let layer = right.layer else { return }
        layer.removeAnimation(forKey: "fade")
        if reduced {
            layer.add(WelcomeMotion.animation("opacity", from: 0, to: 1, curve: .linear, duration: 0.2, delay: delay, on: layer), forKey: "arrive.opacity")
            return
        }
        let spring = WelcomeCurve.spring(response: 0.5, damping: 0.85)
        let small = WelcomeStageView.transform(size: right.bounds.size, anchor: layer.anchorPoint, scale: CGSize(width: 0.94, height: 0.94), about: buttonMiddle)
        layer.add(WelcomeMotion.animation("transform", from: NSValue(caTransform3D: small), to: NSValue(caTransform3D: CATransform3DIdentity),
                                          curve: spring, duration: 0.5, delay: delay, on: layer), forKey: "arrive.transform")
        layer.add(WelcomeMotion.animation("opacity", from: 0, to: 1, curve: spring, duration: 0.5, delay: delay, on: layer), forKey: "arrive.opacity")
    }

    /// The button away until it is brought again: the intro replayed.
    func dropButton() {
        buttonIn = false
        liveAt = .infinity
        right.layer?.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rightBox.alphaValue = 0
        CATransaction.commit()
    }

    /// A view shown or not, in 0.22 arrive or out in 0.15 depart, `after`
    /// seconds; not animated, at once. Its opacity is AppKit's alpha, so
    /// what AppKit asks of the view sees it too.
    private func fade(_ view: NSView, _ visible: Bool, _ animated: Bool, after delay: Double = 0) {
        let target: CGFloat = visible ? 1 : 0
        guard view.alphaValue != target else { return }
        let from = view.layer?.presentation()?.opacity ?? Float(view.alphaValue)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.alphaValue = target
        CATransaction.commit()
        guard let layer = view.layer else { return }
        layer.removeAnimation(forKey: "fade")
        guard animated else { return }
        layer.add(WelcomeMotion.animation("opacity", from: from, to: Float(target), curve: visible ? .arrive : .depart,
                                          duration: visible ? 0.22 : 0.15, delay: delay, on: layer), forKey: "fade")
    }

    // MARK: the one button's place

    /// The button's middle in its box's points: its box is right-aligned,
    /// so the button is as far from the box's end as half its width.
    private var buttonMiddle: CGPoint {
        let width = measure.primary.width > 0 ? measure.primary.width : right.fittingSize.width
        return CGPoint(x: Self.room - width / 2, y: Self.side / 2)
    }

    /// On Welcome, under the name at the stage's scale (its top at 486 in
    /// stage points); in a chapter, 10 in from the corner at 1:1. From one
    /// to the other it glides (glide, 0.34/0.82), scaling as it goes, while
    /// its words morph: the prototype's `primaryWelcomeTf`. Its box is
    /// placed by frame, so the pointer finds it where it is drawn.
    private func placeRight(animated: Bool) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let room = Self.room, side = Self.side
        let welcome = shown.words.frame == .welcome
        let s: CGFloat = welcome ? 1.15 : 1
        let middle = buttonMiddle
        let frame: CGRect
        if welcome {
            let c = StageSpace.toWindow(CGPoint(x: StageSpace.pivot.x, y: Self.welcomeTop + side / 2), in: CGSize(width: WelcomeColumns.leftWidth(size.width), height: size.height))
            let offset = HeroLayout.openingOffset(in: CGSize(width: WelcomeColumns.leftWidth(size.width), height: size.height))
            frame = CGRect(x: c.x - middle.x * s, y: c.y + offset - middle.y * s, width: room * s, height: side * s)
        } else {
            frame = CGRect(x: WelcomeColumns.leftWidth(size.width) - Self.corner - room, y: size.height - Self.corner - side, width: room, height: side)
        }
        let was = placed
        placed = (CGPoint(x: frame.minX + middle.x * s, y: frame.minY + middle.y * s), s)
        guard rightBox.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rightBox.frame = frame
        rightBox.bounds = CGRect(x: 0, y: 0, width: room, height: side)
        right.frame = rightBox.bounds
        CATransaction.commit()
        guard let layer = right.layer else { return }
        guard animated, let was, rightBox.alphaValue > 0 else {
            layer.removeAnimation(forKey: "glide")
            return
        }
        // From where it stood, at the scale it stood at, to here: the
        // button's middle carried from there, about its own middle.
        let k = was.scale / s
        let there = CGPoint(x: (was.center.x - frame.minX) / s, y: (was.center.y - frame.minY) / s)
        let start = WelcomeStageView.transform(size: right.bounds.size, anchor: layer.anchorPoint, scale: CGSize(width: k, height: k),
                                               about: middle, move: CGPoint(x: there.x - middle.x, y: there.y - middle.y))
        layer.add(WelcomeMotion.animation("transform", from: NSValue(caTransform3D: start), to: NSValue(caTransform3D: CATransform3DIdentity),
                                          curve: .glide, duration: 0.34, on: layer), forKey: "glide")
    }
}

private struct WelcomeSkip: View {
    let actions: WelcomeFootActions

    var body: some View {
        Button("Skip Onboarding") { actions.skip() }
            .buttonStyle(.yab(.quiet, .regular))
            .accessibilityIdentifier("welcome.skip")
    }
}

/// Back: glass, large, square, the chevron at 16; ⌘[ and Esc do the same.
private struct WelcomeBack: View {
    let actions: WelcomeFootActions

    var body: some View {
        Button { actions.back() } label: {
            Symbol("chevron.left", size: 16 / Glyphs.scale)
        }
        .buttonStyle(.yab(.glass, .large, icon: .square))
        .accessibilityLabel("Back")
    }
}

/// The footer's other corner: a failure said in words, the quiet word,
/// and the one button, right-aligned, 8 apart, the failure 16 before the
/// next.
private struct WelcomeFootRight: View {
    static let space = "welcome.foot"

    let words: WelcomeWords
    let measure: WelcomeFootMeasure
    let actions: WelcomeFootActions

    var body: some View {
        HStack(spacing: 8) {
            if let failure = words.failure {
                // Said beside the button: no red, no icon, one line.
                Text(failure)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
            if let quiet = words.quiet {
                Button { actions.quiet() } label: { MorphText(quiet) }
                    .buttonStyle(.yab(.quiet, .large))
                    .transition(.opacity)
            }
            if let title = words.primary {
                WelcomePrimary(title: title, busy: words.busy, disabled: words.disabled) { actions.primary() }
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { measure.primary = $0 }
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { measure.cluster = $0 }
        .animation(words.quiet == nil ? Motion.depart : Motion.arrive, value: words.quiet == nil)
        .animation(words.failure == nil ? Motion.depart : Motion.arrive, value: words.failure)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .coordinateSpace(.named(Self.space))
    }
}

/// The one button, from Welcome to the end: glass, large, ↩ on its plate
/// beside its words, which only ever change by morphing. Return presses it
/// (App's key watcher, through browser.welcomeReturn).
private struct WelcomePrimary: View {
    let title: String
    /// Under way: the words muted, no ↩, the press does nothing.
    var busy = false
    /// Not yet: at 0.45, no ↩.
    var disabled = false
    let action: () -> Void

    var body: some View {
        Button(action: { if !busy { action() } }) {
            HStack(spacing: 6) {
                MorphText(title)
                if !(busy || disabled) {
                    KeyGlyphs(keys: "\u{21A9}", size: 13, tint: nil, rest: 0.6)
                        .transaction { $0.animation = nil }
                }
            }
            .foregroundStyle(busy ? Palette.muted : Palette.ink)
            .fixedSize()
        }
        .buttonStyle(.yab(.glass, .large))
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}

/// The corner's one toast: "Everything from Dia is in".
private struct WelcomeToast: View {
    let words: String

    var body: some View {
        NoticePlate(words: words, mark: "tray.and.arrow.down")
    }
}

// MARK: - Welcome, before the chapters

/// Welcome itself: the mark, its light and the name are WelcomeHero's; the
/// stage holds the lede under them.
@MainActor
enum WelcomeOpening: WelcomeChapter {
    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat] { [.welcome] }

    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords {
        WelcomeWords(frame: .welcome, primary: "Get Started")
    }

    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        // The lede comes in after the name, as the intro has it; with
        // Reduce Motion, in the one crossfade.
        let first = moment.phase == "intro" && !stage.reduceMotion
        return WelcomeBoard([
            // Where the mark stands, drawn by WelcomeHero: for the first
            // chapter's parts to grow out of (`.grow(from: "wmark")`).
            StagePart("wmark", HeroLayout.mark, enter: StagePart.Enter.none, exit: .none),
            .view("wlede", CGRect(x: 0, y: 434, width: StageSpace.size.width, height: 48), enter: first ? .lede : .crossfade, delay: first ? HeroView.ledeAt : 0) {
                WelcomeLede()
            },
        ])
    }

    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async {
        player.show("intro")
    }
}

// MARK: - the dashes

/// One dash per chapter on this path, beside Back: done ones lit, the
/// current one longer and filled as far as its beats have gone, the rest
/// faint. A click on a done one goes back there.
///
/// In Core Animation: widths and fills move on the dash curve when the
/// chapter or the beat changes, and nothing is drawn in between. Drawn by
/// SwiftUI, a fill was a render and a commit every frame, each able to
/// wait on the window server.
private final class DashesView: NSView {
    var onSelect: ((Int) -> Void)?
    private var tracks: [CALayer] = []
    private var fills: [CALayer] = []
    private var shown: WelcomeDashes?
    private static let gap: CGFloat = 4
    private static let height: CGFloat = 4
    private static let current: CGFloat = 28
    private static let other: CGFloat = 12
    /// Room above and below for the click.
    private static let reach: CGFloat = 6
    /// When the current run began, for dashes made again in the middle of it.
    private var runBegan: (token: Int, at: CFTimeInterval)?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        tint()
    }

    /// The window's ink, light or dark as the Mac is: done 0.92, the rest
    /// 0.18, the current one's fill 0.92.
    private func tint() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (index, track) in tracks.enumerated() {
                let done = index < (shown?.current ?? 0)
                track.backgroundColor = Palette.NS.ink.withAlphaComponent(done ? 0.92 : 0.18).cgColor
            }
            fills.forEach { $0.backgroundColor = Palette.NS.ink.withAlphaComponent(0.92).cgColor }
            CATransaction.commit()
        }
    }

    private func width(_ index: Int, _ dashes: WelcomeDashes) -> CGFloat {
        index == dashes.current ? Self.current : Self.other
    }

    override var intrinsicContentSize: NSSize {
        guard let dashes = shown, !dashes.chapters.isEmpty else { return NSSize(width: 0, height: Self.height + Self.reach * 2) }
        let total = dashes.chapters.indices.map { width($0, dashes) }.reduce(0, +) + Self.gap * CGFloat(dashes.chapters.count - 1)
        return NSSize(width: total, height: Self.height + Self.reach * 2)
    }

    func show(_ dashes: WelcomeDashes) {
        guard dashes != shown else { return }
        // Only the run held or let go: its fill stops or goes on where it is.
        var same = dashes
        same.paused = shown?.paused ?? dashes.paused
        if let shown, same == shown, dashes.run > 0, fills.indices.contains(dashes.current) {
            self.shown = dashes
            hold(fills[dashes.current], dashes.paused)
            return
        }
        let fresh = dashes.chapters.count != tracks.count
        if fresh {
            tracks.forEach { $0.removeFromSuperlayer() }
            tracks = dashes.chapters.map { _ in
                let track = CALayer()
                track.cornerRadius = Self.height / 2
                track.masksToBounds = true
                return track
            }
            fills = dashes.chapters.map { _ in
                let fill = CALayer()
                fill.cornerRadius = Self.height / 2
                fill.anchorPoint = CGPoint(x: 0, y: 0.5)
                return fill
            }
            for (track, fill) in zip(tracks, fills) {
                track.addSublayer(fill)
                layer?.addSublayer(track)
            }
        }
        let before = intrinsicContentSize
        let animated = shown != nil && !fresh
        let previous = shown
        shown = dashes
        // Only when the width is new: asked on every update, it had the
        // window laid out again on every frame.
        if intrinsicContentSize != before { invalidateIntrinsicContentSize() }
        tint()

        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.34 * WelcomeMotion.pace)
            CATransaction.setAnimationTimingFunction(WelcomeCurve.dash.function)
        } else {
            CATransaction.setDisableActions(true)
        }
        var x: CGFloat = 0
        for index in tracks.indices {
            let w = width(index, dashes)
            tracks[index].frame = CGRect(x: x, y: Self.reach, width: w, height: Self.height)
            fills[index].position = CGPoint(x: 0, y: Self.height / 2)
            let share: CGFloat = index == dashes.current ? dashes.fill : 0
            let running = index == dashes.current && dashes.run > 0
            // A run already going (a refresh of the same beat) is left to go
            // on; on fresh dashes (the path changed under it) it starts again
            // where it had got to.
            let going = running && !fresh && previous?.token == dashes.token && previous?.current == dashes.current && (previous?.run ?? 0) > 0
            if !going {
                // A run's own animation takes the width, not the dash curve.
                if running { CATransaction.setDisableActions(true) }
                fills[index].bounds = CGRect(x: 0, y: 0, width: w * share, height: Self.height)
                fills[index].isHidden = share == 0
                if fills[index].animation(forKey: "run") != nil || fills[index].speed == 0 {
                    fills[index].removeAnimation(forKey: "run")
                    hold(fills[index], false, reset: true)
                }
            }
            if running, !going {
                // Linear, the beat's length: the dash says how long until the next.
                let run = CABasicAnimation(keyPath: "bounds.size.width")
                run.fromValue = w * dashes.from
                run.toValue = w * share
                run.duration = dashes.run
                run.timingFunction = CAMediaTimingFunction(name: .linear)
                let began = runBegan?.token == dashes.token ? runBegan?.at ?? CACurrentMediaTime() : CACurrentMediaTime()
                runBegan = (dashes.token, began)
                run.beginTime = fills[index].convertTime(began, from: nil)
                // In a transaction of its own: the enclosing one's dash curve
                // otherwise replaces the run's linear one.
                CATransaction.begin()
                CATransaction.setAnimationTimingFunction(run.timingFunction)
                fills[index].add(run, forKey: "run")
                CATransaction.commit()
                if dashes.paused { hold(fills[index], true) }
            }
            if running, animated { CATransaction.setDisableActions(false) }
            x += w + Self.gap
        }
        CATransaction.commit()
    }

    /// The current dash's fill as drawn now, for the bench.
    var state: [String: Any] {
        guard let current = shown?.current, fills.indices.contains(current) else { return [:] }
        let fill = fills[current]
        return ["model": Double(fill.bounds.width), "shown": Double(fill.presentation()?.bounds.width ?? -1),
                "track": Double(tracks[current].bounds.width), "keys": fill.animationKeys() ?? [], "speed": Double(fill.speed),
                "hidden": fill.isHidden]
    }

    /// A fill's run stopped where it is, or going on from there.
    private func hold(_ fill: CALayer, _ held: Bool, reset: Bool = false) {
        if reset {
            fill.speed = 1
            fill.timeOffset = 0
            fill.beginTime = 0
            return
        }
        if held {
            guard fill.speed != 0 else { return }
            let now = fill.convertTime(CACurrentMediaTime(), from: nil)
            fill.speed = 0
            fill.timeOffset = now
        } else {
            guard fill.speed == 0 else { return }
            let stopped = fill.timeOffset
            fill.speed = 1
            fill.timeOffset = 0
            fill.beginTime = 0
            fill.beginTime = fill.convertTime(CACurrentMediaTime(), from: nil) - stopped
        }
    }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        guard let dashes = shown else { return }
        var left: CGFloat = 0
        for (index, chapter) in dashes.chapters.enumerated() {
            let w = width(index, dashes)
            if x >= left - Self.gap / 2, x < left + w + Self.gap / 2 {
                if index < dashes.current { onSelect?(chapter) }
                return
            }
            left += w + Self.gap
        }
    }
}

/// Welcome's line under the name, and under it, when this Yab came from a
/// friend's link, who sent it (Invites).
struct WelcomeLede: View {
    @ObservedObject private var invites = Invites.shared

    var body: some View {
        VStack(spacing: 6) {
            Text("Your tabs, your spaces, and your own AI agent.")
                .font(.system(size: WelcomeType.lede))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
            if let received = invites.received {
                Text("From \(received.from)")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .lineLimit(1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.3), value: invites.received)
    }
}
