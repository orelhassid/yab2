import AppKit
import SwiftUI

/// A tick of the trackpad under a finger dragging a value, the way Arc's
/// space editor has one: its grain dial on every step, its intensity
/// slider where the value crosses a mark; and a knock at either end. Only
/// a Force Touch trackpad gives it, and only while the finger is down,
/// which a drag is.
enum Detents {
    /// Whether going from `old` to `new` meets a mark: a whole multiple of
    /// `step`, either end counted (Arc's own test).
    static func crossed(_ old: Double, _ new: Double, every step: Double) -> Bool {
        guard old != new, step > 0 else { return false }
        let lo = min(old, new) / step, hi = max(old, new) / step
        return (lo - 1e-9).rounded(.up) <= (hi + 1e-9).rounded(.down)
    }

    static func tick() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    /// A change felt: a knock where it runs into either end, a tick where
    /// it meets a mark on the way.
    @MainActor
    static func feel(_ old: Double, _ new: Double, every step: Double) {
        guard old != new else { return }
        if new == 0 || new == 1 { Knock.play() } else if crossed(old, new, every: step) { tick() }
    }
}

/// A knock of the trackpad's own actuator, for a value run into its end:
/// far firmer than NSHapticFeedbackManager's patterns, which have no
/// strength to set. Reached through MultitouchSupport, a private framework,
/// the way HapticKey reaches it; where it won't open, `.levelChange`, the
/// firmest public pattern, stands in.
@MainActor
enum Knock {
    private typealias CreateList = @convention(c) () -> Unmanaged<CFArray>?
    private typealias DeviceID = @convention(c) (UnsafeRawPointer, UnsafeMutablePointer<UInt64>) -> Int32
    private typealias FromID = @convention(c) (UInt64) -> UnsafeMutableRawPointer?
    private typealias Open = @convention(c) (UnsafeMutableRawPointer) -> Int32
    private typealias Actuate = @convention(c) (UnsafeMutableRawPointer, Int32, UInt32, Float, Float) -> Int32

    /// The firmest of the actuator's waveforms.
    private static let firm: Int32 = 6

    /// Every trackpad's actuator, opened the first time one knocks and
    /// kept open for good.
    private static let actuators: (actuate: Actuate, all: [UnsafeMutableRawPointer])? = {
        guard let lib = dlopen("/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW),
              let list = dlsym(lib, "MTDeviceCreateList"), let id = dlsym(lib, "MTDeviceGetDeviceID"),
              let from = dlsym(lib, "MTActuatorCreateFromDeviceID"), let open = dlsym(lib, "MTActuatorOpen"),
              let actuate = dlsym(lib, "MTActuatorActuate"),
              let devices = unsafeBitCast(list, to: CreateList.self)()?.takeRetainedValue()
        else { return nil }
        var all: [UnsafeMutableRawPointer] = []
        for i in 0..<CFArrayGetCount(devices) {
            guard let device = CFArrayGetValueAtIndex(devices, i) else { continue }
            var number: UInt64 = 0
            guard unsafeBitCast(id, to: DeviceID.self)(device, &number) == 0,
                  let actuator = unsafeBitCast(from, to: FromID.self)(number),
                  unsafeBitCast(open, to: Open.self)(actuator) == 0 else { continue }
            all.append(actuator)
        }
        guard !all.isEmpty else { return nil }
        return (actuate: unsafeBitCast(actuate, to: Actuate.self), all: all)
    }()

    /// Knocks closer than this are one: a pull to the wave's end and on
    /// into the glass past it knocked at the end and again at the glass, a
    /// double pulse for one arrival (register row 991). A scroll there
    /// did the same.
    static let apart: CFTimeInterval = 0.35
    private static var last: CFTimeInterval = -.infinity
    /// How many knocks were played, for tests.
    private(set) static var played = 0

    /// Whether a knock now is a new one, counted as played if so.
    static func due(at now: CFTimeInterval = CACurrentMediaTime()) -> Bool {
        guard now - last >= apart else { return false }
        last = now
        played += 1
        return true
    }

    static func play() {
        guard due() else { return }
        guard let actuators else {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            return
        }
        for actuator in actuators.all { _ = actuators.actuate(actuator, firm, 0, 0, 0) }
    }
}

/// A look's slider, the transparency's and the grain's, handled alike: the
/// pill is taken where it's held, a press on the track glides it there, ⌥
/// slows a drag to a quarter, a sideways scroll over it moves it, a double
/// click puts it back. The trackpad ticks at each `step` and knocks at
/// either end. The track shows what it does: the transparency a wave that
/// flattens past the pill, as Arc draws it; the grain dots that thicken to
/// the right, dark as far as the pill.
///
/// The wave can go one step past its end: a bead of glass, the window as
/// Liquid Glass with the look's color a tint on it (WindowGlassPolicy).
/// Pulled into it, the pill snaps in with the knock the end gives and
/// "Glass" says so; pulled back out, it is the wave's pill again, where
/// the pointer is. A press on the bead goes in too; a double click puts
/// both back as the editor opened.
struct LookSlider: View {
    enum Track { case wave, grain, drawings }

    let track: Track
    let value: CGFloat
    /// The trackpad ticks every this much.
    let step: Double
    /// Where a double click puts it back.
    let reset: CGFloat
    /// The stops it rounds to, if any: the grain's twentieths, as Arc's dial.
    var stops: Int?
    /// The step past the end, glass; nil where a look can't wear it.
    var glass: Binding<Bool>? = nil
    /// Where a double click puts the glass back.
    var resetGlass = false
    /// The look's color, on the bead.
    var tint: Color = .clear
    /// Said over the pill while it's under the pointer or held.
    let says: (CGFloat) -> String
    let change: (CGFloat) -> Void

    @State private var hand = Hand()
    @State private var hover = false
    @State private var held = false
    /// The press was a double click's second: the rest of it does nothing.
    @State private var twice = false
    /// The pointer is over the glass bead: the label names it.
    @State private var overBead = false
    @State private var label: CGFloat = 0

    static let thumb = CGSize(width: 10, height: 26)
    /// The bead at rest, and as wide as the room past the wave it takes.
    static let bead: CGFloat = 20
    static let beadRoom: CGFloat = 32

    private var glassy: Bool { glass?.wrappedValue == true }

    var body: some View {
        GeometryReader { geo in
            let room = glass == nil ? 0 : Self.beadRoom
            let travel = max(1, geo.size.width - Self.thumb.width - room)
            // Worn, the bead is a size up with the pill's shadow: all of it
            // inside the slider, or the card cuts its edge off.
            let beadX = geo.size.width - (Self.bead + 4) / 2 - Shadow.thumb.radius
            let x = glassy ? beadX : Self.thumb.width / 2 + value * travel
            let lifted = hover || held
            ZStack {
                Group {
                    switch track {
                    case .wave: WaveTrack(value: glassy ? 1 : value, still: glassy)
                    case .grain: GrainTrack(value: value)
                    case .drawings: DrawingsTrack(value: value)
                    }
                }
                .padding(.leading, Self.thumb.width / 2)
                .padding(.trailing, Self.thumb.width / 2 + room) // design: the track stops short of the glass bead's room past its end
                if glass != nil {
                    GlassBead(on: glassy, tint: tint)
                        .position(x: beadX, y: geo.size.height / 2)
                }
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().strokeBorder(.black.opacity(0.22), lineWidth: 0.5))
                    .frame(width: Self.thumb.width, height: Self.thumb.height + (lifted ? 4 : 0))
                    .shadow(color: .black.opacity(Double(Shadow.thumb.opacity)), radius: Shadow.thumb.radius, y: Shadow.thumb.y) // design: Shadow.thumb is from Design.swift
                    .animation(Motion.quick, value: lifted)
                    .opacity(glassy ? 0 : 1)
                    .position(x: x, y: geo.size.height / 2)
                    .animation(Motion.quick, value: glassy)
                if lifted {
                    let named = glassy || (overBead && !held)
                    Text(named ? "Glass" : says(value))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Palette.ground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Palette.ink, in: Capsule())
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { label = $0 }
                        // Centered over the pill, but kept inside the track:
                        // at either end it would run past the popover's edge.
                        .position(x: min(max(named ? beadX : x, label / 2), max(label / 2, geo.size.width - label / 2)), y: -8)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let at) = phase { overBead = glass != nil && at.x >= geo.size.width - room } else { overBead = false }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        // Past the wave's end, over the bead's room.
                        let edge = geo.size.width - room
                        if !held {
                            held = true
                            sync()
                            twice = Self.doubleClick
                            // A second click of a double one puts it back.
                            if twice { glass?.wrappedValue = resetGlass }
                            if let glass, !twice, drag.startLocation.x >= edge {
                                // A press on the bead: glass, the wave as it was.
                                enter(glass)
                                return
                            }
                            if !twice, glassy { glass?.wrappedValue = false }
                            hand.begin(at: drag.startLocation.x, thumb: Self.thumb.width / 2 + value * travel, travel: travel,
                                       twice: twice, reset: reset)
                        }
                        guard !twice else { return }
                        if let glass {
                            // A few points either side of the edge, so a hand
                            // resting on it doesn't flicker in and out.
                            if drag.location.x >= edge + 2 {
                                enter(glass)
                                return
                            }
                            if glass.wrappedValue {
                                guard drag.location.x < edge - 2 else { return }
                                // Back out of the bead: the pill under the pointer.
                                glass.wrappedValue = false
                                hand.take(at: drag.location.x)
                                return
                            }
                        }
                        hand.move(to: drag.location.x, from: drag.startLocation.x, travel: travel)
                    }
                    .onEnded { _ in held = false }
            )
            .onChange(of: travel, initial: true) { _, travel in hand.travel = travel }
        }
        .frame(height: 32)
        .onHover { inside in
            hover = inside
            if inside { sync(); hand.listen() } else { hand.quiet() }
        }
        .onChange(of: value) { _, value in hand.current = value }
        .onDisappear { hand.quiet(); hand.stop() }
        .accessibilityElement()
        .accessibilityLabel(glassy ? "Glass" : says(value))
        .accessibilityAdjustableAction { direction in
            sync()
            if let glass {
                if direction == .increment, value >= 1 { enter(glass); return }
                if direction == .decrement, glass.wrappedValue { glass.wrappedValue = false; return }
            }
            hand.put(hand.current + (direction == .increment ? 0.1 : -0.1))
        }
    }

    /// Into the glass, with the knock the wave's end gives.
    private func enter(_ glass: Binding<Bool>) {
        // A track press may still be gliding toward the wave's end. Glass
        // takes over now; that glide must not change the wave or knock later.
        hand.stop()
        guard !glass.wrappedValue else { return }
        glass.wrappedValue = true
        Knock.play()
    }

    /// Whether the press is a double click's second one. Asked of the event
    /// only when it is a mouse's: clickCount raises on any other, and under
    /// the welcome's stage the current event is often one of AppKit's own,
    /// which killed the drag at its first move.
    private static var doubleClick: Bool {
        guard let event = NSApp.currentEvent, [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type) else { return false }
        return event.clickCount > 1
    }

    private func sync() {
        hand.current = value
        hand.step = step
        hand.stops = stops
        hand.change = change
        if let glass {
            hand.glassy = { glass.wrappedValue }
            hand.glaze = { on in
                glass.wrappedValue = on
                if on { Knock.play() }
            }
        } else {
            hand.glassy = { false }
            hand.glaze = nil
        }
    }
}

/// What a slider's pill does between renders: held, gliding, scrolled.
/// Kept apart from the view so a glide's frames and a scroll's events each
/// start from the value last put, not from the render they began in.
@MainActor
private final class Hand {
    var current: CGFloat = 0
    var step = 0.1
    var stops: Int?
    var change: (CGFloat) -> Void = { _ in }
    var travel: CGFloat = 1
    /// The wave's glass past its end (LookSlider.glass): on now, and
    /// turned on or off by a scroll.
    var glassy: () -> Bool = { false }
    var glaze: ((Bool) -> Void)?

    private var offset: CGFloat = 0
    private var raw: CGFloat = 0
    private var lastX: CGFloat = 0
    private var moved = false
    private var dead = false
    private var glider: Timer?
    private var monitor: Any?
    private var wheel: CGFloat?

    private static let half = LookSlider.thumb.width / 2
    private static func clamp(_ v: CGFloat) -> CGFloat { min(1, max(0, v)) }

    func begin(at start: CGFloat, thumb: CGFloat, travel: CGFloat, twice: Bool, reset: CGFloat) {
        moved = false
        dead = twice
        lastX = start
        raw = current
        if twice { glide(to: reset); return }
        // On the pill (and a little round it) it's taken where it's held;
        // on the track it glides to the press.
        if abs(start - thumb) <= Self.half + 6 {
            offset = start - thumb
            stop()
        } else {
            offset = 0
            glide(to: (start - Self.half) / travel)
        }
    }

    func move(to x: CGFloat, from start: CGFloat, travel: CGFloat) {
        guard !dead else { return }
        if !moved {
            guard abs(x - start) > 3 else { return }
            moved = true
            stop()
            raw = current
        }
        if NSEvent.modifierFlags.contains(.option) {
            raw = Self.clamp(raw + (x - lastX) * 0.25 / travel)
            offset = x - (Self.half + raw * travel)
        } else {
            raw = Self.clamp((x - offset - Self.half) / travel)
        }
        lastX = x
        put(raw)
    }

    /// Taken where the pointer is, with nothing to glide to: the pill back
    /// out of the glass bead onto the wave.
    func take(at x: CGFloat) {
        stop()
        dead = false
        moved = true
        offset = 0
        lastX = x
        raw = Self.clamp((x - Self.half) / travel)
        put(raw)
    }

    func put(_ raw: CGFloat) {
        let clamped = Self.clamp(raw)
        let value = stops.map { (clamped * CGFloat($0)).rounded() / CGFloat($0) } ?? clamped
        guard value != current else { return }
        Detents.feel(Double(current), Double(value), every: step)
        current = value
        change(value)
    }

    func glide(to target: CGFloat) {
        stop()
        let from = current, to = Self.clamp(target), began = CACurrentMediaTime()
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { put(to); return }
        let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let p = min(1, (CACurrentMediaTime() - began) / 0.16)
                self.put(from + (to - from) * CGFloat(1 - pow(1 - p, 3)))
                if p >= 1 { self.stop() }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        glider = timer
    }

    func stop() {
        glider?.invalidate()
        glider = nil
    }

    /// While the pointer is over the slider: a scroll that goes more
    /// sideways than up or down moves the pill with the fingers, and is
    /// taken; any other goes on to the page under it.
    func listen() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scrolled(event) ?? event }
        }
    }

    func quiet() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        wheel = nil
    }

    private func scrolled(_ event: NSEvent) -> NSEvent? {
        let dx = event.scrollingDeltaX
        guard abs(dx) > abs(event.scrollingDeltaY) else { return event }
        stop()
        if event.phase == .began || wheel == nil { wheel = current }
        // With natural scrolling the delta goes the fingers' way.
        let fingers = (event.isDirectionInvertedFromDevice ? dx : -dx) * (event.hasPreciseScrollingDeltas ? 1 : 8)
        // Past the wave's end, the glass; back from it, the wave as it was.
        if let glaze {
            if glassy() {
                if fingers < 0 { glaze(false); wheel = current }
                return nil
            }
            if fingers > 0, current >= 1, (wheel ?? current) + fingers / travel > 1.04 {
                glaze(true)
                return nil
            }
        }
        let next = Self.clamp((wheel ?? current) + fingers / travel)
        wheel = next
        put(next)
        return nil
    }
}

/// The wave's last step: a bead of Liquid Glass past its end, in the look's
/// color, a hairline round it at rest; worn, it takes the pill's place,
/// a size up, in the pill's white ring.
private struct GlassBead: View {
    let on: Bool
    let tint: Color

    var body: some View {
        let side = on ? LookSlider.bead + 4 : LookSlider.bead
        Group {
            if #available(macOS 26.0, *) {
                Circle().fill(tint.opacity(on ? 0.5 : 0.35)).glassEffect(.regular, in: Circle())
            } else {
                Circle().fill(tint.opacity(0.5))
            }
        }
        .overlay(Circle().strokeBorder(on ? Color.white : Palette.ink.opacity(0.22), lineWidth: on ? 2 : 0.5))
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(on ? Double(Shadow.thumb.opacity) : 0), radius: Shadow.thumb.radius, y: Shadow.thumb.y) // design: Shadow.thumb is from Design.swift
        .animation(Motion.quick, value: on)
        .accessibilityHidden(true)
    }
}

/// The lightness's track, as Arc draws it: a wave at full height up to the
/// pill, dying away past it.
private struct WaveTrack: View {
    let value: CGFloat
    /// The pill gone into the glass past the end: the wave quieter.
    var still = false

    var body: some View {
        Canvas { context, size in
            let cut = value * size.width, mid = size.height / 2
            var path = Path()
            var t: CGFloat = 0
            while t <= size.width {
                let amp: CGFloat = t < cut ? 5 : 5 * CGFloat(exp(-Double(t - cut) / 10))
                let p = CGPoint(x: t, y: mid - amp * sin(t / size.width * 5 * 2 * .pi))
                if t == 0 { path.move(to: p) } else { path.addLine(to: p) }
                t += 1
            }
            context.stroke(path, with: .color(Palette.ink.opacity(still ? 0.3 : 0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}

/// The grain's track: a scatter of dots, sparse at none and thick at the
/// roughest, dark as far as the pill and faint past it.
private struct GrainTrack: View {
    let value: CGFloat

    /// Where each dot sits, 0...1 along and -1...1 across, and its size:
    /// the same scatter every time.
    private static let dots: [(x: CGFloat, y: CGFloat, r: CGFloat)] = {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        var out: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []
        while out.count < 170 {
            let x = next()
            if next() < 0.12 + x * 0.88 { out.append((x, next() * 2 - 1, 0.8 + next() * 0.6)) }
        }
        return out
    }()

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            for dot in Self.dots {
                let at = CGPoint(x: dot.x * size.width, y: mid + dot.y * 8)
                context.fill(Path(ellipseIn: CGRect(x: at.x - dot.r, y: at.y - dot.r, width: dot.r * 2, height: dot.r * 2)),
                             with: .color(Palette.ink.opacity(dot.x <= value ? 0.72 : 0.16)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The drawings' track: small crosses, few at the faint end and many at
/// the strong, dark as far as the pill, as the grain's dots are; crosses
/// rather than dots, so the two tracks never read as the same thing.
private struct DrawingsTrack: View {
    let value: CGFloat

    private static let marks: [(x: CGFloat, y: CGFloat, r: CGFloat)] = {
        var seed: UInt64 = 0xD0D1E5
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        var out: [(x: CGFloat, y: CGFloat, r: CGFloat)] = []
        while out.count < 36 {
            let x = next()
            if next() < 0.12 + x * 0.88 { out.append((x, next() * 1.6 - 0.8, 1.8 + next() * 1.2)) }
        }
        return out
    }()

    var body: some View {
        Canvas { context, size in
            let mid = size.height / 2
            for mark in Self.marks {
                let at = CGPoint(x: mark.x * size.width, y: mid + mark.y * 8)
                var cross = Path()
                cross.move(to: CGPoint(x: at.x - mark.r, y: at.y))
                cross.addLine(to: CGPoint(x: at.x + mark.r, y: at.y))
                cross.move(to: CGPoint(x: at.x, y: at.y - mark.r))
                cross.addLine(to: CGPoint(x: at.x, y: at.y + mark.r))
                context.stroke(cross, with: .color(Palette.ink.opacity(mark.x <= value ? 0.72 : 0.16)),
                               style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

/// The color a look is, as the wheel starts from it: your own, or the
/// preset's own color, which turning the wheel makes your own.
extension Swatch {
    func start(custom: NSColor) -> NSColor { self == .custom ? custom : color(dark: false, custom: custom) }
}

/// The dot a look's editor opens from: its color inside the rainbow's
/// ring, which says it turns.
struct LookDot: View {
    let swatch: Swatch
    let custom: NSColor
    var colors: [String] = []

    var body: some View {
        if swatch == .plain {
            // Inside the same ring: it turns too.
            SwatchDot(swatch: .custom, ownPicked: false, custom: custom, dark: false)
                .overlay { PlainDot().padding(3) } // design: the inside of the rainbow's ring, as the picked color's
        } else {
            picked
        }
    }

    private var picked: some View {
        // The colors picked, as the field's dots show them, not the
        // window's dark shade of them.
        SwatchDot(swatch: .custom, ownPicked: true, custom: swatch.start(custom: custom), dark: false)
            .overlay {
                if !colors.isEmpty {
                    Circle().fill(LinearGradient(colors: [Color(nsColor: swatch.start(custom: custom))]
                        + colors.compactMap(NSColor.init(hex:)).map { Color(nsColor: $0) },
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                        .padding(4)
                }
            }
    }
}

/// A look as its dot, opening the look card's own controls in a popover
/// beside it (LookControls), with no head, as the card has none: ⋯ in the
/// field's corner holds Reset once something changed and Use for All
/// Spaces where there are others.
/// How Appearance and a space's page set a look. `footer`: under the
/// controls, Appearance's offer of another browser's look.
struct LookPicker<Footer: View>: View {
    @Binding var paint: SpacePaint
    /// Its space, in the popover's head: "🏠 Personal".
    let named: String
    var forAll: (() -> Void)? = nil
    let onPick: () -> Void
    @ViewBuilder let footer: () -> Footer
    /// Asked open from outside, Window's "A color" picked (#459); set back
    /// once it is.
    var asked: Binding<Bool>? = nil
    /// No dot of its own: only the popover, over what it is laid behind
    /// (Appearance's Look row with spaces).
    var dotless = false
    var offersBrowserTabs = true
    @State private var open = false
    /// The look the popover opened on, for Reset.
    @State private var opened: SpacePaint? = nil

    var body: some View {
        anchor
        // Beside it: the controls are taller than the room under a row.
        .popover(isPresented: $open, arrowEdge: .leading) {
            VStack(alignment: .leading, spacing: 0) {
                LookControls(look: .paint($paint), offersSite: offersBrowserTabs, offersTabShift: offersBrowserTabs,
                             corner: AnyView(LookCorner(changed: opened.map { $0 != paint } ?? false,
                                                        reset: { if let opened { paint = opened } }, forAll: forAll)),
                             picked: onPick)
                footer()
            }
            .frame(width: LookCardView.inner)
            .padding(CardFrame.inset)
        }
        .onChange(of: asked?.wrappedValue ?? false) { _, on in
            guard on else { return }
            asked?.wrappedValue = false
            // After the menu it was picked in has gone.
            DispatchQueue.main.async { if !open { toggle() } }
        }
    }

    @ViewBuilder private var anchor: some View {
        if dotless {
            Color.clear.allowsHitTesting(false)
        } else {
            Button(action: toggle) {
                dot.frame(width: 24, height: 24).contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .keyTip("Look")
            .accessibilityLabel("Look of \(named)")
        }
    }

    private var dot: some View {
        LookDot(swatch: paint.picked, custom: paint.own, colors: paint.colors)
    }

    private func toggle() {
        if !open { opened = paint }
        open.toggle()
    }
}

extension LookPicker where Footer == EmptyView {
    init(paint: Binding<SpacePaint>, named: String, forAll: (() -> Void)? = nil, onPick: @escaping () -> Void = {},
         asked: Binding<Bool>? = nil, dotless: Bool = false, offersBrowserTabs: Bool = true) {
        self.init(paint: paint, named: named, forAll: forAll, onPick: onPick, footer: { EmptyView() }, asked: asked, dotless: dotless, offersBrowserTabs: offersBrowserTabs)
    }
}
