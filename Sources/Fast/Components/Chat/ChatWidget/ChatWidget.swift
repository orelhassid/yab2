import AppKit
import SwiftUI
import WebKit

// A widget Claude drew with its visualize tool (show_widget), where it was
// own: the chat's ground behind it, the column's width, its content's
// height. A small muted line over it names it; ⤢ opens it on the whole
// window in Peek. Its buttons (sendPrompt) put their words in the field,
// never sent; its links open as the chat's links do.
//
// Each is a page of its own in a web view taken from a small pool, nothing
// kept, no cookies, only the CDNs the tool allows, nothing on the local
// network. Only widgets on screen are live; off screen one is a still
// picture of itself at its last height.
//
// Codex's are drawn the same way from the fragment file it named, in its
// bundled plugin's kit (CodexVisualize): drawn again when Codex writes the
// file anew, its follow-ups put in the field, its links to Peek.

struct ChatWidget: View {
    let browser: Browser
    let item: ChatItem
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme
    /// In view of the transcript's scroll: only then a live page.
    @State private var onScreen = false
    @State private var height: CGFloat

    init(browser: Browser, item: ChatItem) {
        self.browser = browser
        self.item = item
        _height = State(initialValue: ChatWidgetView.heights[item.id] ?? ChatWidgetPage.least)
    }

    /// Codex's: its fragment in a file, drawn with its plugin's kit (CodexVisualize).
    @State private var fragment: String?
    @State private var kit: CodexVisualize.Kit?

    private var codex: Bool { item.extra?["widgetKit"] == "codex" }
    private var file: String? { item.extra?["widgetFile"].flatMap { $0.isEmpty ? nil : $0 } }
    private var code: String? { codex ? (kit == nil ? nil : fragment) : item.extra?["widget"].flatMap { $0.isEmpty ? nil : $0 } }
    private var title: String { ChatItem.widgetWords(item.extra?["widgetTitle"] ?? "") }
    private var dark: Bool { scheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let code {
                HStack(spacing: 2) {
                    named
                    Button { expand(code) } label: { Symbol("arrow.up.left.and.arrow.down.right", size: 10) }
                        .buttonStyle(.yab(.quiet, .small, icon: .square))
                        .focusable(false)
                        .keyTip("Open on the Whole Window")
                        .accessibilityLabel("Open on the whole window")
                }
                .padding(.leading, MessageBubble.words - MessageBubble.tailRoom)
                shown(code)
                    .frame(maxWidth: ChatWidgetPage.widest, alignment: .leading)
                    .frame(height: height)
                    .onScrollVisibilityChange(threshold: 0.01) { onScreen = $0 }
            } else if codex {
                // Codex's, its plugin not on this Mac or its file not a
                // fragment: its name, and its file in Peek.
                HStack(spacing: 6) {
                    named
                    if let file, FileManager.default.fileExists(atPath: file) {
                        Button("Open") { open(file) }
                            .buttonStyle(.yab(.quiet, .small))
                            .focusable(false)
                            .keyTip("Open in Peek")
                    }
                }
                .padding(.leading, MessageBubble.words - MessageBubble.tailRoom)
            } else {
                // Its code still on its way: what it said it is drawing.
                Text(item.extra?["loading"] ?? "Drawing")
                    .font(.system(size: 13.5))
                    .glint(item.state == .running)
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, MessageBubble.words - MessageBubble.tailRoom)
            }
        }
        .padding(.leading, MessageBubble.tailRoom)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: file) { await watch() }
    }

    private var named: some View {
        Text(title.isEmpty ? "Widget" : "Widget \u{00B7} " + title)
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    /// Codex's file, read now and again whenever Codex writes it anew
    /// while it is in view (it rewrites it as it works on it).
    private func watch() async {
        guard codex, let file else { return }
        kit = CodexVisualize.kit(for: file)
        guard kit != nil else { return }
        var seen = CodexVisualize.written(file)
        fragment = CodexVisualize.fragment(at: file)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard onScreen, !Task.isCancelled else { continue }
            let now = CodexVisualize.written(file)
            guard now != seen else { continue }
            seen = now
            fragment = CodexVisualize.fragment(at: file)
        }
    }

    @ViewBuilder private func shown(_ code: String) -> some View {
        if onScreen {
            ChatWidgetWeb(id: item.id, code: code, kit: codex ? kit : nil, title: title, dark: dark,
                          grew: { tall in
                              guard abs(tall - height) > 0.5 else { return }
                              height = tall
                          },
                          prompt: { words in browser.chatDraft = words },
                          link: { url in follow(url) })
        } else if let still = ChatWidgetView.still(item.id, dark: dark) {
            // Off screen, or not yet in view: the picture it left.
            Image(nsImage: still).resizable().aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        } else {
            Color.clear
        }
    }

    /// A link from it, or one it opened: as the chat's own links go.
    private func follow(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) else { return }
        openURL(url)
    }

    /// On the whole window: a page of its own, at full size, in Peek.
    private func expand(_ code: String) {
        let page: String? = codex ? kit.map { CodexVisualize.document(code, title: title, kit: $0, full: true) } : ChatWidgetPage.page(code, dark: nil, full: true)
        guard let page, let file = ChatWidgetPage.write(item.id, page: page) else { return }
        open(file.path)
    }

    private func open(_ path: String) {
        guard let source = browser.active else { return }
        if browser.peeking != nil { browser.hidePeek() }
        browser.peek(URL(fileURLWithPath: path), from: source)
    }
}

/// The widget's page in a pooled web view, as tall as its content says.
struct ChatWidgetWeb: NSViewRepresentable {
    let id: String
    /// Claude's widget code, or Codex's fragment.
    let code: String
    /// Codex's plugin kit, for a fragment of Codex's (CodexVisualize).
    var kit: CodexVisualize.Kit? = nil
    var title = ""
    let dark: Bool
    let grew: (CGFloat) -> Void
    let prompt: (String) -> Void
    let link: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Its page: Claude's contract round its code, or Codex's kit round its fragment.
    @MainActor private func page() -> String {
        if let kit { return CodexVisualize.document(code, title: title, kit: kit, state: ChatWidgetView.states[id]) }
        return ChatWidgetPage.page(code, dark: dark)
    }

    func makeNSView(context: Context) -> ChatWidgetView {
        let view = ChatWidgetView.take()
        let coordinator = context.coordinator
        coordinator.hand(self)
        view.owner = coordinator
        view.navigationDelegate = coordinator
        view.uiDelegate = coordinator
        coordinator.code = code
        coordinator.dark = dark
        view.widget = id
        view.look(dark)
        view.loadHTMLString(page(), baseURL: nil)
        return view
    }

    func updateNSView(_ view: ChatWidgetView, context: Context) {
        let coordinator = context.coordinator
        coordinator.hand(self)
        if coordinator.code != code {
            // Its code anew, or Codex's file written again.
            coordinator.code = code
            coordinator.dark = dark
            view.widget = id
            view.look(dark)
            view.loadHTMLString(page(), baseURL: nil)
        } else if coordinator.dark != dark {
            // Light and dark follow the window live: only the page's mode
            // changes (Claude's by data-mode, Codex's kit by the look's
            // prefers-color-scheme).
            coordinator.dark = dark
            view.look(dark)
            if kit == nil { view.evaluateJavaScript("document.documentElement.dataset.mode='\(dark ? "dark" : "light")'") }
            view.keepStill()
        }
    }

    static func dismantleNSView(_ view: ChatWidgetView, coordinator: Coordinator) {
        ChatWidgetView.give(view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ChatWidgetView, context: Context) -> CGSize? {
        CGSize(width: min(proposal.width ?? ChatWidgetPage.widest, ChatWidgetPage.widest), height: proposal.height ?? ChatWidgetPage.least)
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var code = ""
        var dark = false
        var grew: ((CGFloat) -> Void)?
        var prompt: ((String) -> Void)?
        var link: ((URL) -> Void)?

        func hand(_ web: ChatWidgetWeb) {
            grew = web.grew
            prompt = web.prompt
            link = web.link
        }

        /// What its page said through the bridge (ChatWidgetPage.bridge).
        func heard(_ body: Any, from view: ChatWidgetView) {
            guard let said = body as? [String: Any] else { return }
            if let tall = (said["height"] as? NSNumber)?.doubleValue {
                let height = max(ChatWidgetPage.least, CGFloat(tall).rounded(.up))
                ChatWidgetView.heights[view.widget] = height
                grew?(height)
                view.keepStill()
            }
            // What a Codex widget keeps (window.openai.setWidgetState): back
            // in it when it is drawn again, while Yab runs.
            if let state = said["state"] as? String, !view.widget.isEmpty { ChatWidgetView.states[view.widget] = state }
            if let words = said["prompt"] as? String, !words.isEmpty { prompt?(words) }
            if let address = said["link"] as? String, let url = URL(string: address) { link?(url) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Its own page, loaded from its code; anything else it would go
            // to is a link the chat opens, or nothing.
            let url = action.request.url
            if action.navigationType != .linkActivated, url == nil || url?.scheme == "about" {
                return decisionHandler(.allow)
            }
            decisionHandler(.cancel)
            if action.targetFrame?.isMainFrame != false, let url { link?(url) }
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { link?(url) }
            return nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            (webView as? ChatWidgetView)?.keepStill()
        }
    }
}

/// A widget's web view: the wheel goes on to the transcript's scroll, no
/// scroll of its own. Kept in a pool as Mail's are (MailBodyView): one
/// store in memory for all of them, a few waiting with their process up.
final class ChatWidgetView: WKWebView {
    /// The widget it shows, for its height and still picture.
    var widget = ""
    var dark = false
    weak var owner: ChatWidgetWeb.Coordinator?

    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }

    /// Each widget's last height, so scrolling back to it doesn't jump.
    @MainActor static var heights: [String: CGFloat] = [:]
    /// What each Codex widget kept of itself (its widget state, as JSON).
    @MainActor static var states: [String: String] = [:]

    /// Light or dark as the window is: Claude's page is told by data-mode,
    /// Codex's kit reads it as prefers-color-scheme.
    @MainActor func look(_ dark: Bool) {
        self.dark = dark
        appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
    /// Each widget's still picture, light and dark, for while it is off screen.
    @MainActor private static let stills: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 40
        return cache
    }()

    @MainActor static func still(_ widget: String, dark: Bool) -> NSImage? {
        stills.object(forKey: (widget + (dark ? ".dark" : ".light")) as NSString)
    }

    private var stillPending = false

    /// A still picture of it once it has settled: a moment after its last
    /// change of size, so a chart's own motion has played.
    @MainActor func keepStill() {
        guard !stillPending, !widget.isEmpty else { return }
        stillPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.stillPending = false
                guard self.window != nil, self.bounds.height > 1, !self.widget.isEmpty else { return }
                let key = (self.widget + (self.dark ? ".dark" : ".light")) as NSString
                let config = WKSnapshotConfiguration()
                config.afterScreenUpdates = false
                self.takeSnapshot(with: config) { image, _ in
                    guard let image else { return }
                    MainActor.assumeIsolated { Self.stills.setObject(image, forKey: key) }
                }
            }
        }
    }

    /// One store in memory for every widget, no cookies, its script on,
    /// nothing on this Mac's network; the bridge its page talks through.
    @MainActor private static let configuration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.websiteDataStore.httpCookieStore.setCookiePolicy(.disallow, completionHandler: nil)
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.userContentController.add(ChatWidgetRelay(), name: ChatWidgetPage.handler)
        LocalNetwork.protect(config.userContentController)
        return config
    }()

    @MainActor private static var ready: [ChatWidgetView] = []
    /// Two on screen at once is usual; a chat of twenty widgets runs those.
    static let kept = 3

    @MainActor static func take() -> ChatWidgetView {
        ready.popLast() ?? made()
    }

    /// One a widget let go of: emptied, kept while there is room.
    @MainActor static func give(_ view: ChatWidgetView) {
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.owner = nil
        view.widget = ""
        view.appearance = nil
        view.stopLoading()
        view.loadHTMLString("", baseURL: nil)
        guard ready.count < kept else { return }
        ready.append(view)
    }

    @MainActor private static func made() -> ChatWidgetView {
        AppleWritingTools.configure(configuration)
        let view = ChatWidgetView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
}

/// The bridge's one handler, shared by every pooled view: what a page says
/// goes to the view's widget of the moment. Holds nothing, so the
/// configuration keeping it keeps no widget alive.
private final class ChatWidgetRelay: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let view = message.webView as? ChatWidgetView, message.frameInfo.isMainFrame else { return }
        MainActor.assumeIsolated { view.owner?.heard(message.body, from: view) }
    }
}

/// A widget's page: the host's contract (Claude's visualize tool) laid
/// over Yab's palette, and the widget's code in its body.
enum ChatWidgetPage {
    /// The width the tool draws for.
    static let widest: CGFloat = 680
    /// The least height a widget is given, as Claude's app gives it.
    static let least: CGFloat = 100
    static let handler = "widget"

    /// The places a widget may load from: the tool's allowlist.
    static let scripts = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com"
    static let policy = "default-src 'none'; script-src 'unsafe-inline' \(scripts); "
        + "style-src 'unsafe-inline' https://fonts.googleapis.com \(scripts); "
        + "font-src https://fonts.gstatic.com \(scripts) data:; img-src data: blob: \(scripts); "
        + "connect-src \(scripts); form-action 'none'"
    /// The icon font the tool's widgets draw with (Tabler, outline).
    static let icons = "https://cdn.jsdelivr.net/npm/@tabler/icons-webfont@3/dist/tabler-icons.min.css"

    /// The whole page. `full`: on the whole window in Peek, a page of its
    /// own in a tab, the bridge quiet and its links its own.
    @MainActor static func page(_ code: String, dark: Bool?, full: Bool = false) -> String {
        let mode = dark.map { " data-mode=\"\($0 ? "dark" : "light")\"" } ?? ""
        return """
        <!doctype html><html\(mode)><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(policy)">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <link rel="stylesheet" href="\(icons)">
        <style>\(sheet())\(full ? fullSheet : "")</style>
        <script>\(bridge(full: full))</script>
        </head><body>
        \(code)
        </body></html>
        """
    }

    /// The page on the whole window, kept as a file for Peek to open.
    @MainActor static func write(_ widget: String, code: String) -> URL? {
        write(widget, page: page(code, dark: nil, full: true))
    }

    /// A whole page, Claude's or Codex's, kept as code/widgets/<widget>.html.
    @MainActor static func write(_ widget: String, page: String) -> URL? {
        let name = widget.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" ? String($0) : "-" }.joined()
        let file = Store.file("code/widgets/\(name.isEmpty ? "widget" : name).html")
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? Data(page.utf8).write(to: file)) != nil else { return nil }
        return file
    }

    private static let fullSheet = "html,body{overflow:auto}body{max-width:\(Int(widest) * 2)px;margin:0 auto;padding:32px 24px;background:var(--surface-2)}"

    /// sendPrompt, openLink and link clicks through the handler; window.open
    /// and fullscreen dead; its height said whenever it changes.
    static func bridge(full: Bool) -> String {
        guard !full else {
            return "window.sendPrompt=function(){};window.openLink=function(u){if(u)location.href=String(u)};"
        }
        return #"""
        (function(){
          var post=function(m){try{window.webkit.messageHandlers.\#(handler).postMessage(m)}catch(e){}};
          window.sendPrompt=function(t){post({prompt:String(t==null?'':t)})};
          window.openLink=function(u){if(u)post({link:String(u)})};
          window.open=function(u){if(u)post({link:String(u)});return null};
          try{Element.prototype.requestFullscreen=function(){return Promise.reject(new Error('no fullscreen'))}}catch(e){}
          document.addEventListener('click',function(e){
            var a=e.target&&e.target.closest?e.target.closest('a[href]'):null;
            if(!a||e.defaultPrevented)return;
            var h=a.getAttribute('href')||'';
            if(!h||h.charAt(0)==='#'||/^javascript:/i.test(h))return;
            e.preventDefault();post({link:a.href});
          });
          var last=0;
          var size=function(){var b=document.body;if(!b)return;
            var h=Math.ceil(Math.max(b.scrollHeight,b.getBoundingClientRect().height));
            if(Math.abs(h-last)>0.5){last=h;post({height:h})}};
          document.addEventListener('DOMContentLoaded',function(){
            try{new ResizeObserver(size).observe(document.body)}catch(e){}
            size();
          });
          window.addEventListener('load',size);
          if(document.fonts&&document.fonts.ready)document.fonts.ready.then(size);
        })();
        """#
    }

    // MARK: the contract's look, in Yab's colors

    /// The tool's variables (surfaces, text, borders, the roles), its SVG
    /// classes and color ramps, and its pre-styled controls, light and dark.
    /// Dark when the page says so (data-mode, as the chat sets it with the
    /// window's look) or, with no word from it, when the Mac is.
    @MainActor static func sheet() -> String {
        let light = variables(dark: false), dark = variables(dark: true)
        return ":root{\(light)\(fixed)}"
            + "@media (prefers-color-scheme: dark){:root:not([data-mode=light]){\(dark)}\(darkRamps(":root:not([data-mode=light]) "))}"
            + "[data-mode=dark]{\(dark)}" + darkRamps("[data-mode=dark] ")
            + base + svg + ramps
    }

    /// Yab's palette as the tool's names, in one look.
    @MainActor static func variables(dark: Bool) -> String {
        let ns = Palette.NS.self
        func hex(_ color: NSColor) -> String { Self.hex(color, dark: dark) }
        func mix(_ color: NSColor, _ amount: CGFloat) -> String { Self.hex(color, over: ns.ground, amount, dark: dark) }
        let accent = NSColor.controlAccentColor
        // The page and its two steps up, darkest first in both looks, as the tool's are.
        let surfaces = dark ? [ns.ground, ns.hover, ns.wash, ns.wash] : [ns.wash, ns.hover, ns.ground, ns.ground]
        var out: [(String, String)] = [
            ("surface-0", hex(surfaces[0])), ("surface-1", hex(surfaces[1])),
            ("surface-2", hex(surfaces[2])), ("surface-3", hex(surfaces[3])),
            ("surface-panel", hex(surfaces[2])), ("surface-popover", hex(surfaces[3])),
            ("page-bg", hex(ns.ground)),
            ("text-primary", hex(ns.ink)), ("text-secondary", hex(ns.muted)),
            ("text-muted", mix(ns.muted, 0.75)), ("text-disabled", mix(ns.muted, 0.45)),
            ("border", hex(ns.hairline)), ("border-strong", hex(ns.faint)), ("border-stronger", mix(ns.muted, 0.7)),
            ("fill-primary", hex(ns.ink)), ("fill-primary-hover", mix(ns.ink, 0.85)), ("on-primary", hex(ns.ground)),
            ("fill-secondary", "transparent"), ("fill-secondary-hover", hex(ns.hover)), ("fill-secondary-ring", hex(ns.hairline)),
            ("fill-field", hex(surfaces[2])), ("fill-field-ring", hex(ns.hairline)),
            ("fill-ghost-hover", hex(ns.hover)), ("fill-ghost-selected", hex(ns.wash)),
            ("fill-control", hex(ns.wash)), ("fill-control-hover", hex(ns.hairline)), ("fill-disabled", hex(ns.hover)),
            ("bg-neutral", hex(ns.wash)),
        ]
        let roles: [(String, NSColor)] = [("accent", accent), ("danger", .systemRed), ("success", .systemGreen),
                                          ("warning", .systemOrange), ("pro", .systemPurple)]
        for (role, color) in roles {
            out += [("text-\(role)", hex(color)), ("bg-\(role)", mix(color, dark ? 0.22 : 0.12)),
                    ("border-\(role)", mix(color, 0.55)), ("fill-\(role)", hex(color)),
                    ("fill-\(role)-hover", mix(color, 0.88)), ("on-\(role)", role == "warning" || role == "success" ? "#141414" : "#ffffff")]
        }
        out += [("bg-accent-muted", mix(accent, dark ? 0.14 : 0.08)), ("bg-highlight", mix(.systemYellow, 0.35)),
                ("fill-brand", hex(accent)), ("fill-brand-hover", mix(accent, 0.88)), ("on-brand", "#ffffff"),
                ("focus-shadow", "0 0 0 1px \(hex(accent)), 0 0 6px 1px \(mix(accent, 0.2))"),
                ("shadow-color", dark ? "rgba(0,0,0,0.24)" : "rgba(0,0,0,0.08)")]
        return out.map { "--\($0.0):\($0.1);" }.joined() + "color-scheme:\(dark ? "dark" : "light");"
    }

    /// What doesn't change with the look: type, room, motion.
    static let fixed = """
    --font-sans:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",sans-serif;\
    --font-voice:"New York",ui-serif,Georgia,serif;--font-mono:ui-monospace,"SF Mono",Menlo,monospace;\
    --radius:8px;--h-control:36px;--pad-sm:8px;--pad-md:12px;--pad-lg:16px;--pad-xl:24px;\
    --gap-xs:4px;--gap-sm:8px;--gap-md:12px;--gap-lg:16px;--gap-xl:24px;\
    --font-size-caption:12px;--font-size-footnote:13px;--font-size-body:14px;--font-size-prose:16px;\
    --font-size-code:13px;--font-size-heading:18px;--font-size-title:22px;\
    --shadow-sm:0 1px 2px var(--shadow-color);--shadow-md:0 2px 8px var(--shadow-color);\
    --shadow-lg:0 8px 24px var(--shadow-color);--shadow-popover:0 8px 24px rgba(0,0,0,.12),0 2px 6px rgba(0,0,0,.08);\
    --dur-fast:100ms;--dur-snap:150ms;--dur-base:200ms;--dur-slow:300ms;\
    --ease-out:cubic-bezier(.2,.8,.2,1);--ease-snap:cubic-bezier(.3,.7,.2,1);--ease-overshoot:cubic-bezier(.3,1.4,.5,1);
    """

    /// The page, its headings and its pre-styled controls.
    static let base = """
    *{box-sizing:border-box}html,body{overflow:hidden}\
    body{margin:0;background:transparent;color:var(--text-primary);font-family:var(--font-sans);font-size:16px;\
    line-height:1.7;display:flow-root;-webkit-font-smoothing:antialiased}\
    h1,h2,h3,h4{font-weight:500;color:var(--text-primary);line-height:1.35;margin:0 0 .5em}\
    h1{font-size:22px}h2{font-size:18px}h3{font-size:16px}h4{font-size:14px}\
    p{margin:0 0 1em}a{color:var(--text-accent)}b,strong{font-weight:500}\
    code,kbd,pre,samp{font-family:var(--font-mono);font-size:.9em}\
    button{font:inherit;font-size:14px;line-height:1.4;color:var(--text-primary);background:transparent;\
    border:.5px solid var(--border-strong);border-radius:var(--radius);padding:6px 14px;cursor:pointer;\
    transition:background var(--dur-fast),transform var(--dur-fast)}\
    button:hover{background:var(--surface-1)}button:active{transform:scale(.98)}\
    button:disabled{color:var(--text-disabled);cursor:default}\
    input:not([type]),input[type=text],input[type=number],input[type=email],input[type=search],input[type=url],\
    input[type=password],input[type=tel],input[type=date],input[type=time],select,textarea{font:inherit;font-size:14px;\
    color:var(--text-primary);background:var(--fill-field);border:.5px solid var(--border-strong);\
    border-radius:var(--radius);height:36px;padding:0 10px;outline:none}\
    textarea{height:auto;padding:8px 10px;line-height:1.5}\
    input:hover,select:hover,textarea:hover{border-color:var(--border-stronger)}\
    input:focus,select:focus,textarea:focus{border-color:var(--border-accent);box-shadow:0 0 0 3px var(--bg-accent-muted)}\
    input[type=range]{-webkit-appearance:none;appearance:none;height:4px;border-radius:2px;\
    background:var(--border-strong);outline:none;margin:8px 0}\
    input[type=range]::-webkit-slider-thumb{-webkit-appearance:none;width:18px;height:18px;border-radius:50%;\
    background:var(--surface-3);border:.5px solid var(--border-stronger);box-shadow:0 1px 2px var(--shadow-color);cursor:pointer}\
    input[type=checkbox],input[type=radio]{accent-color:var(--fill-accent)}\
    table{border-collapse:collapse}hr{border:0;border-top:.5px solid var(--border);margin:1rem 0}\
    .sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);\
    white-space:nowrap;border:0}\
    body>svg{display:block;width:100%;height:auto}svg{max-width:100%}
    """

    /// The tool's SVG classes: text, boxes, arrows. Inside an SVG only:
    /// widgets name their own HTML "t" or "box" too.
    static let svg = """
    svg text{font-family:var(--font-sans)}\
    svg .t{font-size:14px;fill:var(--text-primary)}svg .ts{font-size:12px;fill:var(--text-secondary)}\
    svg .th{font-size:14px;font-weight:500;fill:var(--text-primary)}\
    svg .box{fill:var(--surface-1);stroke:var(--border-strong);stroke-width:.5}\
    svg .node{cursor:pointer}svg .node:hover{opacity:.85}\
    svg .arr{stroke:var(--text-secondary);stroke-width:1.5;fill:none}\
    svg .leader{stroke:var(--text-muted);stroke-width:.5;stroke-dasharray:3 3;fill:none}
    """

    /// The tool's nine ramps, 50 to 900.
    static let ramp: [(String, [String])] = [
        ("purple", ["#EEEDFE", "#CECBF6", "#AFA9EC", "#7F77DD", "#534AB7", "#3C3489", "#26215C"]),
        ("teal", ["#E1F5EE", "#9FE1CB", "#5DCAA5", "#1D9E75", "#0F6E56", "#085041", "#04342C"]),
        ("coral", ["#FAECE7", "#F5C4B3", "#F0997B", "#D85A30", "#993C1D", "#712B13", "#4A1B0C"]),
        ("pink", ["#FBEAF0", "#F4C0D1", "#ED93B1", "#D4537E", "#993556", "#72243E", "#4B1528"]),
        ("gray", ["#F1EFE8", "#D3D1C7", "#B4B2A9", "#888780", "#5F5E5A", "#444441", "#2C2C2A"]),
        ("blue", ["#E6F1FB", "#B5D4F4", "#85B7EB", "#378ADD", "#185FA5", "#0C447C", "#042C53"]),
        ("green", ["#EAF3DE", "#C0DD97", "#97C459", "#639922", "#3B6D11", "#27500A", "#173404"]),
        ("amber", ["#FAEEDA", "#FAC775", "#EF9F27", "#BA7517", "#854F0B", "#633806", "#412402"]),
        ("red", ["#FCEBEB", "#F7C1C1", "#F09595", "#E24B4A", "#A32D2D", "#791F1F", "#501313"]),
    ]

    /// A ramp on a group, or on a shape itself: light, 50 fill, 600 stroke,
    /// 800 title, 600 subtitle.
    static var ramps: String { ramp.map { name, s in shades(name, fill: s[0], stroke: s[4], title: s[5], sub: s[4], scope: "") }.joined() }

    /// Dark: 800 fill, 200 stroke, 100 title, 200 subtitle.
    static func darkRamps(_ scope: String) -> String {
        ramp.map { name, s in shades(name, fill: s[5], stroke: s[2], title: s[1], sub: s[2], scope: scope) }.joined()
    }

    private static func shades(_ name: String, fill: String, stroke: String, title: String, sub: String, scope: String) -> String {
        let c = scope + "svg .c-" + name
        let shapes = ["rect", "circle", "ellipse", "polygon"].flatMap { ["\(c)>\($0)", "\(scope)svg \($0).c-\(name)"] }.joined(separator: ",")
        return "\(shapes){fill:\(fill);stroke:\(stroke)}\(c) .t,\(c) .th,\(c)>text{fill:\(title)}\(c) .ts{fill:\(sub)}"
    }

    // MARK: colors as CSS

    /// A Palette color as it resolves in one look.
    @MainActor static func hex(_ color: NSColor, dark: Bool) -> String {
        css(rgb(color, dark: dark))
    }

    /// `amount` of a color over another, as it resolves in one look.
    @MainActor static func hex(_ color: NSColor, over ground: NSColor, _ amount: CGFloat, dark: Bool) -> String {
        let a = rgb(color, dark: dark), b = rgb(ground, dark: dark)
        return css((a.0 * amount + b.0 * (1 - amount), a.1 * amount + b.1 * (1 - amount), a.2 * amount + b.2 * (1 - amount), 1))
    }

    @MainActor private static func rgb(_ color: NSColor, dark: Bool) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var out: (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 1)
        let look = NSAppearance(named: dark ? .darkAqua : .aqua) ?? NSAppearance.currentDrawing()
        look.performAsCurrentDrawingAppearance {
            guard let c = color.usingColorSpace(.sRGB) else { return }
            out = (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
        }
        return out
    }

    private static func css(_ c: (CGFloat, CGFloat, CGFloat, CGFloat)) -> String {
        func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        if c.3 < 0.999 { return "rgba(\(byte(c.0)),\(byte(c.1)),\(byte(c.2)),\(String(format: "%.3f", c.3)))" }
        return String(format: "#%02X%02X%02X", byte(c.0), byte(c.1), byte(c.2))
    }
}
