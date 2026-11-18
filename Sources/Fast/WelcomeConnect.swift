import SwiftUI
import AppKit
import Combine

// Chapter 3, Connect your agent: the four providers' own icons in one row,
// always in the same order, each saying where it stands, and the access
// line before any press. No ⌘T box here: its row ("Ask Claude ⌘J") read as something to press in the menu, when
// the press is Connect.
// Connect installs, signs in (in a Yab tab, the welcome stepping aside) and
// sets up Yab's tools, as AgentSetupModel does for Settings; a failure is
// said beside the button, never in a toast.
//
// The tick is the chapter's peak, in one turn of the run loop: the ring
// closes and fades, DoneTick springs, the mark dips as if pressed, a haptic,
// and the connected state line stays.
//
// Then How to Ask, for a connected agent: the marks leave, a Terminal rises
// where they were and the sample's task is typed into it.
//
// Every state can be pretended for the bench (`agents=`, `conn=`, `chosen=`):
// presses then play the prototype's story instead of installing or signing
// in anything.

@MainActor
enum WelcomeConnect: WelcomeChapter {
    static let title = "Connect your agent."

    /// The plans each takes. Claude Code's own sign-in lists Claude's;
    /// Codex's promises Plus and up, and Free and Go run it too, on a
    /// small monthly allowance (docs/agents.md, Names).
    static func needs(_ cli: String) -> String { (AgentPlan.of(cli) ?? .claude).needs }

    /// Where the chosen agent stands (final-spec §2, chapter 3's table).
    enum State: Equatable {
        case looking, notInstalled, installing, codexTerminal, signedOut, signedIn, signingIn, just, connected
        case failInstall, failSignIn, failTools
        /// Signed in already, Yab setting up its tools after Connect (or
        /// right after an install): the ring turns, the press waits.
        case settingUp
    }

    // MARK: - the chapter's memory

    /// The chosen agent's state on the last board shown, to know a landing
    /// when it comes: from waiting (or signed out) to connected.
    private static var last: (cli: String, state: State)?
    /// The agent whose ring is closing: kept on the board a quarter second
    /// more while its arc runs full and fades.
    private static var closing: String?
    /// A mark clicked since arriving: the chosen one is the person's now.
    private static var picked = false
    /// The pretended presses' own clock: a newer press stops an older one's.
    private static var pretendRun = 0
    /// Refreshes the beat as the welcome comes back from a sign-in's tab.
    private static var comingBack: AnyCancellable?

    // MARK: - the chapter

    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat] {
        connected(stage).map(AgentSetupModel.skilled) == true ? [.connect, .howto] : [.connect]
    }

    /// The agent connected, as Yab reads it or the bench pretends; nil for none.
    static func connected(_ stage: WelcomeStage) -> String? {
        if pretending(stage) {
            if connects(pretended(stage)) { return stage.agent }
            guard stage.pretend.connect == nil else { return nil }
            switch stage.pretend.agents {
            case .claudeConnected: return "claude"
            case .codexConnected: return "codex"
            default: return nil
            }
        }
        let setup = AgentSetupModel.shared
        if setup.connected(stage.agent) { return stage.agent }
        return AgentSetupModel.clis.first { setup.connected($0) }
    }

    /// The chosen agent's state now.
    static func state(_ stage: WelcomeStage) -> State {
        let setup = AgentSetupModel.shared
        let cli = stage.agent
        if pretending(stage) {
            // The bench's `flow=signing` fakes the real sign-in.
            if setup.flow == .signingIn(cli) { return .signingIn }
            switch pretended(stage) {
            case .looking: return .looking
            case .notInstalled: return .notInstalled
            case .installing: return .installing
            case .codexTerminal: return .codexTerminal
            case .signedOut: return .signedOut
            case .signedIn: return .signedIn
            case .signingIn: return .signingIn
            case .just: return .just
            case .connected: return .connected
            case .failInstall: return .failInstall
            case .failSignIn: return .failSignIn
            case .failTools: return .failTools
            }
        }
        switch setup.flow {
        case .installing(let now) where now == cli: return setup.installByHand ? .codexTerminal : .installing
        case .signingIn(let now) where now == cli: return .signingIn
        case .landed(let done) where done.contains(cli): return .just
        case .preparing(let now) where now.contains(cli): return .settingUp
        case .finishing(let now) where now.contains(cli): return .settingUp
        default: break
        }
        if setup.connected(cli) { return .connected }
        if setup.found == nil { return .looking }
        // The last try stopped: said beside the button until the next press.
        // Signed in already, it was the tools that stopped (feedback #328:
        // every stop read "The sign-in didn't finish").
        if let trouble = setup.trouble, trouble.clis.contains(cli), setup.flow == nil {
            guard setup.installed(cli) else { return .failInstall }
            return setup.signedIn[cli] == true ? .failTools : .failSignIn
        }
        guard setup.installed(cli) else { return .notInstalled }
        return setup.signedIn[cli] == true ? .signedIn : .signedOut
    }

    /// Every provider, in the order every list shows them: a mark never
    /// moves or hides as sign-in statuses arrive (2026-10-22: two slots
    /// for four providers drew ChatGPT, Cursor and Gemini on one spot).
    static var order: [String] { AgentSetupModel.clis }

    /// A mark's center across the stage, 200 apart, the row centered.
    static func center(_ cli: String) -> CGFloat {
        let index = CGFloat(order.firstIndex(of: cli) ?? 0)
        return 590 + (index - CGFloat(order.count - 1) / 2) * pitch
    }

    private static let pitch: CGFloat = 200

    static func arrive(_ moment: WelcomeMoment, _ stage: WelcomeStage) {
        guard moment.beat == .connect else { return }
        last = nil
        closing = nil
        picked = false
        pretendRun += 1
        watchReturn(stage)
        if pretending(stage) {
            // As the prototype's panel: with no state given, the agent that
            // is further along is the one chosen.
            if stage.pretend.connect == nil { stage.agent = connected(stage) ?? order.first { installed($0, stage) } ?? "claude" }
            return
        }
        let setup = AgentSetupModel.shared
        if moment.forward, !setup.connected(stage.agent) { stage.agent = setup.order.first ?? "claude" }
        // Read again on every arrival: an install done outside Yab shows at
        // once. What was found may choose another agent, if none was clicked.
        Task {
            await setup.look()
            guard stage.beat == .connect, !picked, !pretending(stage), !waits(state(stage)), !setup.connected(stage.agent) else { return }
            let first = setup.order.first ?? "claude"
            guard stage.agent != first else { return }
            stage.agent = first
            stage.needsRefresh()
        }
    }

    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords {
        if moment.beat == .howto {
            return WelcomeWords(title: title, sub: "Ask it in Yab, or from your terminal.")
        }
        let name = AgentSetupModel.name(stage.agent)
        let now = state(stage)
        let sub = connects(now) ? "\(name) is connected." : "Choose Claude, ChatGPT, Cursor or Gemini, on your own plan."
        switch now {
        case .looking: return WelcomeWords(title: title, sub: sub, primary: "Connect", disabled: true, quiet: "Later")
        case .notInstalled: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", quiet: "Later")
        case .installing, .codexTerminal: return WelcomeWords(title: title, sub: sub, primary: "Setting Up\u{2026}", busy: true, quiet: "Cancel")
        case .signedOut, .signedIn: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", quiet: "Later")
        case .signingIn: return WelcomeWords(title: title, sub: sub, primary: "Waiting for Approval", busy: true, quiet: "Cancel")
        case .settingUp: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", busy: true)
        case .just, .connected: return WelcomeWords(title: title, sub: sub, primary: "Continue")
        case .failInstall: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", quiet: "Later", failure: "Couldn\u{2019}t set up \(name)")
        case .failSignIn: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", quiet: "Later", failure: "The sign-in didn\u{2019}t finish")
        case .failTools: return WelcomeWords(title: title, sub: sub, primary: "Connect \(name)", quiet: "Later", failure: "Yab couldn\u{2019}t set up its tools")
        }
    }

    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn {
        guard moment.beat == .connect else { return .next }
        let now = state(stage)
        if pretending(stage) { return pretendPress(button, now, stage) }
        let setup = AgentSetupModel.shared
        if button == .quiet {
            if waits(now) {
                setup.cancel()
                return .stay
            }
            // Later: past How to Ask, on to chapter 4.
            return .chapter(4)
        }
        switch now {
        case .just, .connected:
            ModelDefaults.shared.useProvider(stage.agent)
            // How to Ask is this chapter's own beat, not Settings'.
            switch setup.flow {
            case .landed, .asking: setup.flow = nil
            default: break
            }
            return .next
        case .notInstalled, .failInstall:
            settle(setup)
            if let browser = stage.browser { setup.install(stage.agent, browser) }
            return .stay
        case .signedOut, .signedIn, .failSignIn, .failTools:
            settle(setup)
            if let browser = stage.browser { setup.connect([stage.agent], browser) }
            return .stay
        case .looking, .installing, .codexTerminal, .signingIn, .settingUp:
            return .stay
        }
    }

    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async {
        if moment.beat == .howto {
            await playHowTo(moment, player)
            return
        }
        player.show()
    }

    // MARK: - the boards

    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        moment.beat == .howto ? howTo(moment, stage) : connect(moment, stage)
    }

    private static func connect(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        let now = state(stage)
        let cli = stage.agent
        // A landing: this agent was on the last board, not yet connected.
        let before = last
        let landing = connects(now) && before.map { $0.cli == cli && !connects($0.state) } == true
        last = (cli, now)
        if landing { land(cli, closing: before.map { waits($0.state) } == true && !stage.reduceMotion, stage) }

        var parts = marks(stage, now: now, landing: landing)
        // Into waiting, the still ring fades as the turning one comes in
        // over it, rather than going back into its icon.
        let exits: [String: StagePart.Exit] = waits(now) ? ["pick-" + cli: .crossfade] : [:]
        if !connects(now) {
            // A stop says why under the marks, as Settings does beside its
            // button: the footer's one line only names the step.
            let access = troubleWords(cli, now) ?? WelcomeConnect.needs(cli)
            var said = StagePart.view("access:" + cli, CGRect(x: 0, y: marksTop + 276, width: 1180, height: 16), enter: .fade, delay: 0.18) {
                Text(access).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }
            said.version = access
            parts.append(said)
        }
        // The manual installer has already copied the command, but the
        // welcome must let someone read and copy it again, as Settings does.
        // The slot is as wide as its whole command (the longest installer,
        // Gemini's, about 540 with Copy), centered in
        // the chapter subtitle's 720-point column, below the status and
        // access lines and above the footer controls.
        if now == .codexTerminal {
            let command = AgentSetupModel.install(cli)
            var part = StagePart.view("install-command-" + cli,
                                      CGRect(x: 230, y: marksTop + 306, width: 720, height: 44),
                                      enter: .fade, delay: 0.18, takesClicks: true) {
                CommandSlot(text: command, fits: true, kind: .glass)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            part.version = command
            parts.append(part)
        }
        return WelcomeBoard(parts, exits: exits)
    }

    /// 3b: the marks gone (the other one first), a Terminal in the middle
    /// with the sample's task typed into it.
    private static func howTo(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        let cli = connected(stage) ?? stage.agent
        var parts: [StagePart] = []
        if moment.phase == "leave" {
            // The connected mark a moment longer, where it stood.
            parts.append(WelcomeParts.mark("mark-" + cli, CGRect(x: center(cli) - 56, y: marksTop, width: 112, height: 112), .agent(cli),
                                           tick: true, tickEnters: false, enter: .drop))
            parts.append(name(cli, center: center(cli), top: marksTop + 120, chosen: true, aside: false, delay: 0.1))
            return WelcomeBoard(parts)
        }
        parts.append(WelcomeParts.terminal("term", CGRect(x: 310, y: 352, width: 560, height: 96), who: cli, line: terminalLine(cli), enter: .rise))
        if cli != "codex" {
            let note = "In Codex, the same words start with \(AgentSetupModel.mention("codex"))."
            var part = StagePart.view("hnote", CGRect(x: 0, y: 464, width: 1180, height: 16), enter: .fade, delay: 0.2) {
                Text(note).font(.system(size: 12)).foregroundStyle(Palette.muted).frame(maxWidth: .infinity)
            }
            part.version = note
            parts.append(part)
        }
        return WelcomeBoard(parts)
    }

    /// The marks' top: the icons, names, state line and access line sit
    /// in the middle of the stage, under the words.
    private static let marksTop: CGFloat = 296

    /// The four providers' icons at 112, centers 200 apart, top marksTop;
    /// each name 12 under on a wash pill when chosen; the state line 6
    /// under. Each part keeps its key as its words change, so a status
    /// arriving is drawn again in place, never two words crossing.
    private static func marks(_ stage: WelcomeStage, now: State, landing: Bool) -> [StagePart] {
        let waiting = waits(now)
        let reduce = stage.reduceMotion
        var parts: [StagePart] = []
        for (index, cli) in order.enumerated() {
            let middle = 590 + (CGFloat(index % 2) - 0.5) * 210
            let top = marksTop + CGFloat(index / 2) * 138
            let x = middle - 38
            let chosen = cli == stage.agent
            // The other one, while the chosen one waits: at 0.5.
            let aside = !chosen && waiting
            let ring = chosen && !reduce && (waiting || closing == cli)
            let frame = CGRect(x: x, y: top, width: 76, height: 76)
            parts.append(WelcomeParts.mark("mark-" + cli, frame, .agent(cli),
                                           ring: ring, tick: chosen && connects(now), tickEnters: now == .just || landing,
                                           dim: aside || now == .looking, enter: .drop, delay: Double(index) * 0.04) {
                choose(cli, stage)
            })
            // Choice stays visible after connection too. The moving ring
            // takes its place while waiting, then returns to this still ring.
            // Reduce Motion keeps the still ring throughout the wait.
            if chosen, !ring, now != .looking {
                parts.append(WelcomeParts.pick("pick-" + cli, frame, .agent(cli), delay: Double(index) * 0.04))
            }
            parts.append(name(cli, center: middle, top: frame.maxY, chosen: chosen, aside: aside, delay: 0.1 + Double(index) * 0.04))
            if let words = line(cli, now, stage) {
                var part = StagePart.view("state-" + cli, CGRect(x: middle - lineWidth / 2, y: frame.maxY + 34, width: lineWidth, height: 16),
                                          enter: .fade, delay: 0.14 + Double(index) * 0.04) {
                    Text(words).font(.system(size: 12.5)).foregroundStyle(Palette.muted).opacity(aside ? 0.5 : 1)
                        .lineLimit(1).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
                part.version = "\(words) \(aside)"
                parts.append(part)
            }
        }
        return parts
    }

    /// An agent's name under its mark, 15 medium; the chosen one's in ink
    /// on a wash pill, the others muted.
    private static func name(_ cli: String, center: CGFloat, top: CGFloat, chosen: Bool, aside: Bool, delay: Double) -> StagePart {
        var part = StagePart.view("name-" + cli, CGRect(x: center - lineWidth / 2, y: top, width: lineWidth, height: 28), enter: .fade, delay: delay) {
            Text(AgentSetupModel.name(cli))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                .frame(height: 20)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(chosen ? Palette.wash : .clear, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .opacity(aside ? 0.5 : 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        part.version = "\(chosen) \(aside)"
        return part
    }

    /// A name's and a state line's width: a mark's slot, less a gap.
    private static let lineWidth: CGFloat = 196

    /// The state line under an agent's name.
    private static func line(_ cli: String, _ now: State, _ stage: WelcomeStage) -> String? {
        if cli == stage.agent {
            switch now {
            case .looking: return nil
            case .just, .connected: return "Connected"
            case .notInstalled, .failInstall: return "Yab sets it up, then you sign in"
            case .installing: return "Setting up\u{2026}"
            case .codexTerminal: return "Paste in Terminal"
            case .signedOut, .failSignIn: return "Signed out"
            case .signedIn, .failTools: return "Signed in"
            case .settingUp: return AgentSetupModel.shared.signedIn[cli] == true ? "Signed in" : "Signed out"
            // Codex opens its page in the default browser when that isn't Yab.
            case .signingIn:
                if case .browser(let name) = AgentSetupModel.shared.page { return "Signing in, in \(name ?? "your browser")" }
                return "Signing in, in a Yab tab"
            }
        }
        if now == .looking { return nil }
        if pretending(stage) {
            if (cli == "claude" && stage.pretend.agents == .claudeConnected) || (cli == "codex" && stage.pretend.agents == .codexConnected) {
                return "Connected"
            }
            return installed(cli, stage) ? "Signed out" : "Not set up"
        }
        let setup = AgentSetupModel.shared
        if setup.connected(cli) { return "Connected" }
        guard setup.installed(cli) else { return "Not set up" }
        return setup.signedIn[cli] == true ? "Signed in" : "Signed out"
    }

    /// What is typed in the Terminal: the skill named as the agent takes it.
    static func terminalLine(_ cli: String) -> String {
        "> use \(AgentSetupModel.mention(cli)) to catch me up on my pull requests"
    }

    // MARK: - choosing

    /// A mark clicked: that agent chosen, unless one is waiting.
    private static func choose(_ cli: String, _ stage: WelcomeStage) {
        guard stage.beat == .connect, stage.agent != cli, !waits(state(stage)) else { return }
        stage.agent = cli
        picked = true
        if pretending(stage) {
            pretendRun += 1
            stage.pretend.connect = defaultState(cli, stage)
        } else {
            AgentSetupModel.shared.clearFailure()
            settle(AgentSetupModel.shared)
        }
        stage.refresh()
    }

    /// The tick and How to Ask's wait belong to the agent just connected:
    /// another one picked, or pressed for, they end. Left on, the flow
    /// kept Connect "busy" and its press did nothing (10-27: Claude
    /// connected, ChatGPT picked, Connect ChatGPT dead).
    private static func settle(_ setup: AgentSetupModel) {
        switch setup.flow {
        case .landed, .asking: setup.flow = nil
        default: break
        }
    }

    // MARK: - the tick

    /// How long the tick stays before Connect goes on by itself.
    static let afterTick: Double = 0.7

    /// The peak, on the run loop's turn the landing board is shown on: the
    /// ring closes and fades (DoneTick springs by its own enter), the mark
    /// dips as if pressed, and the haptic.
    private static func land(_ cli: String, closing ring: Bool, _ stage: WelcomeStage) {
        if ring { closing = cli }
        let reduce = stage.reduceMotion
        RunLoop.main.perform(inModes: [.common]) {
            MainActor.assumeIsolated {
                guard stage.beat == .connect else { return }
                if ring, let layer = stage.inputs.layer(for: "mark-\(cli)-ring") { close(layer) }
                if !reduce { stage.inputs.press("mark-" + cli, to: 0.96) }
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            }
        }
        // Connected: on to the next screen by itself once the tick has been
        // seen, as Continue would; nothing more to press here.
        DispatchQueue.main.asyncAfter(deadline: .now() + afterTick * WelcomeMotion.pace) {
            guard stage.beat == .connect, stage.agent == cli, connects(state(stage)) else { return }
            stage.pressPrimary()
        }
        guard ring else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * WelcomeMotion.pace) {
            guard closing == cli else { return }
            closing = nil
            stage.needsRefresh()
        }
    }

    /// The waiting ring's arc runs out to a whole ring in 0.12, then the
    /// ring fades in 0.09; the next board takes it away unseen.
    private static func close(_ layer: CALayer) {
        let all = sublayers(of: layer)
        let ring = all.first { $0 is WelcomeRingLayer } ?? layer
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for arc in all.compactMap({ $0 as? CAShapeLayer }) where arc.lineCap == .round {
            let shown = arc.presentation() ?? arc
            let start = shown.strokeStart
            let end = shown.strokeEnd
            arc.removeAllAnimations()
            arc.strokeStart = 0
            arc.strokeEnd = 1
            arc.add(WelcomeMotion.animation("strokeStart", from: start, to: 0, curve: .easeOut, duration: 0.12, on: arc), forKey: "close.start")
            arc.add(WelcomeMotion.animation("strokeEnd", from: end, to: 1, curve: .easeOut, duration: 0.12, on: arc), forKey: "close.end")
        }
        ring.opacity = 0
        ring.add(WelcomeMotion.animation("opacity", from: 1, to: 0, curve: .linear, duration: 0.09, delay: 0.12, on: ring, fill: .both),
                 forKey: "close.fade")
        CATransaction.commit()
    }

    private static func sublayers(of layer: CALayer) -> [CALayer] {
        (layer.sublayers ?? []).flatMap { [$0] + sublayers(of: $0) }
    }

    /// Back from a sign-in's tab, the welcome settles in as it was, the ring
    /// still turning; then the beat shows where Connect got to, so the tick
    /// lands in full view, as the prototype has it. (The stage skips its
    /// refreshes while the welcome is away.)
    private static func watchReturn(_ stage: WelcomeStage) {
        guard comingBack == nil else { return }
        comingBack = stage.$away.removeDuplicates().dropFirst().sink { [weak stage] away in
            guard !away else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35 * WelcomeMotion.pace) {
                guard let stage, stage.beat == .connect else { return }
                stage.needsRefresh()
            }
        }
    }

    // MARK: - How to Ask, played

    private static func playHowTo(_ moment: WelcomeMoment, _ player: WelcomePlayer) async {
        let cli = connected(player.stage) ?? player.stage.agent
        if moment.from == .connect {
            // The other mark first, then the connected one as the Terminal rises.
            player.show("leave")
            guard await player.wait(0.06) else { return }
        }
        player.show()
        WelcomeTyping.shared.set("> ", for: "term")
        guard await player.wait(0.3) else { return }
        _ = await player.type(terminalLine(cli), in: "term", from: "> ", every: 0.03)
    }

    // MARK: - the pretended Mac

    /// The bench pretends the agents on this Mac or Connect's state.
    private static func pretending(_ stage: WelcomeStage) -> Bool {
        stage.pretend.agents != nil || stage.pretend.connect != nil
    }

    /// The pretended state of the chosen agent: the bench's, or where the
    /// agents on the pretended Mac leave it.
    private static func pretended(_ stage: WelcomeStage) -> WelcomePretend.Connect {
        stage.pretend.connect ?? defaultState(stage.agent, stage)
    }

    private static func installed(_ cli: String, _ stage: WelcomeStage) -> Bool {
        switch stage.pretend.agents ?? .claude {
        case .none: return false
        case .claude, .claudeConnected: return cli == "claude"
        case .codex, .codexConnected: return cli == "codex"
        case .both: return true
        }
    }

    /// An agent's state as the pretended Mac has it, before any press.
    private static func defaultState(_ cli: String, _ stage: WelcomeStage) -> WelcomePretend.Connect {
        if (cli == "claude" && stage.pretend.agents == .claudeConnected) || (cli == "codex" && stage.pretend.agents == .codexConnected) {
            return .connected
        }
        return installed(cli, stage) ? .signedOut : .notInstalled
    }

    /// The prototype's presses: Install runs 1.8 s and leaves it signed
    /// out; Connect steps the welcome aside as a real sign-in does, brings
    /// it back with the ring still turning, and lands at 1.9 s.
    private static func pretendPress(_ button: WelcomeButton, _ now: State, _ stage: WelcomeStage) -> WelcomeTurn {
        let cli = stage.agent
        pretendRun += 1
        let run = pretendRun
        if button == .quiet {
            guard waits(now) else { return .chapter(4) }
            stage.pretend.connect = now == .signingIn || installed(cli, stage) ? .signedOut : .notInstalled
            if AgentSetupModel.shared.flow == .signingIn(cli) { AgentSetupModel.shared.flow = nil }
            return .stay
        }
        switch now {
        case .just, .connected:
            return .next
        case .notInstalled, .failInstall:
            stage.pretend.connect = .installing
            later(1.8, run, stage) {
                guard stage.pretend.connect == .installing || stage.pretend.connect == .codexTerminal else { return false }
                stage.pretend.connect = .signedOut
                return true
            }
            return .stay
        case .signedOut, .signedIn, .failSignIn, .failTools:
            stage.pretend.connect = .signingIn
            AgentSetupModel.shared.flow = .signingIn(cli)
            later(1.0, run, stage) {
                if AgentSetupModel.shared.flow == .signingIn(cli) { AgentSetupModel.shared.flow = nil }
                return false
            }
            later(1.9, run, stage) {
                guard stage.pretend.connect == .signingIn else { return false }
                stage.pretend.connect = .just
                return true
            }
            return .stay
        case .looking, .installing, .codexTerminal, .signingIn, .settingUp:
            return .stay
        }
    }

    /// A pretended press's next step, unless a newer press or another beat
    /// came first; the beat is shown again when the step changed it.
    private static func later(_ seconds: Double, _ run: Int, _ stage: WelcomeStage, _ step: @escaping @MainActor () -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds * WelcomeMotion.pace) {
            guard pretendRun == run, stage.beat == .connect else { return }
            if step() { stage.refresh() }
        }
    }

    // MARK: - states

    /// Why the last try stopped, in AgentSetupModel's own words, while the
    /// board shows that stop.
    private static func troubleWords(_ cli: String, _ now: State) -> String? {
        guard [.failInstall, .failSignIn, .failTools].contains(now),
              let trouble = AgentSetupModel.shared.trouble, trouble.clis.contains(cli) else { return nil }
        return trouble.words
    }

    private static func waits(_ state: State) -> Bool {
        state == .installing || state == .codexTerminal || state == .signingIn || state == .settingUp
    }

    private static func connects(_ state: State) -> Bool { state == .just || state == .connected }
    private static func connects(_ state: WelcomePretend.Connect) -> Bool { state == .just || state == .connected }
}
