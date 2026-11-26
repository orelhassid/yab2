import SwiftUI

struct DevelopmentHome: View {
    let project: DevelopmentProject
    let prefs: Preferences
    let roadmapProgress: String
    let open: (String) -> Void
    @Environment(\.tone) private var tone
    @State private var name: String
    @State private var icon: String
    private var directory: DevelopmentDirectory { .shared }
    private var details: DevelopmentDetails { directory.details(project) }

    init(project: DevelopmentProject, prefs: Preferences, roadmapProgress: String, open: @escaping (String) -> Void) {
        self.project = project
        self.prefs = prefs
        self.roadmapProgress = roadmapProgress
        self.open = open
        let details = DevelopmentDirectory.shared.details(project)
        _name = State(initialValue: details.name)
        _icon = State(initialValue: details.icon)
    }

    var body: some View {
        GeometryReader { room in
            let columns = room.size.width >= 620 ? 4 : (room.size.width >= 320 ? 2 : 1)
            ScrollView {
                VStack(spacing: 0) {
                    cover(width: room.size.width)
                    content(columns: columns)
                }
            }
        }
        .foregroundStyle(Palette.strong(on: tone))
        .onChange(of: details.name) { old, new in
            if name == old { name = new }
        }
    }

    @ViewBuilder private func cover(width: CGFloat) -> some View {
        if let url = Bundle.main.url(forResource: "eclipse", withExtension: "webp", subdirectory: "Development"),
           let cover = NSImage(contentsOf: url) {
            Image(nsImage: cover).resizable().scaledToFill()
                .frame(width: width, height: 152).clipped()
                .accessibilityHidden(true)
        }
    }

    private func content(columns: Int) -> some View {
        VStack(alignment: .leading, spacing: LibraryPageLayout.sectionGap) {
            HStack(spacing: 10) {
                Group {
                    if details.icon.isEmpty { Symbol("house", size: 18) }
                    else { Text(details.icon).font(.system(size: 17)) }
                }
                .frame(width: 36, height: 36)
                .background(Palette.wash(on: tone), in: RoundedRectangle(cornerRadius: Radius.card))
                Text(details.name).font(.title2.weight(.semibold))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(details.name)
            .accessibilityAddTraits(.isHeader)
            navigation("Planning", ids: ["roadmap", "tasks", "specs", "pitch"], columns: columns)
            navigation("Development tools", ids: ["preview", "review", "terminal", "agents"], columns: columns)
            group("Project details") {
                SettingsRow("Source folder", detail: details.folder.isEmpty ? "No folder selected" : details.folder) { EmptyView() }
                if !roadmapProgress.isEmpty {
                    LibrarySeparator()
                    SettingsRow("Roadmap progress", detail: roadmapProgress) { EmptyView() }
                }
                if let created = details.createdAt {
                    LibrarySeparator()
                    SettingsRow("Created", detail: Date(timeIntervalSince1970: created).formatted(date: .abbreviated, time: .omitted)) { EmptyView() }
                }
            }
            group("Project settings") {
                SettingsRow("Project name") { field("Project name", text: $name).labelsHidden() }
                LibrarySeparator()
                SettingsRow("Project icon") { field("Default icon", text: $icon).labelsHidden() }
                LibrarySeparator()
                SettingsRow("Source folder") {
                    Button("Choose folder", action: chooseFolder).buttonStyle(.yab(.secondary, .small))
                }
                LibrarySeparator()
                SettingsRow("Project look") {
                    LookPicker(paint: Binding(get: { details.paint ?? SpacePaint(prefs) }, set: { paint in
                        var updated = details
                        updated.paint = paint
                        directory.save(updated, for: project)
                    }), named: details.name, offersBrowserTabs: false)
                }
                if name != details.name || icon != details.icon {
                    Button("Save changes", action: save).buttonStyle(.yab(.primary, .small))
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            if let events = details.activity, !events.isEmpty {
                group("Activity") {
                    ForEach(Array(events.suffix(8).reversed().enumerated()), id: \.offset) { entry in
                        SettingsRow(entry.element.title) {
                            Text(Date(timeIntervalSince1970: entry.element.time), format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
        .padding(LibraryPageLayout.sectionGap)
        .frame(maxWidth: .infinity)
    }

    private func navigation(_ title: String, ids: [String], columns: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: columns), spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    let item = DevelopmentDestination.tools.first { $0.id == id }
                    let title = id == "tasks" ? "Tasks" : item?.title ?? ""
                    Button { open(id) } label: {
                        HStack(spacing: 8) {
                            Symbol(id == "tasks" ? "checklist" : item?.icon ?? "folder", size: 15)
                            Text(title).lineLimit(1)
                            Spacer(minLength: 0)
                            Symbol("chevron.right", size: 9)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(LibraryCardSurface())
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                }
            }
        }
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: CardFrame.inset, content: rows)
                .padding(CardFrame.inset).modifier(LibraryCardSurface())
        }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .foregroundStyle(Palette.strong(on: tone))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Palette.wash(on: tone), in: RoundedRectangle(cornerRadius: SideBar.radius))
    }

    private func save() {
        var updated = details
        updated.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !updated.name.isEmpty else { return }
        updated.icon = String(icon.prefix(1))
        name = updated.name
        icon = updated.icon
        updated.record("Project settings updated")
        directory.save(updated, for: project)
    }

    private func chooseFolder() {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if !details.folder.isEmpty { panel.directoryURL = URL(fileURLWithPath: details.folder) }
        panel.beginSheetModal(for: window) { result in
            guard result == .OK, let url = panel.url else { return }
            var updated = details
            guard updated.folder != url.path else { return }
            updated.folder = url.path
            updated.record("Source folder changed")
            directory.save(updated, for: project)
        }
    }
}

enum DevelopmentSettingsSection: String, CaseIterable {
    case providers = "Providers"
    case plugins = "Plugins"
    case skills = "Skills"

    var symbol: String {
        switch self {
        case .providers: "cpu"
        case .plugins: "puzzlepiece.extension"
        case .skills: "book"
        }
    }
}

struct DevelopmentEnvironmentSettings: View {
    let browser: Browser
    let state: DevelopmentToolbarState
    @StateObject private var catalog = DevelopmentCatalog()
    @State private var query = ""

    var body: some View {
        LibraryPageFrame(page: .settings, breadcrumbs: ["Development", state.environmentSection.rawValue]) {
            EmptyView()
        } search: {
            ThemedSearchField("Search settings", text: $query)
        } content: {
            SettingsLibraryLayout(maximumWidth: LibraryPageLayout.formWidth) {
                navigation
            } detail: {
                sectionDetail
            }
        }
        .task { await catalog.load(folder: "") }
    }

    private var navigation: some View {
        SettingsSectionList {
            ForEach(DevelopmentSettingsSection.allCases, id: \.self) { section in
                LibraryScopeRow(title: section.rawValue, symbol: section.symbol,
                                selected: state.environmentSection == section, selectedIconTint: .accentColor) {
                    state.environmentSection = section
                    query = ""
                }
            }
        }
    }

    private var sectionDetail: some View {
        DevelopmentSettingsDetail(browser: browser, section: state.environmentSection,
                                  catalog: catalog, query: query) { navigation }
    }
}

private struct DevelopmentSettingsDetail<Navigation: View>: View {
    let browser: Browser
    let section: DevelopmentSettingsSection
    @ObservedObject var catalog: DevelopmentCatalog
    let query: String
    @ViewBuilder let navigation: () -> Navigation
    @Environment(\.settingsLibraryNavigationVisible) private var navigationVisible

    var body: some View {
        if !navigationVisible {
            SettingsSectionsButton(navigation: navigation)
                .padding(.bottom, CardFrame.inset)
        }
        Form {
            Section {
                switch section {
                case .providers: providers
                case .plugins: references(.plugin)
                case .skills: references(.skill)
                }
            }
        }
        .formStyle(LibrarySettingsFormStyle())
        .id(section)
    }

    @ViewBuilder private var providers: some View {
        let plans = AgentPlan.all.filter { matches($0.tool) || matches($0.name) }
        if plans.isEmpty {
            Text("No results").foregroundStyle(.secondary)
        }
        ForEach(plans, id: \.cli) { plan in
            SettingsRow(plan.tool, detail: ProviderConsent.shared.allows(plan.cli) ? "Connected" : "Disconnected",
                        symbol: plan.mark) {
                Button("Manage") { browser.openSettings(.agents) }.buttonStyle(.yab(.secondary, .small))
            }
        }
    }

    @ViewBuilder private func references(_ kind: DevelopmentReference.Kind) -> some View {
        let rows = catalog.references.filter { $0.kind == kind && matches($0.name) }
        if kind == .plugin && !catalog.status.isEmpty {
            Text(catalog.status).foregroundStyle(.secondary)
        } else if rows.isEmpty {
            Text(query.isEmpty ? "No installed " + section.rawValue.lowercased() : "No results")
                .foregroundStyle(.secondary)
        }
        ForEach(rows) { ref in
            SettingsRow(verbatim: ref.name, symbol: symbol(for: ref)) {
                if kind == .plugin {
                    Toggle("Enable " + ref.name, isOn: Binding(get: { DevelopmentPlugins.shared.allows(ref) },
                        set: { DevelopmentPlugins.shared.set(ref, enabled: $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                }
            }
        }
    }

    private func matches(_ title: String) -> Bool {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return search.isEmpty || title.localizedCaseInsensitiveContains(search)
    }

    private func symbol(for reference: DevelopmentReference) -> String {
        switch reference.name.lowercased() {
        case "github": return "brand.github"
        case "notion": return "brand.notion"
        case "figma": return "brand.figma"
        case "vercel": return "brand.vercel"
        default:
            return reference.kind == .plugin ? DevelopmentSettingsSection.plugins.symbol : DevelopmentSettingsSection.skills.symbol
        }
    }
}
