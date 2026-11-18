import AppKit
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct WelcomePickTests {
    private func browser(rows: Int, colors: Bool = false) -> WelcomeYours.Found {
        WelcomeYours.Found(id: "Arc", name: "Arc", caption: "Used today", icon: nil,
                          rows: (0..<rows).map { .init(mark: .init(symbol: "bookmark", tint: .systemOrange), words: "Row \($0)") },
                          colors: colors ? [(name: "Work", color: .systemBlue)] : [],
                          places: 6, placeWord: "spaces", sidebar: true, source: nil, sample: nil)
    }

    @Test func abandonedDirectoriesDisappearButEveryKindOfDataKeepsItsBrowser() {
        #expect(!WelcomeYours.offers(Bringing.Counts(), used: nil))
        #expect(WelcomeYours.offers(Bringing.Counts(), used: .now))
        for field in [\Bringing.Counts.passwords, \.cards, \.addresses, \.memory, \.chats,
                      \.bookmarks, \.places, \.cookies, \.signIns] {
            var counts = Bringing.Counts()
            counts[keyPath: field] = 0
            #expect(!WelcomeYours.offers(counts, used: nil))
            counts[keyPath: field] = 1
            #expect(WelcomeYours.offers(counts, used: nil))
        }
        let url = URL(string: "https://welcome.test/")!
        let place = TabImport.Place(id: "test", name: "Work", profile: "Default", shared: true,
                                   pinned: [], open: [TabImport.Entry(url: url, title: "Open")])
        #expect(WelcomeYours.offers(Bringing.Counts(tabPlaces: [place], withOpen: true), used: nil))
    }

    @Test func theReportedArcCardAndLargestCardStayAboveTheFooter() {
        let arc = browser(rows: 8, colors: true)
        #expect(WelcomeYours.countsColumns(arc, keep: true) == 2)
        #expect(WelcomeYours.countsHeight(arc, keep: true) == 256)
        #expect(348 + WelcomeYours.countsHeight(arc, keep: true) == 604)
        #expect(WelcomeYours.countsColumns(browser(rows: 6), keep: false) == 1)
        #expect(WelcomeYours.countsColumns(browser(rows: 6, colors: true), keep: false) == 2)
        for rows in 0...10 {
            let found = browser(rows: rows, colors: true)
            let bottom = 348 + WelcomeYours.countsHeight(found, keep: true)
            #expect(bottom + 16 + 16 < 716)
        }
    }

    /// Bring's lines (6f6095df) are 64 tall each: a one-column card with
    /// them pairs its counts up rather than run the keychain line into the
    /// footer, as the bench's Arc (five counts, colors, Keep, a manager) did.
    /// Since 2ceefb03f a password manager is Passwords' own beat, not a
    /// Bring line, so only the blocker's line is left to push the card.
    @Test func bringsLinesKeepTheKeychainLineAboveTheFooter() {
        var arc = browser(rows: 5, colors: true)
        arc.manager = PasswordManagers.bitwarden
        #expect(arc.extras == 0)
        #expect(WelcomeYours.countsColumns(arc, keep: true) == 1)
        #expect(348 + WelcomeYours.countsHeight(arc, keep: true) + 16 + 16 < WelcomeYours.countsFloor)
        arc.blockers = [(id: "ddkjiahejlhfcafbddmgiahcphecmpfh", name: "uBlock Origin Lite")]
        #expect(WelcomeYours.countsColumns(arc, keep: true) == 2)
        #expect(348 + WelcomeYours.countsHeight(arc, keep: true) + 16 + 16 < WelcomeYours.countsFloor)
        var dia = browser(rows: 5)
        dia.manager = PasswordManagers.onePassword
        dia.blockers = [(id: "ddkjiahejlhfcafbddmgiahcphecmpfh", name: "uBlock Origin Lite")]
        #expect(WelcomeYours.countsColumns(dia, keep: false) == 1)
        #expect(348 + WelcomeYours.countsHeight(dia, keep: false) + 16 + 16 < WelcomeYours.countsFloor)
    }

    @Test func nineAndTenBrowsersFitWithRoomForTheirNamesAndRings() {
        for count in [9, 10] {
            let frames = (0..<count).map { WelcomeYours.browserFrame($0, count: count) }
            #expect(Set(frames.map(\.midX)).count == 3)
            #expect(Set(frames.map(\.midY)).count == (count + 2) / 3)
            #expect(frames[1].midX - frames[0].midX >= 154)
            #expect(frames[3].minY - frames[0].maxY >= 44)
        }
    }

    @Test func browserChoiceMovesOnlyTheRingAndMissingAppsHaveLetters() {
        let stage = WelcomeStage.shared
        let before = (stage.pretend, stage.source, stage.sourceID, stage.keepSpaces, stage.brought, stage.bringFailure)
        defer { (stage.pretend, stage.source, stage.sourceID, stage.keepSpaces, stage.brought, stage.bringFailure) = before }
        stage.pretend.browsers = .three
        stage.pretend.bring = .fresh
        stage.source = 0
        let first = WelcomeYours.board(WelcomeMoment(beat: .move), stage)
        WelcomeYours.pick(2, stage)
        let next = WelcomeYours.board(WelcomeMoment(beat: .move), stage)
        #expect(WelcomeYours.chosen(stage)?.id == "arc")
        #expect(first.parts.filter { $0.key.hasPrefix("pick-src-") }.map(\.key) == ["pick-src-dia"])
        #expect(next.parts.filter { $0.key.hasPrefix("pick-src-") }.map(\.key) == ["pick-src-arc"])
        for part in first.parts where part.key.hasPrefix("src-") {
            #expect(next.parts.first { $0.key == part.key }?.frame == part.frame)
        }
        if case .letter(let name) = browser(rows: 3).mark { #expect(name == "Arc") }
        else { Issue.record("An absent app must have a visible letter mark") }
    }

    @Test func ringMotionAndCenterAreSharedByWaitingAndSelection() {
        for cli in ["claude", "codex", "cursor", "gemini"] {
            let frame = CGRect(x: 100, y: 176, width: 112, height: 112)
            let waiting = WelcomeParts.mark("mark", frame, .agent(cli), ring: true)
            let pick = WelcomeParts.pick("pick", frame, .agent(cli))
            let ring = waiting.children.first!
            #expect(pick.frame == ring.frame.offsetBy(dx: frame.minX, dy: frame.minY))
            #expect(pick.frame.midX == frame.midX && pick.frame.midY == frame.midY)
            #expect(pick.enter == .pick && pick.exit == .tuck)
        }
    }

    @Test func chosenAgentKeepsItsRingAndStatusInEveryKnownState() {
        let stage = WelcomeStage.shared
        let saved = (stage.pretend, stage.agent)
        defer { (stage.pretend, stage.agent) = saved }
        let states: [(WelcomePretend.Connect, String, Bool, Bool)] = [
            (.notInstalled, "Yab sets it up, then you sign in", false, false),
            (.signedOut, "Signed out", false, false), (.signedIn, "Signed in", false, false),
            (.installing, "Setting up", true, false), (.codexTerminal, "Paste in Terminal", true, false),
            (.signingIn, "Signing in", true, false),
            (.just, "Connected", false, true), (.connected, "Connected", false, true),
            (.failInstall, "Yab sets it up, then you sign in", false, false),
            (.failSignIn, "Signed out", false, false), (.failTools, "Signed in", false, false),
        ]
        for cli in WelcomeConnect.order {
            for reduce in [false, true] {
                for (state, status, waiting, tick) in states {
                    stage.pretend = WelcomePretend()
                    stage.pretend.agents = WelcomePretend.Agents.none
                    stage.pretend.connect = state
                    stage.pretend.reduceMotion = reduce
                    stage.agent = cli
                    let moment = WelcomeMoment(beat: .connect)
                    WelcomeConnect.arrive(moment, stage)
                    let parts = WelcomeConnect.board(moment, stage).parts
                    let keys = parts.map(\.key)
                    #expect(keys.filter { $0.hasPrefix("pick-") } == (waiting && !reduce ? [] : ["pick-" + cli]))
                    let mark = parts.first { $0.key == "mark-" + cli }!
                    #expect(mark.children.contains { $0.key == "mark-\(cli)-ring" } == (waiting && !reduce))
                    #expect(mark.children.contains { $0.key == "mark-\(cli)-tick" } == tick)
                    let line = parts.first { $0.key == "state-" + cli }
                    #expect((line?.version as? String)?.hasPrefix(status) == true)
                    #expect(line!.frame.minY >= parts.first { $0.key == "name-" + cli }!.frame.maxY + 6)
                }
            }
        }
    }

    @Test func continuousRingsKeepSixPointsOfSpaceAlongSidesAndCorners() {
        for (icon, side) in [(WelcomeIcon.agent("claude"), CGFloat(112)), (.agent("codex"), 112),
                             (.agent("cursor"), 112), (.agent("gemini"), 112), (.letter("Comet"), 96), (.letter("Comet"), 128)] {
            let shape: (fill: CGFloat, corner: CGFloat)
            if case .agent(let cli) = icon { shape = AgentIcons.outline(cli) } else { shape = (1, 0.226) }
            let square = side * 0.8 * shape.fill
            let inset = (side - square) / 2
            let edge = polygon(WelcomeRingLayer.outline(CGRect(x: inset, y: inset, width: square, height: square), corner: square * shape.corner))
            let (rect, corner) = WelcomeParts.ringFrame(icon, side: side)
            let ring = polygon(WelcomeRingLayer.outline(rect.insetBy(dx: 1, dy: 1), corner: corner))
            for point in ring {
                let gap = zip(edge, edge.dropFirst()).map { distance(point, $0.0, $0.1) }.min()!
                #expect(gap >= 5.9 && gap <= 6.1)
            }
        }
    }

    private func polygon(_ path: CGPath) -> [CGPoint] {
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            switch e.type {
            case .moveToPoint, .addLineToPoint: points.append(e.points[0])
            case .addCurveToPoint:
                let start = points.last!, a = e.points[0], b = e.points[1], end = e.points[2]
                for step in 1...48 {
                    let t = CGFloat(step) / 48, u = 1 - t
                    points.append(CGPoint(x: u*u*u*start.x + 3*u*u*t*a.x + 3*u*t*t*b.x + t*t*t*end.x,
                                          y: u*u*u*start.y + 3*u*u*t*a.y + 3*u*t*t*b.y + t*t*t*end.y))
                }
            case .closeSubpath: points.append(points[0])
            default: break
            }
        }
        return points
    }

    private func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = dx*dx + dy*dy
        let t = length > 0 ? max(0, min(1, ((p.x-a.x)*dx + (p.y-a.y)*dy) / length)) : 0
        return hypot(p.x-a.x-t*dx, p.y-a.y-t*dy)
    }
}
