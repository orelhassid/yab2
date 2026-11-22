import SwiftUI

/// A tab's name that runs to the tab's edge and, when it is longer than
/// that, goes out into nothing there rather than ending on an ellipsis.
///
/// The letters themselves turn transparent, nothing is laid over them, so it
/// is right on whatever is behind: the tone, the open tab's gray, the hover,
/// the reading gray filling from the left.
///
/// Painted rather than masked. A mask, or a gradient given to a `Text` as
/// its color, is a Core Animation mask in the column: one offscreen pass
/// per row every frame anything there moves, the column sliding in, a
/// scroll. Painted, the name and its fade are one picture, made when the
/// name, its color or its width change and otherwise only composited;
/// measured against the mask it also costs the main thread less, and next
/// to a plain truncated `Text` about the same (the ellipsis is a CoreText
/// layout of its own every time the width changes).
///
/// `clear` is how much of the end to keep empty, for whatever the slot there
/// is showing; the fade moves in to make room for it rather than the name
/// being cut shorter.
///
/// Under the pointer a tab's name changes twice, its ink darker and its fade
/// moved in for the cross, and neither repaints it. Both looks are painted
/// once, the one under the pointer beneath and the one at rest over it, and
/// the pointer only hides the one on top. A name painted again for every
/// frame of a slide was a new surface each frame, and letting go of each one
/// waits on the window server: with the window server busy, that wait is the
/// main thread's, and the pointer on a tab froze the window. The pointer's
/// look comes in the frame the tab lights, as the cross does, so the cross
/// never stands on letters still going.
struct FadingTitle: View, Equatable {
    static let inspectorSource = UIInspectorSource()
    let text: String
    let font: Font
    /// How it looks at rest.
    let rest: Look
    /// At rest with something in the slot at the tab's end, the ring, the
    /// speaker, an agent's face, when that is any different.
    var busy: Look?
    /// And under the pointer, when that is any different.
    var open: Look?
    /// The slot has something in it.
    var slotted = false
    var opened = false
    /// The looks that have been shown: one never needed is never painted.
    @State private var needed = Needed()

    struct Needed: Equatable {
        var open = false
        var busy = false
    }

    struct Look: Equatable {
        var color: Color
        var clear: CGFloat = 0
        /// How long the fade is at the edge; shorter when it has moved in for
        /// the cross, so the name gives up no more than it has to.
        var fade: CGFloat = 40
        /// Struck through: a routine's folder's page that has gone.
        var strike = false
    }

    init(text: String, font: Font, rest: Look, busy: Look? = nil, open: Look? = nil, slotted: Bool = false, opened: Bool = false) {
        self.text = text
        self.font = font
        self.rest = rest
        self.busy = busy == rest ? nil : busy
        self.open = open == rest ? nil : open
        self.slotted = slotted
        self.opened = opened
    }

    init(text: String, font: Font, color: Color, clear: CGFloat = 0, fade: CGFloat = 40) {
        self.init(text: text, font: font, rest: Look(color: color, clear: clear, fade: fade))
    }

    static func == (a: FadingTitle, b: FadingTitle) -> Bool {
        a.text == b.text && a.font == b.font && a.rest == b.rest && a.busy == b.busy && a.open == b.open
            && a.slotted == b.slotted && a.opened == b.opened
    }

    var body: some View {
        // A line's height, from a space: laid out once, whatever the width.
        Text(" ")
            .font(font)
            .hidden()
            .frame(minWidth: 0, maxWidth: .infinity)
            .overlay {
                // Every look painted once and kept: going from one to another
                // is only opacity. A look changed in place paints the Canvas
                // anew, and dropping the old surface makes the next commit wait
                // on the window server (RenderBox's prune, waitForCommitId):
                // with the ring coming and going at every page load, that was
                // up to a few hundred ms of main thread per load on a busy Mac.
                // The slot's comings and goings are state, and flip at once,
                // and so do the pointer's.
                // Each look is painted from the first time it is needed and
                // kept from then on: a name in the strip is painted again at
                // every width its pill passes through as the others make
                // room, and three looks painted for each, two of them never
                // seen, made that three times the work.
                ZStack {
                    if let open, !Narrow.inkLazy || opened || needed.open {
                        Ink(text: text, font: font, look: open).equatable()
                    }
                    let away = opened && open != nil
                    if let busy, !Narrow.inkLazy || slotted || needed.busy {
                        Ink(text: text, font: font, look: busy).equatable()
                            .opacity(away || !slotted ? 0 : 1)
                            .animation(nil, value: opened)
                    }
                    Ink(text: text, font: font, look: rest).equatable()
                        .opacity(away || (slotted && busy != nil) ? 0 : 1)
                        .animation(nil, value: opened)
                }
            }
            .onChange(of: opened, initial: true) { _, now in if now, !needed.open { needed.open = true } }
            .onChange(of: slotted, initial: true) { _, now in if now, !needed.busy { needed.busy = true } }
            .accessibilityElement()
            .accessibilityLabel(text)
    }
}

/// One look of the name, painted when the name, its ink or its width change
/// and otherwise only composited.
private struct Ink: View, Equatable {
    let text: String
    let font: Font
    let look: FadingTitle.Look
    /// The name laid out, kept while its letters, font and ink stay the
    /// same: a repaint at another width only draws it again.
    @State private var memo = InkMemo()

    init(text: String, font: Font, look: FadingTitle.Look) {
        self.text = text
        self.font = font
        self.look = look
    }

    static func ==(a: Ink, b: Ink) -> Bool { a.text == b.text && a.font == b.font && a.look == b.look }

    /// How much is taken away along the fade: eased at both ends, so it has
    /// no line where it starts and no stub of faint letter where it ends.
    private static let away = Gradient(stops: [(0, 0), (0.2, 0.08), (0.45, 0.38), (0.7, 0.72), (0.88, 0.93), (1, 1)]
        .map { Gradient.Stop(color: .black.opacity($0.1), location: $0.0) })

    var body: some View {
        Canvas { [memo, text, font, look] context, size in
            let laid = memo.laid(InkMemo.Key(text: text, font: font, color: look.color, strike: look.strike, height: size.height,
                                             scheme: context.environment.colorScheme,
                                             contrast: context.environment.colorSchemeContrast)) {
                let ink = context.resolve(Text(text).font(font).foregroundStyle(look.color).strikethrough(look.strike))
                return (ink, ink.measure(in: CGSize(width: CGFloat.infinity, height: size.height)).width)
            }
            let ink = laid.ink, natural = laid.natural
            // Repaints counted on a test run (evals/perf/bodies.py).
            MainActor.assumeIsolated { BodyMeter.tick("TitleFade.Ink.paint") }
            let middle = CGPoint(x: 0, y: size.height / 2)
            let end = max(0, size.width - look.clear)
            // Always keep the end slot clear. Core Text's measured advance
            // can be smaller than the painted glyphs on a tight tab.
            context.clip(to: Path(CGRect(x: 0, y: 0, width: end, height: size.height)))
            // A name that fits whole keeps every letter: the fade is only
            // as long as it needs to be for what doesn't fit, up to its full
            // length, so one that fits exactly isn't dimmed, and one a letter
            // too long fades over a few points, not forty.
            let length = min(look.fade, max(0, natural - end) * 2, end)
            guard length > 0.5 else {
                context.draw(ink, at: middle, anchor: .leading)
                return
            }
            context.drawLayer { layer in
                layer.draw(ink, at: middle, anchor: .leading)
                layer.blendMode = .destinationOut
                layer.fill(
                    Path(CGRect(x: end - length, y: 0, width: length, height: size.height)),
                    with: .linearGradient(Self.away, startPoint: CGPoint(x: end - length, y: 0), endPoint: CGPoint(x: end, y: 0)))
            }
        }
    }
}


/// One Ink's name as last resolved and measured. Resolving and measuring
/// were three quarters of a repaint (Text into attributes, a Core Text
/// line, its width), done again at every width of a pill's slide though
/// nothing about the letters had changed.
final class InkMemo: @unchecked Sendable {
    struct Key: Equatable {
        let text: String
        let font: Font
        let color: Color
        let strike: Bool
        let height: CGFloat
        let scheme: ColorScheme
        let contrast: ColorSchemeContrast
    }
    private var key: Key?
    private var kept: (ink: GraphicsContext.ResolvedText, natural: CGFloat)?

    func laid(_ key: Key, _ make: () -> (GraphicsContext.ResolvedText, CGFloat)) -> (ink: GraphicsContext.ResolvedText, natural: CGFloat) {
        if Narrow.inkMemo, let kept, self.key == key { return kept }
        let made = make()
        self.key = key
        kept = (made.0, made.1)
        return (made.0, made.1)
    }
}
