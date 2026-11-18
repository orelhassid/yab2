import Foundation
import SyncKit

/// One step of an agent's turn, the same whoever answers: Codex's
/// app-server items and Claude Code's stream-json blocks both come down to
/// these, so what shows a chat never asks which agent it is showing.
struct ChatItem: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case asked, message, thinking, tool, command, edit, plan, subagent, chose
        /// A widget Claude drew with its visualize tool (show_widget), shown
        /// where it was made in the turn (ChatWidget): its code in
        /// extra["widget"], its title in extra["widgetTitle"], what it said
        /// while it was being drawn in extra["loading"]. Or one Codex drew
        /// (CodexVisualize): its fragment's file in extra["widgetFile"],
        /// extra["widgetKit"] "codex".
        case widget
        /// A thing a step made, as a card under the answer (ResultCard,
        /// ChatResultCard): its kind in `name`, its spec's JSON in `text`.
        /// It follows the step that made it, or Yab puts it in the turn
        /// itself (a routine from Repeat, the task's folder).
        case card
    }
    enum State: String, Codable { case running, done, failed }

    let id: String
    var kind: Kind
    /// The tool's name, or what a subagent was told to do (spawn, wait).
    var name = ""
    /// What it is about: a page's host, a command line, the files edited.
    var detail = ""
    /// Its words: the message, the thinking's summary, the plan, what a
    /// command printed, why a tool failed.
    var text = ""
    var state = State.running
    /// When it started and ended, as yab heard it: how long a turn worked.
    var began: Date?
    var ended: Date?
    /// The page a step was done in, as its tab was then: its row still
    /// says "Read Home / X" once the tab is closed or Yab has started
    /// again, when "tab:<id>" names no tab any more.
    var page: Page?
    /// What a step left behind: an edited file's path and
    /// its lines added and taken out, an image's path, a web search's
    /// sources, a command's exit status. Optional, so chats
    /// written before it read as they were.
    var extra: [String: String]? = nil

    /// Yab's restart instruction reaches the agent as a user message, but
    /// belongs to the existing turn rather than the person's conversation.
    /// Match older saved chats too, which have no separate internal marker.
    static let macAccessContinuationPrefix = "Mac access was allowed for this task. Continue the original request: "
    var isInternalContinuation: Bool {
        kind == .asked && text.hasPrefix(Self.macAccessContinuationPrefix)
    }

    struct Page: Codable, Equatable {
        var title: String
        var host: String
    }

    /// What a finished tool's answer leaves on its step, from an MCP
    /// result (`content` of text parts): only a boost's tries.
    /// A failed one keeps its words, as Claude Code's do (`answered`).
    static func outcome(_ name: String, _ result: Any?, failed: Bool = false) -> String {
        let parts = (result as? [String: Any])?["content"] as? [[String: Any]] ?? []
        let words = parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
        return failed ? String(words.suffix(outputKept)) : boostTries(name, words) ?? ""
    }

    /// The file a step made for you, from its answer's "Saved: PATH":
    /// save_page, pdf, save_file, download. Shown under the answer (ChatFileCard).
    static func savedFile(_ name: String, _ words: String) -> String? {
        guard ["save_page", "pdf", "save_file", "download"].contains(name), let line = words.split(separator: "\n").first(where: { $0.hasPrefix("Saved: ") }) else { return nil }
        var path = String(line.dropFirst("Saved: ".count))
        if let size = path.range(of: #" \([^()]*\)$"#, options: .regularExpression) { path.removeSubrange(size) }
        return path.hasPrefix("/") ? path : nil
    }

    /// What a copy step put on the clipboard, from its answer's "Copied:
    /// 14 addresses": "copied" in words, and "clip", the id Copy Again
    /// finds it by (AgentClips), which Yab kept as the step ran
    /// (AgentClip.recent). Shown under the answer (ChatCopiedLine).
    static func copied(_ name: String, _ words: String) -> [String: String]? {
        guard name == "copy", let line = words.split(separator: "\n").first(where: { $0.hasPrefix("Copied: ") }) else { return nil }
        let what = String(line.dropFirst("Copied: ".count))
        guard !what.isEmpty else { return nil }
        var out = ["copied": what]
        if let clip = AgentClip.recent.withLock({ $0[what] }) { out["clip"] = clip }
        return out
    }

    /// What a finished step left for the chat to show: the file it made,
    /// what it copied, the cards it made (their JSON, a line each).
    static func marks(_ name: String, _ words: String) -> [String: String]? {
        if let file = savedFile(name, words) { return ["file": file] }
        if let cards = made(name, words) { return ["cards": cards.map(\.json).joined(separator: "\n")] }
        return copied(name, words)
    }

    /// The cards one of Yab's own tools said it made ("Card: {json}"); a
    /// tool of another server says none.
    static func made(_ name: String, _ words: String) -> [ResultCard]? {
        guard !name.contains("/") else { return nil }
        let cards = ResultCard.cards(in: words)
        return cards.isEmpty ? nil : cards
    }

    /// A card step, as it stands in a turn.
    static func card(_ card: ResultCard, id: String, at time: Date? = nil) -> ChatItem {
        ChatItem(id: id, kind: .card, name: card.kind.rawValue, text: card.json, state: .done, began: time, ended: time)
    }

    /// Its card, when it is one Yab knows.
    var resultCard: ResultCard? { kind == .card ? ResultCard(json: text) : nil }

    /// The last thing a turn copied, for its line under the answer.
    static func copied(in turn: [ChatItem]) -> (what: String, clip: String?)? {
        turn.last { $0.extra?["copied"] != nil }.map { ($0.extra!["copied"]!, $0.extra?["clip"]) }
    }

    /// An MCP result's words, its text parts in a line each.
    static func words(_ result: Any?) -> String {
        ((result as? [String: Any])?["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    /// A step with the file it made or what it copied, if it did.
    func saving(_ result: Any?) -> ChatItem {
        guard state == .done, let marks = ChatItem.marks(name, ChatItem.words(result)) else { return self }
        var step = self
        step.extra = (extra ?? [:]).merging(marks) { _, new in new }
        return step
    }

    /// The files a turn's steps made, in the order they came, once each.
    static func files(in turn: [ChatItem]) -> [String] {
        turn.compactMap { $0.extra?["file"] }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    }

    /// A boost call's answer says how many versions of it Yab has tried
    /// (Boosts.fit): kept as "tries:2" for its step's words.
    static func boostTries(_ name: String, _ words: String) -> String? {
        guard name == "boost", let found = words.range(of: #""tries"\s*:\s*\d+"#, options: .regularExpression) else { return nil }
        return "tries:" + words[found].filter(\.isNumber)
    }

    /// The most of a command's output kept, from its end.
    static let outputKept = 20_000

    // MARK: Asides

    /// Lines of Yab's between the agent's words, never its answer: the
    /// conversation compacted, a notice from the CLI (a model switched, a
    /// warning), an error that ended the turn, a review's start and end.
    /// Messages by kind, told apart by their name.
    static let asides: Set<String> = ["compacted", "notice", "error", "review"]
    var isAside: Bool { kind == .message && Self.asides.contains(name) }

    static func aside(_ name: String, id: String, text: String) -> ChatItem {
        ChatItem(id: id, kind: .message, name: name, text: text, state: .done)
    }

    /// A plan's steps as TodoWrite's are kept: [x] done, [>] under way,
    /// [ ] to do (Codex's `turn/plan/updated`).
    static func checklist(_ steps: [[String: Any]]) -> String {
        steps.compactMap { step -> String? in
            guard let text = step["step"] as? String, !text.isEmpty else { return nil }
            switch step["status"] as? String {
            case "completed": return "[x] " + text
            case "inProgress", "in_progress": return "[>] " + text
            default: return "[ ] " + text
            }
        }.joined(separator: "\n")
    }

    // MARK: Codex

    /// A Codex app-server `ThreadItem`, as it starts or as it ends: its
    /// first step (a file change of several files is a step a file).
    static func codex(_ item: [String: Any], done: Bool) -> ChatItem? {
        codexSteps(item, done: done).first
    }

    /// A Codex app-server `ThreadItem` as the chat's steps, as it starts or
    /// as it ends. `images` keeps a picture it made and didn't save.
    static func codexSteps(_ item: [String: Any], done: Bool, images: URL? = nil) -> [ChatItem] {
        guard let id = item["id"] as? String else { return [] }
        let status = item["status"] as? String
        var state: State {
            switch status {
            case "failed", "declined": return .failed
            case "completed": return .done
            default: return done ? .done : .running
            }
        }
        func timed(_ step: ChatItem) -> ChatItem {
            guard let took = item["durationMs"] as? NSNumber else { return step }
            var step = step
            step.extra = (step.extra ?? [:]).merging(["ms": took.stringValue]) { $1 }
            return step
        }
        switch item["type"] as? String {
        case "userMessage":
            let words = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
            return [ChatItem(id: id, kind: .asked, text: words.joined(separator: "\n"), state: .done)]
        case "agentMessage":
            let text = item["text"] as? String ?? ""
            // App-server phases are optional and may gain new wire values.
            // Keep them as metadata, never as a reason to discard words.
            func phased(_ steps: [ChatItem]) -> [ChatItem] {
                guard let phase = item["phase"] as? String else { return steps }
                return steps.map { step in
                    var step = step
                    step.extra = (step.extra ?? [:]).merging(["codexPhase": phase]) { _, new in new }
                    return step
                }
            }
            guard done, CodexVisualize.marked(text) else {
                return phased([ChatItem(id: id, kind: .message, text: text, state: done ? .done : .running)])
            }
            // Over: its words, and a widget where it drew one (CodexVisualize).
            // Nothing of its words left, the words streamed under its id give way.
            let steps = CodexVisualize.steps(text, id: id, state: .done) { words in
                let trimmed = words.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return phased(steps.first?.id == id ? steps : [ChatItem(id: id, kind: .message, text: "", state: .done)] + steps)
        case "reasoning":
            let summary = item["summary"] as? [String] ?? []
            return [ChatItem(id: id, kind: .thinking, text: summary.joined(separator: "\n\n"), state: done ? .done : .running)]
        case "plan":
            return [ChatItem(id: id, kind: .plan, text: item["text"] as? String ?? "", state: done ? .done : .running)]
        case "commandExecution":
            return [timed(codexRun(item, id: id, state: state))]
        case "mcpToolCall":
            let failure = (item["error"] as? [String: Any])?["message"] as? String ?? ""
            let name = named(item["tool"] as? String ?? "", server: item["server"] as? String)
            return [timed(ChatItem(id: id, kind: .tool, name: name,
                                   detail: about(name, item["arguments"] as? [String: Any] ?? [:]),
                                   text: failure.isEmpty ? outcome(name, item["result"], failed: state == .failed) : failure, state: state).saving(item["result"]))]
        case "dynamicToolCall":
            let name = item["tool"] as? String ?? ""
            let failed = state == .failed || (done && item["success"] as? Bool == false)
            return [timed(ChatItem(id: id, kind: .tool, name: name,
                                   detail: about(name, item["arguments"] as? [String: Any] ?? [:]), state: failed ? .failed : state))]
        case "webSearch":
            return [codexSearch(item, id: id, state: state)]
        case "fileChange":
            return codexEdits(item, id: id, state: state)
        case "collabAgentToolCall":
            return [ChatItem(id: id, kind: .subagent, name: item["tool"] as? String ?? "",
                             detail: String((item["prompt"] as? String ?? "").prefix(200)), state: state)]
        case "subAgentActivity":
            let path = ((item["agentPath"] as? String ?? "") as NSString).lastPathComponent.replacingOccurrences(of: "_", with: " ")
            switch item["kind"] as? String {
            case "started": return [ChatItem(id: id, kind: .subagent, name: "spawnAgent", detail: path, state: .done)]
            case "completed": return [ChatItem(id: id, kind: .subagent, name: "wait", detail: path, state: .done)]
            default: return []
            }
        case "imageView":
            let path = item["path"] as? String ?? ""
            var step = ChatItem(id: id, kind: .tool, name: "view_image", detail: (path as NSString).lastPathComponent, state: .done)
            if !path.isEmpty { step.extra = ["image": path] }
            return [step]
        case "imageGeneration":
            let prompt = (item["revisedPrompt"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let failed = state == .failed || item["failure"] is [String: Any]
            var step = ChatItem(id: id, kind: .tool, name: "image_gen",
                                detail: prompt.isEmpty ? "" : "\u{201C}" + String(prompt.prefix(80)) + "\u{201D}",
                                state: failed ? .failed : state)
            // Where it saved it, else what it sent, kept as a file of Yab's.
            let saved = (item["savedPath"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (done && !failed ? (item["result"] as? String).flatMap { AgentLines.keep($0, in: images) } : nil)
            if let saved { step.extra = ["image": saved] }
            return [step]
        case "contextCompaction":
            // Under way, a quiet step for the live line; over, the divider.
            return [done ? aside("compacted", id: id, text: "Context compacted")
                         : ChatItem(id: id, kind: .tool, name: "compact", state: .running)]
        case "enteredReviewMode":
            let review = (item["review"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return [aside("review", id: id, text: review.isEmpty ? "Reviewing" : "Reviewing " + String(review.prefix(160)))]
        case "exitedReviewMode":
            return [aside("review", id: id, text: "Review done")]
        case "hookPrompt":
            return [ChatItem(id: id, kind: .tool, name: "hook", state: .done)]
        case "sleep":
            return [ChatItem(id: id, kind: .tool, name: "sleep", state: state)]
        default:
            return []
        }
    }

    /// A command as Codex parsed it (`commandActions`): a file read, a
    /// search, a listing, several of them as a look around, or a command
    /// to run with what it printed; its exit status kept.
    static func codexRun(_ item: [String: Any], id: String, state: State) -> ChatItem {
        let command = item["command"] as? String ?? ""
        let exit = (item["exitCode"] as? NSNumber)?.intValue
        let failed = state == .failed || (state == .done && (exit ?? 0) != 0)
        let actions = item["commandActions"] as? [[String: Any]] ?? []
        let output = String((item["aggregatedOutput"] as? String ?? "").suffix(outputKept))
        var step: ChatItem
        if !actions.isEmpty, actions.allSatisfy({ ["read", "search", "listFiles"].contains($0["type"] as? String) }) {
            let looks = actions.map(codexLook)
            if looks.count == 1 {
                step = ChatItem(id: id, kind: .tool, name: looks[0].tool, detail: looks[0].about)
            } else {
                var seen = Set<String>()
                let about = looks.map { $0.about }.filter { !$0.isEmpty && seen.insert($0).inserted }
                let more = about.count > 4 ? " and \(about.count - 4) more" : ""
                step = ChatItem(id: id, kind: .tool, name: "explore", detail: about.prefix(4).joined(separator: ", ") + more)
            }
            // A look that failed keeps why.
            if failed { step.text = output }
        } else {
            step = ChatItem(id: id, kind: .command, name: "command", detail: command, text: output)
        }
        step.state = failed ? .failed : state
        if let exit { step.extra = ["exit": String(exit)] }
        return step
    }

    /// One of a command's parsed actions as the tool it amounts to.
    private static func codexLook(_ action: [String: Any]) -> (tool: String, about: String) {
        func last(_ key: String) -> String { ((action[key] as? String ?? "") as NSString).lastPathComponent }
        switch action["type"] as? String {
        case "read":
            let name = action["name"] as? String ?? ""
            return ("Read", name.isEmpty ? last("path") : name)
        case "search":
            let query = action["query"] as? String ?? ""
            let quoted = query.isEmpty ? "" : "\u{201C}" + String(query.prefix(120)) + "\u{201D}"
            let place = last("path")
            return ("Grep", place.isEmpty ? quoted : quoted.isEmpty ? place : quoted + " in " + place)
        default:
            let place = last("path")
            return ("Glob", place.isEmpty ? "." : place)
        }
    }

    /// A web search, or a page it opened or looked in, with what it found.
    static func codexSearch(_ item: [String: Any], id: String, state: State) -> ChatItem {
        let action = item["action"] as? [String: Any] ?? [:]
        var step: ChatItem
        if ["openPage", "findInPage"].contains(action["type"] as? String), let url = action["url"] as? String {
            step = ChatItem(id: id, kind: .tool, name: "WebFetch", detail: URL(string: url)?.host() ?? url, state: state)
        } else {
            let query = (item["query"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? action["query"] as? String ?? (action["queries"] as? [String])?.first ?? ""
            step = ChatItem(id: id, kind: .tool, name: "web_search", detail: about("web_search", ["query": query]), state: state)
        }
        let found = (item["results"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String }
        if !found.isEmpty { step.extra = ["sources": found.prefix(6).joined(separator: "\n")] }
        return step
    }

    /// A file change, a step a file with its diff and its lines added and
    /// taken out.
    static func codexEdits(_ item: [String: Any], id: String, state: State) -> [ChatItem] {
        let changes = item["changes"] as? [[String: Any]] ?? []
        guard !changes.isEmpty else { return [ChatItem(id: id, kind: .edit, name: "edit", state: state)] }
        return changes.map { change in
            let path = change["path"] as? String ?? ""
            let kind = (change["kind"] as? [String: Any])?["type"] as? String ?? change["kind"] as? String ?? "update"
            var diff = change["diff"] as? String ?? ""
            // A file added or deleted comes as its contents.
            let plain = !diff.hasPrefix("@@") && !diff.hasPrefix("---") && !diff.hasPrefix("diff ")
            if plain, kind == "add" || kind == "delete", !diff.isEmpty {
                let mark = kind == "add" ? "+" : "-"
                var lines = diff.components(separatedBy: "\n")
                if lines.last == "" { lines.removeLast() }
                diff = lines.map { mark + $0 }.joined(separator: "\n")
            }
            let counted = AgentLines.counts(diff)
            var edit = ChatItem(id: id + ":" + path, kind: .edit, name: "edit", detail: (path as NSString).lastPathComponent,
                                text: String(diff.prefix(outputKept)), state: state)
            edit.extra = ["path": path, "added": "\(counted.added)", "removed": "\(counted.removed)",
                          "new": kind == "add" ? "1" : "0", "diff": "1"]
            return edit
        }
    }

    /// A Codex `exec --json` item, as it starts or ends: the same steps
    /// its app server's become, so a turn run that way shows its work too.
    static func codexExec(_ item: [String: Any], done: Bool) -> ChatItem? {
        guard let id = item["id"] as? String else { return nil }
        let status = item["status"] as? String
        let state: State = status == "failed" || status == "declined" ? .failed : status == "completed" || done ? .done : .running
        switch item["type"] as? String {
        case "agent_message":
            return ChatItem(id: id, kind: .message, text: item["text"] as? String ?? "", state: done ? .done : .running)
        case "reasoning":
            return ChatItem(id: id, kind: .thinking, text: item["text"] as? String ?? "", state: done ? .done : .running)
        case "command_execution":
            let exit = item["exit_code"] as? Int
            let failed = state == .failed || (done && exit.map { $0 != 0 } ?? false)
            var step = ChatItem(id: id, kind: .command, name: "command", detail: item["command"] as? String ?? "",
                                text: String((item["aggregated_output"] as? String ?? "").suffix(outputKept)), state: failed ? .failed : state)
            if let exit { step.extra = ["exit": String(exit)] }
            return step
        case "file_change":
            let paths = (item["changes"] as? [[String: Any]] ?? []).compactMap { $0["path"] as? String }
            return ChatItem(id: id, kind: .edit, name: "edit", detail: paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "), state: state)
        case "mcp_tool_call":
            let name = named(item["tool"] as? String ?? "", server: item["server"] as? String)
            let failure = (item["error"] as? [String: Any])?["message"] as? String ?? ""
            return ChatItem(id: id, kind: .tool, name: name, detail: about(name, item["arguments"] as? [String: Any] ?? [:]),
                            text: failure.isEmpty ? outcome(name, item["result"], failed: state == .failed) : failure, state: state).saving(item["result"])
        case "web_search":
            return ChatItem(id: id, kind: .tool, name: "web_search", detail: about("web_search", ["query": item["query"] as? String ?? ""]), state: done ? .done : .running)
        case "todo_list":
            let steps = (item["items"] as? [[String: Any]] ?? []).compactMap { step -> String? in
                guard let text = step["text"] as? String else { return nil }
                return (step["completed"] as? Bool == true ? "[x] " : "[ ] ") + text
            }
            return ChatItem(id: id, kind: .plan, text: steps.joined(separator: "\n"), state: .done)
        default:
            return nil
        }
    }

    // MARK: Claude Code

    /// A block of a Claude Code `assistant` message: its words, its
    /// thinking, or a tool it calls. `message` names the message, for the
    /// blocks with no id of their own.
    static func claude(_ part: [String: Any], message: String) -> ChatItem? {
        switch part["type"] as? String {
        case "text":
            guard let words = part["text"] as? String, !words.isEmpty else { return nil }
            return ChatItem(id: message + ".text", kind: .message, text: words, state: .done)
        case "thinking":
            guard let words = part["thinking"] as? String, !words.isEmpty else { return nil }
            return ChatItem(id: message + ".thinking", kind: .thinking, text: words, state: .done)
        case "tool_use":
            guard let id = part["id"] as? String else { return nil }
            let input = part["input"] as? [String: Any] ?? [:]
            let tool = part["name"] as? String ?? ""
            // Claude's app's visualize tool, under its own name or its
            // server's id: a widget in the turn, its guide a quiet step.
            if let widget = widget(id: id, tool: tool, input: input) { return widget }
            if tool.hasPrefix("mcp__"), tool.hasSuffix("__read_me") {
                return ChatItem(id: id, kind: .tool, name: readMe)
            }
            // The tool's own name; another server's keeps its server's.
            let pieces = tool.components(separatedBy: "__")
            let name = tool.hasPrefix("mcp__") && pieces.count >= 3 ? named(pieces.dropFirst(2).joined(separator: "__"), server: pieces[1]) : tool
            switch name {
            case "Bash":
                return ChatItem(id: id, kind: .command, name: "command", detail: input["command"] as? String ?? "")
            case "Edit", "Write", "MultiEdit", "NotebookEdit":
                let path = input["file_path"] as? String ?? input["notebook_path"] as? String ?? ""
                return ChatItem(id: id, kind: .edit, name: "edit", detail: (path as NSString).lastPathComponent)
            case "Task", "Agent":
                return ChatItem(id: id, kind: .subagent, name: "spawnAgent",
                                detail: prose(input["description"] as? String ?? String((input["prompt"] as? String ?? "").prefix(200))))
            case "TodoWrite":
                // Each step with where it stands: [x] done, [>] under way, [ ] to do.
                let todos = (input["todos"] as? [[String: Any]] ?? []).compactMap { todo -> String? in
                    guard let content = todo["content"] as? String else { return nil }
                    let status = todo["status"] as? String ?? "pending"
                    return (status == "completed" ? "[x] " : status == "in_progress" ? "[>] " : "[ ] ") + content
                }
                return ChatItem(id: id, kind: .plan, text: todos.joined(separator: "\n"), state: .done)
            default:
                return ChatItem(id: id, kind: .tool, name: name, detail: about(name, input))
            }
        default:
            return nil
        }
    }

    /// The visualize tool's guide, read before a widget: never a row.
    static let readMe = StepWords.readMe

    /// A show_widget call (mcp__visualize__show_widget, or under the id
    /// Claude's app gives the server, mcp__<uuid>__show_widget) as a
    /// widget; nil for any other tool. Its code may still be on its way:
    /// then only what it said while drawing is kept.
    static func widget(id: String, tool: String, input: [String: Any]) -> ChatItem? {
        guard tool.hasPrefix("mcp__"), tool.hasSuffix("__show_widget") else { return nil }
        var extra: [String: String] = [:]
        if let code = input["widget_code"] as? String, !code.isEmpty { extra["widget"] = code }
        if let title = input["title"] as? String, !title.isEmpty { extra["widgetTitle"] = title }
        if let loading = loading(input["loading_messages"]) { extra["loading"] = loading }
        return ChatItem(id: id, kind: .widget, name: "show_widget", extra: extra)
    }

    /// The first of a widget's loading messages: a list, or (as some
    /// transcripts keep it) that list written out as a string.
    static func loading(_ value: Any?) -> String? {
        if let list = value as? [String] { return list.first { !$0.isEmpty } }
        guard let words = value as? String, !words.isEmpty else { return nil }
        let quoted = words.matches(of: #/["']((?:[^"'\\]|\\.)+)["']/#).map { String($0.output.1) }
        return quoted.first ?? words
    }

    /// The first loading message of a widget's input as it streams in, from
    /// the JSON written so far: said in its place until its code is whole.
    static func loading(partial json: String) -> String? {
        guard let found = json.firstMatch(of: #/"loading_messages"\s*:\s*\[\s*"((?:[^"\\]|\\.)*)"/#) else { return nil }
        let raw = "\"" + found.output.1 + "\""
        return (try? JSONSerialization.jsonObject(with: Data(raw.utf8), options: .fragmentsAllowed)) as? String
    }

    /// A widget's title as words: "yab_landing_four_approaches" reads
    /// "yab landing four approaches".
    static func widgetWords(_ title: String) -> String {
        title.replacingOccurrences(of: "_", with: " ").split(separator: " ").joined(separator: " ")
    }

    /// A tool's name as the chat keeps it: Yab's own bare, another
    /// server's with its server's in front, "linear/create_issue". Yab's
    /// server was "fast" before it was renamed: its old chats say so.
    static func named(_ tool: String, server: String?) -> String {
        guard let server, !server.isEmpty, server != Mcp.name, !server.hasPrefix("yab"), server != "fast" else { return tool }
        return server + "/" + tool
    }

    /// What a tool call is about, by the tool: the file read, the pattern
    /// searched for, the question asked, the keys pressed; else the page's
    /// host, a title, the words typed, or the tab it was done in.
    static func about(_ name: String, _ input: [String: Any]) -> String {
        func last(_ key: String) -> String { ((input[key] as? String ?? "") as NSString).lastPathComponent }
        func quoted(_ words: String) -> String { words.isEmpty ? "" : "\u{201C}" + String(words.prefix(120)) + "\u{201D}" }
        switch name {
        case "Read", "NotebookRead":
            return last("file_path").isEmpty ? last("notebook_path") : last("file_path")
        case "Grep":
            let pattern = quoted(input["pattern"] as? String ?? "")
            let place = last("path")
            return place.isEmpty ? pattern : pattern + " in " + place
        case "Glob":
            let pattern = input["pattern"] as? String ?? ""
            let place = last("path")
            return place.isEmpty ? pattern : pattern + " in " + place
        case "LS":
            return last("path")
        case "WebSearch", "web_search", "mail_search", "mail_recall", "files_search":
            return quoted(input["query"] as? String ?? "")
        case "mail_labels":
            // What it did and to what, read back by StepWords: "delete:3", "rename:Work".
            let labels = (input["labels"] as? [String] ?? []).filter { !$0.isEmpty }
            let one = labels.count == 1 ? labels[0] : input["label"] as? String ?? ""
            return (input["do"] as? String ?? "list") + ":" + (labels.count > 1 ? String(labels.count) : one)
        case "mail_act":
            // Read back by StepWords: "unsubscribe:", "remind:".
            if let act = input["do"] as? String, ["unsubscribe", "remind", "unremind"].contains(act) { return act + ":" }
        case "mail_send":
            if input["undo"] as? Bool == true { return "undo:" }
        case "mail_list":
            if let list = input["list"] as? String, !list.isEmpty { return "list:" + String(list.prefix(60)) }
            return "list:"
        case "mail_accounts":
            return (input["do"] as? String ?? "list") + ":" + String((input["address"] as? String ?? "").prefix(80))
        case "ask", "AskUserQuestion":
            if let question = input["question"] as? String { return prose(question) }
            if let first = (input["questions"] as? [[String: Any]])?.first?["question"] as? String { return prose(first) }
        case "handoff", "computer_access":
            if let reason = input["reason"] as? String { return prose(reason) }
        case "remember":
            // A memory page's markdown, said as the fact it keeps.
            return quoted(remembered(input["text"] as? String ?? ""))
        case "folder_access":
            if let path = input["path"] as? String { return ClosedPlace.of(path)?.name ?? (path as NSString).lastPathComponent }
        case "navigate":
            if let url = input["url"] as? String, ["back", "forward", "reload"].contains(url) { return "nav:" + url }
        case "press":
            if let keys = input["keys"] as? String ?? input["key"] as? String { return "keys:" + keys }
        case "scroll":
            let dy = (input["dy"] as? NSNumber)?.doubleValue ?? 600
            return dy < 0 ? "up" : "down"
        case "dialog":
            if let words = input["text"] as? String, !words.isEmpty { return quoted(words) }
            return input["accept"] as? Bool == false ? "Cancel" : "OK"
        case "boost":
            // The site it is tried on, not the boost's slug.
            if let sites = input["sites"] as? [String], !sites.isEmpty { return sites.joined(separator: ", ") }
        case "boost_read":
            if let name = input["name"] as? String { return name }
        case "upload":
            let files = (input["files"] as? [String] ?? (input["file"] as? String).map { [$0] } ?? []).map { ($0 as NSString).lastPathComponent }
            if !files.isEmpty { return files.count == 1 ? files[0] : "\(files[0]) and \(files.count - 1) more" }
        case "autofill":
            switch input["what"] as? String {
            case "address": return "the address"
            case "form": return "the form"
            default: return "the card"
            }
        // Claude Code's own tools.
        case "Monitor":
            if let watched = input["description"] as? String, !watched.isEmpty { return prose(watched) }
        case "ScheduleWakeup":
            return wakeup(input)
        case "Workflow":
            return workflow(input)
        case "SendUserFile":
            return files(input)
        default:
            break
        }
        return about(input)
    }

    /// Words an agent wrote in markdown, as one line of plain words
    /// (StepProse.prose, the iPhone's too).
    static func prose(_ markdown: String) -> String { StepProse.prose(markdown) }

    /// What a `remember` keeps, in a few words (StepProse.remembered).
    static func remembered(_ text: String) -> String { StepProse.remembered(text) }

    /// What a tool call is about, in a few words: the page's host, or the
    /// reason it gave.
    static func about(_ input: [String: Any]) -> String {
        if let url = input["url"] as? String, let host = URL(string: url)?.host { return host }
        // Several at once: their hosts, each once, for a mark apiece.
        if let urls = input["urls"] as? [String] {
            var hosts: [String] = []
            for url in urls { if let host = URL(string: url)?.host, !hosts.contains(host) { hosts.append(host) } }
            if !hosts.isEmpty { return hosts.joined(separator: ", ") }
        }
        if let title = input["title"] as? String ?? input["name"] as? String { return title }
        if let query = input["query"] as? String { return query }
        // Words typed, in quotes; a key by its name.
        if let words = input["text"] as? String ?? input["value"] as? String, !words.isEmpty {
            // A card's number is never kept in the chat, on screen or on disk.
            let digits = words.filter(\.isNumber)
            if (13...19).contains(digits.count), words.allSatisfy({ $0.isNumber || $0 == " " || $0 == "-" }), Wallet.luhn(digits) {
                return "\u{201C}•••• " + String(digits.suffix(4)) + "\u{201D}"
            }
            return "\u{201C}" + String(words.prefix(60)) + "\u{201D}"
        }
        if let key = input["key"] as? String ?? input["keys"] as? String { return key }
        if let reason = input["reason"] as? String { return reason }
        // Else the tab it was done in, named when the step is shown (ChatStepMark.tab).
        if let tab = input["tab"] as? String, !tab.isEmpty { return "tab:" + tab }
        return ""
    }
}

extension Array where Element == ChatItem {
    /// A new step, or a later word on one already here. Heard `at` a time,
    /// it keeps when it began and, once over, when it ended.
    mutating func put(_ item: ChatItem, at time: Date? = nil) {
        var item = item
        if let index = lastIndex(where: { $0.id == item.id }) {
            item.began = item.began ?? self[index].began
            item.ended = item.ended ?? self[index].ended
            item.page = item.page ?? self[index].page
            // The native press handler resolves a tab reference into the
            // clicked control's words. A completion repeats the original
            // arguments; keep the resolved label for history and tool learning.
            if item.kind == .tool, item.name == "press", item.detail.hasPrefix("tab:"),
               self[index].detail.hasPrefix("“") {
                item.detail = self[index].detail
            }
            if item.state != .running, item.ended == nil { item.ended = time }
            self[index] = item
        } else {
            if item.began == nil { item.began = time }
            if item.state != .running, item.ended == nil { item.ended = time }
            append(item)
            if count > 500 { removeFirst(100) }
        }
        if item.kind == .tool, item.extra?["cards"] != nil, let index = lastIndex(where: { $0.id == item.id }) { carded(index) }
    }

    /// The cards a finished step made, each a step of its own right after
    /// it, once.
    mutating func carded(_ index: Int) {
        let step = self[index]
        guard step.state == .done, let lines = step.extra?["cards"] else { return }
        let cards = lines.split(separator: "\n").compactMap { ResultCard(json: String($0)) }
        var at = index + 1
        for (n, card) in cards.enumerated() {
            let id = step.id + ".card.\(n)"
            guard !contains(where: { $0.id == id }) else { continue }
            insert(ChatItem.card(card, id: id, at: step.ended ?? step.began), at: at)
            at += 1
        }
    }

    /// The words of a message as they come: onto the step being written,
    /// or a new one when its start went unheard.
    mutating func grow(_ id: String, by words: String, kind: ChatItem.Kind = .message, at time: Date? = nil) {
        if let index = lastIndex(where: { $0.id == id }) {
            self[index].text += words
        } else {
            put(ChatItem(id: id, kind: kind, text: words), at: time)
        }
    }

    /// What a running command prints, onto its step as it comes, its end
    /// kept (`outputKept`). A step that only reads or searches keeps none.
    mutating func printed(_ id: String, _ words: String) {
        guard let index = lastIndex(where: { $0.id == id }), self[index].kind == .command else { return }
        self[index].text += words
        if self[index].text.utf8.count > ChatItem.outputKept * 2 { self[index].text = String(self[index].text.suffix(ChatItem.outputKept)) }
    }

    /// Claude Code's `tool_result` for one of its calls: the call is over.
    mutating func answered(_ part: [String: Any]) {
        guard part["type"] as? String == "tool_result", let id = part["tool_use_id"] as? String,
              let index = lastIndex(where: { $0.id == id }) else { return }
        let failed = part["is_error"] as? Bool == true
        self[index].state = failed ? .failed : .done
        if self[index].ended == nil, self[index].began != nil { self[index].ended = Date() }
        let words: String
        if let text = part["content"] as? String { words = text } else {
            words = (part["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        }
        // A command's output is worth keeping; another tool's only when it
        // failed, or what its words need (a boost's tries).
        if self[index].kind == .command || failed { self[index].text = String(words.suffix(ChatItem.outputKept)) }
        else if self[index].kind == .tool, let kept = ChatItem.boostTries(self[index].name, words) { self[index].text = kept }
        if !failed, self[index].kind == .tool, let marks = ChatItem.marks(self[index].name, words) {
            self[index].extra = (self[index].extra ?? [:]).merging(marks) { _, new in new }
            carded(index)
        }
        if !failed, self[index].kind == .tool, self[index].name == "Artifact", let published = ChatItem.published(words) {
            self[index].extra = (self[index].extra ?? [:]).merging(published) { old, _ in old }
        }
    }
}
