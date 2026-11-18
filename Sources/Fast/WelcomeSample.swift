import SwiftUI
import AppKit

// Chapters 1 and 2, on the sample world: what Yab is before anything is
// asked. Everything you're used to (pins and folders, Peek into Split View,
// the box that finds anything), then your agent at work in tabs you can see,
// on a recorded run: the task typed into the same box, the agent in its own
// tabs with the dock and the chat, and what each pull request needs. The
// parts are Yab's own (WelcomeParts); the world is a sample, said once by
// chapter 2's marker.
//
// Each beat is the prototype's: its boards at each phase (`board`) and how
// it plays from the beat before (`play`), with the tabs on top or in the
// sidebar as this Mac has them. Chapter 1 folded away (open decision 1),
// Welcome goes straight to the task, the same parts arriving and the box
// rising at once.
//
// Chapter 1 plays on by itself, a beat each `WelcomeStage.runLength`, its
// dash filling as it goes, and stops at the task, which waits for a press.
// Continue goes on sooner; a beat come back to stands still.

@MainActor
enum WelcomeSample: WelcomeChapter {
    static let task = "Catch me up on my pull requests"

    static let scenes: [(beat: WelcomeStage.Beat, label: String)] = [
        (.pins, "Organize tabs in folders"),
        (.peek, "Peek at a link in Split View"),
        (.find, "Find a page or command"),
        (.task, "Give your agent a task"),
        (.watch, "Follow its work in tabs"),
        (.results, "Review what needs you"),
    ]

    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat] {
        scenes.map(\.beat)
    }

    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords {
        var words = WelcomeWords(title: "A tour of Yab.", sub: "Explore a sample workspace. Select any step to play its preview.")
        words.scene = moment.beat
        return words
    }

    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn {
        .chapter(3)
    }

    // MARK: - playing

    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async {
        switch moment.beat {
        case .pins:
            // The row (or the column) and the page out of the mark, the
            // folder shut; then it opens where it sits.
            player.show("arrive")
            guard await player.wait(0.4) else { return }
            player.show()
            await player.runOn()
        case .peek:
            if moment.from != nil {
                // The link pressed, the Peek out of it, a hold, then Split
                // View pressed and the Peek on to the right half.
                player.show("press")
                player.press("link")
                guard await player.wait(0.18) else { return }
                player.show("peek")
                guard await player.wait(1.2) else { return }
                player.show("splitpress")
                player.press(peekButtons + "-split", to: 0.94)
                guard await player.wait(0.17) else { return }
            }
            player.show()
            await player.runOn()
        case .find:
            player.show("type")
            guard await player.wait(0.24), await player.type("peek", in: "box") else { return }
            player.show()
            // Then on to the task by itself, where the agent waits for a press.
            await player.runOn()
        case .task:
            // The same box: what it holds taken back, then the task typed.
            let box = player.frame(of: "box") != nil
            if box {
                guard await player.type("", in: "box", from: moment.from == .find ? "peek" : "") else { return }
            }
            player.show("type")
            guard await player.wait(box ? 0.06 : 0.3), await player.type(task, in: "box") else { return }
            player.show()
            await player.runOn()
        case .watch:
            if moment.from == .task, player.frame(of: "tr-ask") != nil {
                player.press("tr-ask", to: 0.98)
                guard await player.wait(0.16) else { return }
            }
            // Activity advances in the dock and head while the chat waits.
            player.show("run", index: 0)
            for step in 1..<activity.count {
                guard await player.wait(1.1) else { return }
                player.show("run", index: step)
            }
            await player.runOn()
        case .results:
            guard moment.from == .watch else { player.show(); return }
            player.show("done")
            guard await player.wait(0.8) else { return }
            player.show()
        default:
            player.show()
        }
    }

    // MARK: - the boards

    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        let at = Layout(side: stage.held.sidebar)
        let grow = moment.from == .welcome
        switch moment.beat {
        case .pins:
            return pinned(sample(moment.phase == "arrive" ? .shut : .open, at, grow: grow))
        case .peek:
            switch moment.phase {
            case "rest": return pinned(sample(.split, at))
            case "peek", "splitpress": return pinned(sample(.open, at) + peek(at))
            default: return pinned(sample(.open, at))
            }
        case .find:
            return pinned(sample(.split, at) + WelcomeBoard([findBox(at, typing: moment.phase == "type")]))
        case .task:
            let world = sample(.split, at)
            return pinned(world + WelcomeBoard([taskBox(at, typing: moment.phase == "type", delay: grow ? 0.26 : nil)]))
        case .watch:
            // At rest (Back, the bench) it is on its second step, reading.
            let step = moment.phase == "run" || moment.index > 0 ? min(max(moment.index, 0), activity.count - 1) : 1
            let board = agentBoard(at, step: step, dock: activity[step], done: false)
            return pinned(WelcomeBoard(board.parts, exits: ["box": .toward("row")]))
        default:
            // Done: the dock says so, then sinks; then what each one needs.
            return pinned(moment.phase == "done"
                ? agentBoard(at, step: activity.count, dock: "Done", done: false)
                : agentBoard(at, step: nil, dock: nil, done: true))
        }
    }

    /// Where the sample's parts stand, with the tabs on top or in the
    /// sidebar (the prototype's `board` and `agentBoard`).
    private struct Layout {
        let side: Bool

        static let row = CGRect(x: 150, y: 140, width: 880, height: 40)
        /// 230 wide, room for the header's whole row as the app lays it out
        /// (ColumnHead.full: 218 at the least).
        static let column = CGRect(x: 150, y: 136, width: 230, height: 540)
        /// Where the face reads on the pull request, a step each, on top.
        static let discs = [CGPoint(x: 590, y: 262), CGPoint(x: 596, y: 404), CGPoint(x: 596, y: 522), CGPoint(x: 560, y: 300)]

        /// The page alone.
        var page: CGRect { side ? CGRect(x: 388, y: 136, width: 642, height: 540) : CGRect(x: 150, y: 196, width: 880, height: 470) }
        /// Split View's two halves, 16 apart.
        var left: CGRect { side ? CGRect(x: 428, y: 160, width: 293, height: 526) : CGRect(x: 150, y: 216, width: 432, height: 470) }
        var right: CGRect { side ? CGRect(x: 737, y: 160, width: 293, height: 526) : CGRect(x: 598, y: 216, width: 432, height: 470) }
        /// Peek's panel over the page, and its buttons 12 right of it.
        var peek: CGRect { side ? CGRect(x: 465, y: 250, width: 488, height: 400) : CGRect(x: 330, y: 258, width: 520, height: 390) }
        var peekButtons: CGPoint { CGPoint(x: peek.maxX + 12, y: peek.minY) }
        /// Chapter 2's pull request and the agent's chat beside it.
        var pullRequest: CGRect { side ? CGRect(x: 388, y: 136, width: 346, height: 540) : CGRect(x: 150, y: 196, width: 544, height: 470) }
        var chat: CGRect { side ? CGRect(x: 750, y: 136, width: 280, height: 540) : CGRect(x: 710, y: 196, width: 320, height: 470) }

        /// The face's disc at a step, its middle: over the comment it reads
        /// on top, down the page's right side in the sidebar's narrower one.
        func disc(_ step: Int) -> CGPoint {
            let spot = Self.discs[min(max(step, 0), Self.discs.count - 1)]
            let x = side ? pullRequest.maxX - 64 : spot.x
            let y = side ? spot.y - 56 : spot.y
            return CGPoint(x: x + 14, y: y + 14)
        }
    }

    // MARK: chapter 1

    /// The folder "Design": shut on its count, open with its two tabs, or
    /// open with both of them in Split View.
    private enum Folder { case shut, open, split }

    private static let peekButtons = "peekbtns"

    private static let pins: [WelcomeTab] = [.pin(.mail, key: "p-mail"), .pin(.calendar, key: "p-cal"), .pin(.code, key: "p-gh")]

    /// The row of tabs: the pins, the folder, then "Pull requests", "Q3 plan"
    /// and the plus.
    private static func sampleRow(_ folder: Folder) -> [WelcomeTab] {
        let tail: [WelcomeTab] = [.gap(4), .tab("Pull requests", .code, width: 150, key: "t-prs"), .tab("Q3 plan", .docs, width: 136, key: "t-q3"),
                                  .plus(key: "plus")]
        guard folder != .shut else { return pins + [.gap(6), .folder("Design", count: 2, key: "f-design")] + tail }
        let design: WelcomeTab = .nest(key: "nest-design", [
            .folder("Design", open: true, key: "f-design"),
            .tab("Y-214 Peek keeps its scroll", .tracker, width: 200, key: "t-y214", on: true, enter: .slideX, delay: 0),
            .tab("Peek spec", .docs, width: 136, key: "t-spec", on: folder == .split, enter: .slideX, delay: 0.03),
        ])
        return pins + [.gap(6), design] + tail
    }

    /// The same, down the sidebar's column: the folder opens downward and
    /// its two tabs drop in.
    private static func sampleRows(_ folder: Folder) -> [WelcomeTab] {
        guard folder != .shut else { return [.folder("Design", count: 2, key: "f-design")] + columnTail }
        return [.folder("Design", open: true, key: "f-design"),
                .tab("Y-214 Peek keeps its scroll", .tracker, key: "t-y214", on: true, indent: true, enter: .slideY, delay: 0),
                .tab("Peek spec", .docs, key: "t-spec", on: folder == .split, indent: true, enter: .slideY, delay: 0.03)] + columnTail
    }

    /// The column under what is kept: the line, your two tabs, New tab.
    private static var columnTail: [WelcomeTab] {
        // Keyed, so the line moves with the rows under it.
        var line = WelcomeTab.hairline
        line.key = "col-line"
        return [line, .newTab(key: "plus"), .tab("Pull requests", .code, key: "t-prs")]
    }

    /// Chapter 1's world: the row (or column) and the tracker's page, whole
    /// or in Split View beside the Peek spec. `grow`: out of Welcome's mark.
    private static func sample(_ folder: Folder, _ at: Layout, grow: Bool = false) -> WelcomeBoard {
        let enter: StagePart.Enter = grow ? .grow(from: "wmark") : .fade
        var parts = [at.side
            ? WelcomeParts.column("col", Layout.column, pins: columnPins, rows: sampleRows(folder), enter: enter, plate: true)
            : WelcomeParts.row("row", Layout.row, sampleRow(folder), enter: enter)]
        if folder == .split {
            parts.append(WelcomeParts.page("pg-y214", at.left, .tracker, enter: enter, delay: 0.04))
            parts.append(WelcomeParts.page("pg-spec", at.right, .spec, edge: .front, enter: .fade, delay: 0.06))
        } else {
            parts.append(WelcomeParts.page("pg-y214", at.page, .tracker, enter: enter, delay: 0.04))
        }
        return WelcomeBoard(parts)
    }

    /// Peek over the page, grown out of its link, with its three buttons.
    /// The same key as Split View's right half, so Split View takes it there.
    private static func peek(_ at: Layout) -> WelcomeBoard {
        WelcomeBoard([
            WelcomeParts.page("pg-spec", at.peek, .spec, edge: .peek, enter: .grow(from: "link")),
            WelcomeParts.peekButtons(peekButtons, at: at.peekButtons, enter: .fade, delay: 0.1),
        ])
    }

    /// The ⌘T box over the pages, where chapter 1 and chapter 2 both have
    /// it: the Omnibox made smaller for the sample's smaller window, at
    /// most 640 wide and 40 off the page's sides, 300 under its field, in
    /// the middle of the page and placed as Omnibox.top places the real
    /// one. One height, as the real box is, whatever the rows.
    private static func box(_ at: Layout, query: String, rows: [WelcomeBoxRow], foot: WelcomeBoxFoot, delay: Double? = nil) -> StagePart {
        let key = Keymap.shared.text(.newTab)
        let page = at.page
        let width = min(640, page.width - 2 * 40)
        let height = Omnibox.fieldHeight + 300
        let top = max(16, min(((page.height - height) / 2).rounded(), (page.height * 0.18).rounded()))
        return WelcomeParts.box(at: CGPoint(x: (page.midX - width / 2).rounded(), y: page.minY + top), width: width, height: height,
                                query: query, keys: key.isEmpty ? nil : key, rows: rows, foot: foot, enter: .rise, delay: delay)
    }

    private static func findBox(_ at: Layout, typing: Bool) -> StagePart {
        box(at, query: typing ? "" : "peek", rows: typing ? [] : [
            WelcomeBoxRow(key: "fr-1", mark: .site(.docs), title: "Peek spec", detail: "docs.google.com", end: .words("In Design"),
                          chosen: true, enter: .fade, delay: 0),
            WelcomeBoxRow(key: "fr-2", mark: .site(.code), title: "Peek, and why the page keeps its scroll", detail: "github.com",
                          end: .words("Yesterday"), enter: .fade, delay: 0.03),
            WelcomeBoxRow(key: "fr-3", mark: .well("rectangle.split.2x1"), title: "Split View with Peek spec", end: .words("Action"),
                          enter: .fade, delay: 0.06),
            WelcomeBoxRow(key: "fr-4", mark: .well("magnifyingglass"), title: "peek", detail: "Google", enter: .fade, delay: 0.09),
        ], foot: WelcomeBoxFoot(primary: "Switch to Tab"))
    }

    // MARK: chapter 2

    /// The task's row has nothing but Return: the pill says what it does.
    private static func taskBox(_ at: Layout, typing: Bool, delay: Double?) -> StagePart {
        let key = Keymap.shared.text(.agentAsk)
        return box(at, query: typing ? "" : task, rows: typing ? [] : [
            WelcomeBoxRow(key: "tr-ask", mark: .tile("agent.face", .systemBlue), title: "Ask your agent", detail: "in tabs of its own, where you can see",
                          end: key.isEmpty ? .none : .keys(key), chosen: true, enter: .fade, delay: 0),
            WelcomeBoxRow(key: "tr-web", mark: .well("magnifyingglass"), title: "Search the web", detail: "Google", enter: .fade, delay: 0.03),
        ], foot: WelcomeBoxFoot(primary: "Ask Agent", actions: false), delay: delay)
    }

    /// Only the dock and the head say what the recorded agent is doing.
    private static let activity = [
        "Opening your 3 pull requests", "Reading 7 review comments",
        "Checking CI on each", "Writing it up",
    ]

    /// What each pull request needs, one row each, in words.
    private static let answers = [
        WelcomeAnswer(mark: .code, title: "#482 Sidebar width", state: "2 changes asked"),
        WelcomeAnswer(mark: .code, title: "#479 Tab sleep", state: "Approved"),
        WelcomeAnswer(mark: .code, title: "#476 Paste in the field", state: "CI failed"),
    ]

    private static var columnPins: [WelcomeTab] { pins + [.pin(.docs, key: "p-docs")] }

    private static func taskFolder(done: Bool, compact: Bool = false) -> WelcomeTab {
        var folder = WelcomeTab.folder(compact ? "Catch me up\u{2026}" : task, open: true, task: !done, key: "f-agent", enter: .pop)
        folder.unread = done
        return folder
    }

    /// The row with the agent's folder open on its three tabs, "Design"
    /// shut, your two tabs squeezed to their icons.
    private static func agentRow(done: Bool) -> [WelcomeTab] {
        let waiting: FacePose? = done ? nil : .watch
        let agent: WelcomeTab = .nest(key: "nest-agent", [
            taskFolder(done: done, compact: true),
            .tab("#482 Sidebar width", .code, width: 136, key: "a-482", on: true, face: done ? nil : .read, enter: .pop, delay: 0.04),
            .tab("#479 Tab sleep", .code, width: 136, key: "a-479", face: waiting, enter: .pop, delay: 0.08),
            .tab("#476 Paste in the field", .code, width: 136, key: "a-476", face: waiting, enter: .pop, delay: 0.12),
        ], enter: .pop)
        return pins + [.gap(6), .folder("Design", count: 2, key: "f-design"), .gap(4), agent, .gap(4),
                       .icon(.code, key: "t-prs"), .icon(.docs, key: "t-q3"), .plus(key: "plus")]
    }

    /// The same down the column: the agent's folder under "Design", its
    /// tabs 12 in, faces at their ends.
    private static func agentRows(done: Bool) -> [WelcomeTab] {
        let waiting: FacePose? = done ? nil : .watch
        return [.folder("Design", count: 2, key: "f-design"),
                taskFolder(done: done),
                .tab("#482 Sidebar width", .code, key: "a-482", on: true, face: done ? nil : .read, indent: true, enter: .pop, delay: 0.04),
                .tab("#479 Tab sleep", .code, key: "a-479", face: waiting, indent: true, enter: .pop, delay: 0.08),
                .tab("#476 Paste in the field", .code, key: "a-476", face: waiting, indent: true, enter: .pop, delay: 0.12)] + columnTail
    }

    /// Chapter 2's world: the agent in its own tabs, the pull request it
    /// reads with the face's disc over it, the dock at the page's foot and
    /// the chat beside. `step`: the one it is on (past the last: all done);
    /// `done`: the answer in place of the steps, the dock gone.
    private static func agentBoard(_ at: Layout, step: Int?, dock: String?, done: Bool) -> WelcomeBoard {
        var parts = [at.side
            ? WelcomeParts.column("col", Layout.column, pins: columnPins, rows: agentRows(done: done), plate: true)
            : WelcomeParts.row("row", Layout.row, agentRow(done: done))]
        let page = at.pullRequest
        parts.append(WelcomeParts.page("pg-pr", page, .pullRequest(narrow: at.side), enter: .crossfade))
        if !done, let step, step < Layout.discs.count {
            parts.append(WelcomeParts.disc(at: at.disc(step), enter: .pop, delay: 0.26))
        }
        if let dock {
            parts.append(WelcomeParts.dock(under: page, words: dock, enter: .up12, delay: 0.16, exit: .sink))
        }
        let body: WelcomeChatBody = done ? .answer(answers) : .working(activity[min(step ?? 0, activity.count - 1)])
        parts.append(WelcomeParts.chat("chat", at.chat, task: task, body: body, enter: .chat, delay: 0.06))
        return WelcomeBoard(parts)
    }

    // MARK: - moving

    /// Every part of a board takes a new size at once and glides only by
    /// its place, as the prototype's parts did: a tab squeezed to its icon
    /// or a folder shut on its count is never stretched on the way, and the
    /// box takes its rows' height as they come. Pages and the chat were
    /// pinned already; their plates still reshape on Core Animation.
    private static func pinned(_ board: WelcomeBoard) -> WelcomeBoard {
        func pin(_ part: StagePart) -> StagePart {
            var part = part
            part.resize = .pin
            part.children = part.children.map(pin)
            return part
        }
        return WelcomeBoard(board.parts.map(pin), exits: board.exits)
    }
}
