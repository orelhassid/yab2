import SwiftUI

/// Settings › Field (Search until 2026-10-25), laid out as a launcher's settings: what it is at the
/// top, the few switches, then a table of every site Tab can search, its
/// keyword typed straight into its row and a box to turn it off.
struct SearchPage: View {
    @ObservedObject var prefs: Preferences
    /// Bumped on every change to the sites, so the table reads them again.
    @State private var tick = 0
    @State private var filter = ""
    /// The card over the page, adding or changing a site (see SiteCard).
    @ObservedObject private var card = SiteEditing.shared
    /// The site whose alias has the keys. Each row's alias is its words
    /// alone until it is wanted (SiteRow), so the field is found by the
    /// site's id rather than by AppKit's key view loop, which has only the
    /// fields there are.
    @FocusState private var typing: String?
    /// The site whose alias is to have the keys next, Tab's or the
    /// bench's: its row puts its field in and hands it the keys.
    @State private var wanted: String?
    /// Chrome's Keyboard shortcut for site search: Space or Tab, or Tab.
    @AppStorage(Scopes.spaceKey, store: Store.settings) private var spaceStarts = true

    var body: some View {
        let _ = tick
        let _ = card.closed
        PageHero(page: .search)
        Section {
            FieldLine("Search with", detail: SettingsScope.globalDefault.title, mark: { EmptyView() }, status: { EmptyView() }, end: {
                // Yab's engines, then any an installed extension brings
                // (ChatGPT search's ChatGPT), then Other….
                let providers = ExtensionSearchProviders.all
                let options = Engine.allCases.filter { $0 != .custom }.map { (title: $0.title, value: "engine:" + $0.rawValue) }
                    + providers.map { (title: $0.name, value: "extension:" + $0.extensionID) }
                    + [(title: Engine.custom.title, value: "engine:" + Engine.custom.rawValue)]
                DropMenu("Search with", options: options, selection: Binding(
                    get: {
                        if prefs.engine == .custom, let id = ExtensionSearchProviders.picked, providers.contains(where: { $0.extensionID == id }) {
                            return "extension:" + id
                        }
                        return "engine:" + prefs.engine.rawValue
                    },
                    set: { value in
                        if value.hasPrefix("extension:"), let provider = providers.first(where: { "extension:" + $0.extensionID == value }) {
                            ExtensionSearchProviders.pick(provider, in: prefs)
                        } else if let engine = Engine(rawValue: String(value.dropFirst("engine:".count))) {
                            ExtensionSearchProviders.forget()
                            prefs.engine = engine
                        }
                    }), divideBefore: providers.first.map { "extension:" + $0.extensionID } ?? "engine:" + Engine.custom.rawValue)
                    .fixedSize()
            })
            .settingsAnchor("search-engine")
            if prefs.engine == .custom, ExtensionSearchProviders.picked == nil {
                EngineField(text: $prefs.engineCustom)
            }
        }
        FieldSectionSettings(prefs: prefs)
        FieldUnderSettings(prefs: prefs)
        FieldPageSettings()
        QuickActionSettings()
        Section {
            // Chrome's, above its list of sites: what starts a site's
            // search after its alias, Space or Tab (its default) or Tab.
            FieldLine("Keyboard shortcut", detail: "After a site's alias in the field", mark: { FieldLineMark(symbol: "keyboard") },
                      status: { EmptyView() }, end: {
                DropMenu("Keyboard shortcut", options: [DropOption(title: "Space or Tab", value: true), DropOption(title: "Tab", value: false)],
                         selection: $spaceStarts)
                    .fixedSize()
            })
            .settingsAnchor("site-search-space")
            ForEach(shown) { scope in
                SiteRow(scope: scope, on: Scopes.isOn(scope), pointed: card.pointed == scope.id,
                        wanted: wanted == scope.id, typing: $typing, want: { wanted = $0 },
                        step: { step(from: scope.id, by: $0) }) { change in
                    switch change {
                    case .on(let on): Scopes.set(scope, on: on)
                    case .keyword(let word): Scopes.setKeyword(word, for: scope)
                    case .edit: card.open(scope)
                    case .remove: Scopes.forget(scope)
                    }
                    tick += 1
                }
                // A search for the sites comes to the first of them, and
                // lights it alone, not the whole table.
                .settingsAnchor(scope.id == shown.first?.id ? "site-search" : "site-" + scope.id)
            }
            if shown.isEmpty {
                Text(filter.trimmingCharacters(in: .whitespaces).isEmpty ? "No sites yet" : "No site called “\(filter)”")
                    .foregroundStyle(.secondary)
            }
            FieldAddLine("Add Site") { card.open(nil) }
        } header: {
            HStack(spacing: 8) {
                Text(SettingsWords.text("Sites"))
                Spacer()
                ThemedSearchField("Filter", text: $filter)
                    .frame(width: 140)
                    .labelsHidden()
            }
            .textCase(nil)
        }
        // Once the keys are where they were wanted, nothing more is.
        .onChange(of: typing) { _, now in if now != nil { wanted = nil } }
        // The bench: a site's alias given the keys, as a click would.
        .onChange(of: card.typing) { _, host in
            guard let host else { return }
            wanted = host
            card.typing = nil
        }
    }

    /// Tab from one site's alias to the next one's, ⇧Tab to the one
    /// before, round from the last to the first.
    private func step(from id: String, by step: Int) {
        let sites = shown
        guard let at = sites.firstIndex(where: { $0.id == id }), !sites.isEmpty else { return }
        wanted = sites[(at + step + sites.count) % sites.count].id
    }

    /// The sites, narrowed to those the filter names by name, host or
    /// keyword.
    private var shown: [Scope] {
        let needle = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return Scopes.all }
        return Scopes.all.filter { scope in
            scope.name.lowercased().contains(needle) || scope.host.contains(needle)
                || scope.aliases.contains { $0.hasPrefix(needle) }
        }
    }
}

/// Return and blur share this decision: an untouched field follows a new
/// saved alias; an actual draft still goes through normal validation.
@MainActor
enum SiteAliasCommit {
    static func value(_ word: String, saved: String, current: String) -> String {
        word == saved ? current : Scopes.clean(word)
    }
}

/// One site: its mark, name and host, the alias it answers to, typed in
/// place, and whether Tab searches it. Off, the row is drawn faint, as
/// Raycast draws a command that is off.
private struct SiteRow: View {
    static let box: CGFloat = 20

    let scope: Scope
    let on: Bool
    /// The bench: drawn as if the pointer were on its alias.
    var pointed = false
    /// Its alias is to have the keys next: Tab came to it, or the bench.
    var wanted = false
    /// Which site's alias has the keys, the table's.
    var typing: FocusState<String?>.Binding
    /// Asks for a site's alias to have the keys.
    let want: (String?) -> Void
    /// Tab (1) or ⇧Tab (-1) pressed in its alias.
    let step: (Int) -> Void
    let change: (Change) -> Void

    enum Change { case on(Bool), keyword(String), edit, remove }

    @State private var word = ""
    /// The value projected or submitted by this field, before any typing.
    @State private var savedWord = ""
    @State private var hovering = false
    /// What was typed and refused, and why, on a card under the field.
    @State private var refused: (word: String, why: String)?
    @State private var glow: Glow?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        FieldLine(scope.name, off: !on, mark: { Mark(icon: scope.icon, letter: scope.letter, size: FieldLineColumn.mark) }, status: { alias }, end: {
            FieldSwitch(scope.name, isOn: Binding(get: { on }, set: { change(.on($0)) }))
        })
        .contentShape(Rectangle())
        .contextMenu {
            Button("Change Search Address…") { change(.edit) }
            Button(SettingsWords.text(on ? "Turn Off" : "Turn On")) { change(.on(!on)) }
            if scope.removable {
                Divider()
                Button(SettingsWords.text("Remove")) { change(.remove) }
            }
        }
        .onAppear {
            word = scope.aliases.first ?? ""
            savedWord = word
            if scope.icon == nil { for host in scope.allHosts { Favicons.shared.fetch(host: host) } }
        }
        // Adding the same search again replaces it under its identity, so
        // this row's state survives. Follow the saved alias without erasing
        // a draft that is still being edited inline.
        .onChange(of: scope.aliases) { _, aliases in
            if !focused { word = aliases.first ?? ""; savedWord = word }
        }
    }

    private var focused: Bool { typing.wrappedValue == scope.id }

    /// The alias: its words bare at rest, an outline under the pointer, a
    /// firmer one while typed in, Raycast's cell. A real field only while
    /// it is wanted: under the pointer, so a click lands in it, while it
    /// has the keys or is to have them, and while its refusal is up. A
    /// settings page is a SwiftUI scroll view, and every frame it moves a
    /// field in each row is worked out again, seen or not, as a recorder in
    /// each Shortcuts cell was (ShortcutRecorder).
    private var alias: some View {
        Group {
            if hovering || pointed || wanted || focused || refused != nil || ShortcutRecorder.eager {
                field
            } else {
                Text(word.isEmpty ? "Alias" : word)
                    .foregroundStyle(word.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Alias")
                    .accessibilityValue(word)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { want(scope.id) }
            }
        }
        .modifier(TableCell(width: FieldLineColumn.status, hovering: hovering || pointed, active: focused))
        .onHover { hovering = $0 }
        // Watched here, not on the field, which may go in the same pass.
        .onChange(of: focused) { was, now in if was, !now { commit() } }
        .popover(isPresented: Binding(get: { refused != nil }, set: { if !$0 { refused = nil } }), arrowEdge: .bottom) {
            KeySheet(glow: glow) {
                Text(refused?.word ?? "")
                    .font(.system(size: 15, weight: .medium))
                    .frame(height: 24)
                Text(refused?.why ?? "")
                    .font(.system(size: 11))
                    .foregroundStyle(ButtonCSS.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 28, alignment: .top)
            }
        }
    }

    // Its own words, not a label beside it: a form row would set the
    // title "Alias" in front of every field.
    private var field: some View {
        TextField(text: $word, prompt: Text("")) { EmptyView() }
            .textFieldStyle(.plain)
            .labelsHidden()
            .multilineTextAlignment(.leading)
            .focused(typing, equals: scope.id)
            // The prompt drawn by hand: a TextField's own is set in the
            // ink of the words in a form row, not in the table's gray.
            .overlay(alignment: .leading) {
                if word.isEmpty, !InputMethod.composing(focused: focused) {
                    Text("Alias")
                        .foregroundStyle(.secondary)
                        .allowsHitTesting(false)
                }
            }
            .onSubmit { commit() }
            // The next site's alias has no field until it is wanted, so
            // Tab is carried there by hand rather than by AppKit.
            .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")], phases: .down) { press in
                guard press.modifiers.isDisjoint(with: [.command, .option, .control]) else { return .ignored }
                step(press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}") ? -1 : 1)
                return .handled
            }
            // Put in because it was wanted: the keys follow, once the field
            // is in the window.
            .onAppear { if wanted { DispatchQueue.main.async { typing.wrappedValue = scope.id } } }
            .onChange(of: wanted) { _, now in if now { typing.wrappedValue = scope.id } }
    }

    /// What was typed, kept if it can be an alias. If it can't, another
    /// site's already or not a word, the old one comes back and a card
    /// under the field says why, its top lit red for a moment, the way the
    /// recorder's card refuses a key.
    private func commit() {
        let old = scope.aliases.first ?? ""
        let clean = SiteAliasCommit.value(word, saved: savedWord, current: old)
        guard clean != old else {
            word = old
            savedWord = old
            return
        }
        if let problem = Scopes.aliasProblem(clean, for: scope) {
            SiteEditing.shared.said = problem
            word = old
            savedWord = old
            refused = (clean, problem)
            light($glow, .bad, reduceMotion: reduceMotion)
            return
        }
        change(.keyword(clean))
        word = clean
        savedWord = clean
        SiteEditing.shared.said = clean.isEmpty ? "Removed" : "Kept \(clean)"
    }
}

/// The card Settings › Search asks in: the site being added or changed,
/// if one is. Held apart from the page, since the card is laid over the
/// whole of the settings, not inside the list.
@MainActor
final class SiteEditing: ObservableObject {
    static let shared = SiteEditing()

    struct Draft: Identifiable {
        let id = UUID()
        let scope: Scope?
    }

    @Published private(set) var draft: Draft?
    /// Bumped as the card goes, so the list reads the sites again.
    @Published private(set) var closed = 0
    /// The bench: a site's alias drawn as if pointed at, or given the keys.
    @Published var pointed: String?
    @Published var typing: String?
    /// What an alias typed came to, for the bench to read back.
    var said = ""

    func open(_ scope: Scope?) { draft = Draft(scope: scope) }

    func close() {
        draft = nil
        closed += 1
    }
}

/// Over the settings while a site is being added or changed: the page
/// dimmed and the card in the middle, coming up the way a page's question
/// does over a page (Asks.swift), from a touch smaller, and gone at once.
struct SiteCardLayer: View {
    @ObservedObject var editing = SiteEditing.shared

    var body: some View {
        ZStack {
            if let draft = editing.draft {
                SiteCard(draft: draft) { editing.close() }
                    .frame(width: 440)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.97).combined(with: .opacity).animation(Motion.arrive),
                        removal: .identity
                    ))
                    .id(draft.id)
            }
        }
    }
}

/// Add Site…, or Change Search Address…, as the app's own cards ask: the
/// well and the question, the fields washed in ink, the buttons at the foot.
private struct SiteCard: View {
    let draft: SiteEditing.Draft
    let done: () -> Void

    @State private var name = ""
    @State private var template = ""
    @State private var keyword = ""
    @FocusState private var focus: Field?

    private enum Field { case name, template, keyword }

    private var adding: Bool { draft.scope == nil }
    private var clean: String { template.trimmingCharacters(in: .whitespaces) }
    private var valid: Bool { Engine.accepts(clean) && keywordProblem == nil }
    private var keywordProblem: String? {
        guard adding, let scope = Scopes.draft(name: name, template: clean) else { return nil }
        return Scopes.aliasProblem(keyword, for: scope)
    }
    private var preset: Scope? { draft.scope.flatMap { scope in Scopes.preset.first { $0.id == scope.id } } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CardFrame.wellGap) {
                well
                VStack(alignment: .leading, spacing: 2) {
                    Text(adding ? "Add a site to search" : "Where \(draft.scope?.name ?? "") searches")
                        .font(CardFrame.title)
                        .foregroundStyle(Palette.ink)
                    Text(keywordProblem ?? (Engine.accepts(clean) || clean.isEmpty
                         ? "Search the site for anything, copy the address of the results, and put %s where your words were."
                         : "Needs to be a web address with %s where the words go."))
                        .font(CardFrame.detail)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(spacing: 6) {
                if adding { field("Name", text: $name, as: .name) }
                field("https://example.com/search?q=%s", text: $template, as: .template)
                if adding { field("Keyword, like hn", text: $keyword, as: .keyword) }
            }
            .padding(.top, 12)
            HStack(spacing: 6) {
                if preset != nil, clean != preset?.template {
                    Button(SettingsWords.text("Restore")) { template = preset?.template ?? "" }
                        .buttonStyle(.yab(.quiet, CardFrame.button))
                        .fixedSize()
                }
                Spacer(minLength: 8)
                // Escape works here as on every card, and says so as theirs do.
                Button(action: done) {
                    HStack(spacing: 6) {
                        Text(SettingsWords.text("Cancel"))
                        KeyGlyphs(keys: "esc", size: CardFrame.words, tint: nil, rest: 0.6)
                    }
                }
                .buttonStyle(.yab(.secondary, CardFrame.button))
                .fixedSize()
                Button(action: save) {
                    HStack(spacing: 6) {
                        Text(adding ? "Add" : "Save")
                        KeyGlyphs(keys: "↩", size: CardFrame.words, tint: nil, rest: 0.6)
                    }
                }
                .buttonStyle(.yab(.primary, CardFrame.button))
                .fixedSize()
                .disabled(!valid)
                .allowsHitTesting(valid)
            }
            .padding(.top, CardFrame.buttonGap)
        }
        .cardFrame()
        .onExitCommand(perform: done)
        .onAppear {
            template = draft.scope?.template ?? ""
            DispatchQueue.main.async { focus = adding ? .name : .template }
        }
    }

    private func save() {
        guard valid else { return }
        if let scope = draft.scope {
            Scopes.setTemplate(clean, for: scope)
        } else {
            _ = Scopes.add(name: name, template: clean, keyword: keyword)
        }
        done()
    }

    /// The site's own mark when it is one being changed, a plus for a new one.
    @ViewBuilder
    private var well: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        shape.fill(Palette.ink.opacity(0.05))
            .overlay(shape.strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5))
            .overlay {
                if let scope = draft.scope {
                    Mark(icon: scope.icon, letter: scope.letter, size: 20)
                } else {
                    Symbol("plus", size: 16).foregroundStyle(Palette.ink)
                }
            }
            .frame(width: CardFrame.well, height: CardFrame.well)
    }

    /// A wash of ink in the buttons' shape, a hairline round it while it
    /// has the keys, as a page's prompt asks for its answer.
    private func field(_ hint: String, text: Binding<String>, as which: Field) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 13.5))
            .foregroundStyle(Palette.ink)
            .focused($focus, equals: which)
            .modifier(CardField(hint: hint, empty: text.wrappedValue.isEmpty, typing: focus == which))
            .onSubmit(save)
    }
}

/// A field on one of the app's cards: a wash of ink in the buttons'
/// shape, its hint in the muted ink while empty, a hairline round it while
/// it has the keys, as a page's prompt asks for its answer.
struct CardField: ViewModifier {
    let hint: String
    let empty: Bool
    let typing: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return content
            .overlay(alignment: .leading) {
                if empty, !InputMethod.composing(focused: typing) {
                    Text(hint).font(.system(size: 13.5)).foregroundStyle(Palette.muted).allowsHitTesting(false)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(shape.fill(Palette.ink.opacity(typing ? 0.035 : 0.06)))
            .overlay(shape.strokeBorder(Palette.ink.opacity(typing ? 0.22 : 0), lineWidth: 1))
            .animation(Motion.quick, value: typing)
    }
}
