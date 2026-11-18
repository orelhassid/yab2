import SwiftUI

/// A subagent's report as Yab hands it to its task (Agents.report): said
/// to the agent as a message of the person's, so it takes it as a turn, and
/// read back here so the chat draws it as the subagent's card, never as
/// your words in a blue bubble.
struct SubagentReport: Equatable {
    let name: String
    let id: String
    /// Its session's state as it ended: done, stopped, failed.
    let state: String
    /// What it reported, without Yab's lines round it.
    let body: String

    /// What the agent answers to a report that changes nothing it has told
    /// you: a turn the chat doesn't show.
    static let quiet = "(quiet)"

    private static let head = "Subagent "
    private static let done = ") is done ("
    private static let none = " It gave no report."
    /// Under the report, for the agent: a report coming after its answer
    /// needs a word to you only when it changes something.
    static let asking = """

        ---
        If this report changes nothing in what you have told the user, answer with exactly \(quiet) \
        and nothing else. Otherwise tell the user plainly what it changes and what that means for \
        them, in a sentence or two.
        """

    /// The agent's words are only that: nothing for you, nor its answer.
    static func isQuiet(_ words: String) -> Bool { words.trimmingCharacters(in: .whitespacesAndNewlines) == quiet }

    static func message(name: String, id: String, state: String, model: String, over: Int, all: Int, answer: String) -> String {
        var text = head + "\(name) (\(id)" + done + "\(state), \(model), \(over)/\(all) completed)."
        let answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        text += answer.isEmpty ? none : "\n\n" + answer
        return text + asking
    }

    /// The report in a message, or nil for any other message. Chats saved
    /// before `asking` read the same.
    init?(_ said: String) {
        guard said.hasPrefix(Self.head) else { return nil }
        var text = said
        if let asked = text.range(of: Self.asking) { text.removeSubrange(asked) }
        guard let done = text.range(of: Self.done) else { return nil }
        let named = text[text.index(text.startIndex, offsetBy: Self.head.count)..<done.lowerBound]
        guard let open = named.range(of: " (", options: .backwards) else { return nil }
        name = String(named[..<open.lowerBound])
        id = String(named[open.upperBound...])
        let rest = text[done.upperBound...]
        state = String(rest.prefix { $0 != "," && $0 != ")" })
        let body = rest.firstRange(of: "\n\n").map { String(rest[$0.upperBound...]) } ?? ""
        self.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !id.isEmpty else { return nil }
    }

    /// Its finding in one line, under its name.
    var gist: String {
        if body.isEmpty || body.hasPrefix("Stopped at the ") && body.hasSuffix("without a report.") {
            return state == "done" ? "No report" : "Stopped without a report"
        }
        let lines = body.split(whereSeparator: \.isNewline).map { Chat.plain(String($0)).trimmingCharacters(in: .whitespaces) }
        let line = lines.first { !$0.isEmpty && !$0.hasPrefix("```") && $0 != "---" } ?? ""
        return line.trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
    }
}

extension ChatItem {
    /// A subagent's report, said to the agent as yours.
    var subagentReport: SubagentReport? { kind == .asked ? SubagentReport(text) : nil }
    /// The agent's answer to a report that changes nothing: not shown.
    var isQuiet: Bool { kind == .message && SubagentReport.isQuiet(text) }
}

/// A subagent in its task's chat: its face, its name, a line of what it
/// does or found, and its report a click away. A plate on the bubbles'
/// body, as a mail draft's is (ChatMailDraft): steps aren't shown in a
/// chat, a subagent is.
struct ChatSubagentCard: View {
    let name: String
    /// While it works: what it does now, and since when.
    var live: (now: String, since: Date)? = nil
    var report: SubagentReport? = nil
    @State private var open = false

    /// One inset all round: the button as far from the plate's end as from
    /// its top and foot, the words 12 in as a bubble's are.
    private static let inset: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                face
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .glint(live != nil, anchor: live?.since)
                        .foregroundStyle(Palette.ink)
                    Text(line)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.muted)
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 8)
                if let live {
                    TimelineView(.periodic(from: live.since, by: 1)) { context in
                        Text(Self.clock(context.date.timeIntervalSince(live.since)))
                            .font(.system(size: 12))
                            .foregroundStyle(Palette.muted)
                            .monospacedDigit()
                    }
                    .padding(.trailing, 4) // design: the time stands as far in as the button's words would
                } else if let report, !report.body.isEmpty {
                    Button(open ? "Hide" : "Show Report") { open.toggle() }
                        .buttonStyle(.yab(.secondary, .small, capsule: true))
                        .focusable(false)
                        .fixedSize()
                        .keyTip(open ? "Hide its report" : "What it found")
                }
            }
            .frame(minHeight: 24)
            if open, let report {
                ChatWords(text: report.body, streaming: false, size: 13)
                    .textSelection(.enabled)
                    .padding(.leading, 26) // design: under its name, past the face's 18 and its gap of 8
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
                    .transition(.opacity)
            }
        }
        .padding(Self.inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: Radius.window, style: .continuous)) // design: a bubble's own curve, the plate stands among them
        .padding(.trailing, 40) // design: as wide as a bubble, room kept on the right as the bubbles keep it
        .animation(Motion.chatQuick, value: open)
        .accessibilityElement(children: .contain)
    }

    private var line: String {
        if let live { return live.now.isEmpty ? "Working" : live.now }
        return report?.gist ?? ""
    }

    /// Its face: eyes while it works, the tick once it reported, eyes half
    /// shut when it was stopped.
    private var face: some View {
        let done = report?.state == "done"
        let stopped = report != nil && !done
        return ZStack {
            Circle().stroke(lineWidth: 1.5)
            Eyes(gaze: .zero, open: stopped ? 0.35 : 1, tick: done ? 1 : 0)
                .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
        }
        .foregroundStyle(Palette.ink.opacity(0.8))
        .frame(width: 18, height: 18)
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}

/// The task's subagents still at work, under the turn going on: a card
/// each, with what it does now. Each gives way to its report's card.
struct ChatSubagentsLive: View {
    let chat: Chat
    @ObservedObject private var agents = Agents.shared

    var body: some View {
        let working = chat.subagents.compactMap { agents.session($0.id) }.filter { $0.state.live }
        ForEach(working) { session in
            ChatSubagentCard(name: session.name, live: (Self.now(session.now), session.began))
                .padding(.leading, MessageBubble.tailRoom) // design: on the bubbles' body, as the chat's plates stand
                .transition(.opacity)
        }
    }

    /// What it does, in its step's words; Yab's own notes on it aren't that.
    static func now(_ words: String) -> String {
        ["Next: ", "Queued: ", "Steered: ", "Waiting for subagents"].contains { words.hasPrefix($0) } ? "" : words
    }
}
