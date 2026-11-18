import Combine
import Foundation

/// A profile is the sign-in store shared by one or more Spaces.
struct BrowserProfile: Identifiable {
    let id: UUID
    let spaces: [Space]

    var fallbackName: String {
        if id == Space.firstID { return "Default Profile" }
        let owner = spaces.first { $0.id == id } ?? spaces[0]
        return owner.signedInAs ?? spaces.compactMap(\.signedInAs).first ?? owner.name
    }

    static func listed(in spaces: [Space]) -> [Self] {
        let members = Dictionary(grouping: spaces, by: \.profileID)
        var seen = Set<UUID>()
        return spaces.compactMap { space in
            guard seen.insert(space.profileID).inserted, let group = members[space.profileID] else { return nil }
            return Self(id: space.profileID, spaces: group)
        }
    }

    /// Every affected Space must have a destination that will survive the deletion.
    static func reassigning(_ id: UUID, to destinations: [UUID: UUID], in spaces: [Space]) -> [Space]? {
        let members = spaces.filter { $0.profileID == id }
        let surviving = Set(spaces.map(\.profileID)).subtracting([id])
        guard !members.isEmpty, Set(destinations.keys) == Set(members.map(\.id)),
              destinations.values.allSatisfy(surviving.contains) else { return nil }
        return spaces.map { space in
            guard let target = destinations[space.id] else { return space }
            var moved = space
            moved.ownSignIns = target != Space.firstID
            moved.signInWith = moved.ownSignIns && target != moved.id ? target : nil
            moved.signedInAs = nil
            return moved
        }
    }
}

@MainActor
final class BrowserProfileIdentities: ObservableObject {
    static let shared = BrowserProfileIdentities()
    static let nameChanged = Notification.Name("yab.browser-profile.name-changed")

    struct Google: Codable, Equatable, Identifiable {
        let email: String
        let name: String
        let photo: URL?
        var id: String { email }

        init(email: String, name: String, photo: URL?) {
            self.email = email
            self.name = name
            self.photo = photo
        }

        var picture: URL? {
            guard let photo, photo.scheme == "https", let host = photo.host(),
                  host.hasSuffix(".googleusercontent.com") else { return nil }
            return photo
        }
    }

    struct Identity: Codable, Equatable {
        var name: String?
        var google: Google?

        func title(fallback: String) -> String {
            if let name { return name }
            if let google { return google.name.isEmpty ? google.email : google.name }
            return fallback
        }
    }

    private static let key = "browser.profile-identities"
    @Published private var values: [UUID: Identity]
    private let settings: UserDefaults

    init(settings: UserDefaults = Store.settings) {
        self.settings = settings
        values = settings.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([UUID: Identity].self, from: $0) } ?? [:]
    }

    subscript(id: UUID) -> Identity { values[id] ?? Identity() }

    func rename(_ id: UUID, to name: String) {
        var identity = self[id]
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let next = cleaned.isEmpty ? nil : cleaned
        guard identity.name != next else { return }
        identity.name = next
        save(identity, for: id)
        NotificationCenter.default.post(name: Self.nameChanged, object: id)
    }

    func link(_ google: Google?, to id: UUID) {
        var identity = self[id]
        identity.google = google
        save(identity, for: id)
    }

    func remove(_ id: UUID) {
        save(Identity(), for: id)
        settings.removeObject(forKey: profilePictureKey(id))
    }

    private func save(_ identity: Identity, for id: UUID) {
        values[id] = identity == Identity() ? nil : identity
        settings.set(try? JSONEncoder().encode(values), forKey: Self.key)
    }
}

extension Browser {
    var canManageProfiles: Bool { windowPurpose == .normal && !blank && !privateBrowsing && fieldGuest == nil }

    var currentProfileSpace: Space {
        inMail ? (spaces.first { $0.id == homeSpaceID } ?? space) : space
    }

    var browserProfiles: [BrowserProfile] { BrowserProfile.listed(in: spaces) }

    func profileName(for space: Space) -> String {
        let profile = browserProfiles.first { $0.id == space.profileID }
        return BrowserProfileIdentities.shared[space.profileID].title(fallback: profile?.fallbackName ?? space.name)
    }

    var activeProfileName: String { profileName(for: currentProfileSpace) }

    @discardableResult
    func deleteBrowserProfile(_ id: UUID, reassigning destinations: [UUID: UUID]) -> Bool {
        guard canManageProfiles,
              let moved = BrowserProfile.reassigning(id, to: destinations, in: Spaces.read()),
              Spaces.write(moved) else { return false }
        GoogleProfileSignIn.shared.cancel(id)
        // The default store is also used by Mail and app-wide tabs.
        if id == Space.firstID { BrowserProfileIdentities.shared.remove(id) }
        else { Spaces.erase(id) }
        return true
    }
}
