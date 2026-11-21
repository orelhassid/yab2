import SwiftUI

struct DevelopmentChat: View {
    let browser: Browser
    let project: DevelopmentProject
    let attach: ChatAttach
    let compact: Bool
    @StateObject private var feed = ChatFeed()
    @State private var away = false
    private var details: DevelopmentDetails { DevelopmentDirectory.shared.details(project) }

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                if let chat = feed.chat {
                    ChatTranscript(browser: browser, chat: chat, live: feed.live, away: $away)
                } else {
                    Spacer()
                    Text("Chat with Codex").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            if let permit = feed.permit, let chat = feed.chat {
                ChatPermitCard(permit: permit, chat: chat.id, browser: browser)
            } else {
                let asking = feed.chat.flatMap { ChatColumn.asking($0, browser: browser) }
                if let asking { ChatAsk(tab: asking) }
                ChatComposer(browser: browser, chat: feed.chat, live: feed.live, asking: asking, attach: attach, development: project)
            }
        }
        .environment(\.projectChatStyle, true)
        .onChange(of: details.chatID, initial: true) { _, id in feed.follow(id) }
        .onDisappear { feed.stop() }
    }
}

extension DevelopmentDirectory {
    func send(_ text: String, items: [ChatAttachment], references: [DevelopmentReference], project: DevelopmentProject,
              browser: Browser, later: Bool) -> Bool {
        guard ProviderConsent.shared.allows("codex") else { TaskLine.connect(); return false }
        var details = details(project)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: details.folder, isDirectory: &isDirectory), isDirectory.boolValue else {
            browser.developmentContent.view.callAsyncJavaScript("go('settings')", arguments: [:], in: nil, in: .page, completionHandler: nil)
            browser.toaster.pop("Choose a source folder for Codex", mark: "folder")
            return false
        }
        let tabs = ChatAttachment.tabs(items, in: browser)
        let files = items.compactMap(\.file)
        let labels = ChatAttachment.labels(tabs: tabs, files: files) + references.map(\.name)
        let prompt = ChatAttachment.said(tabs: tabs, files: files, quotes: items.compactMap(\.quote), in: browser)
            + references.map { "\($0.kind.rawValue): \($0.name) (\($0.path))\n" }.joined()
            + (text.isEmpty ? ChatAttachment.noWords : text)
        let agents = Agents.shared
        let session: Agents.Session
        let running = agents.session(details.chatID)
        let continuing = running?.state.live == true
        if let running, continuing {
            session = running
        } else {
            session = agents.run(prompt: prompt, cli: "codex", access: "browser", folder: details.folder, resume: details.chatID, strict: true)
            guard agents.session(session.id) != nil else {
                browser.toaster.pop(session.result, mark: "exclamationmark.circle")
                return false
            }
            session.developmentFolder = details.folder
            details.chatID = session.id
            save(details, for: project)
            session.title = details.name
        }
        for tab in tabs { tab.allowed.insert(session.id) }
        session.saying.append(text)
        session.carrying.append(labels)
        session.attaching.append(items)
        if !references.isEmpty { session.developmentInputs[prompt] = references.map(\.input) }
        if !continuing { return true }
        if later { agents.queue(session.id, prompt) } else { _ = agents.steer(session.id, prompt) }
        return true
    }
}

struct DevelopmentReference: Identifiable, Hashable {
    enum Kind: String { case plugin = "Plugin", skill = "Skill" }
    let kind: Kind
    let name: String
    let path: String
    var id: String { path }
    var input: [String: Any] { ["type": kind == .plugin ? "mention" : "skill", "name": name, "path": path] }
}

@MainActor
final class DevelopmentCatalog: ObservableObject {
    @Published private(set) var references: [DevelopmentReference] = []
    @Published private(set) var status = ""
    private var loading = false

    func load(folder: String) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        references = Skills.all().map { DevelopmentReference(kind: .skill, name: $0.name, path: $0.path.path) }
        guard let permit = ProviderConsent.shared.permit("codex") else { status = "Connect Codex in AI settings to see plugins."; return }
        let found = await Shell.find()
        guard let launch = AgentLaunch.resolve("codex", in: found) else { status = "Codex is unavailable."; return }
        let manager = FileManager.default
        let home = manager.homeDirectoryForCurrentUser
        let codex = launch.env["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        var roots = [home.appendingPathComponent(".agents/skills"), codex.appendingPathComponent("skills")]
        if !folder.isEmpty { roots.append(URL(fileURLWithPath: folder).appendingPathComponent(".agents/skills")) }
        let installedSkills = await Task.detached(priority: .utility) { Self.skills(in: roots) }.value
        var seen = Set(references.map(\.path))
        references += installedSkills.filter { seen.insert($0.path).inserted }
        status = "Loading plugins…"
        let (code, output) = await Shell.run(launch.binary, ["plugin", "list", "--json"], env: launch.env, permit: permit)
        struct Catalog: Decodable {
            struct Plugin: Decodable { let name: String; let pluginId: String; let enabled: Bool }
            let installed: [Plugin]
        }
        guard code == 0, let result = try? JSONDecoder().decode(Catalog.self, from: Data(output.utf8)) else {
            status = "Could not load installed Codex plugins."
            return
        }
        guard permit.valid else { status = "Connect Codex in AI settings to see plugins."; return }
        references += result.installed.filter(\.enabled).map { DevelopmentReference(kind: .plugin, name: $0.name, path: "plugin://" + $0.pluginId) }
        status = ""
    }
    nonisolated static func skills(in roots: [URL]) -> [DevelopmentReference] {
        var found: [DevelopmentReference] = []
        for root in roots {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for folder in folders {
                let file = folder.appendingPathComponent("SKILL.md")
                if FileManager.default.isReadableFile(atPath: file.path) {
                    found.append(DevelopmentReference(kind: .skill, name: folder.lastPathComponent, path: file.path))
                }
            }
        }
        return found.sorted { $0.name < $1.name }
    }

}

struct DevelopmentIntegrations: View {
    let browser: Browser
    let project: DevelopmentProject
    @State private var section = "Providers"
    @StateObject private var catalog = DevelopmentCatalog()
    @State private var query = ""
    var body: some View {
        LibraryPageFrame(page: .settings, breadcrumbs: ["Integrations"]) {
            EmptyView()
        } search: { ThemedSearchField("Search integrations", text: $query) } content: {
            VStack(alignment: .leading, spacing: CardFrame.inset) {
                HStack {
                    ForEach(["Providers", "Plugins", "Skills"], id: \.self) { name in
                        SidebarTabButton(title: name, selected: section == name, prefs: browser.prefs, inTabStrip: true, action: { section = name; query = "" }) { EmptyView() }
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: CardFrame.inset) {
                        if section == "Providers" {
                            if query.isEmpty || "Codex".localizedCaseInsensitiveContains(query) {
                                SettingsRow("Codex", detail: ProviderConsent.shared.allows("codex") ? "Connected to Yab" : "Disconnected") {
                                    Button("AI settings") { browser.openSettings(.agents) }.buttonStyle(.yab(.secondary, .small))
                                }
                            }
                        } else {
                            if section == "Plugins", !catalog.status.isEmpty { Text(catalog.status).foregroundStyle(.secondary) }
                            ForEach(catalog.references.filter { ($0.kind == (section == "Plugins" ? .plugin : .skill)) && (query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)) }) { ref in
                                SettingsRow(ref.name, detail: ref.kind.rawValue) { EmptyView() }
                                LibrarySeparator()
                            }
                        }
                    }.padding(CardFrame.inset).modifier(LibraryCardSurface())
                }
            }
        }.task { await catalog.load(folder: DevelopmentDirectory.shared.details(project).folder) }
    }
}

struct DevelopmentMention: Identifiable {
    let name: String
    let detail: String
    let symbol: String
    var attachment: ChatAttachment?
    var reference: DevelopmentReference?
    var id: String { attachment?.id ?? reference?.id ?? name }

    static func files(in folder: String) -> [URL] {
        guard !folder.isEmpty else { return [] }
        let root = URL(fileURLWithPath: folder, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        let ignored = ["node_modules", "build", "target", "dist", "DerivedData", "vendor"]
        for case let url as URL in walker {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isSymbolicLink == true || (values.isDirectory == true && ignored.contains(url.lastPathComponent)) { walker.skipDescendants(); continue }
            if values.isRegularFile == true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
