import AppKit
import SwiftUI

// A space's look, as Arc's space editor: linked colors on a dotted field
// with Auto, Light and Dark at its top, nine presets a page under it, then
// the transparency wave and grain track. The single-color onboarding keeps
// its original hue-across, chroma-down field.

/// The editor, whole, as Arc's: the field, and under it the wave and the
/// grain, `width` wide.
struct ColorEditor: View {
    @Binding var color: NSColor
    @Binding var transparency: Double
    @Binding var grain: Double
    @Binding var colors: [String]
    private let multiple: Bool
    /// The space's own light or dark, over the top of the field (LookModes).
    private let mode: Binding<String>?
    /// What a head held, in the field's top corner (LookCorner).
    private let corner: AnyView?
    /// The wave's step past its end, glass (LookSlider); nil where a look
    /// can't wear it.
    private let glass: Binding<Bool>?
    /// No Color, the Grays page's first dot; nil where a look can't wear it.
    private let plain: Binding<Bool>?
    var showsSurfaceSliders = true
    var width: CGFloat = 260
    var onPick: () -> Void = {}

    @State private var hue: CGFloat
    /// 0 at the field's foot, a gray, to 1 at its top: a share of what this
    /// hue can hold at this lightness.
    @State private var reach: CGFloat
    @State private var lightness: CGFloat
    /// The transparency the editor opened on, where a double click puts it,
    /// and whether on glass.
    @State private var opened: Double
    @State private var openedGlass: Bool
    /// Where the dot was put, while the editor is open. The field is a lossy
    /// picture of a color, both side edges are the same red and a gray has no
    /// hue, so a dot put back from its color would jump; one put stays put.
    @State private var placed: CGPoint?
    @State private var harmony: LookHarmony
    /// Who each linked color is, kept through adding and removing so a dot
    /// grows in and out as itself rather than the next one taking its place.
    @State private var ids: [UUID]
    /// The linked color last touched: lit on the field, and the one − takes
    /// away. Nil for the main color or none, and − takes the last.
    @State private var chosen: Int?
    /// The preset the row under the field shows first (LookPresetRow).
    @State private var first: Int
    /// A color added, and where it comes out of: the linked one it splits
    /// from, or the main one when it is the first.
    @State private var born: (id: UUID, from: CGPoint)?
    @Environment(\.colorScheme) private var scheme

    /// Black to white: the presets have both.
    static let light: ClosedRange<CGFloat> = 0...1

    init(color: Binding<NSColor>, transparency: Binding<Double>, grain: Binding<Double>, colors: Binding<[String]>? = nil,
         mode: Binding<String>? = nil, corner: AnyView? = nil, glass: Binding<Bool>? = nil, plain: Binding<Bool>? = nil,
         width: CGFloat = 260, showsSurfaceSliders: Bool = true, onPick: @escaping () -> Void = {}) {
        _transparency = transparency
        _color = color
        _grain = grain
        _colors = colors ?? .constant([])
        multiple = colors != nil
        self.mode = mode
        self.corner = corner
        self.glass = glass
        self.plain = plain
        _openedGlass = State(initialValue: glass?.wrappedValue ?? false)
        _first = State(initialValue: LookPresets.index(of: color.wrappedValue, colors: colors?.wrappedValue ?? []))
        self.showsSurfaceSliders = showsSurfaceSliders
        self.width = width
        self.onPick = onPick
        let (l, c, h) = Self.read(color.wrappedValue)
        _lightness = State(initialValue: l)
        _opened = State(initialValue: transparency.wrappedValue)
        _hue = State(initialValue: h)
        _reach = State(initialValue: c)
        let harmony = LookHarmony(primary: LookColor(color.wrappedValue), colors: colors?.wrappedValue ?? [])
        _harmony = State(initialValue: harmony)
        _ids = State(initialValue: harmony.links.map { _ in UUID() })
    }

    /// A color as the editor holds it: lightness, reach, hue in 0..<2π.
    private static func read(_ color: NSColor) -> (CGFloat, CGFloat, CGFloat) {
        let (l, c, h) = color.oklch
        let lit = min(light.upperBound, max(light.lowerBound, l))
        let turn = h < 0 ? h + 2 * .pi : h
        return (lit, min(1, c / max(0.001, Gamut.chroma(lit, turn))), turn)
    }

    private var lch: (CGFloat, CGFloat, CGFloat) { (lightness, Gamut.chroma(lightness, hue) * reach, hue) }
    private var primary: LookColor { LookColor(lightness: lightness, reach: reach, hue: hue) }
    private var following: [LookColor] { harmony.colors(from: primary) }

    /// A color as the window wears it in this look: deepened when dark.
    private func worn(_ lch: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        guard scheme == .dark else { return NSColor(oklch: lch) }
        let (l, c) = NSColor.deep(lch.0, lch.1)
        return NSColor(oklch: (l, c, lch.2))
    }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                field
                    // Square-ish, as Arc's, where Auto, Light and Dark take its top.
                    .frame(height: (width * (multiple ? 0.75 : 0.62)).rounded())
                    .overlay(alignment: .top) { if let mode { LookModes(mode: mode) } }
                    .overlay(alignment: .topTrailing) { if let corner { corner } }
                if multiple {
                    LookPresetRow(width: width, first: $first, plain: plain == nil ? nil : pickPlain) { pickPreset($0) }
                }
            }
            if showsSurfaceSliders { VStack(spacing: 4) { wave; dots } }
        }
        .frame(width: width)
        // Changed from elsewhere, another space coming on screen: the editor
        // follows. Its own picks come back as the color it shows, let be.
        .onChange(of: color.hex) { _, _ in
            guard color.hex != NSColor(oklch: lch).hex else { return }
            (lightness, reach, hue) = Self.read(color)
            placed = nil
            harmony = LookHarmony(primary: primary, colors: colors)
            fitIDs()
        }
        .onChange(of: colors) { _, colors in
            guard colors != following.map({ $0.color.hex }) else { return }
            harmony = LookHarmony(primary: primary, colors: colors)
            fitIDs()
        }
    }

    private var field: some View {
        ColorField(point: placed ?? (multiple ? primary.point : CGPoint(x: hue / (2 * .pi), y: 1 - reach)),
                   fill: Color(nsColor: NSColor(oklch: lch)), lightness: lightness,
                   following: zip(following, ids).map { ColorHandle(id: $1, point: $0.point, fill: Color(nsColor: NSColor(oklch: $0.lch))) },
                   born: born, choose: { chosen = $0 },
                   angular: multiple, canAdd: colors.count < 2, canRemove: !colors.isEmpty,
                   add: multiple ? { addColor() } : nil, remove: multiple ? { removeColor() } : nil,
                   moveFollowing: { index, point in
                       harmony.move(index, to: point, from: primary)
                       pick()
                   }) { point in
            placed = point
            if multiple {
                var next = primary
                next.move(to: point)
                hue = next.hue
                reach = next.reach
                placed = next.point
            } else {
                hue = point.x * 2 * .pi
                reach = 1 - point.y
            }
            pick()
        }
    }

    /// Ticks at each fifth, as Arc's; a double click goes back to the
    /// transparency the editor opened on.
    private var wave: some View {
        LookSlider(track: .wave, value: CGFloat(transparency), step: 0.2, reset: CGFloat(opened),
                   glass: glass, resetGlass: openedGlass, tint: Color(nsColor: worn(lch)),
                   says: { "Transparency \(Int(($0 * 100).rounded()))%" }) { t in
            transparency = BackdropTransparency.clamp(Double(t))
        }
    }

    /// In twentieths, ticking at each, as Arc's dial; a double click goes
    /// back to the standard grain.
    private var dots: some View {
        LookSlider(track: .grain, value: CGFloat(grain), step: 0.1, reset: CGFloat(Grain.standard), stops: 20,
                   says: { $0 == 0 ? "No grain" : "Grain \(Int(($0 * 100).rounded()))%" }) { amount in
            grain = Double(amount)
            onPick()
        }
    }

    private func pick() {
        color = NSColor(oklch: lch)
        if multiple { colors = following.map { $0.color.hex } }
        onPick()
    }

    /// A preset, as Arc's: the main dot springs to it (0.27 s, a little
    /// past and back), and the window takes its colors at once. Linked dots
    /// it has that weren't there are put in place at once, ones that were
    /// glide with the main one, and ones it hasn't go at once.
    private func pickPreset(_ preset: LookPresets.Preset) {
        guard let main = NSColor(hex: preset.main) else { return }
        let (l, c, h) = Self.read(main)
        let next = LookHarmony(primary: LookColor(lightness: l, reach: c, hue: h), colors: preset.links)
        born = nil
        if next.links.count != ids.count { ids = next.links.map { _ in UUID() } }
        withAnimation(Self.settle) {
            lightness = l
            reach = c
            hue = h
            harmony = next
            placed = nil
            chosen = nil
        }
        pick()
    }

    /// No Color: the dot springs to white as to its preset, and the window
    /// goes white or black with the Mac's light and dark.
    private func pickPlain() {
        let white = LookPresets.all[LookPresets.plainAt].preset
        pickPreset(white)
        plain?.wrappedValue = true
    }

    /// A color more, as Arc's: it comes out of the linked dot before it (or
    /// the main one, for the first) and the two part to where the colors
    /// sit evenly round the wheel, two opposite, three a third apart.
    private func addColor() {
        guard colors.count < 2 else { return }
        let from = following.last?.point ?? primary.point
        let id = UUID()
        born = (id, from)
        withAnimation(Self.part) {
            harmony = .suggested(extras: colors.count + 1)
            ids.append(id)
            fitIDs()
            chosen = nil
        }
        pick()
    }

    /// A color fewer, as Arc's: the one last touched goes at once, or the
    /// last, and only it. Ones left on an even set glide to where the
    /// colors now sit evenly; ones placed by hand or brought from Arc stay
    /// what they are (request #464: − took all but one).
    private func removeColor() {
        guard !harmony.links.isEmpty else { return }
        born = nil
        let index = chosen.flatMap { harmony.links.indices.contains($0) ? $0 : nil } ?? harmony.links.count - 1
        let fewer = harmony.removing(index)
        let after = harmony.closingUp(after: fewer)
        harmony = fewer
        ids.remove(at: index)
        chosen = nil
        pick()
        guard after.links != fewer.links else { return }
        // The next turn, so the one taken is gone before the rest move.
        DispatchQueue.main.async {
            withAnimation(Self.part) { harmony = after }
            pick()
        }
    }

    /// One id a linked color, whatever changed the colors.
    private func fitIDs() {
        if ids.count > harmony.links.count { ids.removeLast(ids.count - harmony.links.count) }
        while ids.count < harmony.links.count { ids.append(UUID()) }
        if let chosen, chosen >= ids.count { self.chosen = nil }
    }

    /// A preset's dot going to it: Arc's, at its peak 0.18 s in, 7% past,
    /// still by half a second (its film, frames 229 to 260).
    static let settle = Animation.spring(response: 0.27, dampingFraction: 0.65)
    /// Linked dots parting after + or closing up after −: Arc's, there in
    /// about 0.13 s, a point or two past (frames 3672 to 3690, 3566 to 3575).
    static let part = Animation.spring(response: 0.2, dampingFraction: 0.75)
}

struct ColorHandle {
    var id = UUID()
    let point: CGPoint
    let fill: Color
}

/// The field: a rounded ground printed with a fine grid of dots, each the
/// color the dot would give there, and the color's own dot, ringed in
/// white, dragged across it; the grid's dots swell near it, as under a lens.
struct ColorField: View {
    /// Where the dot is, 0...1 each way: hue across, less color down.
    let point: CGPoint
    /// The color's dot, the color picked, as Arc's: a dark look deepens
    /// the window, never the dot, so white stays white on it.
    let fill: Color
    /// The lightness the grid's dots are printed at.
    let lightness: CGFloat
    var following: [ColorHandle] = []
    /// The linked color just added, and where it comes out of.
    var born: (id: UUID, from: CGPoint)? = nil
    /// Which dot a press took: nil for the main one.
    var choose: (Int?) -> Void = { _ in }
    var angular = false
    var canAdd = false
    var canRemove = false
    var add: (() -> Void)? = nil
    var remove: (() -> Void)? = nil
    var moveFollowing: ((Int, CGPoint) -> Void)? = nil
    let move: (CGPoint) -> Void

    /// Spelled out: the private state below would make the memberwise
    /// one private to this file.
    init(point: CGPoint, fill: Color, lightness: CGFloat, following: [ColorHandle] = [],
         born: (id: UUID, from: CGPoint)? = nil, choose: @escaping (Int?) -> Void = { _ in },
         angular: Bool = false, canAdd: Bool = false, canRemove: Bool = false,
         add: (() -> Void)? = nil, remove: (() -> Void)? = nil,
         moveFollowing: ((Int, CGPoint) -> Void)? = nil, move: @escaping (CGPoint) -> Void) {
        self.point = point; self.fill = fill; self.lightness = lightness; self.following = following
        self.born = born; self.choose = choose; self.angular = angular; self.canAdd = canAdd
        self.canRemove = canRemove; self.add = add; self.remove = remove
        self.moveFollowing = moveFollowing; self.move = move
    }

    @State private var grab: LookGrab?
    @State private var overHandle = false
    @State private var cursor: Cursor = .none
    private enum Cursor { case none, open, closed }
    private static let dot: CGFloat = 36

    var body: some View {
        GeometryReader { geo in
            let height = max(Self.dot, geo.size.height - (add == nil ? 0 : 28))
            let travel = CGSize(width: max(1, geo.size.width - Self.dot), height: max(1, height - Self.dot))
            let center = CGPoint(x: Self.dot / 2 + point.x * travel.width, y: Self.dot / 2 + point.y * travel.height)
            let centers = following.map {
                CGPoint(x: Self.dot / 2 + $0.point.x * travel.width,
                        y: Self.dot / 2 + $0.point.y * travel.height)
            }
            ZStack(alignment: .topLeading) {
                // Printed no paler or deeper than reads: a light gray picked
                // shouldn't wash the palette out. The dot is the true color.
                FieldDots(lightness: min(0.75, max(0.55, lightness)), real: lightness, lens: center, dot: Self.dot, angular: angular).equatable()
                ForEach(Array(following.enumerated()), id: \.element.id) { index, handle in
                    let from = born.flatMap { $0.id == handle.id ? $0.from : nil }
                    Circle()
                        .fill(handle.fill)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .frame(width: 24, height: 24)
                        .shadow(color: .black.opacity(Double(Shadow.thumb.opacity)), radius: Shadow.thumb.radius, y: Shadow.thumb.y) // design: Shadow.thumb is from Design.swift
                        .scaleEffect(grab?.handle == .following(index) ? 1.1 : 1)
                        .animation(.snappy(duration: 0.14), value: grab?.handle == .following(index))
                        .position(centers[index])
                        .allowsHitTesting(false)
                        // Added: out of the dot it splits from, under it.
                        // Put by a preset: there at once. Taken: gone at once.
                        .zIndex(from == nil ? 0 : -1)
                        .transition(.asymmetric(
                            insertion: from.map { from in
                                AnyTransition.modifier(
                                    active: Emerge(offset: CGSize(width: Self.dot / 2 + from.x * travel.width - centers[index].x,
                                                                  height: Self.dot / 2 + from.y * travel.height - centers[index].y),
                                                   scale: 0.75),
                                    identity: Emerge(offset: .zero, scale: 1))
                            } ?? AnyTransition.opacity.animation(nil),
                            removal: AnyTransition.opacity.animation(nil)))
                }
                Circle()
                    .fill(fill)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                    .overlay(Circle().strokeBorder(.black.opacity(0.14), lineWidth: 0.5).padding(-0.5))
                    .frame(width: Self.dot, height: Self.dot)
                    .shadow(color: .black.opacity(Double(Shadow.thumb.opacity)), radius: Shadow.thumb.radius, y: Shadow.thumb.y) // design: Shadow.thumb is from Design.swift
                    .scaleEffect(grab?.handle == .primary ? 1.1 : 1)
                    .animation(.snappy(duration: 0.14), value: grab?.handle == .primary)
                    .position(center)
                    .allowsHitTesting(false)
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let at): overHandle = LookGrab.hit(at, primary: center, following: centers) != nil
                case .ended: overHandle = false
                }
                updateCursor()
            }
            // Keep the handle first pressed, including a small color.
            // Empty space still places the main color there.
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let taken = grab ?? LookGrab(at: drag.startLocation, primary: center, following: centers)
                        if grab == nil {
                            switch taken.handle {
                            case .primary: choose(nil)
                            case .following(let index): choose(index)
                            }
                        }
                        grab = taken
                        updateCursor()
                        let at = taken.point(at: drag.location, travel: travel)
                        switch taken.handle {
                        case .primary: move(at)
                        case .following(let index): moveFollowing?(index, at)
                        }
                    }
                    .onEnded { _ in grab = nil; updateCursor() }
            )
        }
        .overlay(alignment: .bottom) {
            if let add, let remove {
                // Each a whole plate to press, lit under the pointer, as
                // Arc's: a plain button took only the minus's thin stroke.
                HStack(spacing: 4) {
                    Button(action: remove) { Image(systemName: "minus") }
                        .disabled(!canRemove)
                        .keyTip("Remove Color")
                        .accessibilityLabel("Remove color")
                    Button(action: add) { Image(systemName: "plus") }
                        .disabled(!canAdd)
                        .keyTip("Add Color")
                        .accessibilityLabel("Add color")
                }
                .font(.system(size: 12, weight: .medium))
                .buttonStyle(.yab(.quiet, .small, icon: .square))
                .padding(.bottom, 2)
            }
        }
        .background(Palette.ink.opacity(0.05), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .onDisappear {
            if cursor != .none { NSCursor.pop(); cursor = .none }
        }
        .accessibilityElement(children: add == nil ? .ignore : .contain)
        .accessibilityLabel("Color")
        .accessibilityHint(angular ? "Drag the main dot to move linked colors, or a small dot to change that color." : "Drag the dot: hue across, more color up.")
        .accessibilityAdjustableAction { direction in
            if angular {
                var color = LookColor(lightness: lightness, reach: 0, hue: 0)
                color.move(to: point)
                color.hue += direction == .increment ? .pi / 12 : -.pi / 12
                move(color.point)
            } else {
                move(CGPoint(x: (point.x + (direction == .increment ? 0.05 : 0.95)).truncatingRemainder(dividingBy: 1), y: point.y))
            }
        }
    }

    private func updateCursor() {
        let next: Cursor = grab != nil ? .closed : overHandle ? .open : .none
        guard next != cursor else { return }
        if cursor != .none { NSCursor.pop() }
        switch next {
        case .none: break
        case .open: NSCursor.openHand.push()
        case .closed: NSCursor.closedHand.push()
        }
        cursor = next
    }
}

/// The field's print: a dot every 10 points, each in the color the handle
/// would give there, at the light window's shade even in a dark look, where
/// the deepened colors would all read as black; only the window wears the
/// dark shade. Redrawn only as the handle or the lightness moves.
private struct FieldDots: View, Equatable {
    let lightness: CGFloat
    /// The color's own lightness: each dot holds no more color than this
    /// lightness can, so at black or white every dot is gray, as moving
    /// the dot there would give.
    let real: CGFloat
    let lens: CGPoint
    let dot: CGFloat
    var angular = false

    var body: some View {
        Canvas { context, size in
            let pitch: CGFloat = 10
            let travel = CGSize(width: max(1, size.width - dot), height: max(1, size.height - dot))
            var x = pitch / 2
            while x < size.width {
                let across = min(1, max(0, (x - dot / 2) / travel.width))
                let hue = across * 2 * .pi
                let most = angular ? 0 : min(Gamut.chroma(lightness, hue), Gamut.chroma(real, hue))
                var y = pitch / 2
                while y < size.height {
                    let down = min(1, max(0, (y - dot / 2) / travel.height))
                    let rgb: (Double, Double, Double)
                    if angular {
                        var color = LookColor(lightness: lightness, reach: 0, hue: hue)
                        color.move(to: CGPoint(x: across, y: down))
                        rgb = Gamut.srgb(color.lightness, min(Gamut.chroma(lightness, color.hue), Gamut.chroma(real, color.hue)) * color.reach, color.hue)
                    } else {
                        rgb = Gamut.srgb(lightness, most * (1 - down), hue)
                    }
                    let (r, g, b) = rgb
                    let near = hypot(x - lens.x, y - lens.y)
                    let radius = 1.6 + 2.2 * exp(-(near * near) / (2 * 24 * 24))
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                                 with: .color(Color(.sRGB, red: r, green: g, blue: b)))
                    y += pitch
                }
                x += pitch
            }
        }
        .accessibilityHidden(true)
    }
}

/// A linked dot coming out of the one it splits from: moved over to it and
/// a little smaller, then at its own place and size.
private struct Emerge: ViewModifier {
    let offset: CGSize
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(scale).offset(offset)
    }
}

/// The presets under the field, as Arc's: ‹ nine dots ›, a page at a time,
/// sliding across on a spring with no give (Arc's: 58% at 0.1 s, 90% at 0.2,
/// still by 0.38) and fading at the ends, outside the dots at rest; ‹ and › fade where there's no
/// page that way. Too narrow for nine, as New Space's tray is, the pages run
/// on as one row: as many dots as fit, that many a step, and at each end a
/// zone the next dots peek into, fading out, so the row reads as going on.
/// No mark on the one picked, as Arc has none: the field and the window
/// show it.
struct LookPresetRow: View {
    let width: CGFloat
    /// The preset on show first, counted along every page (LookPresets.all).
    @Binding var first: Int
    /// No Color in the Grays page's first place, white's; nil keeps white.
    var plain: (() -> Void)? = nil
    let pick: (LookPresets.Preset) -> Void

    static let dot: CGFloat = 20
    static let gap: CGFloat = 4
    static let slide = Animation.spring(response: 0.32, dampingFraction: 1)

    /// How a row of `track` lays out: a page of nine with 3 points left at
    /// each end, as much as the ends fade, so no dot sits faded; or, with no
    /// room for that, as many as fit with at least 12 at each end to fade in.
    static func layout(track: CGFloat) -> (paged: Bool, shown: Int, fade: CGFloat) {
        let step = dot + gap
        let nine = step * 9 - gap
        if track - nine >= 6 { return (true, 9, (track - nine) / 2) }
        let shown = max(1, Int((track - 12 * 2 + gap) / step))
        return (false, shown, (track - step * CGFloat(shown) + gap) / 2)
    }

    var body: some View {
        // The arrows close in on the dots.
        let track = max(1, width - ButtonSize.small.height * 2)
        let (paged, shown, fade) = Self.layout(track: track)
        let all = LookPresets.all
        let page = all.indices.contains(first) ? all[first].page : 0
        let start = min(max(0, first), max(0, all.count - shown))
        HStack(spacing: 0) {
            chevron(-1, paged: paged, page: page, start: start, shown: shown)
            HStack(spacing: paged ? 0 : Self.gap) {
                ForEach(LookPresets.pages.indices, id: \.self) { index in
                    HStack(spacing: Self.gap) {
                        ForEach(LookPresets.pages[index].presets.indices, id: \.self) { at in
                            let along = LookPresets.starts[index] + at
                            // Only the dots on show take a click: the others
                            // lie under the arrows, faded out.
                            let on = paged ? index == page : (start..<start + shown).contains(along)
                            Group {
                                if let plain, along == LookPresets.plainAt {
                                    Button(action: plain) { PlainDot().frame(width: Self.dot, height: Self.dot).contentShape(Circle()) }
                                        .buttonStyle(PressStyle(scale: 0.92))
                                        .accessibilityLabel(Swatch.plain.title)
                                } else {
                                    dot(all[along].preset, name: all[along].name)
                                }
                            }
                                .allowsHitTesting(on)
                                .accessibilityHidden(!on)
                        }
                    }
                    .frame(width: paged ? track : nil)
                }
            }
            .fixedSize()
            .offset(x: paged ? -CGFloat(page) * track : fade - CGFloat(start) * (Self.dot + Self.gap))
            .frame(width: track, alignment: .leading)
            .mask {
                LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: fade / track),
                                       .init(color: .black, location: 1 - fade / track), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
            chevron(1, paged: paged, page: page, start: start, shown: shown)
        }
        .frame(width: width, height: ButtonSize.regular.height)
    }

    /// A page along, or as many dots as show.
    private func chevron(_ way: Int, paged: Bool, page: Int, start: Int, shown: Int) -> some View {
        let count = LookPresets.all.count
        let room = paged ? LookPresets.pages.indices.contains(page + way) : way < 0 ? start > 0 : start + shown < count
        let to = paged ? (room ? LookPresets.starts[page + way] : start) : min(max(0, start + way * shown), max(0, count - shown))
        return Button {
            withAnimation(Self.slide) { first = to }
        } label: {
            Image(systemName: way < 0 ? "chevron.left" : "chevron.right").font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.yab(.quiet, .small, icon: .square))
        .disabled(!room)
        .zIndex(1)
        .accessibilityLabel(way < 0 ? "Previous colors" : "More colors")
    }

    private func dot(_ preset: LookPresets.Preset, name: String) -> some View {
        let main = Color(nsColor: NSColor(hex: preset.main) ?? .gray)
        let links = preset.links.compactMap(NSColor.init(hex:)).map { Color(nsColor: $0) }
        return Button { pick(preset) } label: {
            Circle()
                .fill(LinearGradient(colors: [main] + links.reversed(), startPoint: .topLeading, endPoint: .bottomTrailing))
                // Its own color, deeper, round its edge, as Arc's.
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
                .frame(width: Self.dot, height: Self.dot)
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(scale: 0.92))
        .accessibilityLabel(name)
    }
}

/// No Color's dot: white and black halves, as the window it gives is one or
/// the other with the Mac's light and dark.
struct PlainDot: View {
    var body: some View {
        Circle()
            .fill(LinearGradient(stops: [.init(color: .white, location: 0.5), .init(color: .black, location: 0.5)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 1.5))
    }
}
