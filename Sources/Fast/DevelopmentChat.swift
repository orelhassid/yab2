import SwiftUI

struct DevelopmentChatChoice: Identifiable {
    let title: String
    let selection: String?
    let provider: String
    var savedID: String?
    var updated: Date = .distantPast
    var id: String { selection ?? "general-" + provider }

    @MainActor func isSelected(in details: DevelopmentDetails) -> Bool {
        selection == details.chatSelection && provider == details.cli
    }

    @MainActor func open(project: DevelopmentProject, in browser: Browser) {
        let directory = DevelopmentDirectory.shared
        var details = directory.details(project)
        details.chatSelection = selection
        details.provider = provider
        directory.save(details, for: project)
        browser.developmentProject = project
        browser.developmentContent.revealChat(only: selection == DevelopmentDetails.newChat)
    }

    @MainActor static func start(in project: DevelopmentProject, browser: Browser) {
        let provider = DevelopmentDirectory.shared.details(project).cli
        DevelopmentChatChoice(title: "New chat", selection: DevelopmentDetails.newChat, provider: provider)
            .open(project: project, in: browser)
    }

    @MainActor static func archive(_ chat: Chat, project: DevelopmentProject) {
        ChatQuestions.archive(chat) {
            guard Agents.shared.session(chat.id)?.state.live != true else { return }
            Chats.shared.archive(chat.id, true)
            let directory = DevelopmentDirectory.shared
            var details = directory.details(project)
            if details.selectedChatID == chat.id {
                details.chatSelection = DevelopmentDetails.newChat
                directory.save(details, for: project)
            }
        }
    }

}

extension DevelopmentDetails {
    @MainActor func chatChoices(in history: Chats) -> [DevelopmentChatChoice] {
        let sessions = recentSessions(in: history).map {
            DevelopmentChatChoice(title: $0.title, selection: $0.id, provider: $0.cli, savedID: $0.id, updated: $0.updated)
        }
        var coordinators = providerChats ?? [:]
        coordinators["codex"] = chatID
        return (sessions + coordinators.compactMap { provider, id in
            guard let chat = developmentChat(id, in: history), chat.archived != true else { return nil }
            return DevelopmentChatChoice(title: chat.title, selection: nil, provider: provider, savedID: chat.id, updated: chat.updated)
        }).sorted { ($0.updated, $0.id) > ($1.updated, $1.id) }
    }

    @MainActor private func developmentChat(_ id: String, in history: Chats) -> Chat? {
        history.chat(id) ?? Agents.shared.session(id).map { Agents.shared.chat(of: $0) }
    }
}

private struct DevelopmentChatRow: Identifiable {
    let project: DevelopmentProject
    let chat: DevelopmentChatChoice
    var id: String { project.id + "/" + chat.id }
}

struct DevelopmentChatList: View {
    let browser: Browser
    @AppStorage("development.chats.collapsed", store: Store.settings) private var collapsed = false
    @ObservedObject private var history = Chats.shared
    private var directory: DevelopmentDirectory { .shared }

    var body: some View {
        let active = browser.developmentProject
        let details = directory.details(active)
        let chats = directory.projects.flatMap { project in
            directory.details(project).chatChoices(in: history).map { DevelopmentChatRow(project: project, chat: $0) }
        }.sorted { ($0.chat.updated, $0.project.id, $0.chat.id) > ($1.chat.updated, $1.project.id, $1.chat.id) }
        SidebarSectionDivider()
        SidebarSection(collapsed: collapsed) {
            SidebarSectionHeader(title: "Chat", paint: details.paint ?? SpacePaint(browser.prefs),
                                 collapsed: collapsed, toggle: { collapsed.toggle() }) {
                Symbol("bubble.left", size: SideBar.mark)
            }
        } rows: {
            ForEach(chats) { row in
                let owner = directory.details(row.project)
                SidebarTabButton(title: row.chat.title, selected: row.project == active && row.chat.isSelected(in: owner),
                                 prefs: browser.prefs, showsMark: false, trailingLabel: owner.name,
                                 action: { row.chat.open(project: row.project, in: browser) }) { EmptyView() }
                    .steadyMenu(actions: true, tone: SpaceSurface.tone(in: browser)) {
                        if let chat = history.chat(row.chat.savedID) {
                            Button(Command.developmentRenameChat.title, mark: "pencil") { ChatQuestions.rename(chat) }
                            if Agents.shared.session(chat.id)?.state.live != true {
                                Button(Command.developmentArchiveChat.title, mark: "archivebox") {
                                    DevelopmentChatChoice.archive(chat, project: row.project)
                                }
                            }
                        }
                    }
            }
            Quiet(icon: "plus", title: "New chat", prefs: browser.prefs, browser: browser) {
                DevelopmentChatChoice.start(in: active, browser: browser)
            }
        }
        .onAppear { history.load() }
    }
}

struct DevelopmentChatSwitcher: View {
    let browser: Browser
    let project: DevelopmentProject
    let details: DevelopmentDetails
    @ObservedObject private var history = Chats.shared

    var body: some View {
        let saved = details.chatChoices(in: history)
        let general = DevelopmentChatChoice(title: "General", selection: nil, provider: details.cli)
        let start = DevelopmentChatChoice(title: "New chat", selection: DevelopmentDetails.newChat, provider: details.cli)
        let choices = (saved.contains { $0.id == general.id } ? saved : [general] + saved) + [start]
        let title = choices.first { $0.isSelected(in: details) }?.title ?? "Chat"
        TabWindowSwitcher(title: title, prefs: browser.prefs, items: choices, hidesMark: true,
                          label: { $0.title }, selected: { $0.isSelected(in: details) },
                          choose: { $0.open(project: project, in: browser) },
                          rowIcon: { Symbol($0.selection == DevelopmentDetails.newChat ? "plus" : "bubble.left", size: 13) }) { EmptyView() }
            .accessibilityLabel("Switch chat, " + title)
            .onAppear { history.load() }
    }
}

struct DevelopmentChat: View {
    let browser: Browser
    let project: DevelopmentProject
    let attach: ChatAttach
    let compact: Bool
    let chatOnly: Bool
    @StateObject private var feed = ChatFeed()
    @State private var away = false
    private var details: DevelopmentDetails { DevelopmentDirectory.shared.details(project) }

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                if let chat = feed.chat {
                    ChatTranscript(browser: browser, chat: chat, live: feed.live, away: $away)
                } else if chatOnly && details.chatSelection == DevelopmentDetails.newChat {
                    newChatLanding
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
        .onAppear { Chats.shared.load() }
        .onDisappear { feed.stop() }
    }

    private var newChatLanding: some View {
        let directory = DevelopmentDirectory.shared
        return VStack(spacing: 16) {
            Text("Start a chat in " + details.name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { recentProjectButtons(directory) }.fixedSize()
                VStack(spacing: 4) { recentProjectButtons(directory) }
            }
        }
        .padding(.horizontal, ChatLook.fieldInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func recentProjectButtons(_ directory: DevelopmentDirectory) -> some View {
        ForEach(directory.recentProjects) { recent in
            let name = directory.details(recent).name
            Button {
                DevelopmentChatChoice.start(in: recent, browser: browser)
            } label: {
                Label(name, systemImage: "folder").lineLimit(1)
            }
            .buttonStyle(.yab(recent == project ? .secondary : .quiet, .small))
            .accessibilityLabel("New chat in " + name)
            .accessibilityAddTraits(recent == project ? .isSelected : [])
        }
    }

}

extension DevelopmentDetails {
    @MainActor func resumeProblem(in history: Chats) -> String? {
        guard let id = selectedChatID, Agents.shared.session(id) == nil, history.chat(id) == nil else { return nil }
        return history.loaded ? "This chat is unavailable. Choose another chat or start a new one." : "This chat is still loading. Try again in a moment."
    }

    @MainActor func recentSessions(in history: Chats) -> [Chat] {
        (sessionIDs ?? []).compactMap { id in
            developmentChat(id, in: history)
        }.filter { $0.archived != true }.sorted { $0.updated > $1.updated }
    }

    static func suggestedChat(for draft: String, among sessions: [Chat]) -> Chat? {
        let ignored: Set<String> = ["that", "this", "with", "from", "have", "what", "please", "would", "could", "should",
                                    "need", "want", "make", "about", "again", "chat", "some", "them", "there", "into", "your"]
        func tokens(_ text: String) -> Set<String> {
            Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }
                .filter { $0.count >= 4 }.map(String.init)).subtracting(ignored)
        }
        let query = tokens(draft)
        guard !query.isEmpty else { return nil }
        var best: Chat?
        var bestScore = 0
        for chat in sessions {
            let title = query.intersection(tokens(chat.title)).count
            let recent = chat.items.lazy.filter { $0.kind == .asked }.suffix(4)
            let body = query.intersection(tokens(recent.map(\.text).joined(separator: " "))).count
            let score = title * 3 + body
            if score >= 2, score > bestScore {
                best = chat
                bestScore = score
            }
        }
        return best
    }
}

extension DevelopmentDirectory {
    func send(_ text: String, items: [ChatAttachment], mentions: [DevelopmentMention], spans: [ChatMentionSpan],
              project: DevelopmentProject,
              browser: Browser, later: Bool) -> Bool {
        var details = details(project)
        if details.sourceFolderUnavailable {
            browser.toaster.pop(DevelopmentDetails.unavailableSourceMessage, mark: "folder")
            return false
        }
        let history = Chats.shared
        history.load()
        if let problem = details.resumeProblem(in: history) {
            browser.toaster.pop(problem, mark: "bubble.left")
            return false
        }
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
        let isNewSession = details.chatSelection == DevelopmentDetails.newChat
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
            if details.chatSelection == nil { session.title = details.name }
            else if isNewSession {
                session.title = text.isEmpty ? (labels.first ?? "New chat") : String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(72))
            }
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
        if next.cli != plan.cli, next.chatSelection != nil {
            next.chatSelection = DevelopmentDetails.newChat
        }
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
