import SwiftUI
import AppKit
// The design system is a module of its own (Sources/YabDesign), seen by
// every file here through this one import.
@_exported import YabDesign

extension Tone {
    /// The same, worn by a card laid over the page in this paint: see
    /// through when the paint is and the Mac lets it be. A card on a glass
    /// look is a frosted card like any other: its frost is the page's.
    func card(_ paint: SpaceWash.Paint?) -> Tone {
        var made = self
        made.glass = false
        made.seeThrough = (paint?.transparency ?? 0) > 0
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        return made
    }
}

extension Tone {
    /// The controls' stable backing, with a few top rows as a last resort.
    static let probe = PageScript.load("site-tone")

    /// A clear majority of nearby colors across several rows. Quantized
    /// buckets split a gentle gradient at arbitrary boundaries; a third of
    /// one row also let a canvas or a logo choose the browser's paint.
    static func settle(_ row: NSBitmapImageRep) -> NSColor? {
        guard let pixels = sRGB(row) else { return nil }
        let (bytes, width, height) = pixels
        let rows = min(3, height), across = 48
        var colors: [NSColor] = []
        for y in 0..<rows {
            let py = min(height - 1, Int((CGFloat(y) + 0.5) / CGFloat(rows) * CGFloat(height)))
            for x in 0..<across {
                let px = min(width - 1, Int((CGFloat(x) + 0.5) / CGFloat(across) * CGFloat(width)))
                let i = (py * width + px) * 4, a = CGFloat(bytes[i + 3]) / 255
                guard a >= 0.98 else { continue }
                colors.append(NSColor(srgbRed: CGFloat(bytes[i]) / 255 / a, green: CGFloat(bytes[i + 1]) / 255 / a,
                                      blue: CGFloat(bytes[i + 2]) / 255 / a, alpha: 1))
            }
        }
        let needed = Int(ceil(Double(rows * across) * 0.7))
        guard colors.count >= needed else { return nil }
        var best: [NSColor] = []
        for seed in colors {
            let group = colors.filter { PageToneGate.near(seed, $0) }
            if group.count > best.count { best = group }
        }
        guard best.count >= needed else { return nil }
        let n = CGFloat(best.count)
        return NSColor(srgbRed: best.reduce(0) { $0 + $1.redComponent } / n,
                       green: best.reduce(0) { $0 + $1.greenComponent } / n,
                       blue: best.reduce(0) { $0 + $1.blueComponent } / n, alpha: 1)
    }

    /// The row's pixels as sRGB RGBA bytes, top row first. Drawn by
    /// ColorSync from the image's own profile: colorAt(x:y:) then
    /// usingColorSpace(.sRGB) read an sRGB 0.257 gray about 0.07 off on
    /// the farm (PageToneTests), so the tone was not the page's color.
    private static func sRGB(_ row: NSBitmapImageRep) -> ([UInt8], Int, Int)? {
        let width = row.pixelsWide, height = row.pixelsHigh
        guard width > 0, height > 0, let image = row.cgImage,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (bytes, width, height) : nil
    }
}

/// The page frame within the window.
enum PageLayout: String, CaseIterable {
    case card, edgeToEdge

    var title: String { self == .card ? "Card" : "Edge to Edge" }

    static func restored(_ value: String?, backdrop: Backdrop) -> Self {
        value.flatMap(Self.init(rawValue:)) ?? (backdrop == .none ? .edgeToEdge : .card)
    }
}

/// The window background source. None is the legacy edge-to-edge setting.
enum Backdrop: String, CaseIterable, Identifiable {
    case none, color, site

    static let windowChoices: [Self] = [.color, .site]
    var windowMode: Self { self == .none ? .color : self }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "Edge to edge"
        case .color: return "A color"
        case .site: return "The site\u{2019}s color"
        }
    }

    /// How far in from the window's edges the page is laid, and how round
    /// its corners are.
    static let inset: CGFloat = 8
    static let corner: CGFloat = Radius.surface
}

/// The colors the window can be painted in. Each is a pair, like the
/// palette, the bright one for a light window, a deep one of the same hue
/// for a dark. The one picked by hand is the bright one as it was picked,
/// and its deep one is worked out the way the others' were chosen.
enum Swatch: String, CaseIterable, Identifiable {
    case gray, paper, coral, peach, sage, sky, lavender, rose, graphite, custom
    /// No color: white in a light window, Arc's black in a dark one, as
    /// Arc's grayscale page and Dia's neutral theme. Picked from the Grays
    /// page's first dot (LookPresetRow); a build without it reads gray.
    case plain

    var id: String { rawValue }

    /// The ones offered as dots, in the order they sit.
    static let presets: [Swatch] = [.gray, .paper, .coral, .peach, .sage, .sky, .lavender, .rose, .graphite]

    var title: String {
        switch self {
        case .custom: return "Your own"
        case .gray: return "Gray"
        case .plain: return "No Color"
        default: return rawValue.capitalized
        }
    }

    /// The color for a window of this brightness; for your own, whatever
    /// was picked.
    /// The color No Color keeps as its own: the field's dot sits at white,
    /// and an iPhone that doesn't know No Color wears white.
    static let plainSeed = "FFFFFF"

    func color(dark: Bool, custom: NSColor) -> NSColor {
        func hex(_ light: UInt32, _ deep: UInt32) -> NSColor {
            let v = dark ? deep : light
            return NSColor(
                srgbRed: CGFloat(v >> 16 & 0xFF) / 255,
                green: CGFloat(v >> 8 & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: 1
            )
        }
        switch self {
        case .gray: return hex(0xE3E3E5, 0x202022)
        case .paper: return hex(0xECEAE4, 0x1F1E1C)
        case .coral: return hex(0xF2837C, 0x55282A)
        case .peach: return hex(0xF5BB8C, 0x553823)
        case .sage: return hex(0xA8C3A0, 0x28372A)
        case .sky: return hex(0x8DB6E6, 0x1D304B)
        case .lavender: return hex(0xB6A6E6, 0x2E274C)
        case .rose: return hex(0xEEA2C4, 0x4C2338)
        case .graphite: return hex(0x3B3B3E, 0x18181A)
        // Arc's neutral theme's dark background is 0F0E0F (its
        // semanticColorPalette), here without the tint.
        case .plain: return hex(0xFFFFFF, 0x0F0F0F)
        case .custom:
            let picked = custom.usingColorSpace(.sRGB) ?? custom
            return dark ? picked.deepened : picked
        }
    }
}

/// A fine grain over the backdrop, so a flat color reads as paper rather
/// than as a fill. Made once, from noise, and tiled. How much of it is a
/// share, 0 for none to 1 for the roughest (LookSlider).
enum Grain {
    /// What "grain on" was before it had an amount, and what it starts at.
    static let standard: Double = 0.35
    /// The tile's opacity for an amount: the standard is the 0.07 it
    /// always was.
    static func opacity(_ amount: Double) -> Double { min(1, max(0, amount)) * 0.2 }
    /// Arc's noise factor as Yab's amount, so a space brought from Arc is
    /// as grainy as it was there. Arc's grain is a third of ours at the
    /// same number: pictured on one screen (evals/arc-themes, request
    /// #401), its noise factor 1 over a mid gray swings pixels by 3.4 of
    /// 255 (high-passed spread), where our tile at amount 1 swings them by
    /// about 10.5; taken one for one, the 0.05 to 0.1 Arc's themes mostly
    /// carry came in two to three times as rough.
    static let perArcNoise: Double = 0.33
    static func fromArc(_ noise: Double) -> Double { min(1, max(0, noise)) * perArcNoise }

    static let tile: NSImage = {
        let side = 128
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
            bitsPerSample: 8, samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: side * 2, bitsPerPixel: 16
        ), let data = rep.bitmapData else { return NSImage() }
        var seed: UInt32 = 0x2545F491
        for i in 0..<(side * side) {
            // xorshift: the same grain every launch, and no cost to speak of.
            seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
            data[i * 2] = seed & 1 == 0 ? 0 : 255
            data[i * 2 + 1] = UInt8(seed >> 8 & 0xFF)
        }
        let image = NSImage(size: NSSize(width: side / 2, height: side / 2))
        // Two pixels a point, so it is the one a 2x screen picks.
        rep.size = image.size
        image.addRepresentation(rep)
        // A grain a pixel a point too, for a 1x screen: there the 2x one was
        // halved by the window server picking one pixel of every two, and
        // each pixel's center falls on the line between two of them, so
        // which it picked flipped from one redraw to the next and the grain
        // jumped wherever the window drew again, under the pointer over the
        // spaces' icons (feedback #121). Every other pixel of the 2x one,
        // so a 1x screen keeps the grain it had.
        let half = side / 2
        if let small = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: half, pixelsHigh: half,
            bitsPerSample: 8, samplesPerPixel: 2, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceWhite, bytesPerRow: half * 2, bitsPerPixel: 16
        ), let into = small.bitmapData {
            for y in 0..<half {
                for x in 0..<half {
                    let from = (y * 2 * side + x * 2) * 2, to = (y * half + x) * 2
                    into[to] = data[from]
                    into[to + 1] = data[from + 1]
                }
            }
            small.size = image.size
            image.addRepresentation(small)
        }
        return image
    }()
}

/// The backdrop, drawn: the color, and the grain over it as much as asked.
struct BackdropFill: View {
    let color: Color
    var grain: Double = 0
    var transparency: Double = 0
    var colors: [Color] = []
    /// A card's over the page: its frost blurs the page (BackdropVeil.Frost).
    var card = false

    var body: some View {
        Group {
            if colors.isEmpty { color }
            else { LinearGradient(colors: [color] + colors, startPoint: .topLeading, endPoint: .bottomTrailing) }
        }.overlay {
            if grain > 0 {
                Image(nsImage: Grain.tile)
                    .resizable(resizingMode: .tile)
                    .opacity(Grain.opacity(grain))
                    .allowsHitTesting(false)
            }
        }
        .opacity(BackdropTransparency.opacity(transparency, reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        .background {
            if transparency > 0 {
                BackdropVeil.Frost(color: NSColor(color), card: card, colors: colors.map { NSColor($0) }, transparency: transparency)
            }
        }
    }
}

/// What a see-through backdrop shows under its color: frost, on the
/// color's side and veiled toward it. The ink on a backdrop is worked out
/// from its color as if it were opaque (Tone), but at full transparency
/// the color is a sixth of what shows. Frost alone swings with the desktop
/// behind it, a dark window's from #131313 over black to #8B8B8B over
/// white, where white ink's quiet shades are gone; so the frost takes the
/// color's light or dark, and a veil of black or white over it holds it
/// on that side, #090909 to #393939 for a dark color, #CCCCCC to #F5F5F5
/// for a light one, wherever the window is.
enum BackdropVeil {
    static let opacity: CGFloat = 0.6

    /// Whether the color is on the dark side, as its ink takes it (Tone).
    static func dark(_ color: NSColor) -> Bool {
        Tone(color).scheme == .dark
    }

    static func appearance(for color: NSColor) -> NSAppearance? {
        NSAppearance(named: dark(color) ? .darkAqua : .aqua)
    }

    static func veil(for color: NSColor) -> NSColor {
        (dark(color) ? NSColor.black : .white).withAlphaComponent(opacity)
    }

    /// A card over the page veils it at least this much: the page under it
    /// is what shows, blurred, rather than the desktop, and at the window's
    /// 0.6 it was a sixteenth of it, the card as good as solid.
    static let cardOpacity: CGFloat = 0.2

    /// What a card's words keep over the worst page for its side, black
    /// under a light color, white under a dark: muted 4.5 to 1, faint 2.6.
    static let cardLeast = (muted: CGFloat(4.5), faint: CGFloat(2.6))

    /// A see-through card over the page veils it as much as its words need
    /// (Shades.deep) over the worst page for its color's side, at every end
    /// of its gradient, and no less than `cardOpacity`. At 0.2 always, a
    /// light color over a dark page came out a mid blue gray, the words
    /// meant for the color sunk in it: 1.4 to 1 at full transparency.
    static func cardVeil(_ color: NSColor, colors: [NSColor] = [], transparency: Double) -> CGFloat {
        let key = ([color] + colors).map(\.hex).joined() + String(Int((transparency * 1000).rounded()))
        if let hit = CardVeils.kept[key] { return hit }
        let isDark = dark(color)
        let words = Shades.deep(on: color, dark: isDark)
        let worst: NSColor = isDark ? .white : .black
        let veil: NSColor = isDark ? .black : .white
        let alpha = CGFloat(BackdropTransparency.opacity(transparency, reduced: NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency))
        var made = cardOpacity
        while made < 1 {
            let under = veil.mixed(over: worst, made)
            let holds = ([color] + colors).allSatisfy { end in
                let ground = end.mixed(over: under, alpha)
                return words.mutedNS.contrast(with: ground) >= cardLeast.muted && words.faintNS.contrast(with: ground) >= cardLeast.faint
            }
            if holds { break }
            made = min(1, made + 0.02)
        }
        if CardVeils.kept.count > 64 { CardVeils.kept.removeAll() }
        CardVeils.kept[key] = made
        return made
    }

    static func cardVeil(for color: NSColor, colors: [NSColor] = [], transparency: Double) -> NSColor {
        (dark(color) ? NSColor.black : .white).withAlphaComponent(cardVeil(color, colors: colors, transparency: transparency))
    }

    /// The same for a SwiftUI surface: its material, veiled. A card over
    /// the page blurs the page, in the window (FieldBand's blur); SwiftUI's
    /// own material blends the desktop behind the window, which in full
    /// screen is nothing.
    struct Frost: View {
        let color: NSColor
        var card = false
        /// A card's gradient and transparency, which its veil is worked
        /// out from (cardVeil).
        var colors: [NSColor] = []
        var transparency: Double = 0

        var body: some View {
            if card {
                CardFrost(color: color, colors: colors, transparency: transparency)
            } else {
                Rectangle().fill(.ultraThinMaterial)
                    .overlay(Color(nsColor: BackdropVeil.veil(for: color)))
                    .environment(\.colorScheme, BackdropVeil.dark(color) ? .dark : .light)
            }
        }
    }
}

/// A card's frost: the page under it blurred in the window (FieldBand's
/// blur) and the veil over that, in a view of its own, so the column's
/// spaces, pictured as they slide, leave it out by its kind and lay the
/// same frost back live under the row (ColumnView.picture, SpacePager).
/// Drawn by SwiftUI, the blur was an AppKit view among SwiftUI's own
/// layers, past which the picture didn't look: it came out veiled over
/// the row's own frost, a fifth darker than the card at rest.
private struct CardFrost: NSViewRepresentable {
    let color: NSColor
    var colors: [NSColor] = []
    var transparency: Double = 0

    func makeNSView(context: Context) -> CardFrostView { CardFrostView(frame: .zero) }

    func updateNSView(_ view: CardFrostView, context: Context) {
        view.wear(color, colors: colors, transparency: transparency)
    }
}

final class CardFrostView: NSView {
    private let blur = ClearBand()
    private let veil = NSView()
    override var isOpaque: Bool { false }

    /// The backdrop group its blur is in (ClearBand.group): the card's and
    /// its row's while its spaces slide (SpacePager.raise).
    var group: String? {
        get { blur.group }
        set { blur.group = newValue }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        blur.material = .headerView
        blur.blendingMode = .withinWindow
        blur.state = .active
        veil.wantsLayer = true
        addSubview(blur)
        addSubview(veil)
    }

    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        blur.frame = bounds
        veil.frame = bounds
    }

    /// On the color's side, and veiled toward it as far as its words need.
    func wear(_ color: NSColor, colors: [NSColor] = [], transparency: Double) {
        appearance = BackdropVeil.appearance(for: color)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        veil.layer?.backgroundColor = BackdropVeil.cardVeil(for: color, colors: colors, transparency: transparency).cgColor
        CATransaction.commit()
    }
}

/// Light, dark, or the Mac's own, the one choice that colors everything.
enum Look: String, CaseIterable, Identifiable {
    case light, dark, system

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: return "Light"
        case .dark: return "Dark"
        case .system: return "System"
        }
    }

    /// What the app is told to be. Nothing, for "system": the app then
    /// follows the Mac, and changes with it.
    var appearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }

    /// Set on the app rather than on the window, so every panel, alert and
    /// sheet, and every page, which follows the window it is in, agrees.
    ///
    /// Never from inside whatever is happening when it is asked for: the
    /// switch in Settings changes it from within an animation, over a panel
    /// in transition, and re-skinning every window in the middle of that is
    /// how a window ends up with a layer that takes clicks and shows
    /// nothing. The next turn of the run loop is soon enough.
    func apply() {
        let wanted = appearance
        DispatchQueue.main.async {
            guard NSApp.appearance !== wanted, NSApp.appearance?.name != wanted?.name else { return }
            NSApp.appearance = wanted
        }
    }
}

/// The edge of the window the column of tabs hangs on. The column's own
/// rows read the same either way; only where it sits, and what sits around
/// it, changes: the edge it is pulled by, where it comes out from, where a
/// card out of it opens.
enum Flank: String {
    case left, right

    /// The window's edge the column is against.
    var edge: Edge { self == .left ? .leading : .trailing }
    /// The column's own edge facing the page.
    var inner: Edge { self == .left ? .trailing : .leading }
    var alignment: Alignment { self == .left ? .leading : .trailing }
    var horizontal: HorizontalAlignment { self == .left ? .leading : .trailing }
    /// Pulling the column's edge this way by a point widens it by this much.
    var sign: CGFloat { self == .left ? 1 : -1 }
}

enum PanelPosition: String, CaseIterable {
    case left, right, off

    init(_ flank: Flank) { self = flank == .left ? .left : .right }

    var flank: Flank? { Flank(rawValue: rawValue) }
    var title: String { rawValue.capitalized }
}

enum Metrics {
    /// The tab strip. The window's title bar is grown to match it so the
    /// traffic lights come down with the tabs, otherwise giving the row room
    /// to breathe just leaves it sitting below three buttons it used to line
    /// up with.
    static let strip: CGFloat = 52
    /// The row of tabs across the top, when the tabs aren't in the column:
    /// shorter than the band the column's corner keeps, so the page gets the
    /// height back and the pills sit with a sliver of air above and below:
    /// six over and under a tab of Density.tab.
    static var row: CGFloat { Density.current.tab + 12 }
    /// How far in from the page's top and right edges anything floating
    /// over it keeps, find, "Link copied". The row's own trailing air, so
    /// over a page that runs to the window's edge it lines up under the
    /// reload button, and on a page laid as a card it keeps the same rim
    /// inside the card's edge that the row keeps inside the window's.
    static let rim: CGFloat = 12
    /// Where the first tab starts. The traffic lights run from 19 to 79,
    /// measured, not guessed, so this leaves them the same air on their right
    /// that the window gives them on their left.
    static let lights: CGFloat = 100
    /// Where back starts when the doors are beside the lights rather than
    /// in the address bar: just past the lights' edge (73), close enough to
    /// read as the window's own buttons.
    static let helmLead: CGFloat = 83
    /// Room for the traffic lights at the start of the sidebar title row.
    static let sideLights: CGFloat = 66
    /// The band left at the top when there is no strip: just enough for the
    /// traffic lights to sit in, and nothing else.
    static let bare: CGFloat = 34
    /// Tabs are a fixed width rather than the width of their titles, so the
    /// cross always lands in the same place and the row never rearranges
    /// itself while you read it. They give way when there are too many:
    /// narrower than tabTitled they show their site's mark alone, and they
    /// stop at tabMinWidth, the mark and its air. Past that the row scrolls,
    /// inside its own edges.
    static let tabWidth: CGFloat = 186
    static let tabTitled: CGFloat = 80
    static let tabMinWidth: CGFloat = 36
    static let tabGap: CGFloat = 2
    /// A pinned tab is a square the height of the row, holding one letter:
    /// a tab's height and two (Density.tab).
    static var pinWidth: CGFloat { Density.current.tab + 2 }
    /// The square at the end of the row that opens a new page.
    static let plusWidth: CGFloat = 30
    /// The address field, in both the places it shows up.
    static let fieldWidth: CGFloat = 750
    /// Total width of the desktop column, including the Left Trail on the left.
    static let side: CGFloat = 272
    static let sideMin: CGFloat = 240
    static let sideMax: CGFloat = 420
    /// How far past its narrowest the column's edge has to be pulled before
    /// the column lets go and shuts, and how far out of the window's left
    /// edge a shut one has to be pulled before it catches and opens. Short
    /// of either, it springs back to where it was.
    static let sideSnap: CGFloat = 64
    /// About how far past its widest the column's edge still gives under a
    /// hand that keeps pulling, Dia's (evals/side-width/rubber.py: its edge
    /// goes resisted(past, room: 95) beyond its widest, within half a point
    /// over 750 points of pull). Arc's stops dead there.
    static let sideStretch: CGFloat = 95
    /// How wide the column's edge is to the pointer, centered on the hairline
    /// half over the column, half over the page.
    static let edgeReach: CGFloat = 20
    /// How far in from the window's edges the column sits while it floats
    /// over the page: none. Its corners are the window's,
    /// which the capsule and the doors inside are concentric with, so any
    /// sliver of window round it would put two equal curves an inset apart
    /// at the window's corners. Arc's 3 did exactly that.
    static let floatInset: CGFloat = 0
    /// A floating column's inner corners, facing the page: the window's
    /// radius, so the island's capsule at its foot (Band.edge) sits in the
    /// same curve as in the docked column. Its outer corners are not cut:
    /// flush with the window's edge, the window rounds them (Column).
    static let floatCorner: CGFloat = Radius.window
    /// How far a floating column's ground reaches past its outer edge, out
    /// of the window at rest: more than its spring ever carries it past its
    /// place on the way in (CardMotion: 2% of its run, about 8 points).
    static let floatBleed: CGFloat = 40
    /// Where a rest brings a put-away column out: up to this far in from
    /// the window's left edge, four points with the edge's own, as Dia's
    /// tabs come out and not from a point further in (EdgeReach).
    static let edgeWall: CGFloat = 3
    /// How far past a floating column's right edge the pointer still counts
    /// as over it, so a hand drifting off the card while it reads or aims
    /// at a row doesn't put the column away. Dia's card stays with the
    /// pointer 50 points past it, and goes at 70.
    static let floatSafe: CGFloat = 56
    /// The lights' corner, also used by the hidden top strip's hover target.
    /// The hidden side column reveals only at the side edge (EdgeReach).
    static let lightsCorner = CGSize(width: 72, height: Metrics.strip)
}

/// The blue glass wink, loaded from Icon/Mark.png without a backing tile.
/// The same mark appears in the app icon and on the welcome screen.
struct Logomark: View {
    /// The picture, read once.
    static let image: NSImage? = file("Mark.png").flatMap { NSImage(contentsOf: $0) }

    /// Width over height, for the layouts that size the mark by its height.
    static let aspect: CGFloat = image.map { $0.size.width / $0.size.height } ?? 1

    /// A picture of the app's, from the bundle's resources when there is a
    /// bundle, else from the repository's Icon folder.
    static func file(_ name: String) -> URL? {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let places = [Bundle.main.resourceURL?.appendingPathComponent(name), repo.appendingPathComponent("Icon/\(name)")]
        return places.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color.clear
            }
        }
        .aspectRatio(Logomark.aspect, contentMode: .fit)
    }
}

private enum CardVeils {
    nonisolated(unsafe) static var kept: [String: CGFloat] = [:]
}
