import SwiftUI
import AppKit
import Combine

// Where the welcome is, from its first frame to the page: the chapters on
// this Mac's path and the beats inside each, what was chosen on the way,
// and the one stage the parts are laid out on (WelcomeEngine).
//
// Continue walks a chapter's beats before it turns the chapter. Back walks
// back through the beats actually seen, never onto one that was passed
// over. The chapters are 1 to 6, fewer by path; Welcome and Finish are not
// chapters. Each chapter is its own file and says, for each of its beats,
// its words, its board of parts, how it plays and what its buttons do
// (WelcomeChapter); the stage asks the right one.
//
// Nothing on the stage is animated by SwiftUI: the frame's own SwiftUI
// (Welcome.swift) reads `words` and `dashes`, published once a beat, and
// the parts move on Core Animation.

// MARK: - a chapter

/// One chapter of the welcome, in a file of its own. Every requirement is
/// static: a chapter keeps nothing of its own but reads and writes the stage.
@MainActor
protocol WelcomeChapter {
    /// Its beats on the welcome's path now, in order; none when the path
    /// passes it over.
    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat]
    /// The frame's words and the footer's buttons for a beat.
    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords
    /// What is on the stage at a beat's phase, in stage points. The title,
    /// the sub and the sample marker are the stage's, from `words`.
    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard
    /// Arriving at a beat, before its first board: what it reads fresh.
    static func arrive(_ moment: WelcomeMoment, _ stage: WelcomeStage)
    /// The beat played from where it came, its phases one after another
    /// (`player.show`, `player.wait`, `player.type`). Called only going
    /// forward, with motion; otherwise the beat is shown at rest.
    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async
    /// A press of the primary or the quiet button: what it does, and where
    /// the welcome goes then.
    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn
}

extension WelcomeChapter {
    static func arrive(_ moment: WelcomeMoment, _ stage: WelcomeStage) {}
    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async { player.show() }
    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn { .next }
}

/// A beat as it is being shown.
struct WelcomeMoment: Equatable {
    var beat: WelcomeStage.Beat
    /// How far into its beat: the prototype's phases ("arrive", "press",
    /// "peek", "type", "run", "done", "fly"...), "rest" when it has settled.
    var phase = "rest"
    /// A phase's count: the step the agent is on while it works.
    var index = 0
    /// The beat before, going forward or back; nil on a jump or a refresh.
    var from: WelcomeStage.Beat?
    /// A new chapter: the words come after the parts, 0.30 later.
    var turn = false
    /// Came here by Continue (or a Skip), not by Back or a dash.
    var forward = true
    /// The window's size now, and so the stage's scale (Finish grows into it).
    var window = StageSpace.size
    var scale: CGFloat { StageSpace.scale(for: window) }
}

/// What the frame says and offers at a beat.
struct WelcomeWords: Equatable {
    enum Frame: Equatable {
        /// Welcome: the mark and the name in the middle, no header, Back or dashes.
        case welcome
        /// A chapter: the header, the title and sub, Back, the dashes, the footer.
        case chapter
        /// Finish: the frame gone, only the window-to-be.
        case finish
    }

    var frame: Frame = .chapter
    var title = ""
    var sub = ""
    /// Chapter 2's one line at 702: a recorded run on sample data.
    var marker = false
    /// The one button's words; nil when there is none.
    var primary: String? = "Continue"
    /// Under way: the press does nothing, the ↩ goes.
    var busy = false
    /// Not yet: shown at 0.45.
    var disabled = false
    /// The quiet button's words beside it; nil when the step has no way past.
    var quiet: String?
    /// A failure, said beside the button in words: no red, no icon.
    var failure: String?

    init(frame: Frame = .chapter, title: String = "", sub: String = "", marker: Bool = false, primary: String? = "Continue",
         busy: Bool = false, disabled: Bool = false, quiet: String? = nil, failure: String? = nil) {
        self.frame = frame
        self.title = title
        self.sub = sub
        self.marker = marker
        self.primary = primary
        self.busy = busy
        self.disabled = disabled
        self.quiet = quiet
        self.failure = failure
    }
}

enum WelcomeButton: Equatable { case primary, quiet }

/// Where a press takes the welcome.
enum WelcomeTurn: Equatable {
    /// The next beat on the path.
    case next
    /// Nowhere: something started (an install, a sign-in, macOS's question);
    /// the beat shows its new state.
    case stay
    /// A beat of its own.
    case go(WelcomeStage.Beat)
    /// The first beat of chapter n or after on the path: Skip, Later, Not Now.
    case chapter(Int)
    /// Finish: the parts become the window.
    case finish
}

/// The dashes' reading: one a chapter on the path, the current one filled
/// as far as its beats have gone.
struct WelcomeDashes: Equatable {
    var chapters: [Int] = []
    /// Index of the current chapter in `chapters`; `chapters.count` at Finish.
    var current = 0
    /// The current dash's fill, beat ÷ beats.
    var fill: CGFloat = 0
    /// A beat that plays on by itself (chapter 1): the fill it starts from,
    /// grown to `fill` over `run` seconds, once for the play `token`.
    var from: CGFloat = 0
    var run: Double = 0
    var token = 0
    /// That run held: the window not key.
    var paused = false
}

/// Look, held: the welcome shows it at once on the window-to-be and writes
/// it to prefs only before Finish's motion, never live under the overlay
/// (a page's width changing stalls the main thread for up to half a second).
struct WelcomeHeldLook: Equatable {
    var sidebar: Bool
    var tabsChosen = false
    var backdrop: Backdrop
    var swatch: Swatch
    var color: NSColor
    var grain: Double
    var transparency: Double
    /// What the look card adds, set in the welcome's Color too: the colors
    /// after the main one, Shift with tabs, the drawings and how strong.
    var colors: [String] = []
    var shift = false
    var drawings = ""
    var strength = LookDrawings.standard
    /// ⌘T's field: the small card, or the full box.
    var compactField = false

    init(sidebar: Bool = false, backdrop: Backdrop = .site, swatch: Swatch = .gray, color: NSColor = .gray, grain: Double = Grain.standard, transparency: Double = 0) {
        self.sidebar = sidebar
        self.backdrop = backdrop
        self.swatch = swatch
        self.color = color
        self.grain = grain
        self.transparency = BackdropTransparency.clamp(transparency)
    }

    @MainActor init(_ prefs: Preferences) {
        sidebar = prefs.sidebar
        backdrop = prefs.backdrop
        swatch = prefs.swatch
        color = prefs.backdropColor
        grain = prefs.grain
        transparency = prefs.backdropTransparency
        colors = prefs.backdropColors
        shift = prefs.lookShift
        drawings = prefs.lookDrawings
        strength = prefs.lookDrawingsStrength
        compactField = prefs.compactField
        // A first run offers the page edge to edge or on a color, never the
        // site's: it starts on a color, the default gray leaning to this
        // Mac's accent, the color itself picked on the next beat.
        if !prefs.welcomed {
            if backdrop == .site { backdrop = .color }
            if swatch == .gray {
                swatch = .custom
                color = Self.accentGray()
            }
        }
    }

    /// Gray with a tenth of the Mac's accent color in it.
    static func accentGray(_ accent: NSColor = .controlAccentColor) -> NSColor {
        let gray = Swatch.gray.color(dark: false, custom: .gray)
        return (accent.usingColorSpace(.sRGB) ?? accent).mixed(over: gray, 0.1)
    }

    mutating func adoptDefaultBrowser(_ bundle: String?, welcomed: Bool) {
        guard !welcomed, !tabsChosen, let side = DefaultBrowserImport.sidebar(for: bundle) else { return }
        sidebar = side
    }

    @MainActor func write(to prefs: Preferences) {
        if prefs.sidebar != sidebar { prefs.sidebar = sidebar }
        if prefs.backdrop != backdrop { prefs.backdrop = backdrop }
        if prefs.swatch != swatch { prefs.swatch = swatch }
        if prefs.backdropColor != color { prefs.backdropColor = color }
        if prefs.backdropTransparency != transparency { prefs.backdropTransparency = transparency }
        if prefs.grain != grain { prefs.grain = grain }
        if prefs.backdropColors != colors { prefs.backdropColors = colors }
        if prefs.lookShift != shift { prefs.lookShift = shift }
        if prefs.lookDrawings != drawings { prefs.lookDrawings = drawings }
        if prefs.lookDrawingsStrength != strength { prefs.lookDrawingsStrength = strength }
        if prefs.compactField != compactField { prefs.compactField = compactField }
    }
}

/// Every branch the welcome has, pretended, for the bench to reach any
/// state without installing, importing or asking macOS (final-spec §4, the
/// prototype's panel). nil: as this Mac really is. Each chapter reads the
/// ones about it.
struct WelcomePretend: Equatable {
    enum Agents: String { case none, claude, codex, both, claudeConnected = "claudeConn", codexConnected = "codexConn" }
    /// The chosen agent's state at Connect.
    enum Connect: String {
        case looking, notInstalled = "notinstalled", installing, codexTerminal = "codexterminal"
        case signedOut = "signedout", signedIn = "signedin", signingIn = "signingin", just, connected
        case failInstall = "failinstall", failSignIn = "failsignin", failTools = "failtools"
    }
    enum Browsers: String { case none, dia, three, arc }
    enum Bring: String { case brought, fresh, locked, unreadable }
    enum ColorSource: String { case nothing, colors, spaces }
    /// Chapter 5's Google: not asked, Google's tab open, connected with a
    /// meeting soon or none, or Google said no.
    enum Calendar: String { case not, connecting, meeting, empty, denied }
    enum Default: String { case not, already, no }

    var agents: Agents?
    var connect: Connect?
    var browsers: Browsers?
    var keepSpaces: Bool?
    var bring: Bring?
    var colorSource: ColorSource?
    var memoryFull: Bool?
    /// Passwords' managers found: "1password", "bitwarden", "proton",
    /// "apple"; empty for none.
    var managers: [String]?
    var calendar: Calendar?
    var slack: Bool?
    var defaultBrowser: Default?
    /// The import has all come in (the toast in chapter 5 or 6).
    var importDone: Bool?
    var reduceMotion: Bool?
}

// MARK: - the stage

@MainActor
final class WelcomeStage: ObservableObject {
    static let shared = WelcomeStage()

    /// The beats, by the names the prototype's anchors and the bench use.
    enum Beat: String, CaseIterable, Comparable {
        case welcome
        /// Chapter 1, Everything you're used to: pins and folders, Peek into
        /// Split View, Find anything.
        case pins, peek, find
        /// Chapter 2, Your agent, in tabs you can see: the task, the work, what needs you.
        case task, watch, results
        /// Chapter 3, Connect your agent; How to Ask once connected.
        case connect, howto
        /// Chapter 4, Make it yours: Bring from X, Look, Color, Passwords.
        case move, look, color, vault
        /// Chapter 5, Only what helps: Get to Know, then Calendar.
        case access, accessB = "access-b"
        /// Chapter 6, Links from other apps.
        case links
        /// The parts become the window.
        case finish

        var chapter: Int? {
            switch self {
            case .pins, .peek, .find: return 1
            case .task, .watch, .results: return 2
            case .connect, .howto: return 3
            case .move, .look, .color, .vault: return 4
            case .access, .accessB: return 5
            case .links: return 6
            case .welcome, .finish: return nil
            }
        }

        /// A name the bench or the prototype's links use.
        static func named(_ name: String) -> Beat? {
            let aliases = ["keys": "links", "passwords": "vault", "calendar": "access-b", "accessB": "access-b"]
            return Beat(rawValue: aliases[name] ?? name)
        }

        private var order: Int { Self.allCases.firstIndex(of: self) ?? 0 }
        static func < (lhs: Beat, rhs: Beat) -> Bool { lhs.order < rhs.order }
    }

    /// How this welcome began.
    enum Coming: String {
        /// The first run, from the disk image's dark window.
        case disk
        /// The first run, opened any other way.
        case launch
        /// Again, from Settings or the app menu: what's done shows as done.
        case replay
    }

    /// Open decision 1, as approved: chapter 1 shown, not folded into 2.
    static let foldsFirstChapter = false
    /// Open decision 4, as approved: The site's color doesn't lead to Color.
    static let siteColorTakesGrain = false

    /// The one stage the parts are laid out on, kept for the app's life so
    /// the welcome comes back from a sign-in as it was.
    let view = WelcomeStageView()
    let inputs = WelcomeStageView()
    /// Bringing things over: found while the intro plays.
    let bringing = Bringing()

    // MARK: what the frame shows

    @Published private(set) var beat: Beat = .welcome
    @Published private(set) var words = WelcomeWords(frame: .welcome, primary: "Get Started")
    @Published private(set) var dashes = WelcomeDashes()
    /// The panel stepped aside for a sign-in's tab, to come back when it ends.
    @Published private(set) var away = false
    /// The corner's one toast: "Everything from Dia is in", when nothing on
    /// screen says so.
    @Published var toast: String?
    /// The primary may be pressed: after the intro has brought it in.
    var buttonIn = false
    /// Back from a sign-in's tab: the next panel comes in as the overlay
    /// went, the other way round (WelcomeOverlayView).
    var returning = false
    /// The panel on screen now, for the moves of the whole overlay: the
    /// step aside for a sign-in, and the last fade at Finish.
    weak var overlay: WelcomeOverlayView?

    // MARK: what was chosen on the way

    /// How it began.
    var coming: Coming = .launch
    /// The agent Connect is about: "claude" or "codex".
    var agent = "claude"
    /// Bring: the browser picked, by its place in the list found.
    var source = 0
    /// Keep a real browser selected while asynchronous counts filter the list.
    var sourceID: String?
    /// Started fresh rather than bringing anything.
    var fresh = false
    /// Brought in from the chosen browser (the import may still be running).
    var brought = false
    /// Bring's failure, said beside the button: "The keychain is locked".
    var bringFailure: String?
    /// Keep its spaces, for a browser with more than one place.
    var keepSpaces = false
    /// Bring's line for an ad blocker among the browser's extensions: Yab's
    /// blocker kept over it.
    var yabBlocks = true
    /// Look and Color, held until Finish.
    var held = WelcomeHeldLook()
    /// Get to Know turned on here.
    var suggesting = false
    /// Make Default: macOS asked, waiting on its answer.
    var askedDefault = false
    /// macOS's answer was no.
    var defaultRefused = false
    /// Every branch pretended, for the bench.
    var pretend = WelcomePretend()

    var reduceMotion: Bool { pretend.reduceMotion ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: where it is

    private(set) var moment = WelcomeMoment(beat: .welcome)
    private var history: [Beat] = []
    /// Bumped by every new beat: a play overtaken stops at its next wait.
    private(set) var playing = 0
    private(set) var started = false
    /// The window the welcome is over, for what a chapter's press does in it.
    private(set) weak var browser: Browser?
    private var watching: [AnyCancellable] = []
    private var signIn: AnyCancellable?
    private var mailSignIn: AnyCancellable?
    /// Who the welcome stepped aside for: an agent's sign-in, or Google's.
    private var awayFor: Aside?
    enum Aside { case agent, google, passwords }
    private var refreshQueued = false

    // MARK: playing on by itself

    /// How long each beat of chapter 1 runs before the next comes by itself.
    static let runLength: Double = 4
    /// The play that runs on by itself, if the beat on screen is one.
    private(set) var runToken: Int?
    private var runStart: CFTimeInterval = 0
    private var heldSince: CFTimeInterval?
    private var heldFor: CFTimeInterval = 0
    /// The window not key holds the run.
    private var unfocused = false
    var runHeld: Bool { unfocused }

    private init() {}

    static func chapter(for beat: Beat) -> any WelcomeChapter.Type {
        switch beat {
        case .welcome: return WelcomeOpening.self
        case .pins, .peek, .find, .task, .watch, .results: return WelcomeSample.self
        case .connect, .howto: return WelcomeConnect.self
        case .move, .look, .color: return WelcomeYours.self
        case .vault: return WelcomeVault.self
        case .access, .accessB, .links, .finish: return WelcomeEnd.self
        }
    }

    /// The beats on this Mac's path now, Welcome to Finish.
    var path: [Beat] {
        [.welcome] + WelcomeSample.beats(self) + WelcomeConnect.beats(self) + WelcomeYours.beats(self) + WelcomeVault.beats(self) + WelcomeEnd.beats(self)
    }

    /// The chapters on the path, in order.
    var chapters: [Int] {
        var seen: [Int] = []
        for beat in path { if let chapter = beat.chapter, !seen.contains(chapter) { seen.append(chapter) } }
        return seen
    }

    /// Back is there: past Welcome and the path's first beat, and not at
    /// Finish. Under way too, as the prototype has it: an install goes on,
    /// and Make Default's wait is let go (`back()`).
    var canGoBack: Bool { beat != .welcome && beat != .finish && beat != path.dropFirst().first }

    /// How a welcome that begins now begins: again once welcomed, from the
    /// disk image's window when it was opened from there, else a launch.
    static func arrival(_ prefs: Preferences) -> Coming {
        prefs.welcomed ? .replay : Arrival.frame != nil ? .disk : .launch
    }

    /// How this welcome began, or how it will, before it has.
    func arrival(_ prefs: Preferences) -> Coming { started ? coming : Self.arrival(prefs) }

    // MARK: coming and going

    /// The panel came up (first, or back from a sign-in): the keys, the
    /// models watched, and the first time, the welcome from its first frame.
    func attach(_ browser: Browser) {
        self.browser = browser
        browser.welcomeReturn = { [weak self] in self?.pressPrimary() }
        browser.welcomeBack = { [weak self] in self?.back() }
        browser.welcomeQuiet = { [weak self] in self?.pressQuiet() }
        watchSignIn(browser)
        watchModels()
        guard !started else { return }
        started = true
        begin(browser)
    }

    func detach(_ browser: Browser) {
        browser.welcomeReturn = nil
        browser.welcomeBack = nil
        browser.welcomeQuiet = nil
    }

    private func begin(_ browser: Browser) {
        coming = Self.arrival(browser.prefs)
        held = WelcomeHeldLook(browser.prefs)
        held.adoptDefaultBrowser(DefaultBrowserImport.bundleIdentifier, welcomed: browser.prefs.welcomed)
        Hangs.start()
        // Found while the intro plays, so the chapters that ask know the
        // answers before they come.
        bringing.load()
        Task { await AgentSetupModel.shared.look() }
        Task { for cli in AgentSetupModel.clis { _ = await AgentIcons.icon(cli) } }
        history = []
        start(.welcome, from: nil, play: true, forward: true)
    }

    /// Back to the start, for Welcome… from the menu, and once Finish has
    /// handed the window over.
    func reset() {
        playing += 1
        started = false
        beat = .welcome
        moment = WelcomeMoment(beat: .welcome)
        words = WelcomeWords(frame: .welcome, primary: "Get Started")
        history = []
        buttonIn = false
        away = false
        awayFor = nil
        returning = false
        agent = "claude"
        source = 0
        sourceID = nil
        fresh = false
        brought = false
        bringFailure = nil
        keepSpaces = false
        WelcomeVault.reset()
        yabBlocks = true
        suggesting = false
        askedDefault = false
        defaultRefused = false
        toast = nil
        WelcomeTyping.shared.clear()
        view.show(WelcomeBoard(), animated: false, reduceMotion: true)
        inputs.show(WelcomeBoard(), animated: false, reduceMotion: true)
    }

    /// The window is handed over: welcomed, the overlay gone in a 0.12
    /// crossfade, the stage reset behind it. Finish calls it once its motion
    /// has landed; the held look was written before the motion began.
    /// The overlay fades its own layers: the window's `.animation` on
    /// `welcoming` would have made the 0.12 a 0.30 spring.
    func close() {
        guard let browser else { return }
        browser.prefs.welcomed = true
        let handOver = {
            Self.quietly { browser.welcoming = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.reset() }
        }
        if let overlay { overlay.leave(fade: 0.12, stepping: false, then: handOver) } else { handOver() }
    }

    /// End a replay without pressing any chapter's action. Held preferences
    /// contain only existing values and the choices already made here.
    func skipReplay() {
        guard started, coming == .replay, let browser, browser.welcoming, !away else { return }
        playing += 1
        runToken = nil
        askedDefault = false
        writeHeld()
        close()
    }

    /// Closing a manual replay dismisses its overlay. Keep its stage and
    /// any accepted import intact, just as when it works behind the welcome.
    func dismissReplay(in browser: Browser) {
        guard started, coming == .replay, self.browser === browser,
              browser.welcoming, browser.prefs.welcomed, awayFor == nil else { return }
        Self.quietly { browser.welcoming = false }
    }

    /// A change of `welcoming` that nothing animates: the overlay's own
    /// layers have moved already, or will.
    static func quietly(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    /// Look and Color written to prefs, so the real window lays itself out
    /// under the overlay before Finish's motion starts.
    func writeHeld() {
        guard let prefs = browser?.prefs else { return }
        held.write(to: prefs)
    }

    // MARK: moving through

    /// The next beat on the path.
    func next() {
        let path = path
        if let index = path.firstIndex(of: beat), index + 1 < path.count {
            go(path[index + 1])
        } else if let later = path.first(where: { $0 > beat }) {
            go(later)
        }
    }

    /// A beat, forward, played.
    func go(_ beat: Beat) {
        guard beat != self.beat else { return }
        history.append(self.beat)
        start(beat, from: self.beat, play: true, forward: true)
    }

    /// The first beat of chapter n or after on the path: Skip, Later, Not Now.
    func goChapter(_ chapter: Int) {
        go(path.first { ($0.chapter ?? 0) >= chapter || $0 == .finish } ?? .finish)
    }

    /// Back through the beats seen, never onto one passed over since.
    func back() {
        guard canGoBack else { return }
        let path = path
        var previous: Beat?
        while let last = history.popLast() {
            if path.contains(last), last != beat { previous = last; break }
        }
        if previous == nil, let index = path.firstIndex(of: beat), index > 0 { previous = path[index - 1] }
        guard let previous, previous != .welcome else { return }
        askedDefault = false
        start(previous, from: beat, play: false, forward: false)
    }

    /// A dash clicked: back to a chapter already read, never forward.
    func jump(toChapter chapter: Int) {
        guard let current = beat.chapter ?? (beat == .finish ? Int.max : nil), chapter < current,
              let first = path.first(where: { $0.chapter == chapter }) else { return }
        start(first, from: beat, play: false, forward: false)
    }

    func pressPrimary() {
        guard buttonIn, words.primary != nil, !words.busy, !words.disabled else { return }
        follow(Self.chapter(for: beat).press(.primary, moment, self))
    }

    func pressQuiet() {
        guard words.quiet != nil else { return }
        follow(Self.chapter(for: beat).press(.quiet, moment, self))
    }

    func follow(_ turn: WelcomeTurn) {
        switch turn {
        case .next: next()
        case .stay: refresh()
        case .go(let beat): go(beat)
        case .chapter(let chapter): goChapter(chapter)
        case .finish: go(.finish)
        }
    }

    private func start(_ beat: Beat, from: Beat?, play: Bool, forward: Bool) {
        playing += 1
        // Chapter 1 runs on by itself when played forward; one come back
        // to stands still and waits for Continue.
        runToken = play && forward && !reduceMotion && beat.chapter == 1 ? playing : nil
        runStart = CACurrentMediaTime()
        heldFor = 0
        heldSince = runHeld ? runStart : nil
        self.beat = beat
        let turn = from.flatMap(\.chapter) != beat.chapter
        moment = WelcomeMoment(beat: beat, from: from, turn: turn, forward: forward, window: window)
        let chapter = Self.chapter(for: beat)
        chapter.arrive(moment, self)
        dashes = reading()
        if play, !reduceMotion {
            let player = WelcomePlayer(stage: self, moment: moment, token: playing)
            Task { await chapter.play(moment, player) }
        } else {
            commit(moment, animated: true)
        }
    }

    /// The beat again as it now is, after something changed that it shows:
    /// a pick, an agent's state, an import. Its phase stays.
    func refresh() {
        guard started else { return }
        if beat != .welcome, beat != .finish, !path.contains(beat) {
            // A branch took this beat off the path: on to the one after.
            let path = path
            let after = path.first { $0 > beat } ?? .finish
            start(after, from: beat, play: false, forward: true)
            return
        }
        dashes = reading()
        var now = moment
        now.window = window
        commit(now, animated: true)
    }

    /// A refresh on the next turn of the run loop, once, however many
    /// changes asked for it.
    func needsRefresh() {
        guard !refreshQueued else { return }
        refreshQueued = true
        DispatchQueue.main.async {
            self.refreshQueued = false
            guard self.browser?.welcoming == true, self.beat != .welcome else { return }
            self.refresh()
        }
    }

    /// Shows a beat's board at a phase: the chapter's parts and the frame's
    /// words over them.
    func commit(_ moment: WelcomeMoment, animated: Bool) {
        self.moment = moment
        let chapter = Self.chapter(for: moment.beat)
        let said = chapter.words(moment, self)
        if said != words { words = said }
        WelcomeTyping.shared.clear()
        let board = chapter.board(moment, self)
        var visual = board
        var form = WelcomeBoard()
        let workspace = CGRect(x: 0, y: 0, width: 752, height: 526)
        switch moment.beat {
        case .look, .color:
            form.parts = board.parts.filter { ["editor", "lookcard"].contains($0.key) }
            visual.parts.removeAll { ["editor", "lookcard"].contains($0.key) }
            view.viewport = visual.parts.first?.frame
        case .welcome, .connect, .move, .vault, .access, .accessB:
            form = board
            // Full-width notes belong to the form. Give them a readable measure
            // before fitting the group to the column.
            for i in form.parts.indices where form.parts[i].frame.width == StageSpace.size.width && moment.beat != .welcome {
                form.parts[i].frame.size.width = 440
                form.parts[i].frame.origin.x = StageSpace.pivot.x - 220
            }
            if moment.beat == .access, form.parts.count == 2 {
                form.parts[1].frame.origin = CGPoint(x: form.parts[0].frame.minX, y: form.parts[0].frame.maxY + 12)
            }
            visual = WelcomeBoard([WelcomeParts.windowToBe("wtb", workspace, look: WelcomeYours.windowLook(self),
                                    yours: WelcomeYours.yours(self), page: .newTab, samples: true, field: held.compactField)])
            view.viewport = workspace
            switch moment.beat {
            case .connect:
                visual.parts.append(WelcomeParts.terminal("agent-example", CGRect(x: 100, y: 210, width: 552, height: 100),
                                                          who: agent, line: WelcomeConnect.terminalLine(agent)))
            case .vault, .accessB:
                let key = moment.beat == .vault ? "vault-card" : "g-gains"
                if let index = form.parts.firstIndex(where: { $0.key == key }) {
                    var detail = form.parts.remove(at: index)
                    detail.frame.origin = CGPoint(x: workspace.midX - detail.frame.width / 2, y: workspace.midY - detail.frame.height / 2)
                    visual = WelcomeBoard([detail])
                }
            default: break
            }
        case .finish:
            view.viewport = nil
        default:
            view.viewport = CGRect(x: 0, y: 135, width: 1180, height: 570)
        }
        inputs.viewport = moment.beat == .welcome ? nil : form.parts.reduce(CGRect.null) { $0.union($1.frame) }
        inputs.show(form, animated: animated, reduceMotion: reduceMotion)
        view.show(visual, animated: animated, reduceMotion: reduceMotion)
        overlay?.needsLayout = true
    }

    /// The window's size now.
    var window: CGSize {
        let size = overlay?.bounds.size ?? view.bounds.size
        return size.width > 0 && size.height > 0 ? size : StageSpace.size
    }

    private func reading() -> WelcomeDashes {
        let path = path
        let chapters = chapters
        if beat == .finish { return WelcomeDashes(chapters: chapters, current: chapters.count, fill: 1) }
        guard let chapter = beat.chapter, let current = chapters.firstIndex(of: chapter) else {
            return WelcomeDashes(chapters: chapters, current: 0, fill: 0)
        }
        let beats = path.filter { $0.chapter == chapter }
        let index = beats.firstIndex(of: beat) ?? 0
        let count = CGFloat(max(beats.count, 1))
        var dashes = WelcomeDashes(chapters: chapters, current: current, fill: CGFloat(index + 1) / count)
        if runToken == playing {
            dashes.from = CGFloat(index) / count
            dashes.run = Self.runLength * WelcomeMotion.pace
            dashes.token = playing
            dashes.paused = runHeld
        }
        return dashes
    }

    /// Seconds the running beat has run, the time it was held not counted.
    func ran() -> Double {
        let now = CACurrentMediaTime()
        return now - runStart - heldFor - (heldSince.map { now - $0 } ?? 0)
    }

    /// The window key or not.
    func hold(unfocused: Bool) {
        let was = runHeld
        self.unfocused = unfocused
        guard runHeld != was else { return }
        let now = CACurrentMediaTime()
        if runHeld {
            heldSince = now
        } else if let since = heldSince {
            heldFor += now - since
            heldSince = nil
        }
        if runToken == playing { dashes.paused = runHeld }
    }

    // MARK: the words on the stage

    /// The title, the sub and the marker: parts of the stage, keyed by what
    /// they say, so a change of words crossfades at their fixed height.
    // MARK: watching

    /// While Connect signs an agent in, its page is a tab of yours: the
    /// welcome steps aside so the tab is seen, and comes back to Connect
    /// the moment the sign-in ends, done or not.
    private func watchSignIn(_ browser: Browser) {
        guard signIn == nil else { return }
        signIn = AgentSetupModel.shared.$flow.receive(on: RunLoop.main).sink { [weak self, weak browser] flow in
            guard let self, let browser else { return }
            if case .signingIn = flow {
                guard self.beat == .connect else { return }
                self.stepAside(for: .agent, browser)
            } else if self.awayFor == .agent {
                self.comeBack(browser)
            }
        }
        // Chapter 5's Google: its consent page is a tab too.
        mailSignIn = MailCenter.shared.$connecting.removeDuplicates().dropFirst().receive(on: RunLoop.main).sink { [weak self, weak browser] connecting in
            guard let self, let browser else { return }
            if connecting {
                guard self.beat == .access || self.beat == .accessB else { return }
                self.stepAside(for: .google, browser)
            } else if self.awayFor == .google {
                self.comeBack(browser)
                // Shown again once back: the stage skips refreshes while away.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * WelcomeMotion.pace) { self.needsRefresh() }
            }
        }
    }

    /// The whole overlay out, 0.15 and a little smaller, then gone, so a
    /// sign-in's tab (or a question over the page) is seen.
    func stepAside(for reason: Aside, _ browser: Browser) {
        guard browser.welcoming, awayFor == nil else { return }
        awayFor = reason
        away = true
        let aside = { Self.quietly { browser.welcoming = false } }
        if let overlay { overlay.leave(fade: 0.15, stepping: true, then: aside) } else { aside() }
    }

    /// And back to the same beat, its choices as they were, on settle.
    func comeBack(_ browser: Browser) {
        guard away else { return }
        awayFor = nil
        away = false
        returning = true
        Self.quietly { browser.welcoming = true }
    }

    /// What the chapters show changes with the agents and the import: the
    /// beat is shown again when they do.
    private func watchModels() {
        guard watching.isEmpty else { return }
        watching = [
            AgentSetupModel.shared.objectWillChange.sink { [weak self] _ in self?.needsRefresh() },
            bringing.objectWillChange.sink { [weak self] _ in self?.needsRefresh() },
            // Chapter 5's Google: the accounts found, connected, refused,
            // and the next meeting once it is read.
            MailFound.shared.objectWillChange.sink { [weak self] _ in self?.needsRefresh() },
            MailCenter.shared.$accounts.removeDuplicates().sink { [weak self] _ in self?.needsRefresh() },
            MailCenter.shared.$connectFailed.removeDuplicates().sink { [weak self] _ in self?.needsRefresh() },
            Meetings.shared.$list.sink { [weak self] _ in self?.needsRefresh() },
        ]
    }
}

// MARK: - the player

/// A beat being played: its phases shown one after another, waits between
/// them, letters typed. Overtaken by another beat, it stops at its next
/// wait (each returns false then).
@MainActor
final class WelcomePlayer {
    let stage: WelcomeStage
    private(set) var moment: WelcomeMoment
    let token: Int

    init(stage: WelcomeStage, moment: WelcomeMoment, token: Int) {
        self.stage = stage
        self.moment = moment
        self.token = token
    }

    /// Still the beat on screen.
    var alive: Bool { stage.playing == token }
    var reduceMotion: Bool { stage.reduceMotion }

    /// The beat's board at a phase, moved to from what is there.
    func show(_ phase: String = "rest", index: Int = 0) {
        guard alive else { return }
        moment.phase = phase
        moment.index = index
        moment.window = stage.window
        stage.commit(moment, animated: true)
    }

    /// Waits, at the pace; false once overtaken.
    func wait(_ seconds: Double) async -> Bool {
        guard alive else { return false }
        try? await Task.sleep(for: .seconds(seconds * WelcomeMotion.pace))
        return alive
    }

    /// Types into a field on the stage: first takes back what doesn't
    /// match, a letter each `erase`, then adds a letter each `every`. With
    /// Reduce Motion, the whole line at once. False once overtaken.
    func type(_ text: String, in field: String, from start: String = "", every: Double = 0.038, erase: Double = 0.02) async -> Bool {
        let typing = WelcomeTyping.shared
        if reduceMotion {
            typing.set(text, for: field)
            return alive
        }
        var line = typing.typed[field] ?? start
        while !line.isEmpty, !text.hasPrefix(line) {
            line.removeLast()
            typing.set(line, for: field)
            guard await wait(erase) else { return false }
        }
        while line.count < text.count {
            line = String(text.prefix(line.count + 1))
            typing.set(line, for: field)
            guard await wait(every) else { return false }
        }
        return alive
    }

    /// Chapter 1's beat, once it has run its length (time held not
    /// counted), on to the next by itself. Nothing for a beat that waits.
    func runOn() async {
        guard stage.runToken == token else { return }
        while alive, stage.ran() < WelcomeStage.runLength * WelcomeMotion.pace {
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard alive else { return }
        stage.next()
    }

    /// A part pressed, as a finger would: in to `scale` and back.
    func press(_ key: String, to scale: CGFloat = 0.96) {
        guard alive, !reduceMotion else { return }
        stage.view.press(key, to: scale)
    }

    /// Where a part is on screen now, in stage points.
    func frame(of key: String) -> CGRect? { stage.view.visualFrame(for: key) }

    /// A part's layer, for a move of the chapter's own (an arc, a pour).
    func layer(for key: String) -> CALayer? { stage.view.layer(for: key) }

    /// A haptic, now: `.levelChange` for a peak, `.generic` for a light one.
    func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard alive else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}

// MARK: - the bench

extension WelcomeStage {
    /// `./bench welcome [BEAT] [phase=NAME] [index=N] [play=1] [KEY=VALUE…]
    /// [next=1] [back=1] [quiet=1] [wait=S]`: the welcome put in any state
    /// of final-spec §4, as a person would leave it, then pressed. See
    /// docs in impl-plan and the bench script for the keys.
    func bench(_ request: [String: Any], _ browser: Browser, answer: @escaping ([String: Any]) -> Void) {
        func text(_ key: String) -> String? {
            if let value = request[key] as? String { return value }
            if let value = request[key] as? Bool { return value ? "1" : "0" }
            if let value = request[key] as? Double { return String(value) }
            if let value = request[key] as? Int { return String(value) }
            return nil
        }
        func flag(_ key: String) -> Bool? {
            guard let value = text(key)?.lowercased() else { return nil }
            return ["1", "true", "yes", "on"].contains(value)
        }
        if flag("reset") == true {
            // Back to the start, every pretended branch let go.
            reset()
            pretend = WelcomePretend()
            held = WelcomeHeldLook(browser.prefs)
            held.adoptDefaultBrowser(DefaultBrowserImport.bundleIdentifier, welcomed: browser.prefs.welcomed)
            WelcomeMotion.pace = 1
            coming = Self.arrival(browser.prefs)
        }
        // Up first, before anything is pretended: the welcome's own start
        // reads the look and the arrival from prefs, and would undo them.
        // After a reset too, which lets the start go: otherwise the step
        // below would start it again over this request's defaultApp and tabs.
        if text("step") != nil, !started {
            if !browser.welcoming { browser.welcoming = true }
            attach(browser)
        }
        if let value = text("agents") { pretend.agents = WelcomePretend.Agents(rawValue: value) }
        if let value = text("conn") { pretend.connect = WelcomePretend.Connect(rawValue: value) }
        if let value = text("chosen") ?? text("agent") { agent = AgentSetupModel.clis.contains(value) ? value : "claude" }
        if let value = text("browsers") { pretend.browsers = WelcomePretend.Browsers(rawValue: value) }
        if let value = request["source"] as? Int ?? text("source").flatMap({ Int($0) }) { source = value; sourceID = nil }
        if let value = flag("keep") { pretend.keepSpaces = value; keepSpaces = value }
        // Bring's line: Yab's blocker over its own.
        if let value = flag("blocks") { yabBlocks = value }
        if let value = text("bring") { pretend.bring = WelcomePretend.Bring(rawValue: value) }
        if flag("fresh") == true { pretend.bring = .fresh }
        if let value = text("csrc") { pretend.colorSource = WelcomePretend.ColorSource(rawValue: value) }
        if let value = text("memory") { pretend.memoryFull = value == "full" }
        if let value = text("managers") { pretend.managers = value == "none" ? [] : value.split(separator: ",").map(String.init) }
        if let value = text("cal") ?? text("calendar") {
            pretend.calendar = WelcomePretend.Calendar(rawValue: value) ?? (["1", "true", "yes"].contains(value) ? .meeting : .not)
        }
        if let value = flag("slack") { pretend.slack = value }
        if let value = text("default") { pretend.defaultBrowser = WelcomePretend.Default(rawValue: value) }
        if let value = text("defaultApp"), !held.tabsChosen {
            held.sidebar = browser.prefs.sidebar
            held.adoptDefaultBrowser(value, welcomed: browser.prefs.welcomed)
        }
        if let value = flag("toast") { pretend.importDone = value }
        if let value = flag("reduce") { pretend.reduceMotion = value }
        if let value = flag("slow") { WelcomeMotion.pace = value ? 5 : 1 }
        if let value = flag("suggesting") { suggesting = value }
        // Brought from a browser that keeps its tabs down the side (Arc),
        // Look starts there, as the prototype's panel has it.
        if text("tabs") == nil, text("browsers") != nil || text("bring") != nil || text("csrc") != nil,
           !held.tabsChosen, WelcomeYours.broughtFrom(self)?.sidebar == true {
            held.sidebar = true
        }
        if let value = text("tabs") {
            held.sidebar = value == "side" || value == "sidebar"
            held.tabsChosen = true
        }
        if let value = text("page") {
            switch value {
            case "edge": held.backdrop = .none
            case "color", "card": held.backdrop = .color
            default: held.backdrop = .site
            }
        }
        // The look card's own, as the Color card's controls hold them.
        if let value = text("colors") { held.colors = value.split(separator: ",").map(String.init).filter { NSColor(hex: $0) != nil } }
        if let value = text("drawings") { held.drawings = LookDrawings.Set(rawValue: value)?.rawValue ?? "" }
        if let value = request["strength"] as? Double { held.strength = min(1, max(0, value)) }
        if let value = flag("shift") { held.shift = value }
        if let value = text("field") { held.compactField = value == "compact" }
        if let value = text("arrival") { coming = Coming(rawValue: value) ?? coming }

        if let name = text("step"), let target = Beat.named(name) {
            if !browser.welcoming { browser.welcoming = true }
            if !started { attach(browser) }
            place(onPath: target)
            buttonIn = true
            let phase = text("phase")
            let index = request["index"] as? Int ?? text("index").flatMap { Int($0) } ?? 0
            if flag("play") == true {
                let path = path
                let before = path.firstIndex(of: target).flatMap { $0 > 0 ? path[$0 - 1] : nil }
                let play = { [self] in
                    history = Array(path.prefix { $0 < target })
                    // Welcome played is from its first frame: nothing of it
                    // on the stage yet, so the lede comes in after the name.
                    if target == .welcome { view.show(WelcomeBoard(), animated: false, reduceMotion: true) }
                    start(target, from: before, play: true, forward: true)
                    // Welcome played is the intro again, from its first frame.
                    if target == .welcome {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.overlay?.replayIntro() }
                    }
                }
                if let before, before != beat {
                    // Played from the one before: that one first, at rest,
                    // and the play a moment later, once it is on screen.
                    rest(at: before, phase: "rest", index: 0)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { play() }
                } else {
                    play()
                }
            } else {
                rest(at: target, phase: phase ?? "rest", index: index)
            }
        } else if started {
            refresh()
        }
        if flag("next") == true { pressPrimary() }
        if flag("back") == true { back() }
        if flag("quiet") == true { pressQuiet() }
        if flag("skip") == true { skipReplay() }
        // Connect's sign-in, pretended: the flow as Agents.connect sets it,
        // so the welcome's stepping aside and back can be watched.
        if let flow = text("flow") { AgentSetupModel.shared.flow = flow == "signing" ? .signingIn(agent) : nil }

        let wait = request["wait"] as? Double ?? 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            answer([
                "welcoming": browser.welcoming, "welcomed": browser.prefs.welcomed,
                "step": self.beat.rawValue, "phase": self.moment.phase, "index": self.moment.index,
                "path": self.path.map(\.rawValue), "chapters": self.chapters,
                "dash": self.dashes.current, "fill": Double(self.dashes.fill),
                "running": self.runToken == self.playing, "ran": self.ran(), "held": self.runHeld,
                "dashLayer": self.overlay?.dashState ?? [:],
                "title": self.words.title, "sub": self.words.sub, "primary": self.words.primary ?? "",
                "quiet": self.words.quiet ?? "", "failure": self.words.failure ?? "", "busy": self.words.busy,
                "agent": self.agent, "sidebar": self.held.sidebar, "backdrop": self.held.backdrop.rawValue, "field": self.held.compactField ? "compact" : "full",
                "skipFrame": self.overlay?.skipFrame.map { [Double($0.minX), Double($0.minY), Double($0.width), Double($0.height)] } ?? [],
                "importRunning": self.bringing.busy, "brought": self.brought, "fresh": self.fresh, "askedDefault": self.askedDefault,
                "suggesting": self.suggesting,
                "coming": self.coming.rawValue, "back": self.canGoBack, "buttonIn": self.buttonIn,
                "toast": self.toast ?? "", "reduce": self.reduceMotion, "pace": WelcomeMotion.pace,
                "parts": self.view.keys + self.inputs.keys, "keep": self.keepSpaces, "shift": self.held.shift, "seen": self.benchSeen(),
            ])
        }
    }

    /// Where the parts and the AppKit controls in them are drawn, in the
    /// window's points from its top left, for a probe's real clicks.
    private func benchSeen() -> [String: Any] {
        guard let content = view.window?.contentView else { return [:] }
        func place(_ rect: CGRect, from node: NSView) -> [Double] {
            let r = content.convert(rect, from: node)
            return [r.minX, content.isFlipped ? r.minY : content.bounds.height - r.maxY, r.width, r.height].map(Double.init)
        }
        var parts: [String: [Double]] = [:]
        for column in [view, inputs] {
            for key in column.keys { if let frame = column.visualFrame(for: key) { parts[key] = place(frame, from: column.canvas) } }
        }
        var controls: [[String: Any]] = []
        func walk(_ node: NSView) {
            if node is NSControl { controls.append(["class": "\(type(of: node))", "frame": place(node.bounds, from: node)]) }
            node.subviews.forEach(walk)
        }
        walk(view)
        walk(inputs)
        let button = overlay.map { place($0.cluster(in: $0), from: $0) } ?? []
        return ["parts": parts, "controls": controls, "button": button, "scale": Double(StageSpace.scale(for: view.bounds.size))]
    }

    /// A beat shown at a phase as it rests, with nothing moving: the
    /// bench's way to any state.
    private func rest(at target: Beat, phase: String, index: Int) {
        history = Array(path.prefix { $0 < target })
        playing += 1
        beat = target
        moment = WelcomeMoment(beat: target, phase: phase, index: index, window: window)
        Self.chapter(for: target).arrive(moment, self)
        dashes = reading()
        commit(moment, animated: false)
    }

    /// Puts a beat on the path, as the prototype's storyboard does when a
    /// beat off the path is picked: the branch that shows it, pretended.
    private func place(onPath beat: Beat) {
        switch beat {
        case .color:
            // Color comes after either page: only the site's is moved to one.
            if held.backdrop == .site && !Self.siteColorTakesGrain { held.backdrop = .color }
        case .vault:
            if !path.contains(.vault), pretend.managers == nil { pretend.managers = ["1password"] }
        case .move:
            // A browser of this Mac's found (or the bench's standIn): its own Bring.
            if path.contains(.move), pretend.browsers == nil { break }
            if pretend.browsers == nil || pretend.browsers == WelcomePretend.Browsers.none { pretend.browsers = .dia }
        case .howto:
            if pretend.agents == nil || !(pretend.agents == .claudeConnected || pretend.agents == .codexConnected) {
                pretend.agents = agent == "codex" ? .codexConnected : .claudeConnected
                pretend.connect = .connected
            }
        case .access:
            if pretend.agents != .claudeConnected && pretend.agents != .codexConnected {
                pretend.agents = agent == "codex" ? .codexConnected : .claudeConnected
                pretend.connect = .connected
            }
            pretend.memoryFull = false
        case .accessB:
            // Calendar alone: no agent, or its memory already full.
            if WelcomeConnect.connected(self) != nil { pretend.memoryFull = true }
        case .links:
            if pretend.defaultBrowser == .already { pretend.defaultBrowser = .not }
        default: break
        }
    }
}
