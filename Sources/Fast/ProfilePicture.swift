import SwiftUI

func profilePictureKey(_ profile: UUID) -> String { "profile.picture." + profile.uuidString }

struct ProfilePicture: View {
    @AppStorage private var mark: String
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    let profile: UUID
    let size: CGFloat

    init(profile: UUID, size: CGFloat) {
        _mark = AppStorage(wrappedValue: "", profilePictureKey(profile), store: Store.settings)
        self.profile = profile
        self.size = size
    }

    var body: some View {
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

struct ProfileSwitcher: View {
    @ObservedObject var browser: Browser
    @ObservedObject var popover: ProfilePopover
    @ObservedObject private var identities = BrowserProfileIdentities.shared
    @Environment(\.accessibilityReduceTransparency) private var solid
    @Environment(\.tone) private var tone

    static let width: CGFloat = 260
    private static let pad = CardFrame.rows
    private static let headerHeight = SideBar.row + 2 * pad
    private static let labelHeight = SideBar.mark + pad
    private static let dividerHeight = 1 + pad
    private static let avatarSize: CGFloat = 22

    static func fixedHeight(hasChoices: Bool) -> CGFloat {
        2 * pad + headerHeight + 2 * SideBar.row + dividerHeight
            + (hasChoices ? labelHeight + dividerHeight : 0)
    }

    static func height(for count: Int) -> CGFloat {
        fixedHeight(hasChoices: count > 0) + CGFloat(min(5, count)) * SideBar.row
    }

    var body: some View {
        if let placement = popover.placement {
            let choices = popover.choices
            let available = max(0, placement.bodySize.height - Self.fixedHeight(hasChoices: !choices.isEmpty))
            let outline = ProfilePopoverOutline(placement: placement)
            VStack(alignment: .leading, spacing: 0) {
                header
                rule
                if !choices.isEmpty {
                    Text("Switch Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, SideBar.inner)
                        .frame(height: Self.labelHeight, alignment: .topLeading)
                        .accessibilityAddTraits(.isHeader)
                    profiles(choices, height: available)
                    rule
                }
                action(.tabs, Command.tabOverview.title, icon: LibraryPage.tabs.icon)
                action(.settings, Command.settings.title, icon: "gearshape")
            }
            .padding(Self.pad)
            .frame(width: placement.bodySize.width, height: placement.bodySize.height, alignment: .topLeading)
            .padding(placement.insets)
            .background {
                if solid { outline.fill(tone?.color ?? Palette.ground) } // design: the material's accessible fallback covers the entire pointer
                else {
                    outline.fill(.regularMaterial)
                    if let tone { outline.fill(tone.color.opacity(0.75)) }
                }
            }
            .foregroundStyle(Palette.strong(on: tone))
            .overlay { outline.stroke(tone.map { Color(nsColor: SpaceSurface.rim(on: $0)) } ?? Palette.hairline, lineWidth: 1).allowsHitTesting(false) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Profile Switcher")
        }
    }

    private var header: some View {
        let current = browser.currentProfileSpace
        return TrailMenuItem(height: Self.headerHeight, focused: popover.focused == .header,
                             action: { popover.choose(.header) }) {
            ProfilePicture(profile: current.profileID, size: Self.avatarSize)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(browser.activeProfileName).font(.headline)
                Text(current.name).font(.subheadline).foregroundStyle(.secondary)
            }.lineLimit(1)
        }
        .accessibilityHint("Opens Profile Settings")
    }

    private var rule: some View {
        Divider().frame(height: 1).padding(.vertical, Self.pad / 2)
    }

    @ViewBuilder private func profiles(_ choices: [Space], height: CGFloat) -> some View {
        if height < CGFloat(choices.count) * SideBar.row {
            ScrollViewReader { reader in
                ThreadScrollView(showsIndicators: false) {
                    profileRows(choices)
                }
                .frame(height: height)
                .onChange(of: popover.focused) { _, item in
                    if let item, case .profile = item { reader.scrollTo(item) }
                }
            }
        } else {
            profileRows(choices)
        }
    }

    private func profileRows(_ choices: [Space]) -> some View {
        VStack(spacing: 0) {
            ForEach(choices) { space in
                let item = ProfilePopover.Item.profile(space.id)
                TrailMenuRow(title: browser.profileName(for: space),
                             selected: space.profileID == browser.currentProfileSpace.profileID,
                             focused: popover.focused == item, action: { popover.choose(item) }) {
                    ProfilePicture(profile: space.profileID, size: Self.avatarSize)
                }.id(item)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func action(_ item: ProfilePopover.Item, _ title: String, icon: String) -> some View {
        TrailMenuRow(title: title, focused: popover.focused == item, action: { popover.choose(item) }) {
            Symbol(icon, size: SideBar.mark)
        }
    }
}

struct TrailMenuRow<Icon: View>: View {
    let title: String
    var selected = false
    var focused = false
    var lastActivity: Date?
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon

    var body: some View {
        TrailMenuItem(selected: selected, focused: focused, action: action, icon: icon) {
            Text(title).lineLimit(1)
            if let lastActivity {
                Spacer(minLength: 4)
                Text(lastActivity, format: .relative(presentation: .named))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct TrailMenuItem<Icon: View, Label: View>: View {
    var height = SideBar.row
    var selected = false
    var focused = false
    let action: () -> Void
    @ViewBuilder var icon: () -> Icon
    @ViewBuilder var label: () -> Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: SideBar.markGap) {
                icon().frame(width: 24)
                label()
                Spacer(minLength: 0)
                if selected { Symbol("checkmark", size: SideBar.mark).accessibilityHidden(true) }
            }
            .padding(.horizontal, SideBar.inner)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if hovered || focused || selected {
                    SelectionPlate(corner: SideBar.radius, state: selected ? .selected : .hover)
                }
            }
            .overlay {
                if focused {
                    RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous)
                        .strokeBorder(.primary.opacity(0.32), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(TrailMenuPress())
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct TrailMenuPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.overlay {
            if configuration.isPressed {
                RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous)
                    .fill(.primary.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
    }
}
