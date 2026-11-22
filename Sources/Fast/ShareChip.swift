import SwiftUI
import AppKit

// What a window says of a share going on in it, and where (docs/screen-share.md).
// The words go where Yab already has room for them: the address band, the end
// of the row of tabs, the tab's own row in the column. With none of those in
// view a small tag hangs from the top of the page (ShareOutline). Until
// 2026-11-01 a pill stood over the page, on the site's own search.

/// Where the window has room for the words.
enum ShareSpot { case band, strip, row, tag }

extension Browser {
    var shareSpot: ShareSpot {
        if barShown { return .band }
        if prefs.sidebar { return prefs.sideShut ? .tag : .row }
        return prefs.stripShut ? .tag : .strip
    }

    /// The page runs to the screen's edge: no card, no corners (ContentView.laid).
    var pageSquare: Bool { prefs.pageLayout == .edgeToEdge || (fullScreen && tabsAway && !pageShared) }
}

/// One share, as a place in the window says it.
struct ShareStatus: Equatable {
    var words: String
    var recorded = false
    var paused = false
    /// Nil for the system picker's share, stopped through the call's tab.
    var session: String?
    /// The tab shown, for a click on the words from anywhere else.
    var shown: Tab.ID?
    /// The tab in front can take over: Share Instead.
    var instead: Tab.ID?

    var tint: Color { recorded ? .red : Share.tint }
}

extension Share {
    /// What the band over `tab` says, if anything: the tab shown and the
    /// call each say their side, and a share with nothing to look at in this
    /// window is said over whatever is in front.
    func status(in browser: Browser, over tab: Tab?) -> ShareStatus? {
        guard let tab else { return nil }
        let front = tab.id == browser.activeID
        guard let session = sessions.values.sorted(by: { $0.id < $1.id }).first(where: { $0.browser === browser }) else {
            guard front, browser.call?.presentingScreen == true else { return nil }
            return ShareStatus(words: "Presenting Screen")
        }
        let recorded = session.recorder != nil
        guard case .tab = session.source else {
            guard front else { return nil }
            var kind = "Screen"
            if case .window = session.source { kind = "Window" }
            return ShareStatus(words: (recorded ? "Recording " : "Presenting ") + kind, recorded: recorded, session: session.id)
        }
        guard let shown = session.shown else { return nil }
        // Off screen the picture stands still on its last frame: people
        // see that frame, so it is said, wherever you are.
        if session.paused {
            guard front else { return nil }
            return ShareStatus(words: "Paused: \(shown.rowLabel)", recorded: recorded, paused: true, session: session.id,
                               shown: shown.id, instead: switchable(to: tab) == nil ? nil : tab.id)
        }
        if tab === shown {
            let name = session.recorder ?? Self.callName(of: session.caller)
            return ShareStatus(words: (recorded ? "Recorded by " : "Shown in ") + name, recorded: recorded, session: session.id)
        }
        if tab === session.caller {
            return ShareStatus(words: (recorded ? "Recording " : "Presenting ") + shown.rowLabel, recorded: recorded, session: session.id, shown: shown.id)
        }
        return nil
    }

    func stop(_ status: ShareStatus, in browser: Browser?) {
        if let id = status.session { end(id, tellPage: true) } else { browser?.call?.stopSharing() }
    }

    func shareInstead(_ status: ShareStatus, in browser: Browser?) {
        guard let id = status.session, let session = sessions[id],
              let tab = browser?.everyTab.first(where: { $0.id == status.instead }) else { return }
        switchShown(session, to: tab)
    }

    func look(at status: ShareStatus, in browser: Browser?) {
        guard let tab = browser?.everyTab.first(where: { $0.id == status.shown }) else { return }
        browser?.select(tab)
    }

    /// A tab's Stop in the column, while nothing else in the window says it:
    /// on the tab in front, on a tab standing still, and under the pointer.
    func stopsInRow(_ tab: Tab, hovering: Bool) -> Bool {
        guard let browser = sessions.values.first(where: { $0.caller === tab || $0.shown === tab })?.browser else { return false }
        return browser.shareSpot == .row && (hovering || tab.id == browser.activeID || paused(tab))
    }

    /// The words' state of this share.
    func fold(_ status: ShareStatus) -> ShareFold {
        status.session.flatMap { sessions[$0]?.fold } ?? systemFold
    }

    /// Whatever this tab is part of, ended.
    func stopAll(of tab: Tab) {
        if tab.sharing { return stop(caller: tab) }
        for session in sessions.values where session.shown === tab { end(session.id, tellPage: true) }
    }

    /// The shown tab is off screen, its picture standing still.
    func paused(_ tab: Tab) -> Bool { showing(tab)?.paused == true }
}

/// Whether a share's words are out. They are for the moment you reach for
/// them: the frame says the rest. Out by themselves as a share starts, gone
/// 2.5 s later; out after 80 ms under the pointer, so one passing on its way
/// to the site's menu opens nothing; gone 0.5 s after it leaves. The tag and
/// the chip are one share's, so they hold this together.
@MainActor
final class ShareFold: ObservableObject {
    @Published private(set) var open = false
    /// The tag's panel takes the open size before the shape grows in it,
    /// and its small one after the shape has gathered.
    var opening: () -> Void = {}
    var closed: () -> Void = {}
    private var pointers = 0
    private var coming: DispatchWorkItem?
    private var going: DispatchWorkItem?
    static let intent: TimeInterval = 0.08
    static let shown: TimeInterval = 2.5
    static let held: TimeInterval = 0.5
    /// `Motion.depart`'s length, and a frame.
    static let gathered: TimeInterval = 0.17

    func announce() {
        unfold()
        foldLater(after: Self.shown)
    }

    func hover(_ on: Bool) {
        pointers = max(0, pointers + (on ? 1 : -1))
        if pointers > 0 {
            going?.cancel()
            guard !open else { return }
            let work = DispatchWorkItem { [weak self] in self?.unfold() }
            coming = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.intent, execute: work)
        } else {
            coming?.cancel()
            if open { foldLater(after: Self.held) }
        }
    }

    /// What was under the pointer went away with it.
    func left() {
        pointers = 0
        coming?.cancel()
        if open { foldLater(after: Self.held) }
    }

    private func unfold() {
        going?.cancel()
        guard !open else { return }
        opening()
        open = true
    }

    private func foldLater(after delay: TimeInterval) {
        going?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pointers == 0 else { return }
            self.open = false
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.gathered) { [weak self] in
                if self?.open == false { self?.closed() }
            }
        }
        going = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}

/// The status in the band or at the row's end: at rest its mark, Paused
/// beside it while the picture stands still, and out of it, leftwards over
/// whatever is there, the words and Stop. Over: the site and the doors stay
/// where they are.
struct ShareChip: View {
    @ObservedObject var browser: Browser
    let tab: Tab?
    @ObservedObject private var share = Share.shared

    var body: some View {
        if let status = share.status(in: browser, over: tab) {
            ShareChipFace(browser: browser, status: status, fold: share.fold(status))
        }
    }
}

private struct ShareChipFace: View {
    let browser: Browser
    let status: ShareStatus
    @ObservedObject var fold: ShareFold
    @ObservedObject private var share = Share.shared
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var full: CGFloat = 0

    private var rest: some View {
        HStack(spacing: 6) {
            Symbol("screen.share", size: 13)
                .foregroundStyle(status.tint)
            if status.paused {
                Text("Paused")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.strong(on: tone))
                    .fixedSize()
            }
        }
        .padding(.horizontal, status.paused ? 8 : 6.5) // design: the bare mark centered in the 26 square
        .frame(height: 26)
        .background(status.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    private var plate: some View {
        HStack(spacing: 6) {
            Symbol("screen.share", size: 13)
                .foregroundStyle(status.tint)
            Text(status.words)
                .font(.system(size: 12))
                .foregroundStyle(Palette.strong(on: tone))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
                .fixedSize()
                .padding(.trailing, 2)
                .contentShape(Rectangle())
                .onTapGesture { share.look(at: status, in: browser) }
            if status.instead != nil {
                Button("Share Instead") { share.shareInstead(status, in: browser) }
                    .buttonStyle(.yab(.secondary, .small))
            }
            Button("Stop") { share.stop(status, in: browser) }
                .buttonStyle(.yab(.quiet, .small))
        }
        .padding(.leading, 8) // design: the mark's side has air, Stop sits in the plate's end
        .padding(.trailing, 1)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(tone?.color ?? Palette.ground)
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(status.tint.opacity(0.13))
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { full = $0 }
    }

    var body: some View {
        rest
            .fixedSize()
            .onHover { fold.hover($0) }
            .onDisappear { fold.left() }
            .overlay(alignment: .trailing) {
                plate
                    .opacity(fold.open ? 1 : 0)
                    .mask(alignment: .trailing) {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .frame(width: fold.open || still ? nil : 26)
                    }
                    .allowsHitTesting(fold.open)
                    .onHover { fold.hover($0) }
            }
            .animation(still ? Motion.quick : fold.open ? Motion.arrive : Motion.depart, value: fold.open)
    }
}

/// What the tag's panel holds, and the sizes it was measured at.
@MainActor
final class ShareTagWords: ObservableObject {
    @Published var status: ShareStatus?
    var open = CGSize.zero
    var standing = CGSize.zero

    func say(_ next: ShareStatus?) {
        guard next != status else { return }
        status = next
        guard let next else { return }
        open = NSHostingView(rootView: ShareTagOpen(status: next, browser: { nil })).fittingSize
        standing = NSHostingView(rootView: ShareTagPaused()).fittingSize
    }
}

/// The words and Stop, as far out as they go.
struct ShareTagOpen: View {
    let status: ShareStatus
    let browser: () -> Browser?
    static let height: CGFloat = 28

    var body: some View {
        HStack(spacing: 6) {
            Symbol("screen.share", size: 13)
            Text(status.words)
                .font(.system(size: 12))
                .lineLimit(1)
                .frame(maxWidth: 240, alignment: .leading)
                .fixedSize()
                .padding(.trailing, 2)
            if status.instead != nil {
                Button("Share Instead") { Share.shared.shareInstead(status, in: browser()) }
                    .buttonStyle(.yab(.secondary, .small, surface: .dark))
            }
            Button("Stop") { Share.shared.stop(status, in: browser()) }
                .buttonStyle(.yab(.secondary, .small, surface: .dark))
        }
        .foregroundStyle(.white)
        .padding(.leading, 8) // design: Stop sits in the tag's end, on its curve
        .padding(.trailing, 2)
        .frame(height: Self.height)
        .fixedSize()
    }
}

/// A picture standing still says so at rest: people see that frame.
struct ShareTagPaused: View {
    var body: some View {
        HStack(spacing: 6) {
            Symbol("screen.share", size: 13)
            Text("Paused").font(.system(size: 12))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .fixedSize()
    }
}

/// Hung from the top of the page, on the frame, when the window has nowhere
/// else to say it: at rest a thread, the frame thicker for 44 points, and
/// out of it, on the same curve as the column, the words and Stop. Its own
/// small panel, kept out of every share; the shape grows inside it.
struct ShareTag: View {
    @ObservedObject var words: ShareTagWords
    @ObservedObject var fold: ShareFold
    let browser: () -> Browser?
    @Environment(\.accessibilityReduceMotion) private var still
    static let thread = CGSize(width: 44, height: 4)
    /// Where the pointer finds a thread 4 points tall.
    static let reach = CGSize(width: 200, height: 18)

    var body: some View {
        if let status = words.status {
            let open = fold.open
            let size = open ? words.open : status.paused ? words.standing : Self.thread
            ZStack {
                ShareTagOpen(status: status, browser: browser)
                    .opacity(open ? 1 : 0)
                    .animation(open ? Motion.quick.delay(0.06) : Motion.quick, value: open)
                if status.paused {
                    ShareTagPaused()
                        .opacity(open ? 0 : 1)
                }
            }
            .frame(width: size.width, height: size.height)
            .background(open || !status.paused ? status.tint : Color.gray)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: open || status.paused ? Radius.surface : 3, // design: a thread's end
                                              bottomTrailingRadius: open || status.paused ? Radius.surface : 3, // design: a thread's end
                                              style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .contentShape(Rectangle())
            .onHover { fold.hover($0) }
            .animation(still ? Motion.quick : open ? Motion.arrive : Motion.depart, value: open)
        }
    }
}
