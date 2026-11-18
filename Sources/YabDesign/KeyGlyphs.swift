import SwiftUI

/// A shortcut, the one way it is written anywhere in the app: the address
/// field's rows, the agent's dock, the buttons on a card or a question, a
/// notice, a key cap. Each mark, ⌘ ⇧ ⌥ ⌃ ↩ ⌫ ⇥, is a line drawing from
/// KeyArt, the same one the pages draw with KeysWeb, at the letters' cap
/// height and weight; the letters and a key named in a word, esc, space,
/// are the system font at medium. The font's own marks sat at heights of
/// their own, ↩ high and ⌘ low, and beside the pages' drawn ones they read
/// as crooked.
public struct KeyGlyphs: View {
    let keys: String
    /// The size its letters are set at; the marks are drawn to match them.
    var size: CGFloat = 13
    /// Its ink. nil takes whatever it sits in, a button's label say.
    var tint: Color? = Palette.muted
    /// How strong it stands: 0.6 beside a button's words.
    var rest: Double = 1
    private let plate: Color?

    public init(keys: String, size: CGFloat = 13, tint: Color? = Palette.muted, rest: Double = 1, plate: Color? = nil) {
        self.keys = keys
        self.size = size
        self.tint = tint
        self.rest = rest
        self.plate = plate
    }

    /// A mark's square beside letters of `size`, as the pages have 12 to
    /// 11.5.
    static func side(_ size: CGFloat) -> CGFloat { (size * 12 / 11.5).rounded() }

    /// The cap height of the words beside keys of `size`, a step larger.
    static func capHeight(_ size: CGFloat) -> CGFloat {
        NSFont.systemFont(ofSize: size * 12 / 11).capHeight
    }

    /// Each key on a plate of its ink, faint, so a shortcut reads as keys at a
    /// glance: as tall as the letters with room round them, or, on a
    /// button, as tall as the button less its inset (KeyPlate). One corner
    /// for every plate, a tag's.
    private struct Plate: ViewModifier {
        let size: CGFloat
        /// A mark's plate is square, as wide as it is tall; letters (esc)
        /// take the room they need.
        let square: Bool
        let fill: Color?
        @Environment(\.keyPlate) private var button

        func body(content: Content) -> some View {
            let height = button?.height ?? (size * 1.45).rounded()
            content
                .padding(.horizontal, square ? 0 : button == nil ? (size * 0.28).rounded() : ((height - KeyGlyphs.side(size)) / 2).rounded())
                .frame(minWidth: height, maxWidth: square ? height : nil, minHeight: height)
                .background {
                    let shape = RoundedRectangle(cornerRadius: button?.corner ?? Radius.small, style: .continuous)
                    if let fill { shape.fill(fill) } else { shape.fill(.quaternary) }
                }
        }
    }

    /// On a button, the keys pulled out to the button's inset, so the last
    /// plate is as far from the trailing edge as from the top and bottom.
    private struct Edge: ViewModifier {
        @Environment(\.keyPlate) private var button

        func body(content: Content) -> some View {
            if let button {
                content
                    .padding(.leading, button.lead)
                    .padding(.trailing, -button.pull) // design: the gap before the keys grows by lead, the keys reach into the trailing padding by pull
                    .preference(key: KeyLead.self, value: button.lead)
            } else {
                content
            }
        }
    }

    /// Its own ink, or none, so it takes the ink of what it sits in: set to
    /// `.foreground`, the keys on a red button's white words came out black.
    private struct Ink: ViewModifier {
        let tint: Color?
        func body(content: Content) -> some View {
            if let tint { content.foregroundStyle(tint) } else { content }
        }
    }

    /// The keys in runs: a mark alone, or letters together, esc as one word.
    private var runs: [(mark: Character?, text: String)] {
        var out: [(Character?, String)] = []
        for key in keys.replacingOccurrences(of: "⏎", with: "↩") {
            if KeyArt.paths[key] != nil {
                out.append((key, ""))
            } else if let last = out.last, last.0 == nil {
                out[out.count - 1].1 += String(key)
            } else {
                out.append((nil, String(key)))
            }
        }
        return out
    }

    public var body: some View {
        HStack(spacing: (2 * size / 11.5).rounded(.down)) {
            ForEach(Array(runs.enumerated()), id: \.offset) { _, run in
                Group {
                    if let mark = run.mark, let art = KeyArt.image(mark) {
                        Image(nsImage: art)
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: Self.side(size), height: Self.side(size))
                    } else {
                        Text(verbatim: run.text)
                            .font(.system(size: size, weight: .medium))
                    }
                }
                .modifier(Plate(size: size, square: run.mark != nil || run.text.count == 1, fill: plate))
            }
        }
        .modifier(Ink(tint: tint))
        .opacity(rest)
        .fixedSize()
        // On a line of words, the plates' middle on the letters' middle: a
        // mark has no baseline of its own, so it stood on theirs, all above.
        .alignmentGuide(.firstTextBaseline) { $0.height / 2 + Self.capHeight(size) / 2 }
        .alignmentGuide(.lastTextBaseline) { $0.height / 2 + Self.capHeight(size) / 2 }
        .modifier(Edge())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys)
    }
}
