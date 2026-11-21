import SwiftUI
import WebKit

extension Space {
    static let development = Space(id: UUID(uuidString: "00000000-0000-0000-0000-00000000DE70")!,
                                   name: "Development", icon: "terminal", ownSignIns: false)
}

struct DevelopmentProject: RawRepresentable, Hashable {
    let rawValue: String
    static let yab = Self(rawValue: "yab")
    static let sunday = Self(rawValue: "sunday")
    static let defaults = [yab, sunday, Self(rawValue: "webistory"), Self(rawValue: "agada")]

    var title: String {
        rawValue == "yab" ? "Yab Browser" : rawValue.capitalized
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
    var paint: SpacePaint?
    var createdAt: TimeInterval?
    var activity: [DevelopmentEvent]?
    var chatID: String?
    var provider: String?
    var providerChats: [String: String]?
    var modelChoices: [String: ModelChoice]?
    var workspaceWrite: Bool?

    var cli: String { provider ?? "codex" }
    var choice: ModelChoice { modelChoices?[cli] ?? ModelChoice(cli: cli) }
    var selectedChatID: String? {
        get { cli == "codex" ? chatID : providerChats?[cli] }
        set {
            if cli == "codex" { chatID = newValue }
            else {
                var chats = providerChats ?? [:]
                chats[cli] = newValue
                providerChats = chats
            }
        }
    }

    mutating func record(_ title: String) {
        activity = (activity ?? []) + [DevelopmentEvent(title: title, time: Date().timeIntervalSince1970)]
    }
}

struct DevelopmentEvent: Codable, Equatable {
    let title: String
    let time: TimeInterval
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

    var projects: [DevelopmentProject] {
        DevelopmentProject.defaults + entries.keys.filter { $0.hasPrefix("project-") }.sorted {
            (entries[$0]?.createdAt ?? 0, $0) < (entries[$1]?.createdAt ?? 0, $1)
        }.map(DevelopmentProject.init(rawValue:))
    }

    func create(folder: URL) -> DevelopmentProject {
        let project = DevelopmentProject(rawValue: "project-" + UUID().uuidString.lowercased())
        var details = DevelopmentDetails(name: folder.lastPathComponent, icon: "", folder: folder.path,
                                         createdAt: Date().timeIntervalSince1970)
        details.record("Project created")
        save(details, for: project)
        return project
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
    @AppStorage("development.projects.collapsed", store: Store.settings) private var collapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: SideBar.gap) {
            SpaceName(space: .development, browser: browser)
            SidebarSectionDivider()
            Quiet(icon: "plus", title: "New Project", prefs: browser.prefs, browser: browser) {
                guard let window = NSApp.keyWindow else { return }
                let panel = NSOpenPanel()
                panel.title = "Choose a project folder"
                panel.prompt = "Create Project"
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.beginSheetModal(for: window) { result in
                    guard result == .OK, let folder = panel.url else { return }
                    browser.developmentProject = DevelopmentDirectory.shared.create(folder: folder)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SideBar.gap) {
                    SidebarSection(collapsed: collapsed) {
                        SidebarSectionHeader(title: "Projects", paint: DevelopmentDirectory.shared.details(browser.developmentProject).paint ?? SpacePaint(browser.prefs),
                                             collapsed: collapsed, toggle: { collapsed.toggle() }) {
                            Symbol("folder", size: SideBar.mark)
                        }
                    } rows: {
                        ForEach(DevelopmentDirectory.shared.projects, id: \.self) { project in
                            let details = DevelopmentDirectory.shared.details(project)
                            let selected = browser.developmentProject == project
                            SidebarTabButton(title: details.name, selected: selected, prefs: browser.prefs,
                                             action: { browser.developmentProject = project }) {
                                if details.icon.isEmpty { Symbol("folder", size: SideBar.mark) }
                                else { Text(details.icon) }
                            }
                        }
                    }
                    SidebarSectionDivider()
                    ForEach([("settings", "Settings", "gearshape"), ("integrations", "Integrations", "puzzlepiece.extension")], id: \.0) { item in
                        SidebarTabButton(title: item.1, selected: browser.developmentContent.toolbar.active == item.0 && browser.developmentContent.toolbar.mode != "chat", prefs: browser.prefs, action: {
                            browser.developmentContent.view.callAsyncJavaScript("go(route)", arguments: ["route": item.0], in: nil, in: .page, completionHandler: nil)
                        }) { Symbol(item.2, size: SideBar.mark) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// One private content view per window. The native Space owns selection and
/// the view stays alive across Space switches without entering the tab store.
@MainActor
final class DevelopmentContent: NSObject, WKNavigationDelegate, WKUIDelegate {
    let toolbar = DevelopmentToolbarState()
    let terminals = DevelopmentTerminals()
    private var drafts: [DevelopmentProject: ChatAttach] = [:]
    func draft(for project: DevelopmentProject) -> ChatAttach {
        if let saved = drafts[project] { return saved }
        let draft = ChatAttach()
        draft.set([])
        drafts[project] = draft
        return draft
    }
    weak var browser: Browser? { didSet { toolbar.browser = browser } }
    private(set) var ready = false
    private var sentEntries: [String: DevelopmentDetails]?
    private var sentColors: [String: String]?
    private var selected: DevelopmentProject?

    func updateColors() {
        guard ready, let look = browser?.developmentLook else { return }
        let ground = SpaceWash.painted(look).color
        let tone = SpaceSurface.tone(for: ground)
        let shades = Palette.shades(tone)
        let colors = ["--ground": "#" + ground.hex, "--stage": "#" + tone.page.hex,
                      "--ink": "#" + shades.strongNS.hex, "--muted": "#" + shades.mutedNS.hex,
                      "--faint": "#" + shades.faintNS.hex, "--line": "#" + SpaceSurface.rim(on: tone).hex]
        guard colors != sentColors else { return }
        sentColors = colors
        view.callAsyncJavaScript("for (const [key, value] of Object.entries(colors)) document.documentElement.style.setProperty(key, value)",
                                 arguments: ["colors": colors], in: nil, in: .page, completionHandler: nil)
    }
    lazy var view: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(toolbar, name: "toolbar")
        configuration.userContentController.add(toolbar, name: "activity")
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
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
            let workspace = action.targetFrame?.isMainFrame == true && url.isFileURL && url.path == local?.path
            let preview = action.targetFrame?.isMainFrame != true && ["http", "https"].contains(url.scheme?.lowercased() ?? "")
            let emptyFrame = action.targetFrame?.isMainFrame == false && url.absoluteString == "about:blank"
            decisionHandler(workspace || preview || emptyFrame ? .allow : .cancel)
            return
        }
        decisionHandler(.cancel)
        guard let browser, action.sourceFrame.isMainFrame,
              let project = DevelopmentDirectory.shared.projects.first(where: { $0.rawValue == url.lastPathComponent }) else { return }
        if url.host == "select" {
            browser.developmentProject = project
            return
        }

    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        selected = nil
        sentColors = nil
        updateColors()
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
    weak var browser: Browser?
    var active = "overview"
    var mode = "split"
    var chatWidth: CGFloat = 300
    var toolFrame = CGRect.zero
    var reportedProject: String?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let info = message.body as? [String: Any] else { return }
        if let label = info["discuss"] as? String, let browser, info["project"] as? String == browser.developmentProject.rawValue {
            let project = browser.developmentProject
            let chat = DevelopmentDirectory.shared.details(project).selectedChatID.flatMap { Chats.shared.chat($0) }
            browser.developmentContent.draft(for: project).add(.quote(String(label.prefix(500))), chat: chat, browser: browser)
            return
        }
        if message.name == "activity" {
            let directory = DevelopmentDirectory.shared
            guard let id = info["project"] as? String,
                  let project = directory.projects.first(where: { $0.rawValue == id }),
                  let title = info["title"] as? String, !title.isEmpty else { return }
            var details = directory.details(project)
            details.record(String(title.prefix(200)))
            directory.save(details, for: project)
            return
        }
        guard let active = info["active"] as? String, let mode = info["mode"] as? String,
              let width = info["width"] as? NSNumber else { return }
        reportedProject = info["project"] as? String
        if let frame = info["toolFrame"] as? [Double], frame.count == 4,
           frame.allSatisfy({ $0.isFinite && $0 >= 0 }) {
            toolFrame = CGRect(x: frame[0], y: frame[1], width: frame[2], height: frame[3])
        } else {
            toolFrame = .zero
        }
        self.active = active
        self.mode = mode
        self.chatWidth = CGFloat(width.doubleValue)
    }
}

extension Browser {
    var developmentLook: SpacePaint? {
        guard inDevelopment, windowPurpose != .privateOnly else { return nil }
        return DevelopmentDirectory.shared.details(developmentProject).paint ?? SpacePaint(prefs)
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
        ("terminal", "Terminal", "terminal")
    ]

    var body: some View {
        let content = browser.developmentContent
        let state = content.toolbar
        let look = entries[project.rawValue]?.paint ?? SpacePaint(browser.prefs)
        let paint = SpaceWash.painted(look)
        VStack(spacing: 0) {
            TabWindowHeader(selection: state.active) {
                let details = DevelopmentDirectory.shared.details(project)
                TabWindowSwitcher(title: details.name, action: {
                    guard let anchor = projectAnchor.view else { return }
                    let menu = NSMenu(title: "Switch project")
                    for item in DevelopmentDirectory.shared.projects {
                        let row = ClosureItem(DevelopmentDirectory.shared.details(item).name) { browser.developmentProject = item }
                        row.state = item == project ? .on : .off
                        menu.addItem(row)
                    }
                    ActionMenu.show(menu, under: anchor)
                }) {
                    if !details.icon.isEmpty { Text(details.icon) }
                    else if project == .yab { Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: SideBar.mark, height: SideBar.mark) }
                    else { Symbol("folder", size: SideBar.mark) }
                }
                .background(ChatProjectAnchorView(box: projectAnchor))
                .accessibilityLabel("Switch project, " + DevelopmentDirectory.shared.details(project).name)
                .keyTip("Switch project")
            } tabs: {
                ForEach(tabs, id: \.0) { item in
                    SidebarTabButton(title: item.1, selected: state.active == item.0, prefs: browser.prefs, inTabStrip: true, action: {
                        content.view.callAsyncJavaScript("go(route)", arguments: ["route": item.0], in: nil, in: .page, completionHandler: nil)
                    }) { Symbol(item.2, size: 12) }
                    .disabled(item.0 == "agents")
                    .id(item.0)
                }
            } actions: {
                if browser.prefs.sideShut && browser.trailFlank == nil {
                    ColumnDoor(browser: browser, prefs: browser.prefs)
                        .environment(\.doorSize, .header)
                }
                layoutAction("sidebar.right", state.mode == "chat" ? "Show tools panel" : "Hide tools panel", "panel")
                layoutAction(state.mode == "full" ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             state.mode == "full" ? "Exit full view" : "Enter full view", "full")
            }
            .padding(.horizontal, SideBar.margin).frame(height: NavigationHeader.height(topInset: 0))
            Divider()
            DevelopmentWebPane(browser: browser, project: project, entries: entries)
                .overlay(alignment: .topLeading) {
                    if ["settings", "integrations", "terminal"].contains(state.active), state.reportedProject == project.rawValue,
                       !state.toolFrame.isEmpty, state.mode != "chat" {
                        Group {
                            if state.active == "settings" {
                                DevelopmentSettings(project: project, prefs: browser.prefs)
                            } else if state.active == "integrations" {
                                DevelopmentIntegrations(browser: browser, project: project)
                            } else {
                                DevelopmentTerminalPane(terminals: content.terminals, project: project,
                                                        folder: entries[project.rawValue]?.folder ?? "") {
                                    content.view.callAsyncJavaScript("go('settings')", arguments: [:], in: nil, in: .page, completionHandler: nil)
                                }
                            }
                        }
                        .id(project)
                        .frame(width: state.toolFrame.width, height: state.toolFrame.height)
                        .offset(x: state.toolFrame.minX, y: state.toolFrame.minY)
                    }
                }
                .overlay(alignment: state.mode == "full" ? .bottom : .leading) {
                    if state.reportedProject == project.rawValue {
                        GeometryReader { room in
                            DevelopmentChat(browser: browser, project: project, attach: content.draft(for: project), compact: state.mode == "full")
                                .id(project)
                                .frame(width: state.mode == "split" ? max(0, min(room.size.width, state.chatWidth) - 5) : min(room.size.width, state.mode == "full" ? 680 : room.size.width))
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: state.mode == "split" ? .leading : .bottom)
                        }
                    }
                }
        }
        .toned(SpaceSurface.tone(for: paint.color))
        .background {
            CardGround(paint: paint, step: look.shift ? browser.lookStep : 0)
                .environment(browser)
                .background(Color(nsColor: paint.color))
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
        view.appearance = NSAppearance(named: context.environment.colorScheme == .dark ? .darkAqua : .aqua)
        browser.developmentContent.updateColors()
        browser.developmentContent.updateDirectory()
        browser.developmentContent.select(project)
    }
}
