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
                    Text("Chat with " + AgentSetupModel.tool(details.cli)).foregroundStyle(.secondary)
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
        .environment(\.openUIProject, project)
        .onChange(of: details.selectedChatID, initial: true) { _, id in feed.follow(id) }
        .onDisappear { feed.stop() }
    }
}

extension DevelopmentDirectory {
    func send(_ text: String, items: [ChatAttachment], mentions: [DevelopmentMention], spans: [ChatMentionSpan],
              project: DevelopmentProject,
              browser: Browser, later: Bool) -> Bool {
        var details = details(project)
        let references = mentions.compactMap(\.reference).reduce(into: [DevelopmentReference]()) { list, reference in
            if !list.contains(reference) { list.append(reference) }
        }
        let context = mentions.compactMap(\.attachment).reduce(into: items) { list, item in
            if !list.contains(item) { list.append(item) }
        }
        guard ProviderConsent.shared.allows(details.cli) else { browser.openSettings(.agents); return false }
        guard details.cli == "codex" || references.isEmpty else {
            browser.toaster.pop("Remove Codex mentions or select Codex", mark: "at")
            return false
        }
        guard references.allSatisfy(DevelopmentPlugins.shared.allows) else {
            browser.toaster.pop("Remove the disabled plugin or enable it in Development Settings", mark: "puzzlepiece.extension")
            return false
        }
        if !references.isEmpty, details.availableSourceFolder == nil {
            browser.toaster.pop("Choose a source folder in Project settings to use skills or plugins", mark: "folder")
            return false
        }
        let tabs = ChatAttachment.tabs(context, in: browser)
        let files = context.compactMap(\.file)
        let labels = ChatAttachment.labels(tabs: ChatAttachment.tabs(items, in: browser), files: items.compactMap(\.file))
        let prompt = ChatAttachment.said(tabs: tabs, files: files, quotes: items.compactMap(\.quote), in: browser)
            + references.map { "\($0.kind.rawValue): \($0.name) (\($0.path))\n" }.joined()
            + (text.isEmpty ? ChatAttachment.noWords : text)
        let agents = Agents.shared
        let session: Agents.Session
        let running = agents.session(details.selectedChatID)
        let continuing = running?.state.live == true
        if let running, continuing {
            session = running
        } else {
            session = agents.run(prompt: prompt, cli: details.cli, model: details.choice.model, effort: details.choice.effort, access: "browser", resume: details.selectedChatID, strict: true, development: details)
            guard agents.session(session.id) != nil else {
                browser.toaster.pop(session.result, mark: "exclamationmark.circle")
                return false
            }
            details.selectedChatID = session.id
            save(details, for: project)
            session.title = details.name
        }
        for tab in tabs { tab.allowed.insert(session.id) }
        session.saying.append(text)
        session.keepMentions(spans)
        session.carrying.append(labels)
        session.attaching.append(context)
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

/// Per-environment overrides for plugins enabled in the connected Codex installation.
@MainActor @Observable
final class DevelopmentPlugins {
    static let shared = DevelopmentPlugins()
    private static let key = "development.disabledPlugins"
    private(set) var disabled = Set(Store.settings.stringArray(forKey: key) ?? [])

    func allows(_ ref: DevelopmentReference) -> Bool {
        ref.kind != .plugin || !disabled.contains(ref.path)
    }

    func set(_ ref: DevelopmentReference, enabled: Bool) {
        if enabled { disabled.remove(ref.path) } else { disabled.insert(ref.path) }
        Store.settings.set(disabled.sorted(), forKey: Self.key)
    }

    var launchArguments: [String] {
        disabled.sorted().compactMap { path -> String? in
            guard path.hasPrefix("plugin://") else { return nil }
            let id = String(path.dropFirst("plugin://".count))
            guard let quoted = try? JSONEncoder().encode(id) else { return nil }
            return "plugins." + String(decoding: quoted, as: UTF8.self) + ".enabled=false"
        }.flatMap { ["-c", $0] }
    }
}

struct DevelopmentMention: Identifiable {
    let name: String
    let detail: String
    let symbol: String
    var attachment: ChatAttachment?
    var reference: DevelopmentReference?
    var id: String { attachment?.id ?? reference?.id ?? name }

    var badge: (title: String, tint: FolderTint) {
        if let reference {
            return (reference.kind.rawValue, reference.kind == .skill ? .purple : .teal)
        }
        if attachment?.file != nil { return ("File", .orange) }
        return ("Open tab", .blue)
    }

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

/// The composer and Integrations both read the provider registry used by Settings.
struct DevelopmentProviders: View {
    let project: DevelopmentProject
    let browser: Browser
    let query: String
    @State private var browsing: String?
    @ObservedObject private var accounts = PlanAccounts.shared
    @ObservedObject private var agents = Agents.shared
    let addProvider: () -> Void
    private var details: DevelopmentDetails { DevelopmentDirectory.shared.details(project) }
    private var active: [AgentPlan] { AgentPlan.all.filter { ProviderConsent.shared.allows($0.cli) } }
    private var currentPlan: AgentPlan? {
        active.first { $0.cli == (browsing ?? details.cli) } ?? active.first
    }
    private var busy: Bool { agents.session(details.selectedChatID)?.state.live == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(active, id: \.cli) { provider in
                            SidebarTabButton(title: provider.cli == "codex" ? provider.tool : provider.name,
                                             selected: provider.cli == currentPlan?.cli, prefs: browser.prefs, inTabStrip: true,
                                             action: { browsing = provider.cli }) { Symbol(provider.mark, size: 13) }
                        }
                    }
                }
                Button(action: addProvider) { Symbol("plus", size: 13) }
                    .buttonStyle(.yab(.quiet, .small, icon: .round)).accessibilityLabel("Add AI provider")
            }
            if let plan = currentPlan {
                let selectedModel = AgentModels.find(plan.cli, details.choice.model)
                let efforts = selectedModel?.efforts ?? (details.choice.model == nil ? plan.models.first?.efforts : nil) ?? []
                if details.cli == plan.cli, !efforts.isEmpty {
                    let steps = [""] + efforts
                    HStack {
                        Text("Thinking")
                        Spacer()
                        Text(details.choice.effort.map(AgentModels.effortTitle) ?? "Default").foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(get: { Double(steps.firstIndex(of: details.choice.effort ?? "") ?? 0) },
                                          set: { value in
                        let level = steps[Int(value.rounded())]
                        set(selectedModel, effort: level.isEmpty ? nil : level, plan: plan)
                    }), in: 0...Double(steps.count - 1), step: 1)
                    .disabled(busy).accessibilityLabel("Thinking effort")
                    .accessibilityValue(details.choice.effort.map(AgentModels.effortTitle) ?? "Default")
                    LibrarySeparator()
                }
                ScrollView {
                    VStack(spacing: 2) {
                        if query.isEmpty || "Default".localizedCaseInsensitiveContains(query) { modelRow(nil, plan: plan) }
                        ForEach(plan.models.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }) { model in
                            modelRow(model, plan: plan)
                        }
                    }
                }
            } else {
                Text("No connected providers").foregroundStyle(.secondary)
            }
        }
        .task(id: currentPlan?.cli) {
            guard let plan = currentPlan else { return }
            let found = await Shell.find()
            await accounts.ask([plan.cli], found: found, refreshBlocked: true)
        }
    }

    private func modelRow(_ model: AgentModel?, plan: AgentPlan) -> some View {
        let selected = details.cli == plan.cli && details.choice.model == model?.model
        return SidebarTabButton(title: model?.name ?? "Default", selected: selected, prefs: browser.prefs,
                                action: { set(model, effort: selected ? details.choice.effort : nil, plan: plan) }) {
            Symbol(selected ? "checkmark" : plan.mark, size: 13)
        }
        .disabled(busy)
    }

    private func set(_ model: AgentModel?, effort: String?, plan: AgentPlan) {
        guard ProviderConsent.shared.allows(plan.cli), !busy else { return }
        var next = details
        next.provider = plan.cli
        var choices = next.modelChoices ?? [:]
        choices[plan.cli] = ModelChoice(cli: plan.cli, model: model?.model, effort: effort)
        next.modelChoices = choices
        DevelopmentDirectory.shared.save(next, for: project)
    }
}

struct DevelopmentComposerControls: View {
    let project: DevelopmentProject
    let browser: Browser
    let live: Bool
    @State private var showingModels = false
    @State private var search = ""
    private var details: DevelopmentDetails { DevelopmentDirectory.shared.details(project) }

    var body: some View {
        Button { search = ""; showingModels.toggle() } label: {
            let name = details.choice.model.map { AgentModels.name(details.cli, $0) }
                ?? (details.cli == "codex" ? "Codex" : AgentSetupModel.name(details.cli))
            Text([name, details.choice.effort.map(AgentModels.effortTitle)].compactMap { $0 }.joined(separator: " · "))
                .lineLimit(1)
        }.buttonStyle(.yab(.quiet, .small))
        .accessibilityLabel("Choose provider and model")
        .popover(isPresented: $showingModels, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                ThemedSearchField("Search models", text: $search)
                DevelopmentProviders(project: project, browser: browser, query: search) {
                    showingModels = false
                    browser.openSettings(.agents)
                }
                if details.cli == "codex" {
                    LibrarySeparator()
                    Toggle("Allow project edits", isOn: Binding(get: { details.canWriteProject }, set: setWrite))
                        .disabled(live)
                }
            }.padding(12).frame(width: 420, height: 360)
        }
    }

    private func setWrite(_ enabled: Bool) {
        guard Agents.shared.session(details.selectedChatID)?.state.live != true else { return }
        var next = details
        next.workspaceWrite = enabled
        DevelopmentDirectory.shared.save(next, for: project)
    }
}
