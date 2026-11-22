import AppKit
import WebKit
import YabCoreClient

/// WebKit gives unrelated private tabs distinct nonpersistent stores. CEF must
/// use that same boundary; a space UUID would leak one private tab into another.
@MainActor
enum ChromiumPrivateProfiles {
    private final class Owner { weak var tab: Tab?; init(_ tab: Tab) { self.tab = tab } }
    private final class Identity {
        let profile = "private-" + UUID().uuidString
        var owners: [UUID: Owner] = [:]
    }
    private static let sessions = NSHashTable<WKWebsiteDataStore>.weakObjects()
    private static let stores = NSMapTable<WKWebsiteDataStore, Identity>.weakToStrongObjects()

    /// The space profile a private profile is the off-the-record side of,
    /// chosen as it is made: its first tab's space, when "Allow in private
    /// tabs" is on then. The space's extensions allowed in private tabs run
    /// there (CEF 0092), and nothing is written to the space. Off, it stands
    /// alone as before; the switch applies to new private tabs.
    struct Space { let profile: String; let store: WKWebsiteDataStore }
    private static var spaces: [String: Space] = [:]
    /// Private profiles the helper opened as their space's side.
    private static var sided: Set<String> = []

    /// "Allow in private tabs", as stored.
    static var extensionsAllowed: Bool { Store.settings.bool(forKey: "extensions.private") }

    static func authorize(_ profile: String, store: WKWebsiteDataStore, privateMode: Bool) throws {
        if !privateMode { try ChromiumPersistentProfiles.authorize(profile, store: store); return }
        guard !store.isPersistent, let identity = stores.object(forKey: store), identity.profile == profile,
              identity.owners.values.contains(where: { $0.tab?.gone == false }) else {
            throw ChromiumPersistentProfiles.Refused.unverifiedAssociation
        }
    }

    static func profile(for tab: Tab) -> String {
        let store = tab.pageStore
        precondition(tab.shy || !store.isPersistent)
        let known = stores.object(forKey: store)
        let value = known ?? Identity()
        if known == nil, !sessions.contains(store), extensionsAllowed, let browser = tab.delegate as? Browser {
            let id = browser.spaceHolding(tab) ?? browser.spaceID
            let space = Spaces.store(for: id)
            if space.isPersistent {
                spaces[value.profile] = Space(profile: ChromiumPersistentProfiles.profile(store: space, placement: id), store: space)
            }
        }
        value.owners = value.owners.filter { $0.value.tab?.gone == false }
        value.owners[tab.id] = Owner(tab)
        stores.setObject(value, forKey: store)
        return value.profile
    }

    /// For the bench: what was chosen for a private profile and what the helper did.
    static func benchState(_ profile: String) -> [String: Any] {
        ["chosen": spaces[profile]?.profile ?? "", "sided": sided.contains(profile), "allowed": extensionsAllowed,
         "lastOpen": lastOpen[profile] ?? ""]
    }
    private static var lastOpen: [String: String] = [:]

    /// The space a private profile is the side of, once the helper opened it so.
    static func space(of profile: String) -> Space? {
        sided.contains(profile) ? spaces[profile] : nil
    }

    /// Opens a site profile in the helper: a private one made with a space
    /// as that space profile's off-the-record side, the space opened first,
    /// when this helper can (nativeHooks "privateExtensions"); else alone.
    static func open(_ profile: String, privateMode: Bool, core: YabCoreClient) async throws {
        // A bool, or 1 from a helper that boxed the macro as a number.
        let advertised = await core.nativeHooks["privateExtensions"]
        let capable = advertised == .bool(true) || advertised == .number(1)
        guard privateMode, let space = spaces[profile], capable else {
            if privateMode { lastOpen[profile] = spaces[profile] == nil ? "alone: no space chosen" : "alone: helper lacks privateExtensions" }
            try await core.openProfile(profile, privateMode: privateMode)
            return
        }
        do {
            try ChromiumPersistentProfiles.authorize(space.profile, store: space.store)
            try await core.openProfile(space.profile)
            await ChromiumPermissions.opened(space.profile, core: core)
            await ChromiumClearingDebt.settle(space.profile, core: core)
        } catch {
            // Private browsing never waits on the space: this one stands
            // alone from now on, as with the switch off.
            DebugLog.note("private-profile", ["profile": profile, "error": "Space profile did not open: \(error)"])
            lastOpen[profile] = "alone: space did not open: \(error)"
            spaces[profile] = nil
            try await core.openProfile(profile, privateMode: true)
            return
        }
        do {
            try await core.openProfile(profile, privateMode: true, parent: space.profile)
        } catch {
            lastOpen[profile] = "failed: \(error)"
            throw error
        }
        lastOpen[profile] = "sided"
        sided.insert(profile)
    }

    /// The window's Chromium profile, if one of its tabs ever asked for it.
    static func existing(for store: WKWebsiteDataStore) -> String? {
        stores.object(forKey: store)?.profile
    }

    static func retainSession(_ store: WKWebsiteDataStore) {
        sessions.add(store)
    }

    static func releaseSession(_ store: WKWebsiteDataStore) {
        sessions.remove(store)
        retireIfUnused(store)
    }

    static func release(_ tab: Tab) {
        let store = tab.pageStore
        guard tab.shy || !store.isPersistent, let value = stores.object(forKey: store) else { return }
        if value.owners[tab.id]?.tab === tab { value.owners[tab.id] = nil }
        retireIfUnused(store)
    }

    private static func retireIfUnused(_ store: WKWebsiteDataStore) {
        guard !sessions.contains(store), let value = stores.object(forKey: store) else { return }
        value.owners = value.owners.filter { $0.value.tab?.gone == false }
        guard value.owners.isEmpty else { return }
        stores.removeObject(forKey: store)
        spaces[value.profile] = nil
        sided.remove(value.profile)
        lastOpen[value.profile] = nil
        ChromiumDRMCookies.retirePrivate(value.profile)
        ChromiumDRMExtensionSession.retirePrivate(value.profile)
        ChromiumExtensions.retirePrivate(value.profile)
        ChromiumProcess.shared.retirePrivateProfile(value.profile)
    }
}

extension ChromiumProcess {
    /// Context destruction follows real native tab closure. No helper is
    /// started just to release a private context and no profile is force-killed.
    func retirePrivateProfile(_ profile: String) {
        guard let core = connectedClient else { return }
        Task { @MainActor in
            for _ in 0..<40 {
                guard isCurrent(core), !Task.isCancelled else { return }
                // detach/native close can complete after the last Tab owner
                // goes away. Wait for that page rather than abandoning cleanup.
                if livePages.contains(where: { $0.profile == profile }) {
                    try? await Task.sleep(for: .milliseconds(50))
                    continue
                }
                do {
                    _ = try await core.request("profile.close", params: ["profile": .string(profile)])
                    return
                } catch {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            DebugLog.note("private-profile", ["profile": profile, "error": "Native context did not retire within two seconds"])
        }
    }
}
