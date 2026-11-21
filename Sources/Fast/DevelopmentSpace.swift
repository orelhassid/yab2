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
                TrailMenuRow(title: project.title, selected: browser.developmentProject == project, action: {
                    browser.developmentProject = project
                }) { Symbol("folder", size: SideBar.mark) }
            }
        }
    }
}

/// One private content view per window. The native Space owns selection and
/// the view stays alive across Space switches without entering the tab store.
@MainActor
final class DevelopmentContent: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var browser: Browser?
    private(set) var ready = false
    private var selected: DevelopmentProject?
    lazy var view: WKWebView = {
        let configuration = WKWebViewConfiguration()
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

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        selected = nil
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

struct DevelopmentPane: NSViewRepresentable {
    let browser: Browser
    let project: DevelopmentProject
    func makeNSView(context: Context) -> WKWebView {
        browser.developmentContent.browser = browser
        return browser.developmentContent.view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        browser.developmentContent.select(project)
    }
}
