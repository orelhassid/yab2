import AppKit
import Combine

/// Google identity is requested in Settings and read only from that profile's
/// browser session. The selected account is kept locally as display metadata.
@MainActor
final class GoogleProfileSignIn: ObservableObject {
    static let shared = GoogleProfileSignIn()

    enum Phase {
        case checking
        case signingIn
        case choose([BrowserProfileIdentities.Google])
        case failed
    }

    @Published private(set) var phases: [UUID: Phase] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private let signInURL = URL(string: "https://accounts.google.com/AddSession?continue=https%3A%2F%2Fmyaccount.google.com%2F")!

    func start(in browser: Browser) {
        guard browser.canManageProfiles, !browser.inMail else { return }
        let profile = browser.space.profileID
        let store = Spaces.store(for: browser.spaceID)
        cancel(profile)
        phases[profile] = .checking
        tasks[profile] = Task { [weak browser] in
            let existing = await MailFound.accounts(in: store)
            guard !Task.isCancelled else { return }
            guard let browser, browser.spaces.contains(where: { $0.profileID == profile }) else {
                return cancel(profile)
            }
            if !existing.isEmpty {
                finish(profile, accounts: existing)
                return
            }
            guard browser.canManageProfiles, !browser.inMail, browser.space.profileID == profile else {
                fail(profile)
                return
            }

            phases[profile] = .signingIn
            let tabID = browser.open(signInURL, foreground: true, rowNow: true).id
            BrowserWindows.shared.window(for: browser)?.makeKeyAndOrderFront(nil)
            let deadline = ContinuousClock.now + .seconds(300)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                guard let tab = browser.everyTab.first(where: { $0.id == tabID }), tab.store === store,
                      browser.spaces.contains(where: { $0.profileID == profile }) else { break }
                guard !tab.loading, let address = tab.address, address.scheme == "https",
                      address.host() == "myaccount.google.com" else { continue }
                let accounts = await MailFound.accounts(in: store)
                guard !Task.isCancelled else { return }
                guard !accounts.isEmpty else {
                    try? await Task.sleep(for: .seconds(5))
                    continue
                }
                finish(profile, accounts: accounts)
                return
            }
            if !Task.isCancelled { fail(profile) }
        }
    }

    func select(_ email: String, for profile: UUID) {
        guard case .choose(let accounts)? = phases[profile],
              let selected = accounts.first(where: { $0.email == email }) else { return }
        BrowserProfileIdentities.shared.link(selected, to: profile)
        cancel(profile)
    }

    func cancel(_ profile: UUID) {
        tasks.removeValue(forKey: profile)?.cancel()
        phases[profile] = nil
    }

    private func finish(_ profile: UUID, accounts: [BrowserProfileIdentities.Google]) {
        tasks[profile] = nil
        let choices = accounts.reduce(into: [BrowserProfileIdentities.Google]()) { unique, account in
            if !unique.contains(where: { $0.email == account.email }) { unique.append(account) }
        }
        if choices.count == 1, let account = choices.first,
           (BrowserProfileIdentities.shared[profile].google?.email ?? account.email) == account.email {
            BrowserProfileIdentities.shared.link(account, to: profile)
            phases[profile] = nil
        } else {
            phases[profile] = .choose(choices)
        }
    }

    private func fail(_ profile: UUID) {
        tasks[profile] = nil
        phases[profile] = .failed
    }
}
