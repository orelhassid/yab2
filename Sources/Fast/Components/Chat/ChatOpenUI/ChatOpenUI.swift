import SwiftUI
import WebKit

/// OpenUI is an optional block in a normal assistant reply. Ordinary
/// Markdown and fenced code continue through the native transcript.
struct OpenUIReply: Equatable {
    let prose: String
    let program: String?
    let complete: Bool

    init(_ text: String) {
        var words: [String] = []
        var program: [String] = []
        var fence: String?
        var inside = false
        var complete = false
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if inside {
                if trimmed == "```" {
                    inside = false
                    complete = true
                } else {
                    program.append(line)
                }
            } else if let fenceMarker = fence {
                words.append(line)
                if trimmed.hasPrefix(fenceMarker),
                   trimmed.dropFirst(fenceMarker.count).allSatisfy({ $0 == fenceMarker.first }) {
                    fence = nil
                }
            } else if !complete, trimmed.lowercased() == "```openui", !line.hasPrefix("    ") {
                inside = true
            } else {
                words.append(line)
                if let marker = trimmed.first, marker == "`" || marker == "~",
                   !line.hasPrefix("    ") {
                    let run = trimmed.prefix { $0 == marker }
                    if run.count >= 3 { fence = String(run) }
                }
            }
        }
        prose = words.joined(separator: "\n")
        let body = program.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        self.complete = complete
        self.program = (inside || complete) && !body.isEmpty && body.utf8.count <= 48_000 ? body : nil
    }
}

enum OpenUIRuntime {
    static let page = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "OpenUI")
    static let prompt = Bundle.main.url(forResource: "prompt", withExtension: "txt", subdirectory: "OpenUI")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .map { "\n\n" + $0 } ?? ""
}

extension EnvironmentValues {
    @Entry var openUIProject: DevelopmentProject? = nil
}

struct ChatOpenUI: View {
    let browser: Browser
    let program: String
    let streaming: Bool
    let chatID: String
    @Environment(\.openUIProject) private var project
    @Environment(\.colorScheme) private var scheme
    @Environment(\.tone) private var tone
    @State private var height: CGFloat = 30
    @State private var unavailable = false
    @State private var hasAppeared = false
    @State private var submitted = false

    var body: some View {
        Group {
            if unavailable || OpenUIRuntime.page == nil {
                Text("This reply couldn’t display its interactive content.")
                    .font(CardFrame.detail)
                    .foregroundStyle(Palette.muted(on: tone))
                    .textSelection(.enabled)
            } else if hasAppeared, let page = OpenUIRuntime.page {
                OpenUIReplyWeb(page: page, program: program, streaming: streaming, submitted: submitted, tone: tone, scheme: scheme,
                               grew: { height = $0 }, failed: { unavailable = true },
                               submit: send)
                    .frame(height: height)
            } else {
                Color.clear.frame(height: height).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onScrollVisibilityChange(threshold: 0.01) { visible in
            if visible { hasAppeared = true }
        }
    }

    private func send(_ text: String) {
        let directory = DevelopmentDirectory.shared
        guard !submitted, let project, browser.inDevelopment, browser.developmentProject == project,
              directory.details(project).selectedChatID == chatID else { return }
        let live = Agents.shared.session(chatID)?.state.live == true
        submitted = directory.send(text, items: [], mentions: [], spans: [], project: project, browser: browser, later: live)
    }
}

private struct OpenUIReplyWeb: NSViewRepresentable {
    let page: URL
    let program: String
    let streaming: Bool
    let submitted: Bool
    let tone: Tone?
    let scheme: ColorScheme
    let grew: (CGFloat) -> Void
    let failed: () -> Void
    let submit: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "openUIReply")
        let web = WKWebView(frame: .zero, configuration: configuration)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        context.coordinator.web = web
        context.coordinator.page = page
        web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        let bridge = context.coordinator
        bridge.grew = grew
        bridge.failed = failed
        bridge.submit = submit
        let dark = scheme == .dark
        let surface = tone?.page.blended(withFraction: 0.065, of: dark ? .white : .black)
        let colors = [
            "surface": surface.map { "#" + $0.hex } ?? (dark ? "#292a31" : "#f5f5f7"),
            "border": tone.map { "#" + SpaceSurface.rim(on: $0).hex } ?? (dark ? "#484854" : "#d9dae0"),
            "text": tone.map { "#" + Palette.shades($0).strongNS.hex } ?? (dark ? "#f3f3f6" : "#23242b"),
            "muted": tone.map { "#" + Palette.shades($0).mutedNS.hex } ?? (dark ? "#b3b4c1" : "#575864"),
            "accent": "#" + NSColor.controlAccentColor.hex,
        ]
        bridge.update(program: program, streaming: streaming, submitted: submitted, dark: dark, colors: colors)
    }

    static func dismantleNSView(_ web: WKWebView, coordinator: Coordinator) {
        web.stopLoading()
        web.navigationDelegate = nil
        web.configuration.userContentController.removeScriptMessageHandler(forName: "openUIReply")
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        weak var web: WKWebView?
        var page: URL?
        var grew: ((CGFloat) -> Void)?
        var failed: (() -> Void)?
        var submit: ((String) -> Void)?
        private var ready = false
        private var streaming = true
        private var payload = ""
        private var arguments: [String: Any] = [:]

        func update(program: String, streaming: Bool, submitted: Bool, dark: Bool, colors: [String: String]) {
            let next = ["program": program, "streaming": streaming, "submitted": submitted,
                        "theme": colors.mapValues { $0 as Any }.merging(["dark": dark]) { _, new in new }] as [String: Any]
            guard let data = try? JSONSerialization.data(withJSONObject: next, options: .sortedKeys),
                  let fingerprint = String(data: data, encoding: .utf8), payload != fingerprint else { return }
            self.streaming = streaming
            payload = fingerprint
            arguments = next
            push()
        }

        private func push() {
            guard ready else { return }
            web?.callAsyncJavaScript("window.showOpenUIReply(reply)", arguments: ["reply": arguments],
                                     in: nil, in: .page) { [weak self] result in
                if case .failure = result { self?.failed?() }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.targetFrame?.isMainFrame == true && action.request.url == page
                            && action.navigationType == .other ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            push()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed?() }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed?() }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed?() }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame, message.webView === web,
                  let body = message.body as? [String: Any] else { return }
            if let height = body["height"] as? NSNumber, height.doubleValue.isFinite, height.doubleValue > 0 {
                grew?(CGFloat(min(1000, height.doubleValue)))
            } else if !streaming, body["invalid"] as? Bool == true {
                failed?()
            } else if !streaming, let text = body["action"] as? String,
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 12_000 {
                submit?(text)
            }
        }
    }
}
