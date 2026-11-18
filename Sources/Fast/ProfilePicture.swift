import SwiftUI

func profilePictureKey(_ profile: UUID) -> String { "profile.picture." + profile.uuidString }

struct ProfilePicture: View {
    @AppStorage private var mark: String
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    let profile: UUID
    let size: CGFloat
    private let previewMark: String?

    init(profile: UUID, size: CGFloat, previewMark: String? = nil) {
        _mark = AppStorage(wrappedValue: "", profilePictureKey(profile), store: Store.settings)
        self.profile = profile
        self.size = size
        self.previewMark = previewMark
    }

    var body: some View {
        let mark = previewMark ?? mark
        Group {
            if let image = CustomMarks.image(mark) {
                Image(nsImage: image).resizable().scaledToFit()
                    .padding(mark.hasPrefix("image:") ? 0 : size * 0.12)
                    .background(.quaternary)
            } else if let photo = identities[profile].google?.picture {
                AsyncImage(url: photo) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() }
                    else { fallback }
                }
            } else {
                fallback
            }
        }.frame(width: size, height: size).clipShape(Circle()).accessibilityHidden(true)
    }

    private var fallback: some View {
        Image(systemName: "person.crop.circle.fill").resizable().scaledToFit()
    }
}

struct ProfileSettingsIdentity: View {
    let profile: UUID
    let name: String
    var draft: Binding<String>?
    @State private var editing = false

    var body: some View {
        HStack(spacing: CardFrame.inset) {
            ProfilePicture(profile: profile, size: 36, previewMark: draft?.wrappedValue)
            Text(name).font(.headline)
            Spacer()
            Button("Change Picture…") { editing = true }
                .settingsButton()
                .popover(isPresented: $editing) {
                    ProfilePicturePicker(profile: profile, draft: draft) { editing = false }
                }
        }
    }
}

struct ProfileSwitcher: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    let close: () -> Void
    @State private var editing = false

    private var profiles: [Space] {
        guard browser.windowPurpose == .normal, !browser.blank, browser.prefs.usesSpaces else { return [browser.currentProfileSpace] }
        var seen = Set<UUID>()
        return ([browser.currentProfileSpace] + browser.turnOrder.filter { $0.id != Space.mailID }).filter { seen.insert($0.profileID).inserted }
    }

    var body: some View {
        if editing {
            ProfilePicturePicker(profile: browser.currentProfileSpace.profileID) { editing = false }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: CardFrame.inset) {
                    ProfilePicture(profile: browser.currentProfileSpace.profileID, size: 38)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(browser.activeProfileName).font(.headline)
                        Text(browser.currentProfileSpace.name).foregroundStyle(.secondary)
                    }.lineLimit(1)
                }.padding(CardFrame.inset)
                Divider()
                let choices = profiles
                if choices.count > 1 {
                    Text("Switch Profile").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, CardFrame.inset).padding(.top, 8)
                    ThreadScrollView {
                        VStack(spacing: 0) {
                            ForEach(choices) { space in
                                let current = space.profileID == browser.currentProfileSpace.profileID
                                TrailMenuRow(title: browser.profileName(for: space), selected: current, action: {
                                    close()
                                    if !current { browser.switchSpace(to: space.id) }
                                }) { ProfilePicture(profile: space.profileID, size: 22) }
                            }
                        }
                    }.frame(height: min(CGFloat(choices.count), 5) * SideBar.row)
                    Divider()
                }
                TrailMenuRow(title: "Change Picture…", action: { editing = true }) { Symbol("photo", size: 16) }
                TrailMenuRow(title: Command.tabOverview.title, action: {
                    close()
                    browser.showLibrary(.tabs)
                }) { Symbol(LibraryPage.tabs.icon, size: 16) }
                if Command.manageProfiles.available(in: browser) {
                    TrailMenuRow(title: Command.manageProfiles.title, action: {
                        close()
                        Command.manageProfiles.run(in: browser)
                    }) { Symbol(Command.manageProfiles.symbol, size: 16) }
                }
                TrailMenuRow(title: Command.settings.title, action: {
                    close()
                    SettingsWindow.shared.show(for: browser)
                }) { Symbol("gearshape", size: 16) }
            }.padding(6).frame(width: 260)
        }
    }
}

struct TrailMenuRow<Icon: View>: View {
    let title: String
    var selected = false
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            SidebarTabRow {
                icon().frame(width: 24)
                Text(title).lineLimit(1)
                Spacer()
                if selected { Symbol("checkmark", size: 12) }
            }
            .background {
                if hovered || selected { SelectionPlate(corner: SideBar.radius, state: selected ? .selected : .hover) }
            }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ProfilePicturePicker: View {
    let profile: UUID
    let back: () -> Void
    @AppStorage private var mark: String
    private let draft: Binding<String>?

    init(profile: UUID, draft: Binding<String>? = nil, back: @escaping () -> Void) {
        self.profile = profile
        self.back = back
        self.draft = draft
        _mark = AppStorage(wrappedValue: "", profilePictureKey(profile), store: Store.settings)
    }

    var body: some View {
        let selection = draft ?? $mark
        let mark = selection.wrappedValue
        VStack(spacing: 0) {
            HStack {
                Button(action: back) { Symbol("chevron.left", size: 14) }
                    .buttonStyle(.plain).accessibilityLabel("Back")
                Text("Profile Picture").font(.headline)
                Spacer()
            }.padding(CardFrame.inset)
            Divider()
            ProfilePicture(profile: profile, size: 52, previewMark: mark).padding(8)
            Button {
                CustomMarks.chooseImage { image in
                    if let image { selection.wrappedValue = image }
                }
            } label: { Label("Choose Image…", systemImage: "photo").frame(maxWidth: .infinity) }
            .buttonStyle(.yab(.secondary, .regular)).padding(.horizontal, CardFrame.inset)
            IconPicker(mark: mark.isEmpty ? nil : mark, pick: { selection.wrappedValue = $0 ?? "" }, close: back,
                       profilePicture: true)
            Divider()
            Button("Reset to Default") { selection.wrappedValue = "" }
                .buttonStyle(.yab(.quiet, .small)).disabled(mark.isEmpty).padding(6)
        }.frame(width: 280)
    }
}
