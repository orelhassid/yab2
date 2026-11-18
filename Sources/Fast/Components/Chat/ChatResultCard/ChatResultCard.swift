import AppKit
import SwiftUI
import SyncKit

// What a turn made, as a card under its answer (spec 1SSTkJC2, "Result
// cards"): the pages it found, a comparison, an event, a reminder, a watch,
// a routine, a folder of tabs. The tool that made the thing says it on a
// line of its result (ResultCard), so a card is never guessed from the
// answer's words. Each card is CardFrame's, as wide as what it holds up to
// 356, with one small button at most, on its right; rows are at least 32
// high and lit with ink 0.04 under the pointer. Focused, ↑↓ walk a card's
// rows and ↩ opens one.

/// A turn's cards, one under another. With nothing said before them they
/// grow out of the typing capsule; under an answer they fade up 6.
struct ChatResultCards: View {
    let browser: Browser
    let items: [ChatItem]
    /// Nothing was said before them in the turn.
    var grow = false
    @Environment(\.accessibilityReduceMotion) private var still

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items) { item in
                if let card = item.resultCard {
                    ChatResultCard(browser: browser, card: card)
                        .transition(still ? .identity : grow ? ResultCardArrival.grow : ResultCardArrival.rise)
                }
            }
        }
    }
}

/// How a card comes: out of the capsule's place, on the reshape curve,
/// or up 6 under the words over 0.22 s. It goes at once.
enum ResultCardArrival {
    static let grow = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .scale(scale: 0.4, anchor: .bottomLeading)).animation(Motion.reshape),
        removal: .identity)
    static let rise = AnyTransition.asymmetric(
        insertion: .opacity.combined(with: .offset(y: 6)).animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.22)),
        removal: .identity)
}

struct ChatResultCard: View {
    /// Nil in a picture of it, where nothing opens.
    let browser: Browser?
    let card: ResultCard

    /// The widest a card stands, its inset in.
    static let most: CGFloat = 356
    /// A row's own padding, and the least it stands.
    static let rowHigh: CGFloat = 32

    @FocusState private var focused: Bool
    /// The row ↑↓ lit while the card is focused.
    @State private var lit = 0
    @ObservedObject private var watches = PageWatches.shared
    @ObservedObject private var routines = Routines.shared

    var body: some View {
        framed
            .focusable()
            .focused($focused)
            .focusEffectDisabled()
            .onKeyPress(.downArrow) { step(1) }
            .onKeyPress(.upArrow) { step(-1) }
            .onKeyPress(.return) {
                open(lit, behind: false)
                return .handled
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.words(card))
    }

    @ViewBuilder private var framed: some View {
        switch card.kind {
        case .links, .folder:
            Hug(most: Self.most - 2 * CardFrame.rows) { rows }
                .restingCardFrame(inset: CardFrame.rows)
        case .table:
            Hug(most: Self.most - 2 * CardFrame.rows) {
                ViewThatFits(in: .horizontal) {
                    table.fixedSize(horizontal: true, vertical: false)
                    stacked
                }
            }
            .restingCardFrame(inset: CardFrame.rows)
        case .event, .promise, .watch, .routine:
            Hug(most: Self.most - 2 * CardFrame.inset) { line }
                .restingCardFrame()
                .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .onTapGesture { open(0, behind: NSEvent.modifierFlags.contains(.command)) }
        }
    }

    // MARK: rows: links and a folder

    private var count: Int {
        switch card.kind {
        case .links, .table: card.rows?.count ?? 0
        case .folder: (card.rows?.count ?? 0) + 1
        default: 1
        }
    }

    private func step(_ by: Int) -> KeyPress.Result {
        guard count > 1 else { return .ignored }
        lit = max(0, min(count - 1, lit + by))
        return .handled
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if card.kind == .folder {
                ResultRow(lit: focused && lit == 0, open: { open(0, behind: $0) }) {
                    HStack(spacing: 10) {
                        PenTileView(page: .liveFolders, side: 28)
                        Text(card.title.isEmpty ? "Folder" : card.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 16)
                        Text("in your sidebar")
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }
            let first = card.kind == .folder ? 1 : 0
            ForEach(Array((card.rows ?? []).enumerated()), id: \.offset) { index, row in
                ResultRow(lit: focused && lit == index + first, open: { open(index + first, behind: $0) }) {
                    HStack(spacing: 10) {
                        SiteMark(host: row.site ?? ResultCard.host(row.url) ?? "", size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(.system(size: 13, weight: card.kind == .links ? .medium : .regular))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            if card.kind == .links, !ResultCard.under(row).isEmpty {
                                Text(ResultCard.under(row))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(Palette.muted)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: table

    /// Which columns hold numbers: tabular, to the right, heavier.
    private var numbers: [Bool] {
        let all = card.rows ?? []
        let width = all.map { $0.cells?.count ?? 0 }.max() ?? 0
        return (0..<width).map { column in
            all.allSatisfy { row in column < (row.cells?.count ?? 0) && Self.numeric(row.cells![column]) }
        }
    }

    private var table: some View {
        let all = card.rows ?? []
        let numbers = numbers
        return Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(Array(all.enumerated()), id: \.offset) { index, row in
                let on = card.lit == index || (focused && lit == index)
                GridRow(alignment: .center) {
                    HStack(spacing: 8) {
                        SiteMark(host: row.site ?? ResultCard.host(row.url) ?? "", size: 20)
                        Text(row.title).foregroundStyle(Palette.ink).lineLimit(1)
                    }
                    .cell(on: on, edge: .leading, last: numbers.isEmpty)
                    ForEach(numbers.indices, id: \.self) { column in
                        let words = column < (row.cells?.count ?? 0) ? row.cells![column] : ""
                        Text(words)
                            .fontWeight(numbers[column] ? .semibold : .regular)
                            .foregroundStyle(numbers[column] ? Palette.ink : Palette.muted)
                            .lineLimit(1)
                            .gridColumnAlignment(.trailing)
                            .cell(on: on, edge: column == numbers.count - 1 ? .trailing : nil, last: false, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { open(index, behind: NSEvent.modifierFlags.contains(.command)) }
            }
        }
        .font(.system(size: 13))
        .monospacedDigit()
    }

    /// Wider than a card: a row each, its cells a line under its title.
    private var stacked: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array((card.rows ?? []).enumerated()), id: \.offset) { index, row in
                ResultRow(lit: card.lit == index || (focused && lit == index), open: { open(index, behind: $0) }) {
                    HStack(alignment: .top, spacing: 10) {
                        SiteMark(host: row.site ?? ResultCard.host(row.url) ?? "", size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text((row.cells ?? []).joined(separator: " \u{00B7} "))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// "$195.00", "4.5", "−12%", "1,299": a number as a cell writes one.
    static func numeric(_ cell: String) -> Bool {
        cell.trimmingCharacters(in: .whitespaces).range(of: #"^[$€£¥₽]?\s?[-+−]?[$€£¥₽]?\d[\d,.\s]*(%|[kKmM]|\s?(USD|EUR|GBP))?$"#,
                                                         options: .regularExpression) != nil
    }

    // MARK: one line: event, promise, watch, routine

    @ViewBuilder private var line: some View {
        HStack(spacing: CardFrame.wellGap) {
            switch card.kind {
            case .event:
                DateTile(at: card.at.map { Date(timeIntervalSince1970: $0) })
                two(card.title, [card.hours(), card.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " \u{00B7} "))
            case .promise:
                PenTileView(page: .mail, side: 28)
                promise
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            case .watch:
                PenTileView(symbol: "watch", tint: PenArt.watchColor, side: 28)
                let now = watchNow
                VStack(alignment: .leading, spacing: 1) {
                    Text("Watching: " + card.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if let now {
                        Text("Now " + now + (card.site.map { " on " + $0 } ?? ""))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .monospacedDigit()
                            .lineLimit(1)
                            .contentTransition(.numericText())
                            .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.4), value: now)
                    }
                }
            case .routine:
                PenTileView(page: .agentRoutines, side: 28)
                let routine = routines.all.first { $0.id == card.ref }
                two(routine.map { Routines.say($0.when) } ?? card.title, routineLine(routine))
                if let routine {
                    Button(routine.off == true ? "Resume" : "Pause") { pause(routine) }
                        .buttonStyle(.yab(.secondary, .small))
                }
            default:
                EmptyView()
            }
        }
    }

    private func two(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
    }

    /// "Back in your inbox **Thursday** if Tim hasn't answered".
    private var promise: Text {
        guard let at = card.at else { return Text(card.promise()) }
        let day = ResultCard.day(Date(timeIntervalSince1970: at))
        let who = card.title.isEmpty ? "nobody" : card.title
        return Text("Back in your inbox ") + Text(day).fontWeight(.semibold) + Text(" if \(who) hasn\u{2019}t answered")
    }

    /// What the watched page says now: Yab's last read, else the card's.
    private var watchNow: String? {
        let read = watches.all.first { $0.id == card.ref }?.value
        return [read, card.value].compactMap { $0 }.first { !$0.isEmpty }
    }

    private func routineLine(_ routine: Routine?) -> String {
        guard let routine else { return card.detail ?? "" }
        if routine.off == true { return "Paused" }
        guard let next = Routines.next(routine, after: Date()) else { return card.detail ?? "" }
        return "Next: " + Routines.stamp(next)
    }

    private func pause(_ routine: Routine) {
        var changed = routine
        changed.off = routine.off == true ? nil : true
        _ = Routines.shared.put(changed)
    }

    // MARK: opening

    /// Row `index` opened: a page in a tab beside yours (⌘: behind), a
    /// folder's tab brought up, the folder itself shown in the sidebar.
    private func open(_ index: Int, behind: Bool) {
        guard let browser else { return }
        switch card.kind {
        case .links, .table:
            guard let rows = card.rows, rows.indices.contains(index) else { return }
            page(rows[index].url, behind: behind, in: browser)
        case .folder:
            if index == 0 {
                if let folder = Folders.shared.folder(card.ref ?? ""), !Folders.shared.isOpen(folder.id) { Folders.shared.toggle(folder.id) }
                return
            }
            guard let rows = card.rows, rows.indices.contains(index - 1) else { return }
            let row = rows[index - 1]
            if let tab = browser.everyTab.first(where: { $0.id.uuidString == row.tab }) { browser.select(tab) } else { page(row.url, behind: behind, in: browser) }
        case .event, .watch:
            page(card.url, behind: behind, in: browser)
        case .promise, .routine:
            break
        }
    }

    private func page(_ address: String?, behind: Bool, in browser: Browser) {
        guard let address, let url = URL(string: address), url.scheme?.hasPrefix("http") == true else { return }
        _ = browser.open(url, foreground: !behind, from: browser.active)
    }

    // MARK: words

    /// The card in words: what the chat's text says of it, and VoiceOver.
    static func words(_ card: ResultCard) -> String {
        let rows = card.rows ?? []
        switch card.kind {
        case .links:
            return rows.map(\.title).joined(separator: "; ")
        case .table:
            return rows.map { ([$0.title] + ($0.cells ?? [])).joined(separator: ", ") }.joined(separator: "; ")
        case .event:
            return [card.title, card.hours(), card.detail].compactMap { $0 }.joined(separator: ", ")
        case .promise:
            return card.promise()
        case .watch:
            return "Watching: " + card.title + (card.value.map { ", now " + $0 } ?? "")
        case .routine:
            return [card.title, card.detail].compactMap { $0 }.joined(separator: ", ")
        case .folder:
            return card.title + ": " + rows.map(\.title).joined(separator: "; ")
        }
    }
}

/// A row of a card: 6 by 8 in, at least 32 high, lit with ink under the
/// pointer and when ↑↓ reach it. A click opens it, ⌘-click behind.
struct ResultRow<Content: View>: View {
    let lit: Bool
    let open: (_ behind: Bool) -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false

    var body: some View {
        content
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(minHeight: ChatResultCard.rowHigh)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.ink.opacity(lit ? 0.07 : hovering ? 0.04 : 0),
                        in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { open(NSEvent.modifierFlags.contains(.command)) }
    }
}

private extension View {
    /// A table's cell: 8 by 10 in, its row's light under it, rounded at
    /// the row's two ends.
    func cell(on: Bool, edge: HorizontalEdge?, last: Bool, alignment: Alignment = .leading) -> some View {
        let leading: CGFloat = edge == .leading || last ? Radius.control : 0
        let trailing: CGFloat = edge == .trailing || last ? Radius.control : 0
        return padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .background(Palette.ink.opacity(on ? 0.05 : 0),
                        in: UnevenRoundedRectangle(topLeadingRadius: leading, bottomLeadingRadius: leading,
                                                   bottomTrailingRadius: trailing, topTrailingRadius: trailing, style: .continuous))
    }
}

/// An event's day: the weekday on a red band over the date, 34 by 36.
private struct DateTile: View {
    let at: Date?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        VStack(spacing: 0) {
            Text(at.map { Self.say($0, "EEE").uppercased() } ?? "")
                .font(.system(size: 8, weight: .bold)) // design: a calendar tile's weekday band, as Calendar's icon prints it
                .tracking(0.3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 11)
                .background(Color(red: 0.90, green: 0.28, blue: 0.30))
            Text(at.map { Self.say($0, "d") } ?? "")
                .font(.system(size: 16, weight: .semibold)) // design: a calendar tile's date, as Calendar's icon prints it
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 34, height: 36)
        .background(Palette.ground)
        .clipShape(shape)
        .overlay(shape.stroke(Palette.ink.opacity(0.08), lineWidth: 1))
    }

    static func say(_ date: Date, _ pattern: String) -> String {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US")
        format.dateFormat = pattern
        return format.string(from: date)
    }
}

/// As wide as what it holds, up to `most`: the rows of a card all as wide
/// as its widest, and none past the card's widest.
struct Hug<Content: View>: View {
    let most: CGFloat
    @ViewBuilder let content: Content

    var body: some View { HugLayout(most: most) { content } }
}

private struct HugLayout: Layout {
    let most: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(child.sizeThatFits(.unspecified).width, most, proposal.width ?? .infinity)
        return child.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
