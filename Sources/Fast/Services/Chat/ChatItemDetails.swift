import Foundation

// Details and presentation shared by live agent chats.
extension ChatItem {
    /// A chat's line that is neither yours nor the agent's words, by its
    /// `name` on a `.message`: "compacted" a thin divider, "note" a quiet
    /// line (you stopped it, a model switched, a command's output, a
    /// background task done, another session's message), "status" where it
    /// stands (out of room), "error" an API error, "notice" a safety stop or
    /// a cut answer, "sent" the files it sent you with their caption.
    static let notes: Set<String> = ["compacted", "note", "status", "error", "notice", "sent"]

    var isNote: Bool { kind == .message && Self.notes.contains(name) }

    /// A thinking block folded in the chat ("Thought for
    /// 12s"): its duration in extra["ms"], its words when it has any.
    static let thought = "thought"

    var isThought: Bool { kind == .thinking && name == Self.thought }

    /// ScheduleWakeup's detail: when, and why or what it will do.
    static func wakeup(_ input: [String: Any]) -> String {
        let seconds = (input["delaySeconds"] as? NSNumber)?.doubleValue ?? 0
        let reason = (input["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (input["prompt"] as? String).flatMap { $0.hasPrefix("<<") ? nil : String(($0.split(whereSeparator: \.isNewline).first.map(String.init) ?? "").trimmingCharacters(in: .whitespaces).prefix(120)) }
        let when = seconds > 0 ? "in " + Self.delay(seconds) : ""
        return [when, reason ?? ""].filter { !$0.isEmpty }.joined(separator: ": ")
    }

    /// "90 s" as "2 min", "1 h 30 min".
    static func delay(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        if whole < 60 { return "\(whole) s" }
        let minutes = Int((Double(whole) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
    }

    /// A Workflow's name: its script's meta name, else its file's.
    static func workflow(_ input: [String: Any]) -> String {
        var name = ""
        if let script = input["script"] as? String,
           let found = script.firstMatch(of: #/meta\s*=\s*\{[\s\S]*?name\s*:\s*['"`]([^'"`]+)['"`]/#) {
            name = String(found.output.1)
        } else if let given = input["name"] as? String {
            name = given
        } else if let path = input["scriptPath"] as? String {
            name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            if let run = name.range(of: "-wf_") { name = String(name[..<run.lowerBound]) }
        }
        return name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
    }

    /// Files a SendUserFile call names: "shot.png", "a.md and 2 more".
    static func files(_ input: [String: Any]) -> String {
        let names = (input["files"] as? [String] ?? []).map { ($0 as NSString).lastPathComponent }
        guard let first = names.first else { return "" }
        return names.count == 1 ? first : "\(first) and \(names.count - 1) more"
    }
}

extension ChatItem {
    /// A step's name for a compaction: a thin line across the chat, never words of the agent's.
    static let compacted = "compacted"
    /// What the agent asked you to pick from, said in the turn (Agents.handoff).
    static let question = "question"
    /// A turn you stopped (Codex's turn_aborted): no words, read by ChatTurn.
    static let stopped = "stopped"

    /// A turn you stopped before it ended.
    static func stopped(in turn: [ChatItem]) -> Bool {
        turn.contains { $0.kind == .message && $0.name == ChatItem.stopped }
    }

    /// The pictures a step took or looked at: extra["image"], then any more
    /// in extra["images"], a path a line.
    static func pictures(of item: ChatItem) -> [String] {
        var out: [String] = []
        if let first = item.extra?["image"], !first.isEmpty { out.append(first) }
        out += (item.extra?["images"] ?? "").split(separator: "\n").map(String.init)
        return out
    }
}
