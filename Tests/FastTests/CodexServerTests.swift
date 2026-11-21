import Foundation
import Testing
@testable import Fast

// Codex through app-server: the requests written, and what each answer
// and notification comes to, with no Codex at all.
@MainActor
struct CodexServerTests {
    final class Wire {
        var lines: [[String: Any]] = []
        var last: [String: Any] { lines.last ?? [:] }
        func methods() -> [String] { lines.compactMap { $0["method"] as? String } }
    }

    static func server(archiveTimeout: Duration = .seconds(10)) -> (CodexServer, Wire) {
        let wire = Wire()
        let server = CodexServer(archiveTimeout: archiveTimeout) { data in
            for line in data.split(separator: 0x0A) {
                if let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { wire.lines.append(object) }
            }
        }
        return (server, wire)
    }

    /// Hello answered, the thread started as `thread`.
    static func opened(thread: String? = nil, fork: String? = nil, archiveTimeout: Duration = .seconds(10)) -> (CodexServer, Wire) {
        let (server, wire) = server(archiveTimeout: archiveTimeout)
        server.open(thread: thread, fork: fork, instructions: "brief", cwd: "/room")
        _ = server.heard(["id": wire.last["id"]!, "result": [:]])
        return (server, wire)
    }

    static func ready(_ server: CodexServer, _ wire: Wire, id: String = "T1") -> [CodexServer.Heard] {
        server.heard(["id": wire.last["id"]!, "result": ["thread": ["id": id]]])
    }

    @Test func handshakeThenThread() {
        let (server, wire) = Self.opened()
        #expect(wire.methods() == ["initialize", "initialized", "thread/start"])
        let params = wire.last["params"] as? [String: Any] ?? [:]
        #expect(params["developerInstructions"] as? String == "brief")
        #expect(params["cwd"] as? String == "/room")
        let heard = Self.ready(server, wire)
        guard case .ready(let thread) = heard.first else { Issue.record("no ready"); return }
        #expect(thread == "T1")
    }

    @Test func resumedProjectUsesCurrentAccessAndModel() {
        for mode in ["workspace-write", "read-only"] {
            let (server, wire) = Self.server()
            server.projectSandbox = mode
            server.projectModel = "chosen-model"
            server.projectEffort = "medium"
            server.open(thread: "OLD", fork: nil, instructions: "brief", cwd: "/project")
            _ = server.heard(["id": wire.last["id"]!, "result": [:]])
            _ = server.heard(["id": wire.last["id"]!, "result": ["thread": ["id": "OLD"]]])
            let params = wire.last["params"] as? [String: Any]
            #expect(wire.last["method"] as? String == "thread/resume")
            #expect(params?["cwd"] as? String == "/project")
            #expect(params?["sandbox"] as? String == mode)
            #expect(params?["model"] as? String == "chosen-model")
            _ = Self.ready(server, wire, id: "OLD")
            server.say("Run tests")
            #expect((wire.last["params"] as? [String: Any])?["effort"] as? String == "medium")
        }
    }

    @Test func carriesOnOrForks() {
        let (server, resumed) = Self.opened(thread: "OLD")
        // A chat archived after its answer is taken out first.
        #expect(resumed.last["method"] as? String == "thread/unarchive")
        #expect((resumed.last["params"] as? [String: Any])?["threadId"] as? String == "OLD")
        _ = server.heard(["id": resumed.last["id"]!, "result": ["thread": ["id": "OLD"]]])
        #expect(resumed.last["method"] as? String == "thread/resume")
        #expect((resumed.last["params"] as? [String: Any])?["threadId"] as? String == "OLD")
        #expect((resumed.last["params"] as? [String: Any])?["cwd"] as? String == "/room")
        let (_, forked) = Self.opened(fork: "PARENT")
        #expect(forked.last["method"] as? String == "thread/fork")
        #expect(!forked.methods().contains("thread/unarchive"))
        #expect((forked.last["params"] as? [String: Any])?["cwd"] as? String == "/room")
    }

    @Test func notArchivedStillResumes() {
        let (server, wire) = Self.opened(thread: "LIVE")
        let heard = server.heard(["id": wire.last["id"]!, "error": ["code": -32600, "message": "no archived rollout found"]])
        #expect(heard.isEmpty)
        #expect(wire.last["method"] as? String == "thread/resume")
        #expect((wire.last["params"] as? [String: Any])?["threadId"] as? String == "LIVE")
    }

    @Test func goneThreadStartsAnew() {
        let (server, wire) = Self.opened(thread: "GONE")
        _ = server.heard(["id": wire.last["id"]!, "error": ["code": -32600, "message": "no archived rollout found"]])
        let heard = server.heard(["id": wire.last["id"]!, "error": ["code": -32600, "message": "no rollout"]])
        #expect(heard.isEmpty)
        #expect(wire.last["method"] as? String == "thread/start")
        #expect((wire.last["params"] as? [String: Any])?["cwd"] as? String == "/room")
        guard case .ready = Self.ready(server, wire).first else { Issue.record("no ready"); return }
    }

    @Test func saidEarlyWaitsForTheThread() {
        let (server, wire) = Self.opened()
        server.say("hello")
        #expect(wire.last["method"] as? String == "thread/start")
        _ = Self.ready(server, wire)
        #expect(wire.last["method"] as? String == "turn/start")
        let input = ((wire.last["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first
        #expect(input?["text"] as? String == "hello")
    }

    @Test func developmentPluginSwitchControlsMentionsAndNewLaunches() {
        let settings = DevelopmentPlugins.shared
        let id = "check-" + UUID().uuidString.lowercased() + "@local"
        let ref = DevelopmentReference(kind: .plugin, name: "Check", path: "plugin://" + id)
        let override = "plugins.\"" + id + "\".enabled=false"
        defer { settings.set(ref, enabled: true) }
        settings.set(ref, enabled: false)
        #expect(!settings.allows(ref))
        #expect(settings.launchArguments.contains(override))
        settings.set(ref, enabled: true)
        #expect(settings.allows(ref))
        #expect(!settings.launchArguments.contains(override))
    }

    @Test func developmentReferencesFollowTheirTurn() {
        let (server, wire) = Self.opened()
        let skill = DevelopmentReference(kind: .skill, name: "Review", path: "/project/.agents/skills/review/SKILL.md")
        let plugin = DevelopmentReference(kind: .plugin, name: "Issues", path: "plugin://issues@local")
        server.extraInputs = { $0 == "review" ? [skill.input] : [plugin.input] }
        _ = Self.ready(server, wire)
        server.say("review")
        func lastInput() -> [String: String]? {
            ((wire.last["params"] as? [String: Any])?["input"] as? [[String: Any]])?.last as? [String: String]
        }
        #expect(lastInput() == ["type": "skill", "name": skill.name, "path": skill.path])
        server.steer("check issues")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        #expect(wire.last["method"] as? String == "turn/steer")
        #expect(lastInput() == ["type": "mention", "name": plugin.name, "path": plugin.path])
    }

    @Test func steerMidTurn() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        // Before the turn is named, a steer waits for it.
        server.steer("also this")
        #expect(wire.methods().filter { $0 == "turn/steer" }.isEmpty)
        let taken = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        guard case .taken = taken.first else { Issue.record("not taken"); return }
        #expect(wire.last["method"] as? String == "turn/steer")
        #expect((wire.last["params"] as? [String: Any])?["expectedTurnId"] as? String == "U1")
        // Said again mid-turn: a steer too, not a second turn.
        server.say("and this")
        #expect(wire.methods().filter { $0 == "turn/start" }.count == 1)
    }

    @Test func steerTooLateIsATurnOfItsOwn() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        server.steer("late")
        let steer = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]])
        _ = server.heard(["id": steer, "error": ["message": "no active turn"]])
        #expect(wire.last["method"] as? String == "turn/start")
    }

    @Test func lateSteerErrorKeepsNewTurn() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        server.steer("late")
        let old = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["turn": ["id": "U1"]]])
        server.say("next")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U2"]]])
        _ = server.heard(["id": old, "error": ["message": "no active turn"]])
        #expect(server.turn == "U2")
        #expect(wire.methods().filter { $0 == "turn/start" }.count == 2)
        #expect((wire.last["params"] as? [String: Any])?["expectedTurnId"] as? String == "U2")
        let count = wire.lines.count
        let rejected = server.heard(["id": wire.last["id"]!, "error": ["message": "rejected again"]])
        #expect(wire.lines.count == count)
        guard case .notice(let words) = rejected.first else { Issue.record("no rejection notice"); return }
        #expect(words.contains("late"))
    }

    @Test func activeSteerFailureDoesNotStartAnotherTurn() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        server.steer("extra")
        let count = wire.lines.count
        let rejected = server.heard(["id": wire.last["id"]!, "error": ["message": "upstream unavailable"]])
        #expect(server.turn == "U1")
        #expect(wire.lines.count == count)
        guard case .notice = rejected.first else { Issue.record("no rejection notice"); return }
    }

    @Test func lateSteerWaitsForNewStartAndRetriesOnlyOnce() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        _ = server.heard(["id": wire.last["id"]!, "result": ["turn": ["id": "U1"]]])
        server.steer("late")
        let old = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["turn": ["id": "U1"]]])
        server.say("next")
        let next = wire.last["id"]!
        let count = wire.lines.count
        _ = server.heard(["id": old, "error": ["message": "no active turn"]])
        #expect(wire.lines.count == count)
        _ = server.heard(["id": next, "result": ["turn": ["id": "U2"]]])
        #expect((wire.last["params"] as? [String: Any])?["expectedTurnId"] as? String == "U2")
        let retry = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["turn": ["id": "U2"]]])
        let finalCount = wire.lines.count
        let rejected = server.heard(["id": retry, "error": ["message": "no active turn"]])
        #expect(wire.lines.count == finalCount)
        guard case .notice = rejected.first else { Issue.record("no rejection notice"); return }
    }

    @Test func turnEndsAndLateStartIsIgnored() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        let start = wire.last["id"]!
        _ = server.heard(["method": "turn/started", "params": ["threadId": "T1", "turn": ["id": "U1"]]])
        let ended = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "failed", "error": ["message": "usage limit"]]]])
        guard case .turnEnded(let status, let error) = ended.first else { Issue.record("no end"); return }
        #expect(status == "failed")
        #expect(error == "usage limit")
        _ = server.heard(["id": start, "result": ["turn": ["id": "U1"]]])
        #expect(server.turn == nil)
    }

    @Test func archiveWaitsForAcknowledgementAndCoalesces() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        var callbacks = 0
        var errors: [String] = []
        let completed: (String?) -> Void = { error in
            callbacks += 1
            if let error { errors.append(error) }
        }
        server.archive(completion: completed)
        let request = wire.last["id"]!
        server.archive(completion: completed)
        #expect(wire.methods().filter { $0 == "thread/archive" }.count == 1)
        #expect((wire.last["params"] as? [String: Any])?["threadId"] as? String == "T1")
        #expect(callbacks == 0)
        #expect(server.heard(["method": "thread/archived", "params": ["threadId": "T1"]]).isEmpty)
        #expect(callbacks == 0)
        #expect(server.heard(["id": request, "result": [:]]).isEmpty)
        #expect(callbacks == 2)
        #expect(errors.isEmpty)
        server.archive(completion: completed)
        #expect(callbacks == 3)
        #expect(wire.methods().filter { $0 == "thread/archive" }.count == 1)
        #expect(server.heard(["id": request, "result": [:]]).isEmpty)
        #expect(callbacks == 3)
    }

    @Test func archiveFailureIsCleanupOnlyAndCanRetry() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        var received: [String?] = []
        server.archive { received.append($0) }
        let failed = server.heard(["id": wire.last["id"]!, "error": ["message": "archive unavailable"]])
        #expect(failed.isEmpty)
        #expect(received.count == 1)
        #expect(received[0] == "archive unavailable")
        server.archive { received.append($0) }
        #expect(wire.methods().filter { $0 == "thread/archive" }.count == 2)
        #expect(server.heard(["id": wire.last["id"]!, "result": [:]]).isEmpty)
        #expect(received.count == 2)
        #expect(received[1] == nil)
    }

    @Test func archiveRejectsMissingStartingAndLiveThreads() {
        let (unopened, unopenedWire) = Self.server()
        var missing: String?
        unopened.archive { missing = $0 }
        #expect(missing != nil)
        #expect(unopenedWire.lines.isEmpty)

        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        let start = wire.last["id"]!
        var rejected = 0
        server.archive { if $0 != nil { rejected += 1 } }
        #expect(rejected == 1)
        #expect(wire.methods().filter { $0 == "thread/archive" }.isEmpty)
        _ = server.heard(["id": start, "result": ["turn": ["id": "U1"]]])
        server.archive { if $0 != nil { rejected += 1 } }
        #expect(rejected == 2)
        #expect(wire.methods().filter { $0 == "thread/archive" }.isEmpty)
    }

    @Test func archiveAfterEndBeforeStartAcknowledgement() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        let start = wire.last["id"]!
        _ = server.heard(["method": "turn/started", "params": ["threadId": "T1", "turn": ["id": "U1"]]])
        _ = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]])
        var archived = false
        server.archive { archived = $0 == nil }
        #expect(wire.last["method"] as? String == "thread/archive")
        let archive = wire.last["id"]!
        _ = server.heard(["id": start, "result": ["turn": ["id": "U1"]]])
        #expect(server.turn == nil)
        #expect(!archived)
        _ = server.heard(["id": archive, "result": [:]])
        #expect(archived)
    }

    @Test func archiveRejectsSteersHeldForLateStartAcknowledgement() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("task")
        let start = wire.last["id"]!
        server.steer("next")
        _ = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]])
        var rejected: String?
        server.archive { rejected = $0 }
        #expect(rejected != nil)
        #expect(wire.methods().filter { $0 == "thread/archive" }.isEmpty)
        _ = server.heard(["id": start, "result": ["turn": ["id": "U1"]]])
        #expect(wire.last["method"] as? String == "turn/start")
        #expect(((wire.last["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first?["text"] as? String == "next")
    }

    @Test func lateStartReplyKeepsNewTurnAndItsSteer() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("first")
        let first = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]])
        server.say("second")
        let second = wire.last["id"]!
        server.steer("for second")
        #expect(server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]]).isEmpty)
        _ = server.heard(["id": first, "result": ["turn": ["id": "U1"]]])
        #expect(wire.methods().filter { $0 == "turn/start" }.count == 2)
        #expect(wire.methods().filter { $0 == "turn/steer" }.isEmpty)
        _ = server.heard(["id": second, "result": ["turn": ["id": "U2"]]])
        #expect(server.turn == "U2")
        #expect((wire.last["params"] as? [String: Any])?["expectedTurnId"] as? String == "U2")
        #expect(((wire.last["params"] as? [String: Any])?["input"] as? [[String: Any]])?.first?["text"] as? String == "for second")
    }

    @Test func lateStartErrorDoesNotFailNewTurn() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        server.say("first")
        let first = wire.last["id"]!
        _ = server.heard(["method": "turn/completed", "params": ["threadId": "T1", "turn": ["id": "U1", "status": "completed"]]])
        server.say("second")
        let second = wire.last["id"]!
        #expect(server.heard(["id": first, "error": ["message": "late error"]]).isEmpty)
        _ = server.heard(["id": second, "result": ["turn": ["id": "U2"]]])
        #expect(server.turn == "U2")
    }

    @Test func archiveTimeoutIgnoresLateAcknowledgement() async {
        let (server, wire) = Self.opened(archiveTimeout: .milliseconds(1))
        _ = Self.ready(server, wire)
        var expired: Any?
        let timeout = await withCheckedContinuation { continuation in
            server.archive { continuation.resume(returning: $0) }
            expired = wire.last["id"]
        }
        #expect(timeout == "ChatGPT archive timed out.")
        #expect(server.heard(["id": expired!, "result": [:]]).isEmpty)
        var callbacks = 0
        server.archive { error in
            #expect(error == nil)
            callbacks += 1
        }
        #expect(wire.methods().filter { $0 == "thread/archive" }.count == 2)
        _ = server.heard(["id": wire.last["id"]!, "result": [:]])
        #expect(callbacks == 1)
    }

    @Test func otherThreadsAreNotOurs() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        let heard = server.heard(["method": "item/agentMessage/delta", "params": ["threadId": "CHILD", "delta": "x"]])
        #expect(heard.isEmpty)
        let ours = server.heard(["method": "item/agentMessage/delta", "params": ["threadId": "T1", "delta": "Hi"]])
        guard case .delta(_, "Hi") = ours.first else { Issue.record("no delta"); return }
    }

    @Test func askedIsDeclined() {
        let (server, wire) = Self.opened()
        _ = server.heard(["id": 77, "method": "item/commandExecution/requestApproval", "params": [:]])
        #expect(wire.last["id"] as? Int == 77)
        #expect((wire.last["result"] as? [String: Any])?["decision"] as? String == "decline")
        _ = server.heard(["id": 78, "method": "item/tool/requestUserInput", "params": [:]])
        #expect(wire.last["error"] != nil)
    }

    @Test func retriedErrorIsNotAnEnd() {
        let (server, wire) = Self.opened()
        _ = Self.ready(server, wire)
        #expect(server.heard(["method": "error", "params": ["threadId": "T1", "willRetry": true, "error": ["message": "x"]]]).isEmpty)
        guard case .failed("down", false) = server.heard(["method": "error", "params": ["threadId": "T1", "willRetry": false, "error": ["message": "down"]]]).first
        else { Issue.record("no failure"); return }
    }
}

// Both agents' steps come down to the same ChatItem.
struct ChatItemTests {
    @Test func codexTool() throws {
        let raw: [String: Any] = ["type": "mcpToolCall", "id": "i1", "server": "yab-browser", "tool": "open", "status": "inProgress",
                                  "arguments": ["url": "https://github.com/x"]]
        let item = try #require(ChatItem.codex(raw, done: false))
        #expect(item == ChatItem(id: "i1", kind: .tool, name: "open", detail: "github.com", state: .running))
    }

    @Test func claudeTool() throws {
        let part: [String: Any] = ["type": "tool_use", "id": "t1", "name": "mcp__yab-browser__open", "input": ["url": "https://github.com/x"]]
        let item = try #require(ChatItem.claude(part, message: "m1"))
        #expect(item == ChatItem(id: "t1", kind: .tool, name: "open", detail: "github.com", state: .running))
    }

    @Test func commandsAlike() throws {
        var codex = try #require(ChatItem.codex(["type": "commandExecution", "id": "c", "command": "ls", "status": "completed",
                                                 "aggregatedOutput": "a\nb", "exitCode": 0], done: true))
        // Codex says how it exited; Claude's tool result doesn't.
        #expect(codex.extra == ["exit": "0"])
        codex.extra = nil
        var items: [ChatItem] = []
        items.put(try #require(ChatItem.claude(["type": "tool_use", "id": "c", "name": "Bash", "input": ["command": "ls"]], message: "m")))
        items.answered(["type": "tool_result", "tool_use_id": "c", "content": "a\nb"])
        #expect(items == [codex])
    }

    @Test func failedCallKeepsWhy() {
        var items = [ChatItem(id: "t", kind: .tool, name: "click")]
        items.answered(["type": "tool_result", "tool_use_id": "t", "is_error": true, "content": [["type": "text", "text": "no such ref"]]])
        #expect(items[0].state == .failed)
        #expect(items[0].text == "no such ref")
    }

    @Test func putReplaces() {
        var items: [ChatItem] = []
        items.put(ChatItem(id: "m", kind: .message, text: "Hi"))
        items.put(ChatItem(id: "m", kind: .message, text: "Hi there", state: .done))
        #expect(items.count == 1)
        #expect(items[0].text == "Hi there")
    }

    @Test func messagesAndThinking() throws {
        let said = try #require(ChatItem.codex(["type": "agentMessage", "id": "a", "text": "Done."], done: true))
        #expect(said.kind == .message && said.text == "Done." && said.state == .done)
        let thought = try #require(ChatItem.claude(["type": "thinking", "thinking": "hmm"], message: "m"))
        #expect(thought.kind == .thinking)
        #expect(ChatItem.codex(["type": "contextCompaction", "id": "z"], done: true)?.isAside == true)
        #expect(ChatItem.codex(["type": "functionCallOutput", "id": "f"], done: true) == nil)
    }
}
