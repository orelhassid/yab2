import SwiftUI

struct ProfileSettings: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    @State private var editor: Editor?

    private enum Editor: Identifiable {
        case edit(BrowserProfile)
        case delete(BrowserProfile)

        var id: UUID {
            switch self {
            case .edit(let profile), .delete(let profile): return profile.id
            }
        }
    }

    var body: some View {
        let current = browser.currentProfileSpace
        let profiles = browser.browserProfiles
        Section("Current profile") {
            ProfileSettingsIdentity(profile: current.profileID, name: browser.activeProfileName)
                .id(current.profileID)
                .sheet(item: $editor) { editor in
                    switch editor {
                    case .edit(let profile): ProfileNameSheet(profile: profile)
                    case .delete(let profile): ProfileDeletionSheet(browser: browser, profile: profile)
                    }
                }
            SettingsRow("Current Space") { Text(current.name).foregroundStyle(.secondary) }
            if !browser.inMail {
                GoogleProfileRow(browser: browser, profile: current.profileID)
                    .settingsAnchor("profile-google")
            }
        }

        Section("Profiles") {
            ForEach(profiles) { profile in
                if profile.id == profiles.first?.id {
                    row(profile, current: current.profileID).settingsAnchor("manage-profiles")
                } else {
                    row(profile, current: current.profileID)
                }
            }
        }
    }

    private func row(_ profile: BrowserProfile, current: UUID) -> some View {
        let name = identities[profile.id].title(fallback: profile.fallbackName)
        let spaces = profile.spaces.map(\.name).joined(separator: ", ")
        return HStack(spacing: CardFrame.inset) {
            ProfilePicture(profile: profile.id, size: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).lineLimit(1)
                Text(spaces).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                    .accessibilityLabel("Spaces: " + spaces)
            }
            Spacer()
            if profile.id == current {
                Text("Current").foregroundStyle(.secondary)
            } else if browser.prefs.usesSpaces, let space = profile.spaces.first {
                Button("Switch") { browser.switchSpace(to: space.id) }
                    .settingsButton().accessibilityLabel("Switch to " + name)
            }
            Button("Edit…") { editor = .edit(profile) }
                .settingsButton().accessibilityLabel("Edit " + name)
            Button("Delete…") { editor = .delete(profile) }
                .settingsButton().accessibilityLabel("Delete " + name)
                .disabled(browser.browserProfiles.count < 2)
                .keyTip(browser.browserProfiles.count < 2 ? "Keep at least one profile" : "Delete " + name)
        }
    }
}

private struct GoogleProfileRow: View {
    @ObservedObject var browser: Browser
    let profile: UUID
    @ObservedObject private var signIn = GoogleProfileSignIn.shared
    @ObservedObject private var identities = BrowserProfileIdentities.shared

    var body: some View {
        HStack(spacing: CardFrame.inset) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Google Account")
                if !detail.isEmpty { Text(detail).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            actions
        }
    }

    @ViewBuilder private var actions: some View {
        switch signIn.phases[profile] {
        case .checking, .signingIn:
            Button("Cancel") { signIn.cancel(profile) }.settingsButton()
        case .choose(let accounts):
            Picker("Choose Account", selection: Binding(
                get: { "" },
                set: { signIn.select($0, for: profile) }
            )) {
                Text("Choose Account").tag("")
                ForEach(accounts) { account in Text(account.email).tag(account.email) }
            }
            .labelsHidden().fixedSize()
            Button("Cancel") { signIn.cancel(profile) }.settingsButton()
        case .failed, nil:
            if identities[profile].google != nil {
                Button("Unlink") {
                    signIn.cancel(profile)
                    identities.link(nil, to: profile)
                }.settingsButton()
                Button("Update") { signIn.start(in: browser) }.settingsButton()
            } else {
                Button("Sign in with Google") { signIn.start(in: browser) }.settingsButton()
            }
        }
    }

    private var detail: String {
        switch signIn.phases[profile] {
        case .checking: return "Checking this profile’s Google session…"
        case .signingIn: return "Finish signing in on the Google tab."
        case .failed: return "Google sign-in couldn’t be confirmed. Try again."
        case .choose, nil: return identities[profile].google?.email ?? ""
        }
    }
}

private struct ProfileNameSheet: View {
    let profile: BrowserProfile
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    @State private var name: String
    @State private var picture: String
    @State private var originalName: String
    @State private var originalPicture: String

    init(profile: BrowserProfile) {
        self.profile = profile
        let name = BrowserProfileIdentities.shared[profile.id].name ?? ""
        let mark = Store.settings.string(forKey: profilePictureKey(profile.id)) ?? ""
        _originalName = State(initialValue: name)
        _originalPicture = State(initialValue: mark)
        _name = State(initialValue: name)
        _picture = State(initialValue: mark)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardFrame.inset) {
            Text("Edit Profile").font(.headline)
            ProfileSettingsIdentity(profile: profile.id, name: identities[profile.id].title(fallback: profile.fallbackName), draft: $picture)
            TextField("Profile Name", text: $name, prompt: Text(automaticName))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
                Button("Save") {
                    if Spaces.read().contains(where: { $0.profileID == profile.id }) {
                        if name != originalName { identities.rename(profile.id, to: name) }
                        if picture != originalPicture { Store.settings.set(picture, forKey: profilePictureKey(profile.id)) }
                    }
                    dismiss()
                }.settingsButton(.primary).keyboardShortcut(.defaultAction)
            }
        }.padding(CardFrame.inset).frame(width: 400)
    }

    private var automaticName: String {
        var automatic = identities[profile.id]
        automatic.name = nil
        return automatic.title(fallback: profile.fallbackName)
    }
}

private struct ProfileDeletionSheet: View {
    @ObservedObject var browser: Browser
    let profile: BrowserProfile
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    @State private var destinations: [UUID: UUID] = [:]
    @State private var failed = false

    private var members: [Space] { browser.spaces.filter { $0.profileID == profile.id } }
    private var choices: [BrowserProfile] { browser.browserProfiles.filter { $0.id != profile.id } }
    private var canDelete: Bool {
        !members.isEmpty && members.allSatisfy { space in
            choices.contains { $0.id == destinations[space.id] }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardFrame.inset) {
            Text("Delete “\(identities[profile.id].title(fallback: profile.fallbackName))”?").font(.headline)
            Text(profile.id == Space.firstID
                 ? "Choose where each Space should go. Tabs and folders stay in their Spaces. Yab keeps its shared website data."
                 : "Choose where each Space should go. Tabs and folders stay in their Spaces. This profile’s website data, sign-ins and extensions will be removed.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ThreadScrollView {
                VStack(alignment: .leading, spacing: CardFrame.inset) {
                    ForEach(members) { space in
                        SettingsRow(verbatim: space.name) {
                            Picker("Destination for " + space.name, selection: destination(for: space)) {
                                Text("Choose Profile").tag(UUID?.none)
                                ForEach(choices) { choice in
                                    Text(identities[choice.id].title(fallback: choice.fallbackName)).tag(Optional(choice.id))
                                }
                            }.labelsHidden().frame(width: SignIns.pickerWidth)
                        }
                    }
                }
            }.frame(height: min(CGFloat(members.count) * 38, 220))
            if failed { Text("The profile couldn’t be deleted. Check the destinations and try again.").foregroundStyle(.secondary) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.settingsButton().keyboardShortcut(.cancelAction)
                Button("Delete Profile", role: .destructive) {
                    let assigning = destinations.filter { entry in members.contains { $0.id == entry.key } }
                    if browser.deleteBrowserProfile(profile.id, reassigning: assigning) { dismiss() }
                    else { failed = true }
                }.settingsButton(.danger).disabled(!canDelete)
            }
        }
        .padding(CardFrame.inset).frame(width: 500)
        .onAppear {
            if choices.count == 1, let choice = choices.first {
                destinations = Dictionary(uniqueKeysWithValues: members.map { ($0.id, choice.id) })
            }
        }
    }

    private func destination(for space: Space) -> Binding<UUID?> {
        Binding(get: { destinations[space.id] }, set: { destinations[space.id] = $0 })
    }
}
