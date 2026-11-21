import SwiftUI
import WebKit

extension Space {
    static let development = Space(id: UUID(uuidString: "00000000-0000-0000-0000-00000000DE70")!,
                                   name: "Development", icon: "terminal", ownSignIns: false)
}

enum DevelopmentProject: String, CaseIterable {
    case yab, sunday, webistory, agada

    var title: String {
        switch self {
        case .yab: "Yab Browser"
        case .sunday: "Sunday"
        case .webistory: "Webistory"
        case .agada: "Agada"
        }
    }
}

extension Browser {
    var offersDevelopment: Bool { windowPurpose == .normal && !blank && !privateBrowsing }

    func enterDevelopment() {
        guard offersDevelopment, !inDevelopment else { return }
        hidePeek()
        editing = false
        allTabsSelected = false
        previousDevelopmentSidebar = (prefs.sidebar, prefs.sideShut)
        prefs.sidebar = true
        prefs.sideShut = false
        inDevelopment = true
    }
}

struct DevelopmentDetails: Codable, Equatable {
    var name: String
    var icon: String
    var folder: String
}

@MainActor @Observable
final class DevelopmentDirectory {
    static let shared = DevelopmentDirectory()
    private let key = "development.projectDetails"
    private(set) var entries: [String: DevelopmentDetails]

    init() {
        entries = Store.settings.data(forKey: key).flatMap {
            try? JSONDecoder().decode([String: DevelopmentDetails].self, from: $0)
        } ?? [:]
    }

    func details(_ project: DevelopmentProject) -> DevelopmentDetails {
        entries[project.rawValue] ?? DevelopmentDetails(name: project.title, icon: "", folder: "")
    }

    func save(_ details: DevelopmentDetails, for project: DevelopmentProject) {
        entries[project.rawValue] = details
        Store.settings.set(try? JSONEncoder().encode(entries), forKey: key)
    }
}

struct DevelopmentProjects: View {
    let browser: Browser

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TrailMenuRow(title: Space.development.name, selected: false, action: {
                SpaceTray.openSpaces(browser, from: SpaceAnchors.heading(Space.development.id, overview: false))
            }) { SpaceMark(icon: Space.development.icon, size: SideBar.mark) }
            .background { SpaceAnchor(kind: .heading(Space.development.id)) }
            Divider()
            Text("Projects").font(.caption).foregroundStyle(.secondary).padding(.horizontal, SideBar.inner)
            ForEach(DevelopmentProject.allCases, id: \.self) { project in
                let details = DevelopmentDirectory.shared.details(project)
                TrailMenuRow(title: details.name, selected: browser.developmentProject == project, action: {
                    browser.developmentProject = project
                }) {
                    if details.icon.isEmpty { Symbol("folder", size: SideBar.mark) }
                    else { Text(details.icon) }
                }
            }
        }
    }
}

/// One private content view per window. The native Space owns selection and
/// the view stays alive across Space switches without entering the tab store.
@MainActor
final class DevelopmentContent: NSObject, WKNavigationDelegate, WKUIDelegate {
    let toolbar = DevelopmentToolbarState()
    weak var browser: Browser?
    private(set) var ready = false
    private var sentEntries: [String: DevelopmentDetails]?
    private var selected: DevelopmentProject?
    lazy var view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(toolbar, name: "toolbar")
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = self
        view.uiDelegate = self
        if let file = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Development") {
            view.loadFileURL(file, allowingReadAccessTo: file.deletingLastPathComponent())
        } else {
            view.loadHTMLString("<p>Development workspace resources are missing.</p>", baseURL: nil)
        }
        return view
    }()

    func select(_ project: DevelopmentProject) {
        guard ready, project != selected else { return }
        selected = project
        view.callAsyncJavaScript("chooseProject(project)", arguments: ["project": project.rawValue],
                                 in: nil, in: .page, completionHandler: nil)
    }

    func updateDirectory() {
        let entries = DevelopmentDirectory.shared.entries
        guard ready, sentEntries != entries, let data = try? JSONEncoder().encode(entries),
              let json = String(data: data, encoding: .utf8) else { return }
        sentEntries = entries
        view.callAsyncJavaScript("applyDirectory(JSON.parse(json))", arguments: ["json": json],
                                 in: nil, in: .page, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        guard url.scheme == "yab-development" else {
            let local = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Development")
            let workspace = url.isFileURL && url.path == local?.path
            let preview = action.targetFrame == nil && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            decisionHandler(workspace || preview ? .allow : .cancel)
            return
        }
        decisionHandler(.cancel)
        guard let browser, action.sourceFrame.isMainFrame,
              let project = DevelopmentProject(rawValue: url.lastPathComponent) else { return }
        if url.host == "select" {
            browser.developmentProject = project
            return
        }
        guard project == browser.developmentProject else { return }
        var details = DevelopmentDirectory.shared.details(project)
        if url.host == "save" {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard let name = items.first(where: { $0.name == "name" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, let icon = items.first(where: { $0.name == "icon" })?.value else { return }
            details.name = String(name.prefix(80))
            details.icon = String(icon.prefix(1))
        } else if url.host == "folder" {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            guard let window = webView.window else { return }
            panel.beginSheetModal(for: window) { result in
                guard result == .OK, let url = panel.url else { return }
                var current = DevelopmentDirectory.shared.details(project)
                current.folder = url.path
                DevelopmentDirectory.shared.save(current, for: project)
            }
            return
        } else { return }
        DevelopmentDirectory.shared.save(details, for: project)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        selected = nil
        sentEntries = nil
        updateDirectory()
        if let browser { select(browser.developmentProject) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

@MainActor @Observable
final class DevelopmentToolbarState: NSObject, WKScriptMessageHandler {
    var active = "overview"
    var mode = "split"
    var chatWidth: CGFloat = 300

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let info = message.body as? [String: Any],
              let active = info["active"] as? String, let mode = info["mode"] as? String,
              let width = info["width"] as? NSNumber else { return }
        self.active = active
        self.mode = mode
        self.chatWidth = CGFloat(width.doubleValue)
    }
}

struct DevelopmentPane: View {
    let browser: Browser
    let project: DevelopmentProject
    let entries: [String: DevelopmentDetails]
    @State private var projectAnchor = ChatViewAnchor()
    private let tabs = [
        ("overview", "Overview", "rectangle.grid.2x2"), ("roadmap", "Roadmap", "point.3.connected.trianglepath.dotted"),
        ("specs", "Spec", "doc.text"), ("pitch", "Pitch board", "rectangle.3.group"),
        ("tasks", "Tasks", "checklist"), ("agents", "Agents", "person.2"),
        ("review", "Code", "chevron.left.forwardslash.chevron.right"), ("preview", "Preview", "globe"),
        ("terminal", "Terminal", "terminal"), ("settings", "Settings", "gearshape")
    ]

    var body: some View {
        let content = browser.developmentContent
        let state = content.toolbar
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    guard let anchor = projectAnchor.view else { return }
                    let menu = NSMenu(title: "Switch project")
                    for item in DevelopmentProject.allCases {
                        let row = ClosureItem(DevelopmentDirectory.shared.details(item).name) { browser.developmentProject = item }
                        row.state = item == project ? .on : .off
                        menu.addItem(row)
                    }
                    ActionMenu.show(menu, under: anchor)
                } label: {
                    HStack(spacing: 4) {
                        let details = DevelopmentDirectory.shared.details(project)
                        if !details.icon.isEmpty { Text(details.icon) }
                        else if project == .yab { Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 16, height: 16) }
                        else { Symbol("folder", size: 13) }
                        Text(details.name).lineLimit(1)
                        Symbol("chevron.up.chevron.down", size: 9)
                    }
                }
                .buttonStyle(.yab(.quiet, .small))
                .background(ChatProjectAnchorView(box: projectAnchor))
                .accessibilityLabel("Switch project, " + DevelopmentDirectory.shared.details(project).name)
                .keyTip("Switch project")
                .frame(width: state.mode == "split" ? max(100, state.chatWidth - 12) : nil, alignment: .leading)
                ThreadScrollView(.horizontal) {
                    HStack(spacing: 2) {
                        ForEach(tabs, id: \.0) { item in
                            DevToolTabButton(title: item.1, selected: state.active == item.0, action: {
                                content.view.callAsyncJavaScript("go(route)", arguments: ["route": item.0], in: nil, in: .page, completionHandler: nil)
                            }) { Symbol(item.2, size: 11) }
                            .disabled(item.0 == "agents")
                        }
                    }
                }.scrollIndicators(.never)
                Spacer(minLength: 0)
                layoutAction("sidebar.right", state.mode == "chat" ? "Show tools panel" : "Hide tools panel", "panel")
                layoutAction(state.mode == "full" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             state.mode == "full" ? "Exit full view" : "Enter full view", "full")
            }
            .padding(.horizontal, 8).frame(height: 38)
            Divider()
            DevelopmentWebPane(browser: browser, project: project, entries: entries)
        }
    }

    private func layoutAction(_ icon: String, _ title: String, _ action: String) -> some View {
        Button {
            browser.developmentContent.view.callAsyncJavaScript("toggleLayout(action)", arguments: ["action": action], in: nil, in: .page, completionHandler: nil)
        } label: { Symbol(icon, size: 13) }
        .buttonStyle(.yab(.quiet, .small, icon: .square))
        .accessibilityLabel(title).keyTip(title)
    }
}

private struct DevelopmentWebPane: NSViewRepresentable {
    let browser: Browser
    let project: DevelopmentProject
    var entries: [String: DevelopmentDetails]
    func makeNSView(context: Context) -> WKWebView {
        browser.developmentContent.browser = browser
        return browser.developmentContent.view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        browser.developmentContent.select(project)
        browser.developmentContent.updateDirectory()
    }
}
