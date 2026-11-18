import AppKit
import SwiftUI

/// A space's look, edited in a card over the window it paints: no picture
/// of a window to judge it by, the window itself changes under the card.
/// It comes up from the space's name at the column's foot (Edit Look… in a
/// space's menu, ⌘T's Edit Look) and goes back there with ✕ or Esc.
///
/// Inside, top to bottom, with no head, as Arc's has none: the color editor
/// every look uses (ColorEditor: its field with Auto, Light and Dark at the
/// top, its presets, transparency and grain), two switches that change how
/// the color behaves, and the drawings over it. Everything is worn at once
/// and kept for the space; ⋯ in the field's corner holds Reset, once
/// something changed, which puts back what the card opened on.
@MainActor
final class LookCard: ObservableObject {
    static let shared = LookCard()

    @Published private(set) var open = false
    /// The look the card opened on, for Reset.
    private(set) var opened: SpacePaint?
    private weak var browser: Browser?
    private var keys: Any?
    private var saving: DispatchWorkItem?

    /// Up over the window, on the space on screen, Mail's too: its look is
    /// its own, kept apart from the list (MailSpaceLook).
    func show(_ browser: Browser) {
        guard browser.inMail || browser.spaces.contains(where: { $0.id == browser.spaceID }) else { return }
        self.browser = browser
        let prefs = browser.prefs
        // The editor starts from the color on screen, as your own; No
        // Color stays itself until a color is picked.
        if prefs.swatch != .custom, prefs.swatch != .plain {
            prefs.backdropColor = prefs.swatch.start(custom: prefs.backdropColor)
            prefs.swatch = .custom
        }
        opened = SpacePaint(prefs)
        open = true
        listen()
    }

    func close() {
        guard open else { return }
        open = false
        saveNow()
        if let keys { NSEvent.removeMonitor(keys) }
        keys = nil
    }

    /// Esc closes it, wherever the keyboard is in the window.
    private func listen() {
        guard keys == nil else { return }
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.open, event.keyCode == 53, event.window === Links.window else { return event }
                self.close()
                return nil
            }
        }
    }

    /// Back to the look the card opened on.
    func reset() {
        guard let browser, let opened else { return }
        opened.wear(browser.prefs)
        saveSoon()
    }

    /// This look for every space.
    func useForAll() {
        guard let browser else { return }
        let paint = SpacePaint(browser.prefs)
        browser.spaces.forEach { browser.setSpacePaint($0.id, to: paint) }
        // Mail too, once it wears a look of its own; else it follows already.
        if Space.mail.paint != nil || browser.inMail { browser.setSpacePaint(Space.mailID, to: paint) }
    }

    /// Kept for the space a moment after the last change: a drag across the
    /// field writes the space's file once, not at every point.
    func saveSoon() {
        saving?.cancel()
        let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.saveNow() } }
        saving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func saveNow() {
        saving?.cancel()
        saving = nil
        guard let browser else { return }
        browser.setSpacePaint(browser.spaceID, to: SpacePaint(browser.prefs))
    }

    /// The row of tabs changed size: a step for each tab opened, while the
    /// space's look turns and has two colors or more to turn.
    func counted(_ browser: Browser) {
        let count = browser.spacesShown ? browser.sidebarTabs(browser.tabs).count : browser.tabs.count
        let now = (space: browser.spaceID, count: count)
        defer { browser.lookSeen = now }
        guard let seen = browser.lookSeen, seen.space == now.space, now.count > seen.count, Self.turns(browser.prefs) else { return }
        browser.lookStep += now.count - seen.count
    }

    /// One step, as a new tab would give (the bench's `look step`).
    func turn(_ browser: Browser) { browser.lookStep += 1 }

    static func turns(_ prefs: Preferences) -> Bool {
        prefs.backdrop != .site && prefs.lookShift && !prefs.backdropColors.isEmpty
    }

    /// The colors after the main one, as the window wears them: a page with
    /// a color of its own, with Take the site's color on, tints the last of
    /// them halfway, or makes a second one from the main color.
    nonisolated static func colors(_ paint: SpacePaint, dark: Bool, site: NSColor?) -> [NSColor] {
        var colors = paint.colors.compactMap(NSColor.init(hex:)).map { dark ? $0.deepened : $0 }
        guard paint.site, let site = site?.usingColorSpace(.sRGB) else { return colors }
        if let last = colors.last?.usingColorSpace(.sRGB) {
            colors[colors.count - 1] = last.blended(withFraction: 0.55, of: site) ?? last
        } else if let main = paint.color(dark: dark).usingColorSpace(.sRGB) {
            colors = [main.blended(withFraction: 0.5, of: site) ?? main]
        }
        return colors
    }

    /// What the bench reads back: the card, the look and the window's layer.
    func report(_ browser: Browser) -> [String: Any] {
        let paint = SpacePaint(browser.prefs)
        let coating = browser.spaceWash.backdrop?.coating
        let drawings = browser.spaceWash.backdrop?.drawings
        return [
            "open": open, "step": browser.lookStep, "changed": opened.map { $0 != paint } ?? false,
            "mode": paint.mode, "shift": paint.shift, "site": paint.site, "glass": paint.glass, "swatch": paint.swatch,
            "windowDark": Links.window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            // This browser's own window, which `browserWindow` names.
            "ownDark": BrowserWindows.shared.window(for: browser)?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
            "wornNow": paint.color(dark: Links.window?.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua).hex,
            "drawings": paint.drawings, "strength": paint.drawingsStrength,
            "color": paint.color, "colors": paint.colors, "grain": paint.grain, "transparency": paint.transparency,
            "backdrop": browser.prefs.backdrop.rawValue,
            "saved": browser.space.paint.map { $0 == paint } ?? false,
            "dresser": browser.dresser?.title ?? "", "siteTone": browser.dresser?.tone?.hex ?? "",
            "worn": Self.colors(paint, dark: false, site: browser.dresser?.tone).map(\.hex),
            "layer": [
                "drawn": drawings.map { !$0.pattern.isHidden && !$0.isHidden } ?? false,
                "drawingsOpacity": Double(drawings?.pattern.opacity ?? 0),
                "step": coating?.step ?? 0,
                "start": coating.map { [Double($0.gradient.startPoint.x), Double($0.gradient.startPoint.y)] } ?? [],
                "stops": coating?.gradient.colors?.count ?? 0,
                "gradient": coating.map { !$0.gradient.isHidden } ?? false,
                "colors": (coating?.gradient.colors as? [CGColor] ?? []).compactMap { NSColor(cgColor: $0)?.hex },
            ] as [String: Any],
        ]
    }

    /// The bench's hand on it, a test run's: open or close it, set what its
    /// controls set, turn a step, read it back.
    func bench(_ request: [String: Any], _ browser: Browser) -> [String: Any] {
        if let on = request["open"] as? Bool { on ? show(browser) : close() }
        let prefs = browser.prefs
        if let mode = request["mode"] as? String { prefs.lookMode = LookMode(rawValue: mode)?.rawValue ?? "" }
        if let at = request["preset"] as? [Int], at.count == 2, LookPresets.pages.indices.contains(at[0]),
           LookPresets.pages[at[0]].presets.indices.contains(at[1]) {
            let preset = LookPresets.pages[at[0]].presets[at[1]]
            if let main = NSColor(hex: preset.main) { prefs.backdropColor = main; prefs.swatch = .custom }
            prefs.backdropColors = preset.links
            }
        if let on = request["shift"] as? Bool { prefs.lookShift = on }
        if let on = request["glass"] as? Bool { prefs.lookGlass = on }
        if let on = request["site"] as? Bool { prefs.lookSite = on }
        if let set = request["drawings"] as? String { prefs.lookDrawings = LookDrawings.Set(rawValue: set)?.rawValue ?? "" }
        if let amount = request["strength"] as? Double { prefs.lookDrawingsStrength = min(1, max(0, amount)) }
        if let colors = request["colors"] as? [String] { prefs.backdropColors = colors.filter { NSColor(hex: $0) != nil } }
        if let hex = request["color"] as? String, let color = NSColor(hex: hex) { prefs.backdropColor = color; prefs.swatch = .custom }
        if let swatch = (request["swatch"] as? String).flatMap(Swatch.init) { pick(swatch, prefs: prefs) }
        // No Color, as its dot on the Grays page picks it.
        if request["plain"] as? Bool == true { LookFields.prefs(prefs).plain?.wrappedValue = true }
        if request["step"] as? Bool == true { turn(browser) }
        if request["reset"] as? Bool == true { reset() }
        if request["all"] as? Bool == true { useForAll() }
        if request["save"] as? Bool == true { saveNow() }
        return report(browser)
    }

    /// A swatch picked: its color as your own, one color, the rest kept.
    func pick(_ swatch: Swatch, prefs: Preferences) {
        prefs.backdropColor = swatch.start(custom: prefs.backdropColor)
        prefs.swatch = .custom
        prefs.backdropColors = []
    }
}

/// The window's backdrop, or edge to edge the column's ground, as the look
/// card's switches have it: the site's color, while Take the site's color
/// is on and the page has one, and how far the colors have turned.
struct LookWorn<Content: View>: View {
    @ObservedObject var browser: Browser
    @ViewBuilder let content: (NSColor?, Int) -> Content

    var body: some View {
        // One shape, the site's color or none: the backdrop in it was made
        // anew whenever a tab came or went in front.
        let taken = browser.prefs.backdrop != .site && browser.prefs.lookSite
        content(taken ? browser.worn.color.map { Tone($0) }.flatMap { $0.blank ? nil : $0.page } : nil, browser.lookStep)
    }
}

/// Where the card stands: over the page, beside the column, up from the
/// space's name at its foot.
struct LookCardLayer: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var card = LookCard.shared

    private static let top: CGFloat = 44
    private static let width: CGFloat = 290
    /// Between the column and the card.
    private static let gap: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color.clear.allowsHitTesting(false)
                if card.open {
                    LookCardView(browser: browser, prefs: browser.prefs)
                        .frame(width: Self.width)
                        .frame(maxHeight: max(200, geo.size.height - Self.top - 12), alignment: .top)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: x(in: geo.size.width), y: Self.top)
                        .transition(.scale(scale: 0.2, anchor: right ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                }
            }
            .animation(card.open ? Motion.arrive : Motion.depart, value: card.open)
        }
        // Tabs opened turn the colors (Shift with tabs).
        .onChange(of: browser.tabs.count, initial: true) { _, _ in card.counted(browser) }
        .onChange(of: browser.spaceID) { _, _ in card.counted(browser) }
        .background(LookModeScheme(prefs: browser.prefs, privateWindow: browser.windowPurpose == .privateOnly))
    }

    /// Whether the column is in the window: the card grows from the space's
    /// name at its foot.
    private var column: Bool {
        let prefs = browser.prefs
        return prefs.sidebar && !prefs.sideShut
    }

    /// The column hangs on the right.
    private var right: Bool { browser.prefs.sidebar && browser.prefs.sideFlank == .right }

    /// Beside the column, on its side, wherever it stands: docked, or put
    /// away and brought out over the page, where it is a card inset from
    /// the window's edge. The card does not stand over it, and does not
    /// move when the pointer leaves it or brings it out; in from the
    /// window's left edge with the tabs across the top.
    private func x(in width: CGFloat) -> CGFloat {
        let prefs = browser.prefs
        let beside = prefs.sidebar ? browser.presentedSidebarWidth + (column ? 0 : Metrics.floatInset) : 0
        return right ? width - beside - Self.gap - Self.width : beside + Self.gap
    }
}

/// The card itself.
struct LookCardView: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var card = LookCard.shared

    /// The card's width less its frame's inset each side (CardFrame): the
    /// width of a look's controls wherever they are.
    static let inner: CGFloat = 290 - CardFrame.inset * 2

    var body: some View {
        ThreadScrollView(.vertical) {
            LookControls(look: .prefs(prefs),
                         corner: AnyView(LookCorner(changed: card.opened.map { $0 != SpacePaint(prefs) } ?? false,
                                                    reset: { card.reset() }, forAll: { card.useForAll() },
                                                    settings: {
                                                        card.close()
                                                        SettingsWindow.shared.show(.appearance, for: browser)
                                                    },
                                                    close: { card.close() }))) { picked() }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.never)
        .cardFrame()
        .onChange(of: SpacePaint(prefs)) { _, _ in card.saveSoon() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Look")
    }

    /// A color moved by hand: it is your own now. Edge to edge stays edge
    /// to edge, the sidebar wearing it (Column.card).
    private func picked() {
        // Grain or transparency moved on No Color: still no color.
        if prefs.swatch == .plain, prefs.backdropColor.hex == Swatch.plainSeed, prefs.backdropColors.isEmpty { return }
        if prefs.swatch != .custom { prefs.swatch = .custom }
    }
}

/// What a look's head held, in the field's top corner now that a look has
/// no head, as Arc's has none: ⋯ with Reset (once something changed), Use
/// for All Spaces and More in Settings…, and ✕ where the look is a card of
/// its own; a popover goes with a click away.
struct LookCorner: View {
    let changed: Bool
    let reset: () -> Void
    var forAll: (() -> Void)?
    var settings: (() -> Void)?
    var close: (() -> Void)?
    /// What a card of its own adds to the menu (the Boost editor's Text Case).
    var more: AnyView?

    var body: some View {
        HStack(spacing: 2) {
            if changed || forAll != nil || settings != nil || more != nil {
                Menu {
                    if changed { Button("Reset", mark: "arrow.counterclockwise", action: reset) }
                    if let more { more }
                    if let forAll { Button("Use for All Spaces", mark: "square.2.layers.3d", action: forAll) }
                    if let settings { Button("More in Settings\u{2026}", mark: "gearshape", action: settings) }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: ButtonSize.small.height, height: ButtonSize.small.height)
                .accessibilityLabel("More")
            }
            if let close {
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.yab(.quiet, .small, icon: .square))
                    .focusable(false)
                    .keyTip("Close", keys: "esc")
                    .accessibilityLabel("Close")
            }
        }
        .lookPlate()
    }
}

/// A space's own light or dark, Arc's three at the top of its field: as
/// Appearance's Theme says, always light, always dark. Worn on the window
/// the space is in, so its page, column and cards follow it while the
/// app's panels keep the Theme.
enum LookMode: String, CaseIterable {
    case auto = "", light, dark

    var appearance: NSAppearance? {
        switch self {
        case .auto: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .auto: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var symbol: String {
        switch self {
        case .auto: return "sparkles"
        case .light: return "sun.max.fill"
        case .dark: return "moon.stars.fill"
        }
    }

    var title: String {
        switch self {
        case .auto: return "As Appearance"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

/// Wears the space's own light or dark on the window it is in, the way
/// SwiftUI owns its windows' appearance: a color scheme preference. Set on
/// the window by hand, it was put back at SwiftUI's next update while views
/// that had taken the dark kept it. Always a scheme, never none: going from
/// dark back to none, SwiftUI left the window dark at its next change. Auto
/// is the app's own, as Settings' Theme makes it, the Mac's when System.
struct LookModeScheme: View {
    @ObservedObject var prefs: Preferences
    /// A private window is dark, whatever its space or the Mac wear.
    var privateWindow = false
    @State private var appDark = LookModeScheme.dark(NSApp.effectiveAppearance)

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .preferredColorScheme(scheme)
            .onReceive(NSApp.publisher(for: \.effectiveAppearance)) { appDark = Self.dark($0) }
    }

    private var scheme: ColorScheme {
        if privateWindow { return .dark }
        switch LookMode(rawValue: prefs.lookMode) ?? .auto {
        case .light: return .light
        case .dark: return .dark
        case .auto: return appDark ? .dark : .light
        }
    }

    private static func dark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// Auto, Light and Dark over the top of the field, the one worn lit.
struct LookModes: View {
    @Binding var mode: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LookMode.allCases, id: \.self) { item in
                let on = (LookMode(rawValue: mode) ?? .auto) == item
                Button { mode = item.rawValue } label: { Image(systemName: item.symbol) }
                    .buttonStyle(.yab(on ? .secondary : .quiet, .small, icon: .square))
                    .keyTip(item.title)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .lookPlate()
    }
}

extension View {
    /// What the buttons over the color field stand on, Auto, Light and
    /// Dark, and ⋯ and ✕: a blurred plate for each group, so they read over
    /// any color and any dot under them. Its corner is the buttons' and the
    /// 2 it stands out by (Radius.surface), 4 in from the field's edge.
    func lookPlate() -> some View {
        padding(2)
            .background(RoundedRectangle(cornerRadius: Radius.surface, style: .continuous).fill(.thinMaterial))
            .padding(2)
    }
}

/// What a look's controls change: Preferences for the space on screen, a
/// space's own look in Settings, the welcome's held one.
struct LookFields {
    var color: Binding<NSColor>
    var transparency: Binding<Double>
    var grain: Binding<Double>
    var colors: Binding<[String]>
    var shift: Binding<Bool>
    var site: Binding<Bool>
    var drawings: Binding<String>
    var strength: Binding<Double>
    /// The space's own light or dark; none where there is no space yet.
    var mode: Binding<String>? = nil
    /// The wave's step past its end, the window as Liquid Glass; none on a
    /// Mac without it, or where a look has no window to wear it.
    var glass: Binding<Bool>? = nil
    /// No Color (Swatch.plain), the Grays page's first dot; none where a
    /// look has no window to follow light and dark.
    var plain: Binding<Bool>? = nil

    /// The space on screen's, worn as it changes.
    @MainActor static func prefs(_ prefs: Preferences) -> LookFields {
        LookFields(color: Binding(get: { prefs.backdropColor }, set: { prefs.backdropColor = $0 }),
                   transparency: Binding(get: { prefs.backdropTransparency }, set: { prefs.backdropTransparency = $0 }),
                   grain: Binding(get: { prefs.grain }, set: { prefs.grain = $0 }),
                   colors: Binding(get: { prefs.backdropColors }, set: { prefs.backdropColors = $0 }),
                   shift: Binding(get: { prefs.lookShift }, set: { prefs.lookShift = $0 }),
                   site: Binding(get: { prefs.lookSite }, set: { prefs.lookSite = $0 }),
                   drawings: Binding(get: { prefs.lookDrawings }, set: { prefs.lookDrawings = $0 }),
                   strength: Binding(get: { prefs.lookDrawingsStrength }, set: { prefs.lookDrawingsStrength = $0 }),
                   mode: Binding(get: { prefs.lookMode }, set: { prefs.lookMode = $0 }),
                   glass: WindowGlassPolicy.supported ? Binding(get: { prefs.lookGlass }, set: { prefs.lookGlass = $0 }) : nil,
                   plain: Binding(get: { prefs.swatch == .plain }, set: { on in
                       guard on else { return }
                       var next = SpacePaint(prefs)
                       next.wearPlain()
                       next.wear(prefs)
                   }))
    }

    /// A look held whole and written back whole. The editor starts from a
    /// preset's own color, and a color moved is your own.
    static func paint(_ paint: Binding<SpacePaint>) -> LookFields {
        LookFields(color: Binding(get: { paint.wrappedValue.picked.start(custom: paint.wrappedValue.own) },
                                  set: { color in
                                      var next = paint.wrappedValue
                                      next.color = color.hex
                                      next.swatch = Swatch.custom.rawValue
                                      paint.wrappedValue = next
                                  }),
                   transparency: paint.transparency, grain: paint.grain, colors: paint.colors,
                   shift: paint.shift, site: paint.site, drawings: paint.drawings, strength: paint.drawingsStrength,
                   mode: paint.mode, glass: WindowGlassPolicy.supported ? paint.glass : nil,
                   plain: Binding(get: { paint.wrappedValue.picked == .plain }, set: { on in
                       guard on else { return }
                       paint.wrappedValue.wearPlain()
                   }))
    }
}

/// A look's controls, the same wherever a look is set (the card over the
/// window, a look's popover in Settings, the welcome's color), with no
/// heading over the color, as Arc's: the color editor, Shift with tabs once there are two colors or more, Take the
/// site's color where a page can give one, and the drawings with their
/// strength.
struct LookControls: View {
    let look: LookFields
    var width: CGFloat = LookCardView.inner
    /// Nothing over it: its first section has no line above.
    var bare = false
    /// The welcome's window has no site to take a color from.
    var offersSite = true
    /// What a head held, in the field's top corner (LookCorner).
    var corner: AnyView? = nil
    /// A color moved by hand.
    var picked: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    ColorEditor(color: look.color, transparency: look.transparency, grain: look.grain,
                                colors: look.colors, mode: look.mode, corner: corner, glass: look.glass, plain: look.plain,
                                width: width, onPick: picked)
                    if !look.colors.wrappedValue.isEmpty || offersSite {
                        VStack(spacing: 0) {
                            if !look.colors.wrappedValue.isEmpty {
                                LookSwitchRow(title: "Shift with tabs", detail: "Each new tab moves your colors a step.", isOn: look.shift)
                                if offersSite { Divider() }
                            }
                            if offersSite {
                                LookSwitchRow(title: "Take the site\u{2019}s color", detail: "Pages that have one tint a color of yours.", isOn: look.site)
                            }
                        }
                    }
                }
            }
            let drawings = look.drawings.wrappedValue
            let strength = look.strength.wrappedValue
            section("Drawings", value: drawings.isEmpty ? nil : "\(Int((strength * 100).rounded()))%") {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        drawingTile(nil)
                        ForEach(LookDrawings.Set.allCases, id: \.self) { drawingTile($0) }
                    }
                    if !drawings.isEmpty {
                        LookSlider(track: .drawings, value: CGFloat(strength), step: 0.1, reset: CGFloat(LookDrawings.standard),
                                   says: { "Drawings \(Int(($0 * 100).rounded()))%" }) { look.strength.wrappedValue = Double($0) }
                    }
                }
            }
        }
        .frame(width: width, alignment: .leading)
    }

    private func section<Body: View>(_ title: String, value: String? = nil, first: Bool = false, @ViewBuilder body: () -> Body) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !first { Divider().padding(.top, 12) }
            HStack {
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                if let value { Text(value).font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary) }
            }
            body()
        }
    }

    private func drawingTile(_ set: LookDrawings.Set?) -> some View {
        let on = (set?.rawValue ?? "") == look.drawings.wrappedValue
        let ground = Swatch.custom.color(dark: scheme == .dark, custom: look.color.wrappedValue)
        return Button { look.drawings.wrappedValue = set?.rawValue ?? "" } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(Color(nsColor: ground))
                    .overlay {
                        if let set {
                            Image(nsImage: LookDrawings.tile(set, white: LookDrawings.light(on: ground)))
                                .resizable(resizingMode: .tile)
                                .opacity(LookDrawings.opacity(max(0.6, look.strength.wrappedValue), dark: LookDrawings.light(on: ground)))
                                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                        }
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(on ? Palette.ink : Palette.ink.opacity(0.12), lineWidth: on ? 2 : 0.5)
                    }
                    .frame(height: 44)
                Text(set?.title ?? "None")
                    .font(.system(size: 11))
                    .foregroundStyle(on ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel(set.map { "\($0.title) drawings" } ?? "No drawings")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Drawings over a fill, as the window lays them over its color: the set's
/// tile repeated, in the ink its ground takes, as strong as asked. New
/// Space's strip wears them over its color.
struct LookDrawingsFill: View {
    let drawings: String
    let strength: Double
    let ground: NSColor

    var body: some View {
        if let set = LookDrawings.Set(rawValue: drawings) {
            let white = LookDrawings.light(on: ground)
            Image(nsImage: LookDrawings.tile(set, white: white))
                .resizable(resizingMode: .tile)
                .opacity(LookDrawings.opacity(strength, dark: white))
                .allowsHitTesting(false)
        }
    }
}

/// A switch with its name and a line under it, the switch level with the name.
struct LookSwitchRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
        }
        .padding(.vertical, 8)
    }
}
