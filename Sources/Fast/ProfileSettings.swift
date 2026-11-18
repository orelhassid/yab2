import SwiftUI

struct ProfileSettings: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    var body: some View {
        let current = browser.currentProfileSpace
        let profiles = browser.browserProfiles
        Section("Current profile") {
            if let profile = profiles.first(where: { $0.id == current.profileID }) {
                HStack(spacing: CardFrame.inset) {
                    ProfilePicture(profile: profile.id, size: 36)
                    Text(browser.activeProfileName).font(.headline)
                    Spacer()
                    ProfileEditButton(browser: browser, profile: profile, name: browser.activeProfileName)
                }.id(profile.id)
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
            }
            ProfileRowActions(browser: browser, profile: profile, name: name, current: current)
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

private struct ProfileRowActions: View {
    @ObservedObject var browser: Browser
    let profile: BrowserProfile
    let name: String
    let current: UUID
    @State private var deleting = false

    var body: some View {
        let canDelete = browser.browserProfiles.count > 1
        HStack(spacing: 4) {
            if profile.id != current, browser.prefs.usesSpaces, let space = profile.spaces.first {
                ProfileIconButton(icon: "arrow.up.right", title: "Switch to " + name) {
                    browser.switchSpace(to: space.id)
                }.accessibilityIdentifier("profile-open")
            }
            ProfileEditButton(browser: browser, profile: profile, name: name)
            ProfileIconButton(icon: "trash", title: "Delete " + name,
                              tip: canDelete ? nil : "Keep at least one profile") { deleting = true }
                .accessibilityIdentifier("profile-delete")
                .disabled(!canDelete)
                .popover(isPresented: $deleting, arrowEdge: .bottom) {
                    ProfileDeletionPopover(browser: browser, profile: profile)
                }
        }
    }
}

private struct ProfileIconButton: View {
    let icon: String
    let title: String
    var tip: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) { Symbol(icon, size: 12) }
            .buttonStyle(.yab(.quiet, .small, icon: .square))
            .accessibilityLabel(Text(verbatim: title))
            .keyTip(tip ?? title)
    }
}

private struct ProfileEditButton: View {
    let browser: Browser
    let profile: BrowserProfile
    let name: String
    @State private var editing = false

    var body: some View {
        ProfileIconButton(icon: "pencil", title: "Edit " + name) { editing = true }
            .accessibilityIdentifier("profile-edit")
            .popover(isPresented: $editing, arrowEdge: .bottom) {
                ProfileCustomizer(session: ProfileCustomizeSession(browser: browser, profile: profile)) { editing = false }
            }
    }
}

private struct ProfileCustomizer: View {
    @StateObject var session: ProfileCustomizeSession
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    let close: () -> Void

    var body: some View {
        let profile = session.profile
        IconPicker(mark: session.picture.isEmpty ? nil : session.picture, pick: session.mark, close: close,
                   cancel: { session.cancel(); close() },
                   chooseImage: { session.chooseImage(close: close) },
                   profile: (profile.id, identities[profile.id].title(fallback: profile.fallbackName)),
                   rename: session.rename)
            .onDisappear { session.finish() }
    }
}

@MainActor
private final class ProfileCustomizeSession: ObservableObject {
    let profile: BrowserProfile
    private weak var browser: Browser?
    @Published private(set) var picture: String
    private let openingPicture: String
    private var choosingImage = false
    private var finished = false

    init(browser: Browser, profile: BrowserProfile) {
        self.browser = browser
        self.profile = profile
        openingPicture = Store.settings.string(forKey: profilePictureKey(profile.id)) ?? ""
        picture = openingPicture
    }

    private var exists: Bool {
        browser?.spaces.contains(where: { $0.profileID == profile.id }) == true
    }

    func rename(_ name: String) {
        guard exists else { return }
        let identities = BrowserProfileIdentities.shared
        let id = profile.id
        let before = identities[id].name
        identities.rename(id, to: name)
        let after = identities[id].name
        guard before != after else { return }
        browser?.did { [weak browser] in
            guard browser?.spaces.contains(where: { $0.profileID == id }) == true,
                  identities[id].name == after else { return }
            identities.rename(id, to: before ?? "")
        }
    }

    func mark(_ picked: String?) {
        guard exists else { return }
        picture = picked ?? ""
        Store.settings.set(picture, forKey: profilePictureKey(profile.id))
    }

    func chooseImage(close: () -> Void) {
        choosingImage = true
        close()
        CustomMarks.chooseImage { image in
            if let image { self.mark(image) }
            self.choosingImage = false
            self.finish()
        }
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        if picture != openingPicture { mark(openingPicture) }
    }

    func finish() {
        guard !finished, !choosingImage else { return }
        finished = true
        guard picture != openingPicture else { return }
        let id = profile.id
        let before = openingPicture, after = picture, key = profilePictureKey(id)
        browser?.did { [weak browser] in
            guard browser?.spaces.contains(where: { $0.profileID == id }) == true,
                  Store.settings.string(forKey: key) == after else { return }
            Store.settings.set(before, forKey: key)
        }
    }
}

private struct ProfileDeletionPopover: View {
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
