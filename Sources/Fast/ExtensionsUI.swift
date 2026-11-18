import SwiftUI
import WebKit

/// Where an extension reads and changes pages, the same rows whichever
/// engine's Settings page shows them: what they set is the one list's
/// (ExtensionOneList). `blocks`: its blocked sites, which only WebKit can keep
/// an extension from (ChromiumExtensionGrants).
@available(macOS 15.4, *)
struct ExtensionWebsites: View {
    let id: String
    let item: Installed
    @ObservedObject var extensions: Extensions
    let everywhere: Bool
    let hosts: [String]
    let clickable: Bool
    var blocks = true

    private static func accessDetail(_ access: Extensions.SiteAccess, everywhere: Bool, hosts: [String]) -> String {
        switch access {
        case .click: return "Only the page where you activate it."
        case .sites: return "Only the sites you add below."
        case .asked: return everywhere ? "" : hosts.joined(separator: ", ")
        }
    }

    /// A table of sites, as Search lists its sites: each site's mark and
    /// name, the one action on a right click, Add Site… in the heading.
    @ViewBuilder
    private func sites(_ list: [String], title: String, empty: String, note: String, menu: String, item: Installed,
                       remove: @escaping (String) -> Void) -> some View {
        Section {
            ForEach(list, id: \.self) { host in
                HStack(spacing: 9) { // design: the same gap as Search's site rows, which this table matches
                    Mark(icon: Favicons.shared.cached(host), letter: host.first.map { String($0).uppercased() } ?? "", size: 16)
                    Text(host).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu { Button(menu) { remove(host) } }
                .onAppear { Favicons.shared.fetch(host: host) }
            }
            if list.isEmpty {
                Text(empty).foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                Text(title)
                Spacer()
                Button("Add Site…") { BlockEditing.shared.open(id: id, name: item.name, allow: true) }
                    .settingsButton()
            }
            .textCase(nil)
        } footer: {
            SettingsNote(note)
        }
    }

    var body: some View {
        let blocked = extensions.blocked(id)
        Section {
            if hosts.isEmpty, !everywhere {
                SettingsRow("Reads and changes pages", detail: clickable ? "Only the page where you activate it." : nil ?? "") {
                    Text(clickable ? "On click" : "None").foregroundStyle(.secondary)
                }
            } else {
                SettingsRow("Reads and changes pages", detail: Self.accessDetail(extensions.access(id), everywhere: everywhere, hosts: hosts)) {
                    // Chrome's three: everywhere it asked, only the sites
                    // chosen below, or only the page it is pressed on.
                    DropMenu("Reads and changes pages",
                             options: [(title: everywhere ? "On all sites" : hosts.count == 1 ? "On \(hosts[0])" : "On \(hosts.count) sites", value: Extensions.SiteAccess.asked),
                                       (title: "On specific sites", value: .sites)]
                                 + (clickable || extensions.access(id) == .click ? [(title: "On click", value: .click)] : []),
                             selection: Binding(get: { extensions.access(id) }, set: { extensions.setAccess(id, $0) }))
                        .fixedSize()
                }
            }
        } header: {
            Text("Websites")
        }
        if extensions.access(id) == .sites, !hosts.isEmpty || everywhere {
            sites(extensions.allowed(id), title: "Allowed sites", empty: "No sites yet",
                  note: extensions.allowed(id).isEmpty
                      ? "\(item.name) runs on no site until you add one."
                      : "\(item.name) runs only on these sites. Right-click one to remove it.",
                  menu: "Remove", item: item) { extensions.disallow($0, for: id) }
        }
        // The sites it never runs on, a table as Search lists its sites:
        // each site's mark and name, Unblock on a right click, and Add
        // Site… in the heading asking in the app's own card, as Search's
        // Add Site… does.
        if blocks { Section {
            ForEach(blocked, id: \.self) { host in
                HStack(spacing: 9) { // design: the same gap as Search's site rows, which this table matches
                    Mark(icon: Favicons.shared.cached(host), letter: host.first.map { String($0).uppercased() } ?? "", size: 16)
                    Text(host).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .contextMenu {
                    Button("Unblock") { extensions.unblock(host, for: id) }
                }
                .onAppear { Favicons.shared.fetch(host: host) }
            }
            if blocked.isEmpty {
                Text("No blocked sites")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HStack(spacing: 8) {
                Text("Blocked sites")
                Spacer()
                Button("Add Site…") { BlockEditing.shared.open(id: id, name: item.name, allow: false) }
                    .settingsButton()
            }
            .textCase(nil)
        } footer: {
            SettingsNote(blocked.isEmpty
                ? "\(item.name) never runs on a site you block, even when you press it."
                : "\(item.name) never runs on these sites. Right-click one to unblock it.")
        } }
    }
}

/// Settings › Extensions: what is installed as a list to read across, where
/// each may reach, its key, pinned, on, and each one's own page a click in,
/// Adding one is its own few steps,
/// in ExtensionAdd.
struct ExtensionsPage: View {
    @ObservedObject var browser: Browser
    @ObservedObject var model: SettingsModel

    var body: some View {
        if PageEngineFactory.chromiumEnabled {
            ChromiumExtensionsSettings(browser: browser, model: model, extensions: .of(browser))
        } else if #available(macOS 15.4, *) {
            let extensions = ExtensionsPage.listed(browser, model)
            if let id = model.opened {
                ExtensionDetail(id: id, browser: browser, model: model, extensions: extensions)
            } else {
                SignInPicker(browser: browser, model: model)
                Installer(browser: browser, model: model, extensions: extensions)
            }
        } else {
            Section {
                SettingsNote("Chrome extensions require macOS 15.4 or later.")
            }
        }
    }

    /// Whose list the page shows: the sign-in picked here, or the one the
    /// window's space is signed in with.
    @available(macOS 15.4, *)
    @MainActor
    static func listed(_ browser: Browser, _ model: SettingsModel) -> Extensions {
        let space = model.extensionsSpace.flatMap { id in browser.spaces.contains { $0.id == id } ? id : nil } ?? browser.spaceID
        return Extensions.of(space: space)
    }

    /// Which sign-in's extensions the list is, once some space has sign-ins
    /// of its own: each keeps its own, as each Chrome profile does.
    @available(macOS 15.4, *)
    private struct SignInPicker: View {
        @ObservedObject var browser: Browser
        @ObservedObject var model: SettingsModel

        var body: some View {
            if SignIns.split(browser) {
                let places = SignIns.places(browser)
                let shown = ExtensionsPage.listed(browser, model).signIn
                let picked = places.first { place in place.spaces.contains { Extensions.signIn(of: $0.id) == shown } }
                Section {
                    SettingsRow("Sign-ins", detail: "Spaces with separate sign-ins have separate extensions.") {
                        DropMenu("Sign-ins",
                                 options: places.compactMap { place in place.spaces.first.map { (title: place.names, value: $0.id) } },
                                 selection: Binding(
                                     get: { picked?.spaces.first?.id ?? browser.spaceID },
                                     set: { model.extensionsSpace = $0 }
                                 ))
                            .frame(maxWidth: SignIns.pickerWidth)
                            .layoutPriority(1)
                    }
                    .settingsAnchor("extensions-sign-ins")
                }
            }
        }
    }

    @available(macOS 15.4, *)
    private struct Installer: View {
        @ObservedObject var browser: Browser
        @ObservedObject var model: SettingsModel
        @ObservedObject var extensions: Extensions
        @ObservedObject var installs = SyncInstalls.shared
        @State private var hovering = false

        var body: some View {
            Section {
                ForEach(extensions.installed) { item in
                    Row(item: item, model: model, extensions: extensions)
                }
                // Another Mac's, on their way here (sync).
                ForEach(installs.extensions) { item in
                    Arriving(item: item)
                }
                // The way in sits where the next one will: under the last.
                Button { model.open(extension: ExtensionAdd.Step.arrival.rawValue) } label: {
                    // As wide as its words, not the row: a press gives up a
                    // point or so all round, as every button's does, where
                    // the whole row would shrink by a dozen at its ends.
                    HStack(spacing: 8) {
                        Symbol("plus", size: 11, weight: .semibold)
                            .frame(width: 20)
                        Text("Add Extension")
                    }
                    // Ink, as every word yab writes; muted until the hand
                    // is on it, like the column's New tab.
                    .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: ButtonSize.regular.pressed))
                .onHover { hovering = $0 }
                .frame(maxWidth: .infinity, alignment: .leading)
                .settingsAnchor("add-extension")
            }
            UserscriptsSection(browser: browser)
            PrivateTabs(prefs: browser.prefs)
        }
    }

    /// Whether private tabs get extensions too: the one row Settings search
    /// finds as "Allow in private tabs", on both engines' pages (feedback
    /// #1894, where the Chromium page dropped the row and search pointed at
    /// nothing). On Chromium a new private tab is then its space profile's
    /// off-the-record side, and each extension's own "Allow in Incognito"
    /// follows this switch (ChromiumPrivateProfiles, ChromiumExtensions).
    struct PrivateTabs: View {
        @ObservedObject var prefs: Preferences

        static let note = "Applies to new private tabs. Enabled extensions may access private page content."

        var body: some View {
            Section {
                SettingsSwitch("Allow in private tabs", isOn: $prefs.extensionsInPrivate)
                    .settingsAnchor("extensions-private")
            } footer: {
                SettingsNote(Self.note)
            }
        }
    }

    /// One another Mac has, on its way in (SyncInstalls): its name, and how
    /// it is coming in words.
    @available(macOS 15.4, *)
    private struct Arriving: View {
        let item: SyncInstalls.Waiting

        var body: some View {
            HStack(spacing: 8) {
                ExtensionMark(id: item.item, side: 20)
                VStack(alignment: .leading, spacing: 3) { // design: a Settings row's title and its line, as SettingsRow sets them
                    Text(item.name).lineLimit(1)
                    Text(item.state.words)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    /// One extension across the list: press it for its own page.
    @available(macOS 15.4, *)
    private struct Row: View {
        let item: Installed
        @ObservedObject var model: SettingsModel
        @ObservedObject var extensions: Extensions
        @State private var hovering = false

        static let gap: CGFloat = 10
        static let sites: CGFloat = 78
        static let key: CGFloat = 64
        static let pin: CGFloat = 18
        static let toggle: CGFloat = 32

        var body: some View {
            let context = extensions.contexts[item.id]
            let replaced = ExtensionDetail.replacedByYab(item)
            HStack(spacing: Row.gap) {
                HStack(spacing: Row.gap) {
                    HStack(spacing: 8) {
                        ExtensionMark(id: item.id, side: 20)
                        VStack(alignment: .leading, spacing: 3) { // design: a Settings row's title and its line, as SettingsRow sets them
                            HStack(spacing: 8) {
                                Text(item.name).lineLimit(1)
                                if let warnings = ExtensionDetail.warnings(item, context, extensions) {
                                    Symbol("exclamationmark.triangle.fill", size: 10)
                                        .foregroundStyle(.orange)
                                        // Room for the pointer around a small mark.
                                        .frame(width: 16, height: 20)
                                        .contentShape(Rectangle())
                                        .keyTip(warnings)
                                }
                            }
                            // While 1Password's app won't talk to Yab, how
                            // to connect it, in the line a row says more in;
                            // gone once the app answers.
                            if ExtensionDetail.unconnected(item, context, extensions) {
                                Text(ExtensionDetail.unconnectedLine)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // macOS killed the app it talks to as Yab
                            // started it: said for as long as Yab runs, as
                            // it isn't started again until then.
                            if ExtensionDetail.stoppedByMacOS(item, context, extensions) {
                                Text(ExtensionDetail.stoppedLine(item.id))
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            // From another Mac at a version that asks for
                            // more than it was allowed there: off until
                            // turned on here, which asks.
                            if replaced {
                                Text(ExtensionDetail.replacedLine)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            if item.wants != nil {
                                Text(ExtensionDetail.wantsLine)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                            // Rule sets WebKit couldn't compile with the
                            // rest, kept off rather than crash on.
                            if let line = ExtensionRuleBudget.line(extensions.rulesLeftOff(item.id).count) {
                                Text(line)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(ExtensionDetail.reach(item, context, extensions))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: Row.sites, alignment: .leading)
                    Group {
                        if let command = context?.commands.first(where: { extensions.routedKey($0) != nil }) {
                            HotkeyCaps(symbols: Hotkey.caps(command.activationKey?.lowercased(), command.modifierFlags), fontSize: 10, snug: true)
                        } else {
                            // No key, no mark: the column is bare, as the
                            // tables' cells are.
                            Color.clear.frame(height: 1)
                        }
                    }
                    .frame(width: Row.key, alignment: .leading)
                }
                .contentShape(Rectangle())
                .onTapGesture { model.open(extension: item.id) }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.open(extension: item.id) }

                let pinned = item.pinned ?? false
                Button {
                    extensions.setPinned(item.id, !pinned)
                } label: {
                    Symbol(pinned ? "pin.fill" : "pin", size: 11)
                        .foregroundStyle(pinned ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                        .frame(width: Row.pin, height: Row.pin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .keyTip(pinned ? "Unpin from the extensions list" : "Pin to the top of the extensions list")
                .opacity(pinned || hovering ? 1 : 0)

                if replaced {
                    // Nothing to switch: its page has Turn On, with what it costs.
                    Color.clear.frame(width: Row.toggle, height: 1)
                } else {
                    Toggle("Enabled", isOn: Binding(get: { item.enabled }, set: { extensions.setEnabled(item.id, $0) }))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .frame(width: Row.toggle)
                }
                Symbol("chevron.right", size: 10, weight: .semibold)
                    .foregroundStyle(.tertiary)
                    .onTapGesture { model.open(extension: item.id) }
                    .accessibilityHidden(true)
            }
            .opacity(item.enabled || replaced ? 1 : 0.55)
            .onHover { hovering = $0 }
        }
    }
}

/// An extension's own icon, or the puzzle piece while it has none to give.
@available(macOS 15.4, *)
struct ExtensionMark: View {
    let id: String
    let side: CGFloat
    @ObservedObject var extensions: Extensions = .shared

    var body: some View {
        Group {
            if let icon = extensions.icon(for: id, side: side) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Symbol("puzzlepiece.extension", size: side * 0.65).foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
    }
}

/// Settings › Extensions › one of them: what it is, its keys, where it may
/// reach, and the rest that was in the row's menu.
@available(macOS 15.4, *)
struct ExtensionDetail: View {
    let id: String
    @ObservedObject var browser: Browser
    @ObservedObject var model: SettingsModel
    @ObservedObject var extensions: Extensions

    var body: some View {
        if let item = extensions.installed.first(where: { $0.id == id }) {
            page(item, extensions.contexts[id])
                // Left asleep by the launch: its page here reads it loaded.
                .onAppear { extensions.wake(id) }
        } else {
            Section { SettingsNote("This extension has been removed.") }
        }
    }

    @ViewBuilder
    private func page(_ item: Installed, _ context: WKWebExtensionContext?) -> some View {
        Section {
            VStack(spacing: 6) {
                ExtensionMark(id: item.id, side: 64)
                    .padding(.bottom, 4)
                Text(item.name)
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                if let about = context?.webExtension.displayDescription, !about.isEmpty {
                    Text(about)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("Version \(item.version) · \(source(item))")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .pointerTip(item.source ?? "")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            if ExtensionDetail.replacedByYab(item) {
                SettingsRow("Yab fills Apple Passwords itself", detail: "This extension isn't needed while Apple Passwords is connected.") {
                    Button("Passwords") { model.go(.passwords) }
                        .settingsButton()
                }
                SettingsRow("Use the Extension Too", detail: "Its own menu also comes up on every sign-in box.") {
                    Button("Turn On") { extensions.setEnabled(id, true) }
                        .settingsButton()
                }
            } else {
                SettingsSwitch("On", isOn: Binding(get: { item.enabled }, set: { extensions.setEnabled(id, $0) }))
                SettingsSwitch("Pinned in the extensions list", isOn: Binding(get: { item.pinned ?? false }, set: { extensions.setPinned(id, $0) }))
            }
            if ExtensionDetail.unconnected(item, context, extensions) {
                SettingsRow("Not connected to the 1Password app",
                            detail: "In 1Password, unlocked: Settings › Browser › Add Browser, then choose Yab.") {
                    Button("Open 1Password") { Extensions.openOnePassword() }
                        .settingsButton()
                }
            }
            if ExtensionDetail.stoppedByMacOS(item, context, extensions) {
                SettingsNote(ExtensionDetail.stoppedNote(item.id))
            }
            if item.wants != nil {
                SettingsNote("This version needs additional permissions. Enabling it asks for approval.")
            }
            if let trouble = ExtensionDetail.trouble(item, context, extensions) {
                SettingsNote(trouble)
            }
        }

        if let context {
            if !context.commands.isEmpty {
                // The table Settings › Shortcuts keeps: what the key does,
                // and the key in the column, bare at rest and outlined
                // under the pointer.
                Section {
                    ForEach(context.commands, id: \.id) { command in
                        CommandRow(title: Self.title(of: command, item), command: command, extensions: extensions)
                    }
                } header: {
                    Text("Shortcuts")
                } footer: {
                    SettingsNote("Hotkeys work while Yab is active. Click to record a new hotkey.")
                }
            }
            ExtensionWebsites(id: id, item: item, extensions: extensions,
                              everywhere: context.webExtension.allRequestedMatchPatterns.contains { $0.matchesAllHosts || $0.matchesAllURLs },
                              hosts: Self.hosts(context.webExtension), clickable: context.webExtension.requestedPermissions.contains(.activeTab))
            more(item, context)
        } else {
            if !ExtensionDetail.replacedByYab(item) {
                Section {
                    SettingsNote(item.enabled
                        ? "Extension failed to start. Reload it or reinstall to view shortcuts and site access."
                        : "Enable to view shortcuts and site access.")
                }
            }
            more(item, nil)
        }

        Section {
            SettingsRow("Remove", detail: "Remove the extension and its saved data from Yab.") {
                Button("Remove…") {
                    Task {
                        guard await extensions.ask(Extensions.removal(id, name: item.name, place: .settings)) else { return }
                        extensions.remove(id)
                        model.travel(-1)
                    }
                }
                    // The red of what cannot be undone, on the wash.
                    .buttonStyle(.yab(.secondary, .regular, tint: ButtonCSS.danger))
            }
        }
    }

    @ViewBuilder
    private func more(_ item: Installed, _ context: WKWebExtensionContext?) -> some View {
        let options = context?.optionsPageURL != nil
        let newTab = context?.overrideNewTabPageURL != nil
        let reloads = item.source != nil || !item.fromStore
        if options || newTab || reloads {
            Section {
                if options {
                    SettingsRow("Its own settings") {
                        Button("Open") {
                            browser.tuning = false
                            extensions.openOptions(id)
                        }
                        .settingsButton()
                    }
                }
                if newTab {
                    SettingsSwitch("Draws the new tab page", isOn: Binding(
                        get: { Store.settings.object(forKey: "extensions.newtab.\(id)") as? Bool == true },
                        set: {
                            Store.settings.set($0, forKey: "extensions.newtab.\(id)")
                            extensions.objectWillChange.send()
                        }
                    ))
                }
                if reloads {
                    SettingsRow("Reload", detail: item.source.map { "Reload changes from “\(URL(fileURLWithPath: $0).lastPathComponent)”." } ?? "") {
                        Button("Reload") { extensions.reload(id) }.settingsButton()
                    }
                }
            }
        }
    }

    private func source(_ item: Installed) -> String {
        if item.fromStore { return "Chrome Web Store" }
        return item.source.map { "From “\(URL(fileURLWithPath: $0).lastPathComponent)”" } ?? "From a folder"
    }

    /// A command's name. The button's own has none in the manifest.
    static func title(of command: WKWebExtension.Command, _ item: Installed) -> String {
        if !command.title.isEmpty { return command.title }
        return command.id == "_execute_action" || command.id == "_execute_browser_action" ? "Press its button" : command.id
    }

    /// One command: its words, and its keys in the Hotkey column; Remove
    /// on a right click, as a Shortcuts row has it.
    private struct CommandRow: View {
        let title: String
        let command: WKWebExtension.Command
        @ObservedObject var extensions: Extensions

        var body: some View {
            HStack(spacing: 12) {
                Text(title)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ShortcutRecorder.command(command, extensions)
            }
            .contentShape(Rectangle())
            .contextMenu {
                Button("Remove") { extensions.setKey(nil, [], for: command) }
                    .disabled(command.activationKey == nil)
            }
        }
    }

    /// The sites its manifest names, by host, without the scheme and path.
    static func hosts(_ found: WKWebExtension) -> [String] {
        let all = found.allRequestedMatchPatterns.compactMap { pattern -> String? in
            guard !pattern.matchesAllHosts, !pattern.matchesAllURLs, let host = pattern.host, !host.isEmpty else { return nil }
            return host.hasPrefix("*.") ? String(host.dropFirst(2)) : host
        }
        return Array(Set(all)).sorted()
    }

    /// Where it may reach, in a word, for the list.
    static func reach(_ item: Installed, _ context: WKWebExtensionContext?, _ extensions: Extensions) -> String {
        guard item.enabled else { return "Off" }
        guard let found = context?.webExtension else { return "–" }
        let clickable = found.requestedPermissions.contains(.activeTab)
        if extensions.access(item.id) == .click, clickable { return "On click" }
        if extensions.access(item.id) == .sites {
            let allowed = extensions.allowed(item.id)
            return allowed.count == 1 ? allowed[0] : allowed.isEmpty ? "No sites" : "\(allowed.count) sites"
        }
        if found.allRequestedMatchPatterns.contains(where: { $0.matchesAllHosts || $0.matchesAllURLs }) { return "All sites" }
        let hosts = hosts(found)
        if hosts.count == 1 { return hosts[0] }
        if !hosts.isEmpty { return "\(hosts.count) sites" }
        return clickable ? "On click" : "None"
    }

    /// 1Password's, on and running, while its app won't talk to Yab: the app
    /// lets in only the browsers it knows and those added in it by hand.
    static func unconnected(_ item: Installed, _ context: WKWebExtensionContext?, _ extensions: Extensions) -> Bool {
        item.enabled && context != nil && extensions.unconnected.contains(item.id)
    }

    /// On and running, and macOS killed the app it talks to as Yab started
    /// it (Extensions.stoppedByMacOS).
    static func stoppedByMacOS(_ item: Installed, _ context: WKWebExtensionContext?, _ extensions: Extensions) -> Bool {
        item.enabled && context != nil && extensions.stoppedByMacOS.contains(item.id)
    }

    /// Apple's helper for iCloud Passwords runs only for a browser with
    /// Apple's web browser entitlement, or one on Apple's list; Yab has
    /// neither until Apple grants the entitlement passkeys wait on too
    /// (docs/evidence/icloud-passwords-2026-10-08.md). Signed with it, the
    /// reason is something else, and only what happened is said.
    static let waitsOnApple = !Preferences.entitledToPasskeys

    static func iCloudWaiting(_ id: String, waitsOnApple: Bool = waitsOnApple) -> Bool {
        Extensions.iCloudPasswords.contains(id) && waitsOnApple
    }

    /// iCloud Passwords left off while Yab fills Apple Passwords itself
    /// (PasswordManagers.quietAppleExtension): its page and row say so
    /// rather than show a switch that reads as broken.
    @MainActor static func replacedByYab(_ item: Installed) -> Bool {
        !item.enabled && Extensions.iCloudPasswords.contains(item.id) && PasswordManagers.appleNative
    }

    static let replacedLine = "Not needed · Yab fills Apple Passwords"

    /// Under its name in the popover its button opens instead of its popup
    /// while it waits on Apple (ExtensionWithheld); the note follows.
    static let waitingTitle = "Can't connect in Yab yet"

    /// Two lines, each whole in the name's column.
    static func stoppedLine(_ id: String, waitsOnApple: Bool = waitsOnApple) -> String {
        iCloudWaiting(id, waitsOnApple: waitsOnApple)
            ? "Can't connect in Yab yet.\nIts helper needs Apple's approval."
            : "macOS stopped the app it talks to."
    }

    static func stoppedNote(_ id: String, waitsOnApple: Bool = waitsOnApple) -> String {
        iCloudWaiting(id, waitsOnApple: waitsOnApple)
            ? "macOS stops Apple's iCloud Passwords helper as soon as Yab starts it: it runs only in browsers Apple has approved. Yab has applied, as for passkeys, and an update turns it on. Until then your iCloud passwords are in Safari and the Passwords app."
            : "macOS stopped the app on this Mac that this extension talks to as Yab started it. Yab tries again after a restart."
    }

    /// One from another Mac whose version here asks for more than it was
    /// allowed there, in the Store's words for an update that does.
    static let wantsLine = "New version asks for more"

    /// Two lines, each whole in the name's column.
    static let unconnectedLine = "Not connected to the 1Password app.\nAdd Yab in its Settings › Browser."

    /// What is wrong with it, if anything, in a sentence.
    static func trouble(_ item: Installed, _ context: WKWebExtensionContext?, _ extensions: Extensions) -> String? {
        if item.enabled, context == nil { return "It didn't start" }
        let noted = extensions.warnings(item)
        let theirs = extensions.contextErrors[item.id] ?? []
        let count = theirs.count + noted.count
        guard count > 0 else { return nil }
        let first = theirs.first ?? noted.first ?? ""
        return count == 1 ? first : "\(count) warnings. The first: \(first)"
    }

    /// The row's tip: every warning on a line of its own, the first few.
    static func warnings(_ item: Installed, _ context: WKWebExtensionContext?, _ extensions: Extensions) -> String? {
        if item.enabled, context == nil { return "It didn't start. Open it to reload it." }
        // WebKit's own, as read when they changed: never `context.errors`
        // here, at every redraw (crash #60).
        let all = (extensions.contextErrors[item.id] ?? []) + extensions.warnings(item)
        guard !all.isEmpty else { return nil }
        let shown = 4
        var lines = all.prefix(shown).map { $0 }
        if all.count > shown { lines.append("And \(all.count - shown) more on its page.") }
        return lines.joined(separator: "\n")
    }
}

/// The card an extension's page asks in: the site to block it on. Held
/// apart from the page, since the card is laid over the whole of the
/// settings, as Search's is (SiteEditing).
@available(macOS 15.4, *)
@MainActor
final class BlockEditing: ObservableObject {
    static let shared = BlockEditing()

    struct Draft: Identifiable {
        let id = UUID()
        let extensionID: String
        let name: String
        /// Adding a site it may run on, not one it may never run on.
        var allow = false
    }

    @Published private(set) var draft: Draft?

    func open(id: String, name: String, allow: Bool = false) {
        draft = Draft(extensionID: id, name: name, allow: allow)
    }

    func close() { draft = nil }
}

/// Over the settings while a site is being blocked: the page dimmed and
/// the card in the middle, as Search's card comes (SiteCardLayer).
@available(macOS 15.4, *)
struct BlockCardLayer: View {
    @ObservedObject var editing = BlockEditing.shared

    var body: some View {
        ZStack {
            if let draft = editing.draft {
                BlockCard(draft: draft) { editing.close() }
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

/// Add Site… on an extension's page, as the app's own cards ask: the
/// extension's mark in the well, the question, the field washed in ink,
/// the buttons at the foot. What can't be blocked says so in the line
/// under the question, and Block waits until there is a site.
@available(macOS 15.4, *)
private struct BlockCard: View {
    let draft: BlockEditing.Draft
    let done: () -> Void

    @State private var text = ""
    @FocusState private var typing: Bool

    private var host: String? { Extensions.host(in: text) }
    private var already: Bool {
        host.map { (draft.allow ? Extensions.here.allowed(draft.extensionID) : Extensions.here.blocked(draft.extensionID)).contains($0) } ?? false
    }
    private var valid: Bool { host != nil && !already }

    private var line: String {
        let typed = text.trimmingCharacters(in: .whitespaces)
        if already { return draft.allow ? "\(host ?? typed) is on the list already." : "\(host ?? typed) is blocked already." }
        if !typed.isEmpty, host == nil { return draft.allow ? "Type a site, like github.com." : "Type a site, like bank.com." }
        return draft.allow ? "It will run there, and on every page under it." : "It won't run there, even when you press it."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: CardFrame.wellGap) {
                let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                shape.fill(Palette.ink.opacity(0.05))
                    .overlay(shape.strokeBorder(Palette.ink.opacity(0.08), lineWidth: 0.5))
                    .overlay { ExtensionMark(id: draft.extensionID, side: 24) }
                    .frame(width: CardFrame.well, height: CardFrame.well)
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.allow ? "Let \(draft.name) run on a site" : "Block \(draft.name) on a site")
                        .font(CardFrame.title)
                        .foregroundStyle(Palette.ink)
                    Text(line)
                        .font(CardFrame.detail)
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink)
                .focused($typing)
                .modifier(CardField(hint: draft.allow ? "github.com" : "bank.com", empty: text.isEmpty, typing: typing))
                .onSubmit(save)
                .padding(.top, 12)
            HStack(spacing: 6) {
                Spacer(minLength: 8)
                // Escape works here as on every card, and says so as theirs do.
                Button(action: done) {
                    HStack(spacing: 6) {
                        Text("Cancel")
                        KeyGlyphs(keys: "esc", size: CardFrame.words, tint: nil, rest: 0.6)
                    }
                }
                .buttonStyle(.yab(.secondary, CardFrame.button))
                .fixedSize()
                Button(action: save) {
                    HStack(spacing: 6) {
                        Text(draft.allow ? "Add" : "Block")
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
        .onAppear { DispatchQueue.main.async { typing = true } }
    }

    private func save() {
        guard valid, let host else { return }
        if draft.allow { Extensions.here.allow(host, for: draft.extensionID) } else { Extensions.here.block(host, for: draft.extensionID) }
        done()
    }
}

/// One key drawn as a cap, the way a menu prints a shortcut.
struct HotkeyKeyCap: View {
    let symbol: String
    var fontSize: CGFloat = 12
    var dimmed = false
    /// A cap in a settings row, where it stands beside a line of text rather
    /// than on a surface of its own, and must not tower over it.
    var snug = false
    @Environment(\.tone) private var tone

    var body: some View {
        // The one way a key is drawn (KeyGlyphs), plate and all: a cap of
        // its own around it put a plate inside a plate.
        KeyGlyphs(keys: symbol, size: fontSize, tint: tone.map { dimmed ? Palette.faint(on: $0) : Palette.strong(on: $0) },
                  plate: tone.map { SpaceSurface.badge(on: $0) })
            .foregroundStyle(dimmed ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
    }
}

/// A whole shortcut: its modifiers and its key, side by side.
struct HotkeyCaps: View {
    let symbols: [String]
    var fontSize: CGFloat = 12
    var dimmed = false
    var snug = false

    var body: some View {
        HStack(spacing: snug ? 3 : 4) {
            ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                HotkeyKeyCap(symbol: symbol, fontSize: fontSize, dimmed: dimmed, snug: snug)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(symbols.joined(separator: " "))
    }
}

/// Keys, and the way to record others.
/// The row shows the caps bare in a table's cell, outlined under the
/// pointer, with ✕ to take them away; recording happens in a popover, where the keys being
/// held are drawn at full size as the hand presses them and a refusal has a
/// line to be written on. It stays open after the keys land, its top lit
/// green for a moment, or red for keys refused, so they can be read back
/// or pressed over.
///
/// It knows nothing of whose keys they are: it is given the keys there are
/// now, who else has a keystroke, and where to write one down, so an
/// extension's command and one of the browser's own record the same way.
///
/// At rest it is only the caps, drawn as the recorder draws them: the
/// recorder itself, its button, popover, key monitor and a dozen states
/// (LiveRecorder), is put in while the pointer is on the cell, while it
/// records, or when the bench or VoiceOver asks. A settings page is a
/// SwiftUI scroll view, and every frame it moves, whatever in a row hangs
/// on where the row is, a button's hit area, a popover's anchor, is worked
/// out again in every row, seen or not: with a recorder in each, scrolling
/// Settings › Shortcuts took 8.5 million instructions a frame, with this
/// 5.3 (./bench scroll, ./bench keys eager).
struct ShortcutRecorder: View {
    let current: Hotkey?
    let clash: (Hotkey) -> Keymap.Clash?
    let save: (Hotkey?) -> Void
    var allowPlain = false
    var lit = false
    var listen = false
    var heard: () -> Void = {}
    /// The same recorder in a card's full-width form field, not a table cell.
    var card = false
    /// The keys on a filled button of their own: for a lone row on a page, not a table's column.
    var pill = false
    var column: CGFloat = TableCell.column

    @State private var pointer = false
    @State private var recording = false
    /// VoiceOver pressed the cell at rest: the recorder, put in, listens.
    @State private var asked = false

    /// The bench: a recorder in every cell, as there used to be, to measure
    /// against (./bench keys eager on). Read as the page is next built.
    @MainActor static var eager = false

    var body: some View {
        Group {
            // Not for the pointer: rows pass under it as the page scrolls, and
            // a recorder put in each time froze the page for seconds on the
            // older design (evals/settings-opening). A press puts it in.
            if card || pill || recording || listen || asked || lit || Self.eager {
                LiveRecorder(
                    current: current, clash: clash, save: save, allowPlain: allowPlain,
                    lit: lit,
                    listen: listen || asked,
                    heard: { asked = false; heard() },
                    card: card, pill: pill, column: column, pointer: pointer,
                    busy: { recording = $0 }
                )
            } else {
                HStack(spacing: 6) {
                    if let current {
                        HotkeyCaps(symbols: current.caps, fontSize: 10, snug: true)
                    } else {
                        Text("Add Hotkey")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if current != nil && pointer {
                        Button { save(nil) } label: {
                            Symbol("xmark", size: 8, weight: .semibold) // design: a glyph the size of the caps' ink, not type
                                .foregroundStyle(.secondary)
                                .padding(2)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                    }
                }
                .modifier(TableCell(width: column, hovering: pointer))
                .onTapGesture { asked = true }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Shortcut")
                .accessibilityValue(current?.caps.joined(separator: " ") ?? "None")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { asked = true }
            }
        }
        // Watched here, not in the recorder: it stays out until pressed, and
        // keeps the cell lit while it is in.
        .onHover { pointer = $0 }
    }
}

/// The recorder itself, while it is wanted (see ShortcutRecorder).
private struct LiveRecorder: View {
    /// The keys it has now, nil for none.
    let current: Hotkey?
    /// Who else answers to a keystroke, if anyone.
    let clash: (Hotkey) -> Keymap.Clash?
    /// Writes a keystroke down, or takes the keys away with nil.
    let save: (Hotkey?) -> Void
    var allowPlain = false
    /// Drawn as if the pointer were on it, for the bench's pictures.
    var lit = false
    /// Starts listening as soon as this turns true, the bench's way in.
    var listen = false
    /// Told that it has started listening, so `listen` can be put back.
    var heard: () -> Void = {}
    var card = false
    var pill = false
    /// The width of its column: the caps or "Add Hotkey" bare in a cell
    /// that fills it (TableCell), outlined under the pointer.
    var column: CGFloat = TableCell.column
    /// The pointer on the cell, as ShortcutRecorder watches it.
    var pointer = false
    /// Told as it starts recording and as it stops.
    var busy: (Bool) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var monitor: Any?
    @State private var recording = false
    /// The modifiers held right now, so the caps follow the hand.
    @State private var held: NSEvent.ModifierFlags = []
    /// The physical modifiers, also while the attempted or saved key is
    /// shown instead of them. Letting a chord go is not starting another.
    @State private var lastModifiers: NSEvent.ModifierFlags = []
    /// What was pressed and could not be taken, kept on screen beside why.
    @State private var attempted: [String]?
    /// Keys another has, pressed once: pressed again, they are taken.
    @State private var offered: Hotkey?
    /// What was just written down, so the caps stay lit and the popover can
    /// say so instead of closing itself in the same moment.
    @State private var recorded: [String]?
    @State private var refusal: String?
    @State private var removed = false
    /// The card's top, green as a key lands, red as one is refused.
    @State private var glow: Glow?

    var body: some View {
        button
            .accessibilityLabel("Shortcut")
            .accessibilityValue(current?.caps.joined(separator: " ") ?? "None")
            .popover(isPresented: $recording, arrowEdge: .top) { sheet }
            .onChange(of: recording) { _, recording in
                guard !recording else { return }
                end()
                busy(false)
            }
            .onChange(of: listen) { _, listen in if listen, !recording { start() } }
            .onAppear { if listen, !recording { start() } }
            // Settings closed with the recorder open would otherwise leave a
            // monitor swallowing every key the app is sent.
            .onDisappear { end() }
    }

    @ViewBuilder
    private var button: some View {
        if pill {
            Button { start() } label: {
                if let current {
                    // One run of keys. A button's keys reach for its trailing
                    // edge beside words; alone here they stand in its middle.
                    KeyGlyphs(keys: current.caps.joined(), size: 10, tint: nil)
                        .environment(\.keyPlate, KeyPlate(height: ButtonSize.small.height - 2 * ButtonSize.small.keyInset, pull: 0))
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(current.caps.joined(separator: " "))
                } else {
                    Text("Add Hotkey")
                }
            }
            .buttonStyle(.yab(.secondary, .small))
        } else {
            Button { start() } label: { cell(column) }
                // A table's cell stays still when pressed, as a field does.
                .buttonStyle(.plain)
        }
    }

    /// The caps bare, or the words to click in the table's quiet gray, and
    /// ✕ at the cell's end only under the pointer.
    @ViewBuilder
    private func cell(_ width: CGFloat) -> some View {
        let lit = pointer || self.lit
        let content = HStack(spacing: 6) {
            if let current {
                HotkeyCaps(symbols: current.caps, fontSize: 10, snug: true)
            } else {
                Text(card ? "Click to record" : "Add Hotkey")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if current != nil && card {
                Text(recording ? "Listening…" : "Change")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.muted)
            }
            if current != nil && !card {
                Button { save(nil) } label: {
                    Symbol("xmark", size: 8, weight: .semibold) // design: a glyph the size of the caps' ink, not type
                        .foregroundStyle(.secondary)
                        .padding(2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .opacity(lit && !recording ? 1 : 0)
                .accessibilityLabel("Remove shortcut")
            }
        }
        if card {
            let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
            content
                .padding(.horizontal, 10)
                .frame(height: 32)
                .frame(maxWidth: .infinity)
                .background(shape.fill(Palette.ink.opacity(recording ? 0.035 : 0.06)))
                .overlay(shape.strokeBorder(Palette.ink.opacity(recording ? 0.22 : 0), lineWidth: 1))
                .contentShape(shape)
        } else {
            content.modifier(TableCell(width: width, hovering: lit, active: recording))
        }
    }

    private var sheet: some View {
        KeySheet(glow: glow, overwrite: canOverwrite ? overwrite : nil) {
            HotkeyCaps(symbols: shown, fontSize: 14, dimmed: waiting)
                .frame(height: 24)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(refusal == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(ButtonCSS.danger))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 28, alignment: .top)
        }
    }

    /// Nothing has been pressed yet: the caps stand for what is there now,
    /// or for what one looks like, and are drawn as the example they are.
    private var waiting: Bool { held.isEmpty && attempted == nil && recorded == nil }

    // Starting another chord hides the old offer, but keeps `offered` so
    // pressing that same chord again can still take it.
    private var canOverwrite: Bool { offered != nil && refusal != nil }

    private var shown: [String] {
        if let attempted { return attempted }
        if let recorded { return recorded }
        if !held.isEmpty { return Hotkey.caps(nil, held) }
        return current?.caps ?? ["⌥", "⇧", "K"]
    }

    private var caption: String {
        if let refusal { return refusal }
        if removed { return "Removed" }
        if !held.isEmpty { return "…and a key" }
        if recorded != nil || current != nil { return "Press ⌫ to delete" }
        return allowPlain ? "Press a key" : "Hold ⌘, ⌃ or ⌥ and press a key"
    }

    private func start() {
        attempted = nil
        offered = nil
        recorded = nil
        refusal = nil
        removed = false
        held = []
        lastModifiers = []
        recording = true
        // Said at once, before `heard`: the cell holds the recorder only
        // while something asks for it, and must not let it go in between.
        busy(true)
        Keymap.shared.recording = true
        Keymap.shared.said = caption
        heard()
        guard monitor == nil else { return }
        // Seen before the window and the main menu, so ⌘W is written down
        // rather than closing Settings, and nothing typed here reaches the
        // page. The window's own key monitor stands aside meanwhile
        // (Keymap.recording), whichever of the two is asked first.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(Hotkey.carried)
                let starting = !flags.subtracting(lastModifiers).isEmpty
                lastModifiers = flags
                // A hand going back to the keys is recording again, not
                // reading the answer to the last one.
                if starting {
                    recorded = nil
                    removed = false
                    refusal = nil
                    attempted = nil
                }
                held = attempted != nil || recorded != nil || removed ? [] : flags
            } else if !event.isARepeat {
                received(event)
            }
            return nil
        }
    }

    private func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        Keymap.shared.recording = false
        held = []
        lastModifiers = []
        attempted = nil
        offered = nil
        recorded = nil
        refusal = nil
        removed = false
        glow = nil
    }

    private func received(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(Hotkey.carried)
        lastModifiers = flags
        if event.keyCode == 53, flags.isEmpty { // escape
            recording = false
            return
        }
        if event.keyCode == 51, flags.isEmpty { // delete
            write(nil)
            return
        }
        if [36, 76].contains(event.keyCode), flags.isEmpty, canOverwrite { // return / keypad enter
            overwrite()
            return
        }
        guard let hotkey = Hotkey(event) else { return }
        if !allowPlain, !hotkey.commands {
            refuse(hotkey, "Hold ⌘, ⌃ or ⌥ as well.")
            return
        }
        switch clash(hotkey) {
        case .refused(let why):
            refuse(hotkey, why)
        case .taken(let why, let free):
            // The same keys again: the other lets them go.
            if offered == hotkey {
                free()
                write(hotkey)
            } else {
                refuse(hotkey, why)
                offered = hotkey
            }
        case nil:
            write(hotkey)
        }
    }

    private func overwrite() {
        guard canOverwrite, let hotkey = offered else { return }
        // The popover may have stayed open while an owner changed. Ask
        // again before freeing keys so a new refusal still protects them.
        switch clash(hotkey) {
        case .refused(let why): refuse(hotkey, why)
        case .taken(_, let free):
            free()
            write(hotkey)
        case nil: write(hotkey)
        }
    }

    private func refuse(_ hotkey: Hotkey, _ why: String) {
        attempted = hotkey.caps
        refusal = why
        offered = nil
        held = []
        Keymap.shared.said = why
        light($glow, .bad, reduceMotion: reduceMotion)
    }

    private func write(_ hotkey: Hotkey?) {
        save(hotkey)
        attempted = nil
        offered = nil
        refusal = nil
        held = []
        guard recording else { return }
        recorded = hotkey?.caps
        removed = hotkey == nil
        Keymap.shared.said = hotkey.map { "Recorded \($0.text)" } ?? "Removed"
        guard hotkey != nil else { return }
        light($glow, .good, reduceMotion: reduceMotion)
    }
}

extension ShortcutRecorder {
    /// An extension's command: its keys kept by Extensions, where WebKit
    /// looks for them.
    @available(macOS 15.4, *)
    static func command(_ command: WKWebExtension.Command, _ extensions: Extensions) -> ShortcutRecorder {
        ShortcutRecorder(
            current: command.activationKey.map { Hotkey($0, command.modifierFlags) },
            clash: { Keymap.shared.clash($0, for: nil, command: command) },
            save: { extensions.setKey($0?.key, $0?.flags ?? [], for: command) }
        )
    }
}

/// On an extension's page in the Chrome Web Store, the offer to add it,
/// where the store's own button only says "Switch to Chrome". The page's
/// own "Add to Yab" is the way in (StoreRelay); only where a store that has
/// changed its markup leaves no room for it does the corner offer it, once
/// for each extension, with Add on it.
struct StoreOffer: View {
    @ObservedObject var browser: Browser

    var body: some View {
        if #available(macOS 15.4, *), let tab = browser.active {
            if tab.engineKind == .chromium {
                ChromiumStoreOffer(browser: browser, tab: tab, native: .of(browser))
            } else {
                Watch(browser: browser, tab: tab, extensions: .shared)
            }
        }
    }

    /// The extensions offered in the corner this run.
    @MainActor static var offered: Set<String> = []

    @available(macOS 15.4, *)
    private struct Watch: View {
        let browser: Browser
        @ObservedObject var tab: Tab
        @ObservedObject var extensions: Extensions

        /// The extension this page is about, while the page's own button
        /// isn't in place and it isn't installed.
        private var wanted: String? {
            guard let url = tab.address, StoreOffer.isStorePage(url), let id = Crx.id(in: url.absoluteString),
                  tab.storePlaced != id, !extensions.installed.contains(where: { $0.id == id }) else { return nil }
            return id
        }

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .task(id: wanted) {
                    guard let id = wanted, !StoreOffer.offered.contains(id) else { return }
                    // A moment for the page's own button to be put in.
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled, wanted == id, StoreOffer.offered.insert(id).inserted else { return }
                    browser.toaster.pop("Install in Yab", mark: "puzzlepiece.extension",
                                        undo: { [extensions] in extensions.install(from: id) }, act: "Add")
                }
        }
    }

    static func isStorePage(_ url: URL) -> Bool {
        let host = url.host()?.lowercased() ?? ""
        return host == "chromewebstore.google.com"
            || (host == "chrome.google.com" && url.path.hasPrefix("/webstore"))
    }
}
