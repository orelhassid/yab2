import AppKit
import Combine
import SwiftUI

/// A hosting preference only. Both presentations edit the same settings.
enum SettingsPresentation: String, CaseIterable {
    case tab, window
    static let key = "settings.presentation"
    static func read(from store: UserDefaults) -> Self {
        store.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .tab
    }
    static var saved: Self { read(from: Store.settings) }
}

struct SettingsTab: NSViewRepresentable {
    @ObservedObject var browser: Browser
    let tab: Tab

    func makeNSView(context: Context) -> SettingsTabHost {
        SettingsTabHost(browser: browser, tab: tab)
    }

    func updateNSView(_ host: SettingsTabHost, context: Context) {
        host.browser = browser
        host.tab = tab
        if browser.activeID == tab.id { host.attach() } else { SettingsWindow.shared.detachTab(host) }
    }

    static func dismantleNSView(_ host: SettingsTabHost, coordinator: ()) {
        SettingsWindow.shared.detachTab(host)
    }
}

/// Hosts the shared Settings components in the library template. Window
/// mode keeps its native split view; both presentations use the same model.
final class SettingsTabHost: NSView {
    weak var browser: Browser?
    weak var tab: Tab?
    private var header: NSView?
    private var keys: Any?
    private var keyWatch: AnyCancellable?

    init(browser: Browser, tab: Tab) {
        self.browser = browser
        self.tab = tab
        super.init(frame: .zero)
        keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window != nil, self.browser?.activeID == self.tab?.id else { return event }
            return SettingsWindow.shared.tabKeys(event) ? nil : event
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { if let keys { NSEvent.removeMonitor(keys) } }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        keyWatch = nil
        if let window {
            keyWatch = Publishers.Merge(
                NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification, object: window),
                NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: window)
            ).sink { [weak self] _ in
                if let self {
                    if self.window?.isKeyWindow == true { self.attach() }
                    SettingsWindow.shared.tabFocusChanged(self)
                }
            }
        }
        if window == nil { SettingsWindow.shared.detachTab(self) } else { attach() }
    }

    func attach() {
        guard let browser, let tab, window != nil else { return }
        SettingsWindow.shared.attachTab(self, browser: browser, tab: tab)
    }

    func install(browser: Browser, model: SettingsModel) {
        header?.removeFromSuperview()
        let header = NSHostingView(rootView: SettingsLibraryPage(browser: browser, model: model))
        header.sizingOptions = []
        header.safeAreaRegions = []
        self.header = header
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: topAnchor),
            header.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}

private struct SettingsLibraryPage: View {
    @ObservedObject var browser: Browser
    @ObservedObject var model: SettingsModel
    var body: some View {
        LibraryPageFrame(browser: browser, page: .settings, breadcrumbs: SettingsNavigation.breadcrumbs(for: model.page)) {
            EmptyView()
        } search: {
            SettingsLibrarySearch(model: model)
        } content: {
            SettingsLibraryBody(browser: browser, model: model)
        }
    }
}

/// Stable task groups, with everyday controls first. Search keeps its relevance order.
enum SettingsNavigation {
    static let groups: [(title: String, pages: [SettingsPage])] = [
        ("Personal", [.profile, .appearance, .general]),
        ("Workspace", [.spaces, .tabs]),
        ("Tools", [.ai, .extensions, .shortcuts, .mouse, .mail]),
        ("Other", [.privacy, .developers, .about]),
    ]

    static func destination(for page: SettingsPage) -> SettingsPage {
        switch page {
        case .bringIn, .passwords, .autofill, .sync: return .profile
        case .search, .smallWindow: return .general
        case .liveFolders: return .tabs
        case .boosts: return .extensions
        case .snippets: return .shortcuts
        case .websites, .reading: return .privacy
        case .experimental: return .developers
        case .inviteFriends, .bestFriend: return .about
        default: return page.top
        }
    }

    static func title(for page: SettingsPage) -> String {
        switch page {
        case .general: return "Browser behavior"
        case .tabs: return "Tabs & folders"
        case .extensions: return "Extensions & Boosts"
        case .shortcuts: return "Shortcuts & Snippets"
        case .privacy: return "Privacy & websites"
        case .developers: return "Developer tools"
        case .about: return "Help & updates"
        default: return page.title
        }
    }

    static func breadcrumbs(for page: SettingsPage) -> [String] {
        let root = destination(for: page)
        return root == page ? [title(for: root)] : [title(for: root), page.title]
    }

    static func collections(for page: SettingsPage) -> [SettingsPage] {
        switch destination(for: page) {
        case .tabs: return [.tabs, .liveFolders]
        case .extensions: return [.extensions, .boosts]
        case .shortcuts: return [.shortcuts, .snippets]
        default: return []
        }
    }

    static func children(of page: SettingsPage) -> [SettingsPage] {
        SettingsPage.allCases.filter { $0.parent == page && $0.available }
    }

    static func maximumWidth(for page: SettingsPage) -> CGFloat {
        switch page {
        case .shortcuts, .websites, .extensions, .passwords, .autofill, .spaces, .liveFolders, .history:
            LibraryPageLayout.collectionWidth
        default: LibraryPageLayout.formWidth
        }
    }
}

private struct SettingsLibraryBody: View {
    @ObservedObject var browser: Browser
    @ObservedObject var model: SettingsModel
    var body: some View {
        GeometryReader { bounds in
            let narrow = bounds.size.width < 650
            HStack(alignment: .top, spacing: LibraryPageLayout.columnGap) {
                if !narrow {
                    SettingsSidebar(model: model, inLibrary: true)
                        .frame(width: LibraryPageLayout.navigationWidth)
                }
                VStack(alignment: .leading, spacing: 0) {
                    SettingsDetail(browser: browser, prefs: browser.prefs, model: model, inLibrary: true)
                        .environment(\.settingsLibraryNavigationVisible, !narrow)
                }.frame(maxWidth: SettingsNavigation.maximumWidth(for: model.page), alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct SettingsLibraryNavigationVisible: EnvironmentKey { static let defaultValue = true }
extension EnvironmentValues {
    var settingsLibraryNavigationVisible: Bool {
        get { self[SettingsLibraryNavigationVisible.self] }
        set { self[SettingsLibraryNavigationVisible.self] = newValue }
    }
}

/// Page controls share the library's content heading, rather than a window titlebar.
struct SettingsTabToolbar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var model: SettingsModel
    @Environment(\.settingsLibraryNavigationVisible) private var navigationVisible
    @State private var showSections = false

    var body: some View {
        if !navigationVisible || model.page == .shortcuts || model.page == .engine || model.page == .extensions || model.page.master != nil {
        HStack(spacing: 8) {
            if !navigationVisible {
                Button { showSections.toggle() } label: { Label("Sections", systemImage: "sidebar.left") }
                    .popover(isPresented: $showSections) {
                        SettingsSidebar(model: model, inLibrary: true)
                            .padding(CardFrame.inset).frame(width: 220, height: 400)
                    }
            }
            Spacer(minLength: 8)
            if model.page == .shortcuts {
                SettingsShortcutTools(selection: model.shortcutFilters)
            } else if model.page == .engine {
                SettingsEngineTools(search: model.engineSearch)
            } else if model.page == .extensions, PageEngineFactory.chromiumEnabled {
                if #available(macOS 15.4, *) { SettingsExtensionTools(browser: browser, model: model) }
            } else if let master = model.page.master,
                      !(model.page == .spaces && model.opened == SpacePlace.new),
                      !(model.page.top == .ai && AgentSetupModel.shared.arriving),
                      !(model.page == .mail && MailArrival.shows) {
                SettingsTabMaster(prefs: browser.prefs, title: master.title, key: master.key)
            }
        }
        .frame(minHeight: ButtonSize.small.height)
        .buttonStyle(.yab(.quiet, .small))
        .foregroundStyle(Palette.ink)
        }
    }
}

/// Restyles the existing Form sections and rows with the library's card surfaces.
struct LibrarySettingsFormStyle: FormStyle {
    @Environment(\.tone) private var tone
    func makeBody(configuration: Configuration) -> some View {
        ThreadScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(sections: configuration.content) { section in
                    VStack(alignment: .leading, spacing: 8) {
                        if !section.header.isEmpty {
                            VStack(alignment: .leading, spacing: 0) { ForEach(section.header) { $0 } }
                                .font(CardFrame.detail).foregroundStyle(Palette.muted(on: tone))
                        }
                        if !section.content.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(section.content.indices, id: \.self) { index in
                                    section.content[index]
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(CardFrame.inset)
                                    if index < section.content.count - 1 { LibrarySeparator().padding(.horizontal, CardFrame.inset) }
                                }
                            }
                            .padding(1)
                            .modifier(LibraryCardSurface())
                        }
                        if !section.footer.isEmpty {
                            VStack(alignment: .leading, spacing: 0) { ForEach(section.footer) { $0 } }
                                .font(CardFrame.detail).foregroundStyle(Palette.muted(on: tone))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.bottom, 1) // design: keep the card's lower hairline inside the scroll viewport.
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SettingsInLibraryKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var settingsInLibrary: Bool {
        get { self[SettingsInLibraryKey.self] }
        set { self[SettingsInLibraryKey.self] = newValue }
    }
}

private struct SettingsTabMaster: View {
    @ObservedObject var prefs: Preferences
    let title: String
    let key: ReferenceWritableKeyPath<Preferences, Bool>
    var body: some View {
        Toggle(SettingsWords.text(title), isOn: Binding(get: { prefs[keyPath: key] }, set: { prefs[keyPath: key] = $0 }))
            .labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

private struct SettingsEngineTools: View {
    @ObservedObject var search: EngineSearch
    var body: some View {
        SettingsTabSearch(prompt: "Search sites", text: $search.words)
            .frame(width: 220)
        Button("Add Site…") { EngineSiteEditing.shared.open() }
    }
}

private struct SettingsShortcutTools: View {
    @ObservedObject var selection: ShortcutFilter.Selection
    var body: some View {
        SettingsTabSearch(prompt: "Search by name or alias", text: $selection.search, capturesShortcuts: true)
            .frame(width: 220)
        SettingsTabFilters().frame(width: 90)
    }
}

private struct SettingsTabFilters: NSViewRepresentable {
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Filters", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Shortcut filters")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator: NSObject {
        @objc func open(_ sender: NSButton) { SettingsWindow.shared.showShortcutFilters(under: sender) }
    }
}

@available(macOS 15.4, *)
private struct SettingsExtensionTools: View {
    let browser: Browser
    @ObservedObject var model: SettingsModel
    @ObservedObject var extensions: ChromiumExtensions

    init(browser: Browser, model: SettingsModel) {
        self.browser = browser
        self.model = model
        extensions = ChromiumExtensions.of(browser)
    }
    var body: some View {
        if model.opened == nil {
            if extensions.canImportWebKitList(browser) {
                Button("Import") { extensions.importWebKitList(browser) }.disabled(extensions.busy)
            }
            Button("Add") { model.open(extension: ExtensionAdd.Step.arrival.rawValue) }.disabled(extensions.busy)
        }
    }
}

private struct SettingsTabSearch: View {
    let prompt: String
    @Binding var text: String
    var capturesShortcuts = false
    @Environment(\.tone) private var tone

    var body: some View {
        if tone != nil {
            LibrarySearchWell(text: $text) {
                SettingsTabSearchField(prompt: prompt, text: $text, capturesShortcuts: capturesShortcuts, bare: true)
            }
        } else {
            SettingsTabSearchField(prompt: prompt, text: $text, capturesShortcuts: capturesShortcuts, bare: false)
        }
    }
}

private struct SettingsTabSearchField: NSViewRepresentable {
    let prompt: String
    @Binding var text: String
    let capturesShortcuts: Bool
    let bare: Bool

    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.placeholderString = prompt
        field.setAccessibilityLabel(prompt)
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        if bare {
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            if let cell = field.cell as? NSSearchFieldCell {
                cell.searchButtonCell = nil
                cell.cancelButtonCell = nil
            }
        }
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.capturesShortcuts = capturesShortcuts
        field.textColor = context.environment.tone.map { Palette.shades($0).strongNS } ?? .labelColor
        if field.stringValue != text { field.stringValue = text }
    }
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SettingsTabSearchField
        init(parent: SettingsTabSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSSearchField { parent.text = field.stringValue }
        }
    }
    final class Field: NSSearchField {
        var capturesShortcuts = false
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let editing: Set<String> = ["⌘A", "⌘C", "⌘V", "⌘X", "⌘Z", "⇧⌘Z", "⌘⌫", "⌥⌫", "⌃⌫"]
            if capturesShortcuts, currentEditor() != nil, !Keymap.shared.recording,
               let key = Hotkey(event), !key.flags.intersection([.command, .option, .control]).isEmpty,
               !["←", "→", "↑", "↓", "home", "end"].contains(key.key), !editing.contains(key.text) {
                stringValue = key.text
                currentEditor()?.string = key.text
                delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: self))
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }
}
