import SwiftUI

/// The selected project's paint is scoped to its window and never written to
/// the browser preferences that dress regular Spaces.
struct DevelopmentLook: ViewModifier {
    let paint: SpacePaint
    var drawsBackdrop = true

    func body(content: Content) -> some View {
        let resolved = SpaceWash.painted(paint)
        let color = resolved.color
        let tone = SpaceSurface.tone(for: color)
        content
            .environment(\.tone, tone)
            .environment(\.colorScheme, tone.scheme)
            .background {
                if drawsBackdrop {
                    BackdropFill(color: Color(nsColor: color), grain: paint.grain,
                                 transparency: resolved.transparency, colors: resolved.colors.map { Color(nsColor: $0) })
                        .overlay { LookDrawingsFill(drawings: paint.drawings, strength: paint.drawingsStrength, ground: color) }
                }
            }
    }
}

struct DevelopmentSettings: View {
    let project: DevelopmentProject
    let prefs: Preferences
    @State private var appearance = false
    @State private var query = ""
    @State private var name: String
    @State private var icon: String
    private var directory: DevelopmentDirectory { .shared }
    private var details: DevelopmentDetails { directory.details(project) }

    init(project: DevelopmentProject, prefs: Preferences) {
        self.project = project
        self.prefs = prefs
        let details = DevelopmentDirectory.shared.details(project)
        _name = State(initialValue: details.name)
        _icon = State(initialValue: details.icon)
    }

    var body: some View {
        LibraryPageFrame(page: .settings, breadcrumbs: [appearance ? "Appearance" : "Project"]) {
            EmptyView()
        } search: {
            ThemedSearchField("Search settings", text: $query)
        } content: {
            GeometryReader { bounds in
                let wide = bounds.size.width >= 520
                HStack(alignment: .top, spacing: LibraryPageLayout.columnGap) {
                    if wide { VStack { navigation }.frame(width: LibraryPageLayout.navigationWidth) }
                    ScrollView {
                        VStack(alignment: .leading, spacing: LibraryPageLayout.sectionGap) {
                            if !wide { HStack { navigation } }
                            if matches("Project name icon source folder", page: false) {
                                group("Project details") {
                                    SettingsRow("Project name") { TextField("Project name", text: $name).labelsHidden() }
                                    LibrarySeparator()
                                    SettingsRow("Project icon") { TextField("Default icon", text: $icon).labelsHidden() }
                                    LibrarySeparator()
                                    SettingsRow("Source folder", detail: details.folder) {
                                        Button("Choose folder", action: chooseFolder).buttonStyle(.yab(.secondary, .small))
                                    }
                                    if name != details.name || icon != details.icon {
                                        Button("Save changes", action: save).buttonStyle(.yab(.primary, .small))
                                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                    }
                                }
                            }
                            if matches("Appearance theme look color", page: true) {
                                group("Appearance") {
                                    SettingsRow("Project look") {
                                        LookPicker(paint: Binding(get: { details.paint ?? SpacePaint(prefs) }, set: { paint in
                                            var updated = details
                                            updated.paint = paint
                                            directory.save(updated, for: project)
                                        }), named: details.name, offersBrowserTabs: false)
                                    }
                                }
                            }
                            if !query.isEmpty && !matches("Project name icon source folder", page: false)
                                && !matches("Appearance theme look color", page: true) {
                                Text("No matching settings").foregroundStyle(.secondary)
                            }
                        }.frame(maxWidth: LibraryPageLayout.formWidth, alignment: .leading)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func matches(_ words: String, page: Bool) -> Bool {
        query.isEmpty ? appearance == page : words.localizedCaseInsensitiveContains(query)
    }

    @ViewBuilder private var navigation: some View {
        LibraryScopeRow(title: "Project", symbol: "folder", selected: !appearance) { appearance = false; query = "" }
        LibraryScopeRow(title: "Appearance", symbol: "circle.lefthalf.filled", selected: appearance) { appearance = true; query = "" }
    }

    private func group<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsText(title).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: CardFrame.inset, content: rows)
                .padding(CardFrame.inset).modifier(LibraryCardSurface())
        }
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
