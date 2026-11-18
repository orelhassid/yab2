import SwiftUI
import AppKit
import QuartzCore
import CoreImage
import Combine

// The welcome's first screen and the header of every chapter after it, in
// Core Animation from the first frame to the last: the ground, the glass
// mark, the light it throws, and the name, "yet another browser." Leaving
// the first screen, the mark rises into the header and the name folds into
// it, everything but its initials going, so the words become "yab" beside
// the mark.
//
// On Welcome the mark and the name stand in the stage's points, the
// 1180 × 780 window it was composed for, and scale with it as one piece
// about the header's line (StageSpace); the header stays at 1:1. The
// letters are pictures drawn for the scale they stand at, so they stay
// crisp at any size of window; a new size moves them, and nothing is laid
// out again.
//
// The blue glass wink arrives as one picture, then rises into the header.
// Its opacity and scale are animated by Core Animation; the letters keep
// their existing transition from the full name to "yab".

/// Where the mark and the name stand: on Welcome in the stage's points,
/// scaled as the stage is, and in the header at 1:1. One set of numbers,
/// for the view and for the stage's parts around it.
enum HeroLayout {
    /// The square source includes the wink's transparent breathing room.
    static let mark = CGRect(x: 506, y: 160, width: 168, height: 168)
    /// "yet another browser.": the top of its 52 line, under the mark.
    static let nameTop: CGFloat = 372
    static let nameLine: CGFloat = 52

    /// The header: level with the traffic lights, the mark 29 tall and
    /// "yab" beside it, 6 apart, the pair in the middle of the window. The
    /// name is set at 20, the size SF Pro switches to its display cut, the
    /// same cut as the title's, so the letters don't change shape when
    /// they settle.
    static let headerY: CGFloat = StageSpace.pivot.y / 2
    static let headerMark: CGFloat = 29
    static let headerFont: CGFloat = 20
    static let headerGap: CGFloat = 6
    /// The logotype's tracking, in ems.
    static let headerTracking: CGFloat = -0.036

    static func font(_ size: CGFloat) -> NSFont { .systemFont(ofSize: size, weight: .medium) }

    struct Place {
        /// The mark's middle, and its scale from the 168 × 148 it is laid out at.
        var markCenter: CGPoint
        var markScale: CGFloat
        /// Where the name's line starts, at its baseline.
        var nameLeft: CGFloat
        var baseline: CGFloat
        /// The name's letters' scale from the 44 they are set at.
        var nameScale: CGFloat
    }

    /// Welcome: the mark in the middle and the name under it, in the
    /// stage's points brought into the window's.
    static func openingOffset(in size: CGSize) -> CGFloat {
        let middle = StageSpace.toWindow(CGPoint(x: 590, y: 336), in: size).y
        return size.height / 2 - middle
    }

    static func welcome(in size: CGSize) -> Place {
        let s = StageSpace.scale(for: size)
        let font = font(WelcomeType.name)
        // As a line box sets it: the letters' own height in the middle of the 52.
        let baseline = nameTop + (nameLine - (font.ascender - font.descender)) / 2 + font.ascender
        let start = StageSpace.toWindow(CGPoint(x: StageSpace.pivot.x - Title.nameWidth / 2, y: baseline), in: size)
        return Place(
            markCenter: StageSpace.toWindow(CGPoint(x: mark.midX, y: mark.midY), in: size).applying(CGAffineTransform(translationX: 0, y: openingOffset(in: size))), markScale: s,
            nameLeft: (start.x * 2).rounded() / 2, baseline: (start.y * 2).rounded() / 2 + openingOffset(in: size), nameScale: s
        )
    }

    /// The mark and "yab" side by side, centered on the header's line.
    static func header(in size: CGSize) -> Place {
        let font = font(headerFont)
        let k = headerMark / mark.height
        let markW = mark.width * k
        let left: CGFloat = 88
        return Place(
            markCenter: CGPoint(x: left + markW / 2, y: headerY), markScale: k,
            nameLeft: left + markW + headerGap,
            baseline: (headerY + (font.ascender + font.descender) / 2).rounded(),
            nameScale: headerFont / WelcomeType.name
        )
    }
}

/// The name's letters as pictures: "yet another browser." in pieces, the
/// initials apart from what folds away between them, and "yab" at the
/// header's size for the initials to settle into.
struct Title {
    struct Piece {
        let picture: CGImage
        /// In points.
        let size: CGSize
        /// The picture's left end of its baseline, as an anchor point.
        let anchor: CGPoint
        /// Where it starts along the line.
        let x: CGFloat
        /// Which of y, a, b this is; nil for what folds away.
        let initial: Int?
    }

    let pieces: [Piece]
    let width: CGFloat
    /// Pixels a point: the screen's, times the scale the letters stand at.
    let density: CGFloat

    static let texts: [(String, Int?)] = [("y", 0), ("et ", nil), ("a", 1), ("nother ", nil), ("b", 2), ("rowser", nil), (".", nil)]
    static let headerTexts: [(String, Int?)] = [("y", 0), ("a", 1), ("b", 2)]
    /// The three words, for the way they come in.
    static let words: [[Int]] = [[0, 1], [2, 3], [4, 5, 6]]

    /// The name's ink, Palette's, in either look.
    static func ink(dark: Bool) -> NSColor { resolved(Palette.NS.ink, dark: dark) }
    /// The Mac's accent, only for the full stop.
    static func accent(dark: Bool) -> NSColor { resolved(.controlAccentColor, dark: dark) }

    static func resolved(_ color: NSColor, dark: Bool) -> NSColor {
        var cg = color.cgColor
        (NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()).performAsCurrentDrawingAppearance {
            cg = color.cgColor
        }
        return NSColor(cgColor: cg) ?? color
    }

    /// Where "another" starts and ends along the line at 44, for the pen's
    /// line under it.
    static let another: (start: CGFloat, end: CGFloat) = {
        let size = WelcomeType.name
        let whole = NSAttributedString(string: texts.map(\.0).joined(),
                                       attributes: [.font: HeroLayout.font(size), .kern: WelcomeType.tracking * size])
        let line = CTLineCreateWithAttributedString(whole)
        return (CTLineGetOffsetForStringIndex(line, 4, nil), CTLineGetOffsetForStringIndex(line, 11, nil))
    }()

    /// The pen's line under "another", as yetanotherbrowser.com draws it
    /// under the same word: one wave a little past both ends. In the
    /// name's points at 44, from the left end of its baseline.
    static let underline: CGPath = {
        let k: CGFloat = 1.3, y: CGFloat = 6
        let x = another.start - 4 * k, w = another.end - another.start + 8 * k
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x, y: y + 1.5 * k))
        path.addCurve(to: CGPoint(x: x + w, y: y + 0.8 * k),
                      control1: CGPoint(x: x + w * 0.3, y: y + 4 * k), control2: CGPoint(x: x + w * 0.68, y: y - 1.5 * k))
        return path
    }()

    /// The whole name's width at 44, and "yab"'s at 20: the same in any
    /// ink and at any density.
    static let nameWidth = line(texts, size: WelcomeType.name, tracking: WelcomeType.tracking).width
    static let headerLine = line(headerTexts, size: HeroLayout.headerFont, tracking: HeroLayout.headerTracking)
    static var headerWidth: CGFloat { headerLine.width }

    private static var cache: [String: Title] = [:]

    /// "yet another browser." at 44, the welcome's one display tracking.
    static func name(dark: Bool, density: CGFloat) -> Title {
        made("name \(dark) \(density)") {
            Title(texts: texts, size: WelcomeType.name, tracking: WelcomeType.tracking, dark: dark, density: density)
        }
    }

    /// "yab" at 20, the logotype's tracking.
    static func header(dark: Bool, density: CGFloat) -> Title {
        made("header \(dark) \(density)") {
            Title(texts: headerTexts, size: HeroLayout.headerFont, tracking: HeroLayout.headerTracking, dark: dark, density: density)
        }
    }

    private static func made(_ key: String, _ make: () -> Title) -> Title {
        if let title = cache[key] { return title }
        let title = make()
        cache[key] = title
        return title
    }

    /// Where each piece starts along the line and the line's width, as
    /// the whole line sets them, kerning and all.
    static func line(_ texts: [(String, Int?)], size: CGFloat, tracking: CGFloat) -> (starts: [CGFloat], width: CGFloat) {
        let font = HeroLayout.font(size)
        let kern = tracking * size
        let whole = NSAttributedString(string: texts.map(\.0).joined(), attributes: [.font: font, .kern: kern])
        let line = CTLineCreateWithAttributedString(whole)
        var index = 0
        let starts: [CGFloat] = texts.map { text, _ in
            let x = CTLineGetOffsetForStringIndex(line, index, nil)
            index += (text as NSString).length
            return x
        }
        return (starts, CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) - kern)
    }

    init(texts: [(String, Int?)], size: CGFloat, tracking: CGFloat, dark: Bool, density: CGFloat) {
        let font = HeroLayout.font(size)
        let kern = tracking * size
        let ink = Self.ink(dark: dark), accent = Self.accent(dark: dark)
        let (starts, width) = Self.line(texts, size: size, tracking: tracking)
        pieces = zip(texts, starts).map { piece, x in
            let color = piece.0 == "." ? accent : ink
            let text = NSAttributedString(string: piece.0, attributes: [.font: font, .kern: kern, .foregroundColor: color])
            return Self.piece(text, x: x, initial: piece.1, density: density)
        }
        self.width = width
        self.density = density
    }

    private static func piece(_ text: NSAttributedString, x: CGFloat, initial: Int?, density: CGFloat) -> Piece {
        let line = CTLineCreateWithAttributedString(text)
        var ascent: CGFloat = 0, descent: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let pad: CGFloat = 4
        // Whole pixels, and the points they make exactly: the picture is
        // never stretched by a fraction of a pixel.
        let pixels = (width: Int(ceil((width + pad * 2) * density)), height: Int(ceil((ascent + descent + pad * 2) * density)))
        let size = CGSize(width: CGFloat(pixels.width) / density, height: CGFloat(pixels.height) / density)
        let context = CGContext(
            data: nil, width: pixels.width, height: pixels.height,
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        context.scaleBy(x: density, y: density)
        context.setShouldSmoothFonts(false)
        context.textPosition = CGPoint(x: pad, y: size.height - pad - ascent)
        CTLineDraw(line, context)
        return Piece(
            picture: context.makeImage()!, size: size,
            anchor: CGPoint(x: pad / size.width, y: (pad + ascent) / size.height),
            x: x, initial: initial
        )
    }
}

struct WelcomeHero: NSViewRepresentable {
    /// Up in the header, the chapters under it.
    var risen: Bool
    /// Finish: the header leaves with the rest of the frame; the ground stays.
    var finished = false
    /// Off when the Mac asks for less motion: the settled frame and one crossfade.
    var animated: Bool
    /// The first run, opened from the disk image's window.
    var fromDisk = false

    func makeNSView(context: Context) -> HeroView { HeroView(risen: risen, animated: animated, fromDisk: fromDisk) }

    func updateNSView(_ view: HeroView, context: Context) {
        view.animated = animated
        view.set(risen: risen)
        view.set(finished: finished)
    }
}

final class HeroView: NSView {
    /// The intro, counted from the view's first frame: the mark alone in
    /// the middle of the window, then it rises to its place and the name
    /// comes in under it, then the lede and the button.
    static let markFor = 0.45
    static let riseAt = 0.75
    static let nameAt = 0.9
    static let ledeAt = 1.3
    static let buttonAt = 1.45
    /// The pen's line under "another": once the name has come in, as the
    /// site draws it, on the pen's curve.
    static let penAt = 1.2
    static let penDuration = 0.5
    static let penCurve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)

    /// The rise and the fold, one curve for everything that moves.
    /// Snappy: off at once and most of the way there in the first third,
    /// then settling, as the chapter under it is already arriving.
    static let riseDuration = 0.42
    static let riseCurve = WelcomeCurve.rise.function
    static let arriveCurve = WelcomeCurve.arrive.function

    var animated: Bool
    /// From the disk image: its dark ground first, the smoked glass standing.
    var fromDisk: Bool
    /// The intro plays on the first frame; not for a Welcome shown settled
    /// (the bench's), nor in the header.
    var plays = true
    private(set) var risen: Bool
    private(set) var finished = false

    private let root = CALayer()
    /// The disk image's ground over the stage's, going in the intro's first half second.
    private let disk = CALayer()
    /// Everything but the ground: what Finish takes away.
    private let content = CALayer()
    /// The mark and its light, moved and scaled as one.
    private let group = CALayer()
    private let glasses = WinkLayers()
    /// The gift from a friend's link, put where the mark stands once the
    /// site says who sent it (Invites).
    private var gift: AnyCancellable?
    private var letters: [CALayer] = []
    /// The pen's line under "another", in the Mac's accent, as the full stop.
    private let pen = CAShapeLayer()
    /// The pictures the letters show now: the name at the stage's scale,
    /// "yab" at the header's.
    private var nameTitle: Title?
    private var headerTitle: Title?

    private var laidOut: CGSize = .zero
    private var laidDensity: CGFloat = 0
    /// The Mac's look: the ground and the name's ink follow it.
    private var dark = true
    private var played = false
    /// Which move is the latest, so a finished one that was overtaken
    /// doesn't settle what came after it.
    private var generation = 0

    /// The welcome's mark on screen now, for the light panel and the bench.
    static weak var shown: HeroView?

    init(risen: Bool, animated: Bool, fromDisk: Bool = false) {
        self.risen = risen
        self.animated = animated
        self.fromDisk = fromDisk
        super.init(frame: .zero)
        Self.shown = self
        LightPanel.showIfAsked()
        layer = root
        wantsLayer = true
        root.isGeometryFlipped = true
        dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        root.backgroundColor = Self.ground(dark: dark)
        disk.backgroundColor = Self.diskGround
        disk.opacity = 0
        root.addSublayer(disk)
        root.addSublayer(content)
        content.addSublayer(group)
        group.addSublayer(glasses.space)
        glasses.rest(lit: !risen)
        // Unpacked off the main thread, well before their first frame at
        // 0.1 s: handed over as PNGs, the commit that shows them would
        // unpack them. The light is made from the front glass there too.
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let picture = Logomark.file("Mark.png")
                .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) }
            DispatchQueue.main.async { if let picture, Invites.shared.received == nil { self?.glasses.show(picture) } }
        }
        // A friend's link: their stamp in the mark's place, numbered once
        // the site says (Stamp); Wax Seal unlocks quietly at the end.
        gift = Invites.shared.$received.combineLatest(MemberStamp.shared.$info).receive(on: RunLoop.main).sink { [weak self] received, info in
            guard let received, let picture = MemberStamp.welcomePicture(from: received, info: info) ?? Invites.giftPicture(received) else { return }
            self?.glasses.show(picture)
        }
        for _ in Title.texts {
            let letter = CALayer()
            letter.minificationFilter = .trilinear
            content.addSublayer(letter)
            letters.append(letter)
        }
        pen.path = Title.underline
        pen.fillColor = nil
        pen.lineWidth = 2.6
        pen.lineCap = .round
        pen.lineJoin = .round
        pen.strokeColor = Title.accent(dark: dark).cgColor
        pen.strokeEnd = risen ? 0 : 1
        content.addSublayer(pen)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The stage's ground (Palette.stage) in the look the view is in.
    static func ground(dark: Bool) -> CGColor { Title.resolved(Palette.NS.stage, dark: dark).cgColor }
    /// The disk image window's ground, the brand's ink: #141414.
    static let diskGround = NSColor(srgbRed: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x14 / 255.0, alpha: 1).cgColor

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The Mac turned light or dark: the ground, and each letter's picture
    /// for the same piece in the other ink, where it stands and mid-move.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let now = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        guard now != dark else { return }
        dark = now
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        root.backgroundColor = Self.ground(dark: dark)
        pen.strokeColor = Title.accent(dark: dark).cgColor
        retitle()
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    /// Pixels a point for the name on Welcome: the screen's times the
    /// stage's scale, in quarters, so a resize redraws it only now and then.
    private func nameDensity(_ size: CGSize) -> CGFloat {
        ((window?.backingScaleFactor ?? 2) * StageSpace.scale(for: size) * 4).rounded(.up) / 4
    }

    var contentWidth: CGFloat? { didSet { if oldValue != contentWidth { needsLayout = true } } }

    override func layout() {
        super.layout()
        let size = CGSize(width: contentWidth ?? bounds.width, height: bounds.height)
        guard size.width > 0, size.height > 0 else { return }
        let density = nameDensity(size)
        guard size != laidOut || density != laidDensity else { return }
        laidOut = size
        laidDensity = density
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disk.frame = bounds
        content.frame = bounds
        retitle()
        place(risen: risen)
        CATransaction.commit()
        guard !played else { return }
        played = true
        if risen || !plays { return }
        if animated { playIntro() } else { crossfadeIn() }
    }

    // MARK: - places

    /// The pictures for the look and the scale now, swapped in where the
    /// old ones stand, mid-move or not.
    private func retitle() {
        let backing = window?.backingScaleFactor ?? 2
        let name = Title.name(dark: dark, density: laidDensity > 0 ? laidDensity : backing)
        let header = Title.header(dark: dark, density: backing)
        let was = (name: nameTitle, header: headerTitle)
        nameTitle = name
        headerTitle = header
        for (index, letter) in letters.enumerated() {
            let shown = letter.contents as AnyObject?
            if let old = was.name, shown === old.pieces[index].picture {
                show(name.pieces[index], of: name, on: letter)
            } else if let initial = name.pieces[index].initial, let old = was.header, shown === old.pieces[initial].picture {
                show(header.pieces[initial], of: header, on: letter)
            }
        }
    }

    /// Everything where it rests, on the first screen or in the header.
    private func place(risen: Bool) {
        guard let name = nameTitle, let header = headerTitle else { return }
        let size = laidOut
        let at = risen ? HeroLayout.header(in: size) : HeroLayout.welcome(in: size)
        group.bounds = CGRect(origin: .zero, size: HeroLayout.mark.size)
        glasses.fit(height: HeroLayout.mark.height)
        group.position = at.markCenter
        group.transform = CATransform3DMakeScale(at.markScale, at.markScale, 1)
        glasses.light.opacity = risen ? 0 : 1
        // The pen's line stays where the name stands on Welcome; in the
        // header it is taken back.
        let welcome = risen ? HeroLayout.welcome(in: size) : at
        pen.position = CGPoint(x: welcome.nameLeft, y: welcome.baseline)
        pen.transform = CATransform3DMakeScale(welcome.nameScale, welcome.nameScale, 1)
        pen.strokeEnd = risen ? 0 : 1
        pen.opacity = 1
        for (index, (letter, piece)) in zip(letters, name.pieces).enumerated() {
            if risen {
                let resting = rest(index, in: size)
                if let initial = piece.initial {
                    show(header.pieces[initial], of: header, on: letter)
                    letter.position = resting.position
                    letter.transform = CATransform3DIdentity
                    letter.opacity = 1
                } else {
                    show(piece, of: name, on: letter)
                    letter.position = resting.position
                    letter.transform = resting.transform
                    letter.opacity = 0
                }
            } else {
                show(piece, of: name, on: letter)
                letter.position = CGPoint(x: at.nameLeft + piece.x * at.nameScale, y: at.baseline)
                letter.transform = CATransform3DMakeScale(at.nameScale, at.nameScale, 1)
                letter.opacity = 1
            }
        }
    }

    private func show(_ piece: Title.Piece, of title: Title, on letter: CALayer) {
        letter.contents = piece.picture
        letter.contentsScale = title.density
        letter.bounds = CGRect(origin: .zero, size: piece.size)
        letter.anchorPoint = piece.anchor
    }

    /// Where a piece of the name goes in the header: an initial onto its
    /// letter of "yab", what's between them folded to nothing where the
    /// next initial begins. At the name's own size, scaled to the header's.
    private func rest(_ index: Int, in size: CGSize) -> (position: CGPoint, transform: CATransform3D) {
        let header = HeroLayout.header(in: size)
        let small = Title.headerLine
        let x: CGFloat
        if let initial = Title.texts[index].1 {
            x = small.starts[initial]
        } else {
            // Folds into where the next initial begins, or the name's end.
            let next = Title.texts[index...].lazy.compactMap { $0.1 }.first
            x = next.map { small.starts[$0] } ?? small.width
        }
        let k = header.nameScale
        let scaleX = Title.texts[index].1 == nil ? 0.05 * k : k
        return (CGPoint(x: header.nameLeft + x, y: header.baseline), CATransform3DMakeScale(scaleX, k, 1))
    }

    // MARK: - the intro

    /// The intro from its first frame again, with the light as it is set
    /// now: the light panel's Replay, and the bench's.
    func replay() {
        guard !risen, laidOut != .zero else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glasses.rest(lit: true)
        content.opacity = 1
        CATransaction.commit()
        if animated { playIntro() } else { crossfadeIn() }
    }

    func relight() { glasses.relight() }

    /// The mark alone in the middle of the window, then it rises to its
    /// place and the name comes in under it. The lede and the button are
    /// the stage's and the frame's, on the same clock.
    private func playIntro() {
        let now = CACurrentMediaTime()
        let pace = WelcomeMotion.pace
        // From the disk image, in the light: its dark ground first, the
        // smoked glass already standing on it.
        let fromImage = fromDisk && !dark
        glasses.play(at: now, standing: fromImage, duration: Self.markFor, pace: pace)
        if !fromImage {
            // Held in the window's middle, then up to its place on a spring.
            let middle = laidOut.height / 2
            let rise = WelcomeMotion.animation("position.y", from: middle - group.position.y, to: 0, curve: .spring(response: 0.55, damping: 0.86),
                                               duration: 0, delay: Self.riseAt, on: group)
            rise.isAdditive = true
            group.add(rise, forKey: "arrive.rise")
        }
        if fromImage {
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, NSNumber(value: 0.15 / 0.55), 1]
            fade.duration = 0.55 * pace
            fade.calculationMode = .linear
            disk.add(fade, forKey: "arrival")
        }

        let at = now + Self.nameAt * pace
        for letter in letters {
            arrive(letter, "opacity", from: 0, to: 1, at: at, for: 0.45 * pace, curve: CAMediaTimingFunction(name: .easeOut))
            arrive(letter, "transform.translation.y", from: 10, to: 0, at: at, for: 0.45 * pace, curve: Self.arriveCurve)
        }
        arrive(pen, "strokeEnd", from: 0, to: 1, at: now + Self.penAt * pace, for: Self.penDuration * pace, curve: Self.penCurve)
    }

    /// With Reduce Motion: the settled frame, in one crossfade.
    private func crossfadeIn() {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.2 * WelcomeMotion.pace
        content.add(fade, forKey: "arrival")
    }

    private func arrive(_ layer: CALayer, _ key: String, from: CGFloat, to: CGFloat, at: CFTimeInterval, for duration: Double, curve: CAMediaTimingFunction) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = from
        animation.toValue = to
        animation.beginTime = layer.convertTime(at, from: nil)
        animation.duration = duration
        animation.timingFunction = curve
        animation.fillMode = .backwards
        layer.add(animation, forKey: "arrive." + key)
    }

    // MARK: - Finish

    /// Finish: the header leaves with the title and the footer, in 0.15,
    /// and the ground stays for the window-to-be to grow over.
    func set(finished: Bool) {
        guard finished != self.finished else { return }
        self.finished = finished
        let from = content.presentation()?.opacity ?? content.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        content.opacity = finished ? 0 : 1
        CATransaction.commit()
        guard laidOut != .zero else { return }
        let fade = WelcomeMotion.animation("opacity", from: from, to: finished ? 0 : 1, curve: finished ? .depart : .arrive,
                                           duration: finished ? 0.15 : 0.22, on: content)
        content.add(fade, forKey: "finish")
    }

    // MARK: - the rise

    func set(risen: Bool) {
        guard risen != self.risen else { return }
        self.risen = risen
        guard played, laidOut != .zero, let name = nameTitle else { return }
        generation += 1
        let generation = generation
        guard animated else {
            // One crossfade from where it stood to where it stands.
            let swap = CATransition()
            swap.type = .fade
            swap.duration = 0.2 * WelcomeMotion.pace
            content.add(swap, forKey: "rise")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            place(risen: risen)
            CATransaction.commit()
            return
        }
        let size = laidOut
        let pace = WelcomeMotion.pace
        let small = HeroLayout.headerFont / WelcomeType.name
        let welcome = HeroLayout.welcome(in: size)

        // The initials come down from the header as the name's own
        // letters: swapped before the move, at the size they stand at.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (letter, piece) in zip(letters, name.pieces) where piece.initial != nil {
            let now = letter.presentation()
            let position = now?.position ?? letter.position
            let transform = now?.transform ?? letter.transform
            letter.removeAllAnimations()
            let wasSmall = (letter.contents as AnyObject?) !== piece.picture
            show(piece, of: name, on: letter)
            letter.position = position
            letter.transform = wasSmall ? CATransform3DScale(transform, small, small, 1) : transform
        }
        CATransaction.commit()

        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.riseDuration * pace)
        CATransaction.setAnimationTimingFunction(Self.riseCurve)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.generation == generation, risen, let header = self.headerTitle, let name = self.nameTitle else { return }
            // Settled: the initials become "yab" drawn at its own size, crisp.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for (letter, piece) in zip(self.letters, name.pieces) {
                guard let initial = piece.initial else { continue }
                self.show(header.pieces[initial], of: header, on: letter)
                letter.transform = CATransform3DIdentity
            }
            CATransaction.commit()
        }

        let at = risen ? HeroLayout.header(in: size) : welcome
        // The intro's rise gives way: `move` starts from where it has the
        // mark on screen now (the presentation keeps it until the commit).
        group.removeAnimation(forKey: "arrive.rise")
        move(group, "position", to: NSValue(point: at.markCenter))
        move(group, "transform", to: NSValue(caTransform3D: CATransform3DMakeScale(at.markScale, at.markScale, 1)))

        // The pen takes its line back as the letters around it fold; on the
        // way down it is there again, drawn, with them.
        if risen {
            move(pen, "strokeEnd", to: 0, duration: 0.16 * pace, curve: CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pen.removeAnimation(forKey: "rise.strokeEnd")
            pen.strokeEnd = 1
            CATransaction.commit()
            arrive(pen, "opacity", from: 0, to: 1, at: CACurrentMediaTime() + 0.15 * pace, for: 0.25 * pace, curve: CAMediaTimingFunction(name: .easeOut))
        }

        // The light goes out quickly on the way up, comes back late on the way down.
        move(glasses.light, "opacity", to: risen ? 0 : 1, duration: (risen ? 0.18 : 0.3) * pace, delay: (risen ? 0 : 0.15) * pace,
             curve: CAMediaTimingFunction(name: .easeOut))

        for (index, (letter, piece)) in zip(letters, name.pieces).enumerated() {
            let target: (position: CGPoint, transform: CATransform3D) = risen
                ? rest(index, in: size)
                : (CGPoint(x: welcome.nameLeft + piece.x * welcome.nameScale, y: welcome.baseline),
                   CATransform3DMakeScale(welcome.nameScale, welcome.nameScale, 1))
            move(letter, "position", to: NSValue(point: target.position))
            move(letter, "transform", to: NSValue(caTransform3D: target.transform))
            if piece.initial == nil {
                // What folds away goes early, faster than it moves.
                move(letter, "opacity", to: risen ? 0 : 1, duration: (risen ? 0.16 : 0.25) * pace, delay: (risen ? 0 : 0.15) * pace,
                     curve: CAMediaTimingFunction(name: .easeOut))
            }
        }
        CATransaction.commit()
    }

    private func move(_ layer: CALayer, _ key: String, to value: Any, duration: Double? = nil, delay: Double = 0, curve: CAMediaTimingFunction = riseCurve) {
        let animation = CABasicAnimation(keyPath: key)
        animation.fromValue = layer.presentation()?.value(forKeyPath: key) ?? layer.value(forKeyPath: key)
        animation.toValue = value
        animation.duration = duration ?? Self.riseDuration * WelcomeMotion.pace
        animation.timingFunction = curve
        if delay > 0 {
            animation.beginTime = layer.convertTime(CACurrentMediaTime() + delay, from: nil)
            animation.fillMode = .backwards
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setValue(value, forKeyPath: key)
        CATransaction.commit()
        layer.add(animation, forKey: "rise." + key)
    }
}


// MARK: - the two glasses

/// The mark in its two pieces: the old browser's smoked glass behind and
/// Yab's dichroic glass in front (Icon/MarkBack.png, Icon/MarkFront.png,
/// cut from the app icon's art), and where each stands in it. In the icon
/// art's own 1024 space, where the mark's box runs from (73, 124) to
/// (950, 898); fitted onto the art by shape, 98.6% and 97.3% the same.
private enum Glass {
    struct Pose {
        var center: CGPoint
        var scale: CGSize
        var angle: CGFloat
        var z: CGFloat = 0

        static func mix(_ a: Pose, _ b: Pose, _ p: CGFloat) -> Pose {
            Pose(
                center: CGPoint(x: Glass.lerp(a.center.x, b.center.x, p), y: Glass.lerp(a.center.y, b.center.y, p)),
                scale: CGSize(width: Glass.lerp(a.scale.width, b.scale.width, p), height: Glass.lerp(a.scale.height, b.scale.height, p)),
                angle: Glass.lerp(a.angle, b.angle, p), z: Glass.lerp(a.z, b.z, p)
            )
        }

        func scaled(_ k: CGFloat) -> Pose {
            var pose = self
            pose.scale = CGSize(width: scale.width * k, height: scale.height * k)
            return pose
        }

        /// About the glass's middle, as the layer's anchor is.
        var transform: CATransform3D {
            let size = CATransform3DMakeScale(scale.width, scale.height, 1)
            let turn = CATransform3DMakeRotation(angle, 0, 0, 1)
            return CATransform3DConcat(CATransform3DConcat(size, turn), CATransform3DMakeTranslation(0, 0, z))
        }
    }

    /// The mark's box in the art.
    static let box = CGRect(x: 73, y: 124, width: 877, height: 774)
    /// Both glasses' layers are the back picture's size, in art units.
    static let size = CGSize(width: 796, height: 785)
    static let frontSize = CGSize(width: 1054, height: 930)

    static let back = Pose(center: CGPoint(x: 380.103, y: 434.2), scale: CGSize(width: 0.786134, height: 0.786134), angle: -0.029634)
    /// Where the back picture would lie to take the front glass's shape: the
    /// copy's pose once it has stepped forward.
    static let front = Pose(center: CGPoint(x: 591.04, y: 570.558), scale: CGSize(width: 0.889876, height: 0.807773), angle: -0.030703)
    /// The front picture inside that pose.
    static let frontInBack = CGAffineTransform(a: 0.77527, b: 0.00103, c: -0.00093, d: 0.85407, tx: -7.7786, ty: -5.8905)
    /// Before the split: one glass, a little larger, where the two will part from.
    static let single = Pose(
        center: CGPoint(x: (back.center.x + front.center.x) / 2, y: (back.center.y + front.center.y) / 2),
        scale: CGSize(width: back.scale.width * 1.1, height: back.scale.height * 1.1), angle: back.angle
    )

    /// How the light under the glass falls: a copy of the front glass,
    /// dropped and moved (in a glass layer's units), sheared, stretched about
    /// its middle, blurred, then saturated, as a browser draws
    /// `translate skewX scale` with `blur saturate`; how bright it is when
    /// the glass lights and once it has settled. Set by hand, in the light
    /// panel a test build opens with YAB_LIGHT_PANEL=1.
    struct LightLook: Equatable {
        var x: CGFloat = -92
        var y: CGFloat = 187
        var skew: CGFloat = 24
        var width: CGFloat = 1.05
        var height: CGFloat = 0.68
        var blur: CGFloat = 102
        var saturation: CGFloat = 2.1
        var peak: CGFloat = 0.67
        var rest: CGFloat = 0.56

        /// The values in one line, as the prototype's panel gives them.
        var line: String {
            func n(_ v: CGFloat) -> String { String(format: "%g", (v * 100).rounded() / 100) }
            return "light x \(n(x)) y \(n(y)) skew \(n(skew)) scale \(n(width))×\(n(height)) blur \(n(blur)) sat \(n(saturation)) peak \(n(peak)) rest \(n(rest))"
        }
    }
    static var look = LightLook()

    /// The light a glass throws, in the front pose's own units.
    static var lightFromFront: CGAffineTransform {
        CGAffineTransform(translationX: -size.width / 2, y: -size.height / 2)
            .concatenating(CGAffineTransform(scaleX: look.width, y: look.height))
            .concatenating(CGAffineTransform(a: 1, b: 0, c: tan(look.skew * .pi / 180), d: 1, tx: 0, ty: 0))
            .concatenating(CGAffineTransform(translationX: look.x, y: look.y))
            .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
    }
    static var lightBlur: CGFloat { look.blur }
    /// The front picture's units into a glass layer's, where its light falls.
    static var lightPlace: CGAffineTransform { frontInBack.concatenating(lightFromFront) }
    /// Where the light picture lies, in a glass layer's units: the placed
    /// front glass and room for its blur.
    static var lightFrame: CGRect {
        CGRect(origin: .zero, size: frontSize).applying(lightPlace)
            .insetBy(dx: -lightBlur * 3, dy: -lightBlur * 3).integral
    }
    /// The light is uncovered along the same diagonal as the color, a little
    /// behind it; this far along (in the front glass's lengths at 125°) its
    /// soft edge has left the whole light picture.
    static var lightEnd: CGFloat {
        let into = lightPlace.inverted()
        let reach = [CGPoint(x: lightFrame.minX, y: lightFrame.minY), CGPoint(x: lightFrame.maxX, y: lightFrame.minY),
                     CGPoint(x: lightFrame.minX, y: lightFrame.maxY), CGPoint(x: lightFrame.maxX, y: lightFrame.maxY)]
            .map { Stripe.at(125, $0.applying(into), over: frontSize) }.max() ?? 1
        return reach + Stripe.lightRamp + 0.02
    }

    static func lerp(_ a: CGFloat, _ b: CGFloat, _ p: CGFloat) -> CGFloat { a + (b - a) * p }

    /// The pictures, and the light made from the front one.
    struct Pictures {
        let back: CGImage
        let front: CGImage
        let light: CGImage

        static func load() -> Pictures? {
            func picture(_ name: String) -> CGImage? {
                Logomark.file(name)
                    .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
                    .flatMap { CGImageSourceCreateImageAtIndex($0, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) }
            }
            guard let back = picture("MarkBack.png"), let front = picture("MarkFront.png") else { return nil }
            guard let light = Self.light(from: front) else { return nil }
            return Pictures(back: back, front: front, light: light)
        }

        /// Drawn at a quarter of the art's units: it is all blur.
        static func light(from front: CGImage) -> CGImage? {
            let place = Glass.lightPlace, frame = Glass.lightFrame
            let density: CGFloat = 0.25
            let perUnit = CGFloat(front.width) / Glass.frontSize.width
            let W = (frame.width * density).rounded(), H = (frame.height * density).rounded()
            // Core Image counts up from the bottom: into units down from the
            // top, placed, into the picture's pixels, turned back over.
            let fromPicture = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: CGFloat(front.height))
                .concatenating(CGAffineTransform(scaleX: 1 / perUnit, y: 1 / perUnit))
                .concatenating(place)
                .concatenating(CGAffineTransform(translationX: -frame.minX, y: -frame.minY))
                .concatenating(CGAffineTransform(scaleX: density, y: density))
                .concatenating(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: H))
            // Blurred, then saturated, the order a browser's filter list has.
            let image = CIImage(cgImage: front)
                .transformed(by: fromPicture).applyingGaussianBlur(sigma: Glass.lightBlur * density)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: Glass.look.saturation])
            return CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
                .createCGImage(image, from: CGRect(x: 0, y: 0, width: W, height: H))
        }
    }
}

/// The intro, as a picture of every moment: where each glass is, how lit,
/// at `t` seconds from the view's first frame. Every curve leaves from rest
/// and lands at rest, and nothing is swapped or switched on the way, so
/// there is no frame that jumps.
private enum Split {
    /// When the last thing moves: the light has settled.
    static let end = 2.6

    struct Frame {
        var back: Glass.Pose
        var backOpacity: Float
        /// Black over the back glass as it steps back, as if further from the light.
        var backShade: Float
        var front: Glass.Pose
        var frontOpacity: Float
        /// The smoked picture under the front glass, the copy it was.
        var skin: Float
        /// A glint across the lone glass: where, 0 to 1 along it, and how bright.
        var glint: (at: CGFloat, strength: Float)
        /// How far the color has crossed the front glass, 0 to 1.
        var lit: CGFloat
        var shine: (at: CGFloat, strength: Float)
        var light: Float
        /// How far the light is uncovered, along the color's diagonal.
        var lightAt: CGFloat
    }

    /// `standing`: from the disk image, the smoked glass is there from the
    /// first frame rather than coming in.
    static func frame(_ t: Double, standing: Bool = false) -> Frame {
        let comeIn = standing ? 1 : easeOut(seg(t, 0.1, 0.9))
        let grow = Glass.lerp(0.9, 1, arrive(seg(t, 0.1, 1.0)))

        // The old one. Until they part it lies exactly under its twin; it
        // comes up over 0.2 s as they start to move, so the two soft rims
        // never add up in one frame.
        var back = Glass.Pose.mix(Glass.single, Glass.back, glide(seg(t, 1.0, 1.75)))
        back.z = -50 * bump(seg(t, 1.0, 1.75))

        // The copy: leaves from rest, overshoots a little, lands at rest.
        var front = t < 1.05 ? Glass.single.scaled(grow) : Glass.Pose.mix(Glass.single, Glass.front, settle(seg(t, 1.05, 2.05)))
        front.z = 70 * bump(seg(t, 1.05, 1.8))

        let lit = inOut(seg(t, 1.25, 2.0))
        // The light's soft edge runs a little ahead of the color down its
        // diagonal, then moves on off the blur, and the light settles.
        let lead = lit.revealed + 0.4
        let lightAt = lead + max(0, Glass.lightEnd - 1.63) * inOut(seg(t, 2.0, 2.6))
        return Frame(
            back: back,
            backOpacity: Float(inOut(seg(t, 0.95, 1.15))),
            backShade: Float(0.16 * bump(seg(t, 1.0, 1.75))),
            front: front,
            frontOpacity: Float(comeIn),
            // Goes only once the color covers the whole glass.
            skin: Float(1 - inOut(seg(t, 2.0, 2.3))),
            glint: (Glass.lerp(-0.2, 1.2, seg(t, 0.45, 1.15)), Float(0.75 * bump(seg(t, 0.45, 1.15)))),
            lit: lit,
            shine: (Glass.lerp(-0.1, 1.15, lit) - 0.08, Float(bump(lit))),
            light: Float(Glass.look.peak * min(1, lit * 1.3) - (Glass.look.peak - Glass.look.rest) * inOut(seg(t, 2.05, 2.6))),
            lightAt: lightAt
        )
    }

    // The curves.
    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> CGFloat { CGFloat(min(max((t - a) / (b - a), 0), 1)) }
    private static func easeOut(_ p: CGFloat) -> CGFloat { 1 - pow(1 - p, 3) }
    private static func inOut(_ p: CGFloat) -> CGFloat { p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2 }
    /// Up and back down, leaving and landing at rest.
    private static func bump(_ p: CGFloat) -> CGFloat { let s = sin(.pi * p); return s * s }
    /// Leaves from rest, overshoots about 5%, comes to rest exactly at 1.
    private static func settle(_ p: CGFloat) -> CGFloat {
        guard p > 0 else { return 0 }
        guard p < 1 else { return 1 }
        let g = pow(p, 1.6)
        return 1 - exp(-7 * g) * cos(7.5 * g) * (1 - pow(p, 4))
    }
    private static let arrive = bezier(0.2, 0.8, 0.2, 1)
    private static let glide = bezier(0.5, 0, 0.15, 1)

    private static func bezier(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> (CGFloat) -> CGFloat {
        func at(_ u: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { 3 * (1 - u) * (1 - u) * u * a + 3 * (1 - u) * u * u * b + u * u * u }
        return { p in
            guard p > 0 else { return 0 }
            guard p < 1 else { return 1 }
            var lo: CGFloat = 0, hi: CGFloat = 1, u = p
            for _ in 0..<24 {
                u = (lo + hi) / 2
                if at(u, x1, x2) < p { lo = u } else { hi = u }
            }
            return at(u, y1, y2)
        }
    }
}

/// The mark as a layer in the art's units, with a little perspective for
/// the step forward and back.
/// The wink is one piece of artwork. Its entrance moves the whole mark,
/// so the face keeps its proportions as it rises into the header.
private final class WinkLayers {
    let space = CALayer()
    // Retains the header transition's existing light fade target.
    let light = CALayer()
    private let picture = CALayer()

    init() {
        space.bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        picture.frame = space.bounds
        picture.contentsGravity = .resizeAspect
        picture.minificationFilter = .trilinear
        space.addSublayer(light)
        space.addSublayer(picture)
    }

    func show(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        picture.contents = image
        CATransaction.commit()
    }

    func fit(height: CGFloat) {
        space.position = CGPoint(x: height / 2, y: height / 2)
        space.transform = CATransform3DMakeScale(height / 1024, height / 1024, 1)
    }

    func rest(lit: Bool) {
        picture.removeAllAnimations()
    }

    // The selected material already contains its lighting.
    func relight() {}

    func play(at start: CFTimeInterval, standing: Bool = false, duration: Double, pace: Double = 1) {
        guard !standing else { return }
        let entrance = CAAnimationGroup()
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0
        opacity.toValue = 1
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.92
        scale.toValue = 1
        entrance.animations = [opacity, scale]
        entrance.duration = duration * pace
        entrance.beginTime = picture.convertTime(start, from: nil)
        entrance.timingFunction = CAMediaTimingFunction(name: .easeOut)
        entrance.fillMode = .backwards
        picture.add(entrance, forKey: "wink.entrance")
    }
}

private extension CGFloat {
    /// Where the edge of the reveal's soft ramp is along the glass, from how
    /// lit it is: off the glass at 0, and at 1 far enough past its end that
    /// the ramp has left it too.
    var revealed: CGFloat { Glass.lerp(-0.23, 1.23, self) }
}

/// A soft stripe of light, moved across a glass along a CSS-style angle,
/// shown only where the glass is (its host's mask).
private struct Stripe {
    let host = CALayer()
    let band = CAGradientLayer()
    let angle: CGFloat
    /// The stripe's width, as a part of the glass's length along the angle.
    let part: CGFloat

    /// `stops` across the stripe, 0 to 1, with each color's alpha; `width`
    /// of the stripe as a part of the glass's length along the angle.
    init(angle: CGFloat, stops: [(CGFloat, CGFloat)], colors: [NSColor], width: CGFloat) {
        self.angle = angle
        part = width
        band.colors = zip(stops, colors).map { $1.withAlphaComponent($0.1).cgColor }
        band.locations = stops.map { NSNumber(value: Double($0.0)) }
        band.startPoint = CGPoint(x: 0, y: 0.5)
        band.endPoint = CGPoint(x: 1, y: 0.5)
        host.opacity = 0
        host.addSublayer(band)
    }

    func place(_ at: CGFloat, over size: CGSize) {
        let length = Stripe.length(angle, over: size)
        band.bounds = CGRect(x: 0, y: 0, width: part * length, height: (size.width + size.height) * 2)
        band.transform = CATransform3DMakeRotation((angle - 90) * .pi / 180, 0, 0, 1)
        band.position = Stripe.along(angle, at, over: size)
    }

    /// A CSS gradient's length at `angle` over a box.
    static func length(_ angle: CGFloat, over size: CGSize) -> CGFloat {
        let a = angle * .pi / 180
        return abs(size.width * sin(a)) + abs(size.height * cos(a))
    }

    /// The point `at` of the way along a CSS gradient's line at `angle`
    /// across a box, y down.
    static func along(_ angle: CGFloat, _ at: CGFloat, over size: CGSize) -> CGPoint {
        let a = angle * .pi / 180
        let length = length(angle, over: size)
        return CGPoint(x: size.width / 2 + (at - 0.5) * length * sin(a), y: size.height / 2 - (at - 0.5) * length * cos(a))
    }

    /// The inverse of `along`: how far along the line a point lies.
    static func at(_ angle: CGFloat, _ point: CGPoint, over size: CGSize) -> CGFloat {
        let a = angle * .pi / 180
        return ((point.x - size.width / 2) * sin(a) - (point.y - size.height / 2) * cos(a)) / length(angle, over: size) + 0.5
    }

    /// The light's ramp is longer than the glass's: it falls on blur.
    static let lightRamp: CGFloat = 0.24

    /// A reveal at 125°: black behind a soft ramp `ramp` of the glass long,
    /// clear ahead of it, the ramp's clear end at the layer's middle; `span`
    /// glass lengths wide, so the black covers all behind it.
    static func stretch(_ reveal: CAGradientLayer, over size: CGSize, ramp: CGFloat = 0.18, span: CGFloat = 3) {
        let length = length(125, over: size)
        reveal.bounds = CGRect(x: 0, y: 0, width: length * span, height: max(length * span, (size.width + size.height) * 2))
        reveal.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.black.withAlphaComponent(0).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        reveal.locations = [0, NSNumber(value: Double(0.5 - ramp / span)), 0.5, 1]
        reveal.startPoint = CGPoint(x: 0, y: 0.5)
        reveal.endPoint = CGPoint(x: 1, y: 0.5)
        reveal.transform = CATransform3DMakeRotation((125 - 90) * .pi / 180, 0, 0, 1)
    }
}

// MARK: - the light panel

/// Sliders for the light under the glass, beside the welcome in a test build
/// started with YAB_LIGHT_PANEL=1: every change redraws the light as it
/// rests, Replay plays the intro with it, Copy puts the values on the
/// pasteboard in the prototype's words.
@MainActor private enum LightPanel {
    static var window: NSPanel?

    static func showIfAsked() {
        guard window == nil, ProcessInfo.processInfo.environment["YAB_LIGHT_PANEL"] != nil else { return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
                            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Light"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // Dark, as the welcome it sits beside is.
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = WindowHosting.content(LightControls().environment(\.colorScheme, .dark))
        window = panel
        DispatchQueue.main.async {
            if let screen = NSScreen.main {
                panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 20, y: screen.visibleFrame.minY + 20))
            }
            panel.orderFrontRegardless()
        }
    }
}

private struct LightControls: View {
    @State private var look = Glass.look
    @State private var copied = false

    private struct Row {
        let name: String
        let key: WritableKeyPath<Glass.LightLook, CGFloat>
        let range: ClosedRange<Double>
        let step: Double
    }

    private let rows: [Row] = [
        Row(name: "Right", key: \.x, range: -300...300, step: 1),
        Row(name: "Down", key: \.y, range: -100...450, step: 1),
        Row(name: "Skew", key: \.skew, range: -40...60, step: 1),
        Row(name: "Width", key: \.width, range: 0.5...2, step: 0.01),
        Row(name: "Height", key: \.height, range: 0.3...1.5, step: 0.01),
        Row(name: "Blur", key: \.blur, range: 10...200, step: 1),
        Row(name: "Saturation", key: \.saturation, range: 0...3, step: 0.05),
        Row(name: "Peak", key: \.peak, range: 0...1.5, step: 0.01),
        Row(name: "Rest", key: \.rest, range: 0...1.5, step: 0.01),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                let row = rows[i]
                HStack(spacing: 10) {
                    Text(row.name).frame(width: 74, alignment: .leading)
                    Slider(value: Binding(
                        get: { Double(look[keyPath: row.key]) },
                        set: { look[keyPath: row.key] = CGFloat(($0 / row.step).rounded() * row.step) }
                    ), in: row.range)
                    Text(String(format: row.step < 1 ? "%.2f" : "%.0f", Double(look[keyPath: row.key])))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            HStack(spacing: 6) {
                Button("Replay") { HeroView.shown?.replay() }
                    .buttonStyle(.yab(.primary, .small))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(look.line, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    ZStack { Text("Copied").hidden(); Text(copied ? "Copied" : "Copy") }
                }
                .buttonStyle(.yab(.secondary, .small))
                Button("Reset") { look = Glass.LightLook() }
                    .buttonStyle(.yab(.quiet, .small))
            }
            Text(look.line)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .padding(16)
        .frame(width: 360)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: look) { _, new in
            Glass.look = new
            HeroView.shown?.relight()
        }
    }
}
