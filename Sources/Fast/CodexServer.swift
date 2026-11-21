import Foundation
import os

/// Codex through `codex app-server`: one process for a session's whole
/// conversation, JSON-RPC a line at a time on its stdin and stdout, the way
/// Claude Code's stream-json is. A message said mid-turn is steered into
/// that turn rather than stopping it. The requests, their ids and their
/// answers stay in here; what Agents needs to act on comes back as `Heard`.
@MainActor
final class CodexServer {
    private static let log = Logger(subsystem: "dev.serafim.fast", category: "Codex")
    enum Heard {
        /// The thread is there to talk to: new, carried on, or forked.
        case ready(thread: String)
        /// A message was taken in: a turn started with it, or it was
        /// folded into the turn going on.
        case taken
        case started(ChatItem, raw: [String: Any])
        case completed(ChatItem)
        /// The words of a message being written, as they come.
        case delta(item: String, words: String)
        /// The turn is over: completed, interrupted or failed.
        case turnEnded(status: String, error: String?)
        /// Something went wrong. Fatal when no turn is going on to end it:
        /// the thread could not be started, or a turn could not.
        case failed(String, fatal: Bool)
        case rateLimits([String: Any])
        /// It asks you something (`item/tool/requestUserInput`): answered
        /// with `reply` under the same id.
        case asked(id: Int, params: [String: Any])
        /// Its thinking's summary as it comes, onto the thinking step.
        case thinking(item: String, words: String)
        /// A plan item's words as they come (plan mode's proposed plan).
        case planned(item: String, words: String)
        /// What a running command prints, as it prints it.
        case output(item: String, words: String)
        /// The turn's checklist as it stands (`turn/plan/updated`), kept
        /// as TodoWrite's is (ChatItem.checklist).
        case checklist(turn: String, text: String)
        /// The thread's name, given or changed.
        case named(String)
        /// How much of the model's context the thread fills now, and what
        /// the whole thread has used (`thread/tokenUsage/updated`).
        case usage(used: Int, window: Int?, total: Int)
        /// Everything the turn has changed so far, one unified diff.
        case diff(String)
        /// A tool's own word on how far along it is.
        case progress(item: String, words: String)
        /// Something to tell you on a quiet line: a model switched, a
        /// warning, a setting that is wrong, something going away.
        case notice(String)
    }

    private enum Pending {
        case initialize, unarchive, thread, fallback, turn, steer(text: String, turn: String, recovered: Bool), interrupt, archive
    }

    private let write: (Data) -> Void
    /// Where a picture it made and didn't save is kept.
    var images: URL?
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    /// What the thread is opened with, once the server has said hello.
    private var opening: (thread: String?, fork: String?, instructions: String, cwd: String)?
    private(set) var thread: String?
    var projectSandbox: String?
    var projectModel: String?
    var projectEffort: String?
    var extraInputs: (String) -> [[String: Any]] = { _ in [] }
    /// Someone is there to answer its questions.
    var asks = false
    /// The turn going on, once the server has named it.
    private(set) var turn: String?
    /// A turn asked for and not yet named: steers wait for its id.
    private var starting: Int?
    /// Turns already over, should one's start be answered after its end.
    private var over: Set<String> = []
    /// Messages said before the thread was there.
    private var waiting: [String] = []
    /// Steers said while a turn was starting.
    private var held: [(text: String, recovered: Bool)] = []
    private let archiveTimeout: Duration
    private var archiveDeadline: Task<Void, Never>?
    private var archiveCompletions: [(String?) -> Void] = []
    private var archived = false

    init(archiveTimeout: Duration = .seconds(10), write: @escaping (Data) -> Void) {
        self.archiveTimeout = archiveTimeout
        self.write = write
    }

    /// Says hello, then starts a thread, carries `thread` on, or forks
    /// `fork`. `instructions` go in as the developer's, every time: a
    /// thread carried on in a new process is told them again.
    func open(thread: String?, fork: String?, instructions: String, cwd: String) {
        opening = (thread, fork, instructions, cwd)
        request("initialize", ["clientInfo": ["name": "yab", "title": "yab", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"], "capabilities": NSNull()], .initialize)
    }

    /// A message: the next turn, or, while one is going on, into it.
    func say(_ text: String, recovered: Bool = false) {
        guard let thread else { waiting.append(text); return }
        if turn != nil || starting != nil { steer(text, recovered: recovered); return }
        starting = nextID + 1
        var params: [String: Any] = ["threadId": thread, "input": [Self.input(text)] + extraInputs(text)]
        if let projectModel { params["model"] = projectModel }
        if let projectEffort { params["effort"] = projectEffort }
        request("turn/start", params, .turn)
    }

    /// Words for the turn going on, read at its next step.
    func steer(_ text: String, recovered: Bool = false) {
        guard let thread else { waiting.append(text); return }
        if starting != nil { held.append((text, recovered)); return }
        guard let turn else { say(text, recovered: recovered); return }
        request("turn/steer", ["threadId": thread, "expectedTurnId": turn, "input": [Self.input(text)] + extraInputs(text)], .steer(text: text, turn: turn, recovered: recovered))
    }

    func interrupt() {
        guard let thread, let turn else { return }
        request("turn/interrupt", ["threadId": thread, "turnId": turn], .interrupt)
    }

    /// Retires a background conversation after its last turn. The caller
    /// keeps stdin open until the acknowledgement or bounded failure comes
    /// back; cleanup errors do not become the model's answer.
    func archive(completion: @escaping (String?) -> Void) {
        if !archiveCompletions.isEmpty {
            archiveCompletions.append(completion)
            return
        }
        if archived { completion(nil); return }
        guard let thread else { completion("ChatGPT has no thread to archive."); return }
        guard turn == nil, starting == nil, held.isEmpty, waiting.isEmpty else {
            completion("ChatGPT is still answering.")
            return
        }
        archiveCompletions = [completion]
        archiveDeadline = Task { @MainActor [weak self, archiveTimeout] in
            do { try await Task.sleep(for: archiveTimeout) }
            catch { return }
            self?.finishArchive("ChatGPT archive timed out.")
        }
        request("thread/archive", ["threadId": thread], .archive)
    }

    /// A line the server wrote.
    func heard(_ message: [String: Any]) -> [Heard] {
        let method = message["method"] as? String
        if let id = message["id"] as? Int {
            // The server asking something of us.
            if let method {
                let params = message["params"] as? [String: Any] ?? [:]
                if asks, method == "item/tool/requestUserInput", (params["threadId"] as? String).map({ $0 == thread }) ?? true {
                    return [.asked(id: id, params: params)]
                }
                answer(id, method)
                return []
            }
            guard let what = pending.removeValue(forKey: id) else { return [] }
            if let error = message["error"] as? [String: Any] {
                return failed(what, error["message"] as? String ?? "ChatGPT said no.", id: id)
            }
            return answered(what, message["result"] as? [String: Any] ?? [:], id: id)
        }
        guard let method else { return [] }
        let params = message["params"] as? [String: Any] ?? [:]
        // Only this thread's: a subagent's threads talk on the same line.
        if let about = params["threadId"] as? String, about != thread { return [] }
        switch method {
        case "turn/started":
            if let id = (params["turn"] as? [String: Any])?["id"] as? String { turn = id }
        case "turn/completed":
            let ended = params["turn"] as? [String: Any] ?? [:]
            guard ended["id"] as? String == turn || turn == nil else { return [] }
            if let id = ended["id"] as? String {
                guard over.insert(id).inserted else { return [] }
            }
            turn = nil
            if held.isEmpty { starting = nil }
            let error = (ended["error"] as? [String: Any]).map { Self.failure($0) }
            return [.turnEnded(status: ended["status"] as? String ?? "completed", error: error)]
        case "item/started", "item/completed":
            let raw = params["item"] as? [String: Any] ?? [:]
            let steps = ChatItem.codexSteps(raw, done: method == "item/completed", images: images)
            return steps.map { method == "item/started" ? Heard.started($0, raw: raw) : Heard.completed($0) }
        case "item/agentMessage/delta":
            if let words = params["delta"] as? String { return [.delta(item: params["itemId"] as? String ?? "", words: words)] }
        case "item/reasoning/summaryTextDelta":
            if let words = params["delta"] as? String { return [.thinking(item: params["itemId"] as? String ?? "", words: words)] }
        case "item/reasoning/summaryPartAdded":
            // A new part of the summary: a paragraph of its own.
            if (params["summaryIndex"] as? Int ?? 0) > 0 { return [.thinking(item: params["itemId"] as? String ?? "", words: "\n\n")] }
        case "item/plan/delta":
            if let words = params["delta"] as? String { return [.planned(item: params["itemId"] as? String ?? "", words: words)] }
        case "item/commandExecution/outputDelta":
            if let words = params["delta"] as? String { return [.output(item: params["itemId"] as? String ?? "", words: words)] }
        case "turn/plan/updated":
            let steps = params["plan"] as? [[String: Any]] ?? []
            return [.checklist(turn: params["turnId"] as? String ?? turn ?? "", text: ChatItem.checklist(steps))]
        case "thread/name/updated":
            if let name = (params["threadName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return [.named(name)] }
        case "thread/tokenUsage/updated":
            let usage = params["tokenUsage"] as? [String: Any] ?? [:]
            let last = usage["last"] as? [String: Any] ?? [:], total = usage["total"] as? [String: Any] ?? [:]
            guard let used = last["totalTokens"] as? Int else { return [] }
            return [.usage(used: used, window: usage["modelContextWindow"] as? Int, total: total["totalTokens"] as? Int ?? used)]
        case "turn/diff/updated":
            if let diff = params["diff"] as? String { return [.diff(diff)] }
        case "item/mcpToolCall/progress":
            if let words = params["message"] as? String, !words.isEmpty { return [.progress(item: params["itemId"] as? String ?? "", words: words)] }
        case "model/rerouted":
            let to = params["toModel"] as? String ?? "another model"
            let from = (params["fromModel"] as? String).map { " from " + $0 } ?? ""
            return [.notice("Switched to " + to + from + " for this turn")]
        case "warning":
            guard let words = params["message"] as? String, !words.isEmpty else { break }
            // Codex trimming its own list of skills, said on every turn of
            // a Mac with many: nothing for the person to do (feedback #131).
            if words.localizedCaseInsensitiveContains("skills context budget") {
                Self.log.notice("warning: \(words, privacy: .public)")
                break
            }
            return [.notice(words)]
        case "configWarning", "deprecationNotice":
            // Codex telling Yab about its own API and config: for whoever
            // works on Yab, never a line in the person's chat.
            if let words = params["summary"] as? String, !words.isEmpty { Self.log.notice("\(method, privacy: .public): \(words, privacy: .public)") }
        case "error":
            // One it will try again after isn't the turn's end.
            guard params["willRetry"] as? Bool != true else { return [] }
            let error = Self.failure(params["error"] as? [String: Any] ?? [:])
            return [.failed(error, fatal: false)]
        case "account/rateLimits/updated":
            if let limits = params["rateLimits"] as? [String: Any] { return [.rateLimits(limits)] }
        default:
            break
        }
        return []
    }

    // MARK: -

    /// Codex may put the upstream HTTP status only in codexErrorInfo,
    /// while its message describes the failed transport. Keep that status
    /// for ChatProblem's recovery, never headers or additionalDetails.
    private static func failure(_ error: [String: Any]) -> String {
        let message = error["message"] as? String ?? "ChatGPT failed."
        guard let info = error["codexErrorInfo"] as? [String: Any] else { return message }
        for variant in ["httpConnectionFailed", "responseStreamConnectionFailed",
                        "responseStreamDisconnected", "responseTooManyFailedAttempts"] {
            guard let fields = info[variant] as? [String: Any],
                  let status = fields["httpStatusCode"] as? Int, (400...599).contains(status) else { continue }
            return "HTTP \(status): \(message)"
        }
        return message
    }

    private func answered(_ what: Pending, _ result: [String: Any], id: Int) -> [Heard] {
        switch what {
        case .initialize:
            notify("initialized")
            unarchiveThread()
            return []
        case .unarchive:
            openThread()
            return []
        case .thread, .fallback:
            guard let id = (result["thread"] as? [String: Any])?["id"] as? String else {
                return [.failed("ChatGPT didn't start.", fatal: true)]
            }
            thread = id
            let said = waiting
            waiting = []
            for text in said { say(text) }
            return [.ready(thread: id)]
        case .turn:
            guard starting == id else { return [.taken] }
            starting = nil
            if let id = (result["turn"] as? [String: Any])?["id"] as? String, turn == nil, !over.contains(id) { turn = id }
            let steers = held
            held = []
            for message in steers { steer(message.text, recovered: message.recovered) }
            return [.taken]
        case .steer:
            return [.taken]
        case .interrupt:
            return []
        case .archive:
            finishArchive(nil)
            return []
        }
    }

    private func failed(_ what: Pending, _ error: String, id: Int) -> [Heard] {
        switch what {
        case .thread:
            // The thread to carry on is gone: a new one, without what was said.
            if let opening, opening.thread != nil || opening.fork != nil {
                self.opening = (nil, nil, opening.instructions, opening.cwd)
                openThread(fallback: true)
                return []
            }
            return [.failed(error, fatal: true)]
        case .steer(let text, let expected, let recovered):
            // A late rejection belongs to the turn it was sent to. Keep a
            // newer turn intact, and forward the words to it at most once.
            guard !recovered, turn != expected || over.contains(expected) else {
                return [.notice("ChatGPT couldn't take this message: \(error)\n\(text)")]
            }
            say(text, recovered: true)
            return []
        case .turn:
            guard starting == id else { return [] }
            starting = nil
            held = []
            return [.failed(error, fatal: true)]
        case .unarchive:
            // Not archived, or not known: resume says which.
            openThread()
            return []
        case .initialize, .fallback:
            return [.failed(error, fatal: true)]
        case .interrupt:
            return []
        case .archive:
            finishArchive(error)
            return []
        }
    }

    private func finishArchive(_ error: String?) {
        archiveDeadline?.cancel()
        archiveDeadline = nil
        pending = pending.filter { if case .archive = $0.value { return false }; return true }
        archived = error == nil
        let completions = archiveCompletions
        archiveCompletions = []
        for completion in completions { completion(error) }
    }

    /// A chat Yab archived after its answer can't be resumed until it is
    /// taken out again; it goes back once this turn's answer is in.
    private func unarchiveThread() {
        guard let opening, let thread = opening.thread, opening.fork == nil else { return openThread() }
        request("thread/unarchive", ["threadId": thread], .unarchive)
    }

    private func openThread(fallback: Bool = false) {
        guard let opening else { return }
        // Resume and fork also need the current folder: older Yab threads
        // otherwise keep their per-session folder as a separate project.
        var params: [String: Any] = ["developerInstructions": opening.instructions, "cwd": opening.cwd]
        let method: String
        if let projectSandbox { params["sandbox"] = projectSandbox }
        if let projectModel { params["model"] = projectModel }
        if let fork = opening.fork {
            method = "thread/fork"
            params["threadId"] = fork
        } else if let thread = opening.thread {
            method = "thread/resume"
            params["threadId"] = thread
        } else {
            method = "thread/start"
        }
        request(method, params, fallback ? .fallback : .thread)
    }

    /// Nobody is there to approve anything: the session's sandbox and
    /// `approval_policy` already say what it may do, so anything asked
    /// anyway is declined.
    private func answer(_ id: Int, _ method: String) {
        let result: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            result = ["decision": "decline"]
        case "mcpServer/elicitation/request":
            result = ["action": "decline", "content": NSNull(), "_meta": NSNull()]
        default:
            line(["id": id, "error": ["code": -32601, "message": "Yab doesn't answer \(method)"]])
            return
        }
        line(["id": id, "result": result])
    }

    /// The answer to its question (`asked`): each question's id with
    /// what was picked or typed, `{answers: {id: {answers: [...]}}}`.
    func reply(_ id: Int, answers: [String: Any]) {
        line(["id": id, "result": ["answers": answers]])
    }

    private func request(_ method: String, _ params: [String: Any], _ what: Pending) {
        nextID += 1
        pending[nextID] = what
        line(["id": nextID, "method": method, "params": params])
    }

    private func notify(_ method: String) {
        line(["method": method])
    }

    private func line(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        write(data)
    }

    static func input(_ text: String) -> [String: Any] {
        ["type": "text", "text": text, "text_elements": [Any]()]
    }
}
