import Foundation

/// Presentation only: keep the provider's original error in the transcript.
/// A recovery is offered to the person; it never retries or changes plans itself.
struct ChatProblem {
    enum Kind: String {
        case modelUnavailable = "MODEL_UNAVAILABLE", signIn = "SIGN_IN_REQUIRED"
        case access = "ACCESS_DENIED", quota = "PLAN_LIMIT", rateLimit = "RATE_LIMIT"
        case service = "SERVICE_UNAVAILABLE", network = "CONNECTION_FAILED"
        case invalidRequest = "REQUEST_REJECTED", stopped = "AGENT_STOPPED", unknown = "AGENT_ERROR"
    }
    enum Recovery { case retry, model, account }

    let kind: Kind
    let status: Int?
    let providerCode: String?
    let message: String
    let agent: String
    let isEnvelope: Bool

    init(_ raw: String, agent: String) {
        self.agent = agent
        let extracted = Self.extract(raw)
        status = extracted.status
        providerCode = extracted.code
        message = extracted.message
        isEnvelope = extracted.isEnvelope
        let text = (extracted.message + " " + (extracted.code ?? "")).lowercased()
        if status == 401 {
            kind = .signIn
        } else if text.contains("model_not_found") || text.contains("unsupported_model") ||
            (text.contains("model") && ["not supported", "unsupported", "not available", "does not exist", "may not exist", "do not have access",
                                         "don't have access", "not have access to it"].contains(where: text.contains)) {
            kind = .modelUnavailable
        // Plain CLI auth failures can also say "timed out". Recognize the
        // authentication failure before the generic network fallback.
        } else if ["authentication_error", "authentication required", "authentication failed", "requires google sign-in",
                   "unauthorized", "invalid_api_key", "invalid api key", "token expired", "token has expired",
                   "not logged in", "not signed in", "login required", "invalid_grant"].contains(where: text.contains) {
            kind = .signIn
        } else if status == 403 || text.contains("permission_error") || text.contains("permission_denied") {
            kind = .access
        } else if ["insufficient_quota", "usage_limit", "usage limit", "weekly limit", "limit reached", "hit your", "credit balance", "billing_hard_limit"].contains(where: text.contains) {
            kind = .quota
        } else if status == 429 || text.contains("rate_limit") || text.contains("rate limit") || text.contains("too many requests") {
            kind = .rateLimit
        } else if status.map({ $0 >= 500 }) == true || ["internal server error", "overloaded", "server_error", "service_unavailable"].contains(where: text.contains) {
            kind = .service
        } else if status == 408 || ["network", "econn", "timed out", "timeout", "connection", "offline", "dns"].contains(where: text.contains) {
            kind = .network
        } else if status == 400 || status == 404 || status == 422 || text.contains("invalid_request_error") {
            kind = .invalidRequest
        } else if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || ["stopped (", "exit code", "terminated", "killed"].contains(where: text.contains) {
            kind = .stopped
        } else {
            kind = .unknown
        }
    }

    var title: String {
        switch kind {
        case .modelUnavailable: "This model isn’t available"
        case .signIn: "Sign in to \(agent) again"
        case .access: "\(agent) didn’t allow this request"
        case .quota: "\(agent) is out of room on this plan for now."
        case .rateLimit: "\(agent) is receiving too many requests"
        case .service: "\(agent)’s server failed partway."
        case .network: "The connection dropped partway."
        case .invalidRequest: "\(agent) couldn’t accept this request"
        case .stopped: "\(agent) stopped before it finished."
        case .unknown: "\(agent) couldn’t finish."
        }
    }

    var detail: String {
        switch kind {
        case .modelUnavailable:
            "Choose another model to try again. Availability can depend on your plan and the installed agent version."
        case .signIn: "Reconnect your account in AI settings, then try again."
        case .access: "Check your account’s permissions in AI settings before trying again."
        case .quota: "Wait for your plan’s limit to reset, or review your connected accounts in AI settings."
        case .rateLimit: "Wait a moment before trying again."
        case .service: "The service is temporarily unavailable. Try again in a moment."
        case .network: "Check your internet connection, then try again."
        case .invalidRequest: "Check the model and its settings before trying again."
        case .stopped, .unknown:
            said.map { "\(agent.isEmpty ? "It" : agent) said: \u{201C}\($0)\u{201D} You can try again to continue this chat." }
                ?? "You can try again to continue this chat."
        }
    }

    /// What went wrong in the agent's own words, when they read as a
    /// sentence: its message's first line, short, with no code, envelope
    /// or stack in it ("Error: the session file is locked" says "The
    /// session file is locked."). The whole message stays in Details.
    var said: String? {
        guard !isEnvelope else { return nil }
        var line = message.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        for lead in ["Error:", "error:", "ERROR:", "Fatal:", "fatal:", "FATAL:"] where line.hasPrefix(lead) {
            line = String(line.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        guard line.count >= 4, line.count <= 160, line.filter(\.isLetter).count >= 4,
              !line.contains("{"), !line.contains("}"), !line.contains("stopped ("), !line.hasPrefix("at "), !line.contains(".js:"), !line.contains("    ") else { return nil }
        line = line.prefix(1).uppercased() + line.dropFirst()
        return ".!?".contains(line.last ?? " ") ? line : line + "."
    }

    var recovery: Recovery {
        switch kind {
        case .modelUnavailable: .model
        case .signIn, .access, .quota, .invalidRequest: .account
        default: .retry
        }
    }

    var action: String {
        switch recovery {
        case .model: "Choose Model"
        case .account: "Open AI Settings"
        case .retry: "Try Again"
        }
    }

    var code: String { status.map { "HTTP \($0) · \(kind.rawValue)" } ?? kind.rawValue }
    var diagnostics: String {
        ([providerCode.map { "Provider code: \($0)" }, message.isEmpty ? nil : message].compactMap { $0 }).joined(separator: "\n")
    }

    /// Both CLIs send envelopes, plain messages, and JSON inside messages.
    /// Read nested envelopes before deciding whether retrying would help.
    private static func extract(_ raw: String) -> (status: Int?, code: String?, message: String, isEnvelope: Bool) {
        var message = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var status: Int?
        // A transport's explicit HTTP status outranks JSON inside its
        // human message; an outer envelope likewise outranks an inner one.
        if let range = message.range(of: #"(?i)^HTTP(?:\s+status)?\s*[:=]?\s*([45][0-9]{2})\b"#, options: .regularExpression),
           let digits = message[range].range(of: #"[45][0-9]{2}$"#, options: .regularExpression) {
            status = Int(message[digits])
        }
        var code: String?
        var isEnvelope = false
        for _ in 0..<6 {
            guard let start = message.firstIndex(of: "{"), let end = message.lastIndex(of: "}"), start <= end,
                  let data = String(message[start...end]).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { break }
            let error = object["error"] as? [String: Any] ?? object
            isEnvelope = isEnvelope || object["error"] != nil || object["type"] as? String == "error" ||
                (object["code"] != nil && object["message"] != nil)
            if status == nil, let http = (object["status"] as? Int) ?? (error["status"] as? Int), (400...599).contains(http) { status = http }
            let name = error["code"] as? String ?? error["type"] as? String
            if let name, name != "error", name.range(of: #"^[A-Za-z0-9_.-]{1,80}$"#, options: .regularExpression) != nil { code = name }
            let next = error["message"] as? String ?? object["message"] as? String ?? object["error"] as? String
            guard let next, next != message else { message = ""; break }
            message = next.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if status == nil,
           let range = raw.range(of: #"(?i)(?:HTTP(?:\s+status)?|API\s+error|status(?:\s+code)?)\s*[:=]?\s*([45][0-9]{2})\b"#, options: .regularExpression),
           let digits = raw[range].range(of: #"[45][0-9]{2}$"#, options: .regularExpression) {
            status = Int(raw[digits])
        }
        // A broken envelope isn't useful to read and must not fill the card.
        if message.hasPrefix("{") { isEnvelope = true; message = "" }
        if message.hasPrefix("[") { message = "" }
        return (status, code, message, isEnvelope)
    }
}
