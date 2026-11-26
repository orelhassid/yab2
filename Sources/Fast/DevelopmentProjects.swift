import SwiftUI

enum DevelopmentProjectOrder: String, CaseIterable, Identifiable {
    static let key = "development.projectOrder"

    case recent = "Recent Activity"
    case name = "Name"
    case created = "Date Created"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .recent: "clock"
        case .name: "textformat"
        case .created: "calendar"
        }
    }
}

extension DevelopmentDirectory {
    func sortedProjects(_ order: DevelopmentProjectOrder, history: Chats, includeHidden: Bool = false) -> [DevelopmentProject] {
        let rows = projects.compactMap { project -> (DevelopmentProject, DevelopmentDetails, Date?)? in
            let details = details(project)
            guard includeHidden || details.hiddenFromSidebar != true else { return nil }
            return (project, details, latestActivity(project, history: history))
        }
        return rows.sorted { left, right in
            let (_, first, firstActivity) = left
            let (_, second, secondActivity) = right
            if (first.pinned == true) != (second.pinned == true) { return first.pinned == true }
            switch order {
            case .recent:
                if firstActivity != secondActivity { return (firstActivity ?? .distantPast) > (secondActivity ?? .distantPast) }
            case .created:
                if first.createdAt != second.createdAt { return (first.createdAt ?? 0) > (second.createdAt ?? 0) }
            case .name: break
            }
            let comparison = first.name.localizedStandardCompare(second.name)
            return comparison == .orderedSame ? left.0.id < right.0.id : comparison == .orderedAscending
        }.map { $0.0 }
    }

    func latestActivity(_ project: DevelopmentProject, history: Chats) -> Date? {
        let project = details(project)
        let chat = project.chatChoices(in: history).first?.updated
        let storedTimes = [project.activity?.last?.time, project.modifiedAt, project.createdAt].compactMap { $0 }.max()
        return [chat, storedTimes.map(Date.init(timeIntervalSince1970:))].compactMap { $0 }.max()
    }

    func setPinned(_ value: Bool, project: DevelopmentProject) {
        var projectDetails = details(project)
        projectDetails.pinned = value
        save(projectDetails, for: project)
    }

    func select(_ project: DevelopmentProject, in browser: Browser) {
        browser.developmentContent.toolbar.projectsSelected = false
        browser.developmentContent.toolbar.environmentSelected = false
        browser.developmentProject = project
    }

    func confirmHide(_ project: DevelopmentProject, in browser: Browser) {
        let question = Question(title: "Remove project from the sidebar?",
                                detail: "You can restore it from Projects. Its source folder and chats stay available.",
                                glyph: "sidebar.left", yes: "Remove")
        Task { @MainActor in
            guard await Questions.shared.ask(question) else { return }
            setHidden(true, project: project)
            if browser.developmentProject == project { browser.developmentContent.toolbar.showProjects() }
        }
    }

    func setHidden(_ value: Bool, project: DevelopmentProject) {
        var projectDetails = details(project)
        projectDetails.hiddenFromSidebar = value
        save(projectDetails, for: project)
    }
}

private struct DevelopmentProjectOrderPicker: View {
    @Binding var order: DevelopmentProjectOrder
    @State private var open = false
    @Environment(\.tone) private var tone
    var compact = false

    var body: some View {
        Button { open.toggle() } label: {
            if compact { Symbol("arrow.up.arrow.down", size: 12) }
            else { Label(order.rawValue, systemImage: order.symbol) }
        }
        .buttonStyle(.yab(.quiet, .small))
        .accessibilityLabel("Sort Projects")
        .accessibilityValue(order.rawValue)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(spacing: 2) {
                ForEach(DevelopmentProjectOrder.allCases) { item in
                    TrailMenuRow(title: item.rawValue, selected: item == order, action: {
                        order = item
                        open = false
                    }) { Symbol(item.symbol, size: 13) }
                }
            }
            .padding(6).frame(width: 168).toned(tone)
        }
    }
}

struct DevelopmentProjects: View {
    let browser: Browser
    @AppStorage(DevelopmentProjectOrder.key, store: Store.settings) private var order = DevelopmentProjectOrder.recent
    @ObservedObject private var history = Chats.shared

    var body: some View {
        let directory = DevelopmentDirectory.shared
        let state = browser.developmentContent.toolbar
        VStack(alignment: .leading, spacing: SideBar.gap) {
            SpaceName(space: .development, browser: browser)
            SidebarSectionDivider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: SideBar.gap) {
                    HStack(spacing: 0) {
                        SidebarTabButton(title: "Projects", selected: state.projectsSelected, prefs: browser.prefs,
                                         action: state.showProjects) { Symbol("folder", size: SideBar.mark) }
                        DevelopmentProjectOrderPicker(order: $order, compact: true)
                    }
                    ForEach(directory.sortedProjects(order, history: history)) { project in
                        let details = directory.details(project)
                        SidebarTabButton(title: details.name,
                                         selected: !state.projectsSelected && browser.developmentProject == project,
                                         prefs: browser.prefs, action: { directory.select(project, in: browser) }) {
                            DevelopmentProjectMark(details: details)
                        }
                        .steadyMenu(actions: true, tone: SpaceSurface.tone(in: browser)) {
                            DevelopmentProjectMenu(project: project, browser: browser)
                        }
                    }
                    DevelopmentChatList(browser: browser)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { history.load() }
    }
}

private struct DevelopmentProjectMark: View {
    let details: DevelopmentDetails

    var body: some View {
        if details.icon.isEmpty { Symbol("folder", size: SideBar.mark) }
        else { Text(details.icon) }
    }
}

struct DevelopmentProjectIndex: View {
    let browser: Browser
    @State private var search = ""
    @State private var expanded: Set<DevelopmentProject> = []
    @AppStorage(DevelopmentProjectOrder.key, store: Store.settings) private var order = DevelopmentProjectOrder.recent
    @ObservedObject private var history = Chats.shared
    @Environment(\.tone) private var tone

    var body: some View {
        let directory = DevelopmentDirectory.shared
        let state = browser.developmentContent.toolbar
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = directory.sortedProjects(order, history: history, includeHidden: true).filter { project in
            let details = directory.details(project)
            return query.isEmpty || details.name.localizedCaseInsensitiveContains(query) || details.folder.localizedCaseInsensitiveContains(query)
        }
        VStack(spacing: 0) {
            HStack {
                Button { state.projectsSelected = false } label: { Symbol("chevron.left", size: 13) }
                    .buttonStyle(.yab(.quiet, .small, icon: .square))
                    .accessibilityLabel("Back to Workspace")
                Label("Projects", systemImage: "folder")
                Spacer()
                if browser.prefs.sideShut && browser.trailFlank == nil {
                    ColumnDoor(browser: browser, prefs: browser.prefs).environment(\.doorSize, .header)
                }
            }
            .padding(.horizontal, SideBar.margin)
            .frame(height: NavigationHeader.height(topInset: 0))
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    toolbar(state)
                    if projects.isEmpty { Text("No projects found").foregroundStyle(Palette.muted(on: tone)) }
                    ForEach(projects) { project in
                        DevelopmentProjectIndexRow(project: project, browser: browser, history: history,
                                                   expanded: expanded.contains(project)) {
                            if !expanded.insert(project).inserted { expanded.remove(project) }
                        }
                        LibrarySeparator()
                    }
                }
                .frame(maxWidth: 1040)
                .padding(24).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(Palette.strong(on: tone))
        .onAppear { history.load() }
    }

    private func toolbar(_ state: DevelopmentToolbarState) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { title; Spacer(minLength: 8); controls(state) }
            VStack(alignment: .leading, spacing: 8) { title; controls(state) }
        }
    }

    private var title: some View {
        Text("Projects").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
    }

    private func controls(_ state: DevelopmentToolbarState) -> some View {
        HStack(spacing: 8) {
            ThemedSearchField("Search projects", text: $search).frame(idealWidth: 200, maxWidth: 230)
            DevelopmentProjectOrderPicker(order: $order)
            Button { state.projectEditor = .create } label: { Label("New", systemImage: "plus") }
                .buttonStyle(.yab(.primary, .small))
                .accessibilityLabel("New Project")
        }
    }
}

private struct DevelopmentProjectIndexRow: View {
    let project: DevelopmentProject
    let browser: Browser
    let history: Chats
    let expanded: Bool
    let toggle: () -> Void
    @State private var showMenu = false
    @Environment(\.tone) private var tone

    var body: some View {
        let directory = DevelopmentDirectory.shared
        let details = directory.details(project)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(action: toggle) {
                    HStack(spacing: 8) {
                        Symbol(expanded ? "chevron.down" : "chevron.right", size: 10)
                        DevelopmentProjectMark(details: details)
                        Text(details.name).lineLimit(1)
                    }
                }
                .buttonStyle(.yab(.quiet, .small))
                .accessibilityLabel((expanded ? "Collapse " : "Expand ") + details.name)
                Spacer(minLength: 4)
                if let activity = directory.latestActivity(project, history: history) {
                    Text(activity, format: .relative(presentation: .named))
                        .font(CardFrame.detail).foregroundStyle(Palette.muted(on: tone)).lineLimit(1)
                }
                let pinned = details.pinned == true
                RailButton((pinned ? "Unpin " : "Pin ") + details.name, icon: pinned ? "pin.fill" : "pin", selected: pinned) {
                    directory.setPinned(!pinned, project: project)
                }
                RailButton("Edit " + details.name, icon: "pencil") { edit() }
                RailMoreButton(title: "Actions for " + details.name, selected: showMenu) { showMenu.toggle() }
                    .popover(isPresented: $showMenu, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 4) {
                            DevelopmentProjectMenu(project: project, browser: browser) { showMenu = false }
                        }
                        .buttonStyle(.yab(.quiet, .small))
                        .padding(8).toned(tone)
                    }
            }
            HStack(spacing: 8) {
                if let path = details.availableSourceFolder {
                    Text((path as NSString).abbreviatingWithTildeInPath).lineLimit(1).truncationMode(.middle).help(path)
                } else {
                    Text(details.folder.isEmpty ? "No folder linked" : "Source folder unavailable")
                    Button("Link Folder…", action: edit).buttonStyle(.yab(.quiet, .small))
                }
                if details.hiddenFromSidebar == true { Text("Hidden from Sidebar") }
            }
            .font(CardFrame.detail)
            .foregroundStyle(Palette.muted(on: tone))
            .padding(.leading, 24)
            if expanded { chats(details) }
        }
        .padding(8)
        .background(expanded ? Palette.hover(on: tone) : .clear, in: RoundedRectangle(cornerRadius: Radius.card))
        .steadyMenu(actions: true, tone: tone) { DevelopmentProjectMenu(project: project, browser: browser) }
    }

    private func edit() { browser.developmentContent.toolbar.projectEditor = .edit(project) }

    private func chats(_ details: DevelopmentDetails) -> some View {
        let chats = details.chatChoices(in: history)
        return VStack(alignment: .leading, spacing: 4) {
            if chats.isEmpty { Text("No chats yet").foregroundStyle(Palette.muted(on: tone)).font(CardFrame.detail) }
            ForEach(chats) { choice in
                SidebarTabButton(title: choice.title, selected: false, prefs: browser.prefs, showsMark: false,
                                 action: { choice.open(project: project, in: browser) }) { EmptyView() }
                    .steadyMenu(actions: true, tone: tone) {
                        if let chat = history.chat(choice.savedID) {
                            DevelopmentChatMenu(chat: chat, project: project, browser: browser)
                        }
                    }
            }
        }.padding(.leading, 24)
    }
}

enum DevelopmentProjectEditorTarget: Identifiable {
    case create
    case edit(DevelopmentProject)

    var id: String { project?.id ?? "new" }
    var project: DevelopmentProject? {
        if case .edit(let project) = self { return project }
        return nil
    }
}

struct DevelopmentProjectEditor: View {
    let target: DevelopmentProjectEditorTarget
    @State private var name: String
    @State private var icon: String
    @State private var folder: String
    @Environment(\.dismiss) private var dismiss

    init(target: DevelopmentProjectEditorTarget) {
        self.target = target
        let details = target.project.map { DevelopmentDirectory.shared.details($0) }
        _name = State(initialValue: details?.name ?? "")
        _icon = State(initialValue: details?.icon ?? "")
        _folder = State(initialValue: details?.folder ?? "")
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var folderAvailable: Bool {
        var isDirectory: ObjCBool = false
        return !folder.isEmpty && FileManager.default.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(target.project == nil ? "New Project" : "Edit Project").font(.title2.weight(.semibold))
            YabFormField("Project name", text: $name)
            YabFormField("Project icon", text: $icon)
            Text("Source folder").font(.headline)
            HStack {
                Text(folder.isEmpty ? "No folder selected" : (folder as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose Folder…", action: choose).buttonStyle(.yab(.secondary, .small))
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(.yab(.quiet, .small)).keyboardShortcut(.cancelAction)
                Button(target.project == nil ? "Create Project" : "Save Changes", action: save)
                    .buttonStyle(.yab(.primary, .small)).keyboardShortcut(.defaultAction)
                    .disabled(cleanName.isEmpty || (target.project == nil && !folderAvailable))
            }
        }
        .padding(24).frame(width: 460)
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.title = "Choose a source folder"
        panel.prompt = "Choose Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if folderAvailable { panel.directoryURL = URL(fileURLWithPath: folder, isDirectory: true) }
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            folder = url.path
            if cleanName.isEmpty { name = url.lastPathComponent }
        }
    }

    private func save() {
        guard !cleanName.isEmpty else { return }
        let directory = DevelopmentDirectory.shared
        let name = String(cleanName.prefix(80))
        let icon = String(icon.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8))
        if let project = target.project {
            var details = directory.details(project)
            details.name = name
            details.icon = icon
            details.folder = folder
            details.modifiedAt = Date().timeIntervalSince1970
            directory.save(details, for: project)
        } else {
            guard folderAvailable else { return }
            _ = directory.create(folder: URL(fileURLWithPath: folder, isDirectory: true), name: name, icon: icon)
        }
        dismiss()
    }
}
