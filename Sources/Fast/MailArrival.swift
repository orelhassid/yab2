import AppKit
import SwiftUI
import WebKit

// Settings › Mail before an account is in, and just after: not a form but a
// way in, in the middle of the pane, as Agents and Extensions are. The
// Google accounts Yab is already signed in to, space by space, are found
// first (MailFound) and one is picked, so Connect opens Google's page in a
// tab where it knows you and has only the yes to ask. While that tab is
// open the mark's edge runs round it; once Google answers, a tick, and how
// to get to mail, said once. After that Settings › Mail is its page
// (MailSettings).

/// The Google accounts signed in in Yab's spaces, as Google itself lists
/// them to its own pages (the account menu's list), read with each space's
/// cookies. Only this Mac asks, and only Settings › Mail shows it.
@MainActor
final class MailFound: ObservableObject {
    static let shared = MailFound()

    struct Account: Identifiable, Equatable {
        let email: String
        let name: String
        let photo: URL?
        /// The space it is signed in in: the first one for every space
        /// sharing its sign-ins.
        let space: UUID
        var id: String { email }
    }

    @Published private(set) var accounts: [Account] = []
    @Published private(set) var looked = false
    /// The one picked; "" for another account, nil for the first found.
    @Published var chosen: String?
    /// A test world's accounts, in place of Google's list.
    static var fake: [Account]?

    private static let list = URL(string: "https://accounts.google.com/ListAccounts?listPages=0&gpsia=1&source=ogb&mo=1&origin=https%3A%2F%2Fmail.google.com")!

    /// Each store once, the space on screen first; not the ones connected.
    func look(_ browser: Browser) async {
        accounts = await discover(browser).filter { !MailCenter.shared.accounts.contains($0.email) }
        looked = true
    }

    /// All Google sign-ins, including accounts already connected to Mail.
    /// Other account pickers must filter their own connected accounts.
    func discover(_ browser: Browser) async -> [Account] {
        if let fake = Self.fake { return fake }
        let here = browser.inMail ? browser.homeSpaceID : browser.spaceID
        let spaces = browser.prefs.usesSpaces ? browser.spaces.map(\.id) : [browser.homeSpaceID]
        var seen = Set<ObjectIdentifier>()
        var places: [UUID] = []
        for id in [here] + spaces {
            let store = Spaces.store(for: id)
            if seen.insert(ObjectIdentifier(store)).inserted { places.append(id) }
        }
        var found: [Account] = []
        for space in places {
            let listed = await Self.read(Spaces.store(for: space))
            for account in listed where !found.contains(where: { $0.email == account.email }) {
                found.append(Account(email: account.email, name: account.name, photo: account.photo, space: space))
            }
        }
        return found
    }

    /// The one Connect is for: picked, else the first found.
    var pick: Account? {
        if chosen == "" { return nil }
        return accounts.first { $0.email == chosen } ?? accounts.first
    }

    static func accounts(in store: WKWebsiteDataStore) async -> [BrowserProfileIdentities.Google] {
        await read(store).map { BrowserProfileIdentities.Google(email: $0.email, name: $0.name, photo: $0.photo) }
    }

    private static func read(_ store: WKWebsiteDataStore) async -> [(email: String, name: String, photo: URL?)] {
        await withCheckedContinuation { done in
            AgentRead.run(list, method: "GET", body: nil, type: nil, keepHTML: true, store: store) { got in
                let text = (got["status"] as? Int) == 200 ? got["text"] as? String ?? "" : ""
                done.resume(returning: parse(text))
            }
        }
    }

    /// Google's answer is a page that posts the list to its opener as a
    /// script string: `["gaia.l.a.r", [["gaia.l.a", 1, name, email, photo,
    /// …, index, …], …]]`, an account signed in having its index (the u/N
    /// of Gmail's addresses) and one signed out none.
    nonisolated static func parse(_ page: String) -> [(email: String, name: String, photo: URL?)] {
        guard let start = page.range(of: "postMessage('"),
              let end = page.range(of: "',", range: start.upperBound..<page.endIndex) else { return [] }
        var json = ""
        var rest = page[start.upperBound..<end.lowerBound]
        while let slash = rest.firstIndex(of: "\\") {
            json += rest[rest.startIndex..<slash]
            let next = rest.index(after: slash)
            guard next < rest.endIndex else { break }
            let char = rest[next]
            if char == "x", let hexEnd = rest.index(next, offsetBy: 3, limitedBy: rest.endIndex),
               let code = UInt8(rest[rest.index(after: next)..<hexEnd], radix: 16) {
                // A quote or a backslash stays escaped for the JSON inside.
                json += code == 0x5c ? "\\\\" : String(UnicodeScalar(code))
                rest = rest[hexEnd...]
            } else if char == "/" || char == "'" {
                json.append(char)
                rest = rest[rest.index(after: next)...]
            } else {
                json += "\\" + String(char)
                rest = rest[rest.index(after: next)...]
            }
        }
        json += rest
        guard let top = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [Any], top.count > 1,
              let entries = top[1] as? [[Any]] else { return [] }
        return entries.compactMap { entry in
            guard entry.count > 7, let email = entry[3] as? String, email.contains("@"), entry[7] is NSNumber else { return nil }
            if entry.count > 14, (entry[14] as? NSNumber)?.intValue == 1 { return nil }
            let photo = (entry[4] as? String).flatMap { URL(string: $0.replacingOccurrences(of: "/s48-c/", with: "/s96-c/")) }
            return (email.lowercased(), entry[2] as? String ?? "", photo)
        }
    }
}

// MARK: - the way in

struct MailArrival: View {
    @ObservedObject var browser: Browser
    @ObservedObject var prefs: Preferences
    @ObservedObject private var center = MailCenter.shared
    @ObservedObject private var found = MailFound.shared
    @MailStill private var still
    /// The rest of a long list of accounts, opened.
    @State private var more = false
    /// Add a Mail Account for iCloud, Zoho and the rest (MailOtherAccountSheet).
    @State private var other: MailSheetStart?
    @AppStorage(MailExperiment.key, store: Store.settings) private var mailOn = false

    /// Whether Settings › Mail is this rather than its page.
    @MainActor static var shows: Bool { MailCenter.shared.accounts.isEmpty || MailCenter.shared.landed != nil }

    var body: some View {
        ArrivalFrame {
            Group {
                if let account = center.landed { MailLanding(browser: browser, account: account) } else { way }
            }
            .animation(still ? nil : Motion.glide, value: center.landed)
        }
        .task { if MailClient.configured != nil { await found.look(browser) } }
        // The first connection replaces the way in with its landing.
        // Keep its sheet alive until the success tick dismisses it.
        .sheet(item: $other) { MailOtherAccountSheet(browser: browser, start: $0.address, provider: $0.provider) }
        .modifier(MailSheetOpened(asked: $other))
    }

    private var ready: Bool { true }

    private var way: some View {
        VStack(spacing: 0) {
            MailMark(badge: ready ? badge : nil, working: center.connecting, ticked: false)
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 16)
                .id(title)
                .transition(.opacity)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.top, 6)
            if center.connecting {
                Button("Cancel") { center.cancelConnect(in: browser) }
                    .settingsButton(.quiet)
                    .padding(.top, 16)
            } else {
                gains.padding(.top, 16)
                if ready, found.looked { picker.padding(.top, 16) }
                Button(button) { connect() }
                    .settingsButton(.primary)
                    .disabled(!ready)
                    .padding(.top, 20)
                // Mail includes IMAP accounts beside Gmail.
                if mailOn {
                    Button("Other Account…") { other = MailSheetStart(address: "") }
                        .settingsButton(.quiet)
                        .padding(.top, 8)
                }
                if center.connectFailed {
                    Text("Google didn’t give Yab access. Nothing was read.")
                        .font(.callout)
                        .foregroundStyle(ButtonCSS.danger)
                        .frame(maxWidth: 340)
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
            Text(footnote)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)
                .padding(.top, 12)
        }
        .animation(still ? nil : Motion.settle, value: center.connecting)
        .animation(still ? nil : Motion.settle, value: found.looked)
    }

    // MARK: - what shows

    private var badge: MailMark.Badge {
        guard let pick = found.pick else { return .google }
        return .person(pick.email, pick.photo)
    }

    private var title: String { center.connecting ? "Allow Yab in Google" : "Bring your mail into Yab" }

    private var detail: String {
        guard center.connecting else {
            return "Gmail in a space of its own: sorted by what each mail wants, with replies written before you open it."
        }
        guard let pick = found.pick else { return "A tab in Yab is asking. Sign in to the account you want there, then Allow." }
        return "A tab in \(place(of: pick)) is asking. You’re signed in there as \(pick.email), so it’s one Allow."
    }

    private var footnote: String {
        if !ready { return "This build has no Google client for Mail yet, so Gmail can’t be connected here." }
        if center.connecting { return "If Google says it hasn’t checked Yab yet, choose Advanced, then Go to Yab." }
        return "Gmail connects with an app password. Your mail stays on this Mac, and Disconnect deletes it."
    }

    private var button: String {
        guard ready, let pick = found.pick else { return "Connect Gmail" }
        return "Connect \(pick.email)"
    }

    /// "💼 Work", or "Yab" where there is only the one place to be signed in.
    private func place(of account: MailFound.Account) -> String {
        guard splits, let space = browser.spaces.first(where: { $0.id == account.space }) else { return "Yab" }
        return space.marked()
    }

    /// Whether some space keeps sign-ins of its own, so where an account is
    /// signed in is worth saying.
    private var splits: Bool { prefs.usesSpaces && browser.spaces.contains(where: \.ownSignIns) }

    /// What connecting gives, in three lines, as Agents says its own.
    static let gains: [(icon: String, text: String)] = [
        ("tray", "Needs you, Waiting and the rest, sorted on this Mac"),
        ("square.and.pencil", "Replies written ahead by your agent"),
        ("number", "Codes from mail, filled where sites ask"),
    ]

    private var gains: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.gains, id: \.text) { gain in
                HStack(spacing: 8) {
                    Symbol(gain.icon, size: 12)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(gain.text)
                }
            }
        }
        .multilineTextAlignment(.leading)
        .fixedSize()
    }

    // MARK: - the choice

    /// The accounts found, the first picked; four, and the rest a press
    /// away; then another account, signed in to in the tab.
    private var picker: some View {
        let shown = more ? found.accounts : Array(found.accounts.prefix(4))
        let hidden = found.accounts.count - shown.count
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, account in
                choice(index: index, picked: found.pick == account, choose: { found.chosen = account.email }) {
                    MailFace(email: account.email, photo: account.photo, side: 28)
                } words: {
                    Text(account.email).lineLimit(1).truncationMode(.middle)
                    Text(splits ? "Signed in in \(place(of: account))" : account.name.isEmpty ? "Signed in in Yab" : account.name)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if hidden > 0 {
                choice(index: shown.count, picked: nil, choose: { more = true }) {
                    Symbol("ellipsis", size: 12).foregroundStyle(.secondary).frame(width: 28, height: 28)
                } words: {
                    Text("\(hidden) more signed in").foregroundStyle(.secondary)
                }
            }
            choice(index: shown.count + (hidden > 0 ? 1 : 0), picked: found.pick == nil, choose: { found.chosen = "" }) {
                Symbol("plus", size: 12, weight: .semibold)
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Palette.ink.opacity(0.06)))
            } words: {
                Text(found.accounts.isEmpty ? "A Google account" : "Another Google Account")
                Text("You sign in to it in a tab")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(width: 340)
        .background(Palette.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: Radius.surface, style: .continuous))
        .animation(still ? nil : Motion.settle, value: more)
    }

    /// One row of the choice: its mark, its words, a tick when it is the
    /// one; the whole row picks it.
    private func choice<Mark: View, Words: View>(index: Int, picked: Bool?, choose: @escaping () -> Void,
                                                 @ViewBuilder mark: () -> Mark, @ViewBuilder words: () -> Words) -> some View {
        HStack(spacing: 12) {
            mark()
            VStack(alignment: .leading, spacing: 2) { words() }
                .frame(maxWidth: .infinity, alignment: .leading)
            if let picked {
                Symbol("checkmark", size: 11, weight: .bold)
                    .foregroundStyle(Palette.ink)
                    .opacity(picked ? 1 : 0)
                    .frame(width: 16)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: choose)
        .overlay(alignment: .top) { if index > 0 { Divider().padding(.horizontal, 12) } }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(picked == true ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, choose)
    }

    private func connect() {
        let pick = found.pick
        prefs.usesMail = true
        if let pick { MailSettings.remember(pick) }
        other = MailSheetStart(address: pick?.email ?? "@gmail.com", provider: "gmail")
    }
}

// MARK: - once connected

/// Said once, right after Connect, as Agents' How to Ask is: where mail is
/// now, since nothing of it shows in Settings. Open Mail goes there.
struct MailLanding: View {
    @ObservedObject var browser: Browser
    let account: String
    @ObservedObject private var center = MailCenter.shared

    var body: some View {
        VStack(spacing: 0) {
            MailMark(badge: .person(account, MailSettings.photo(account)), working: false, ticked: true)
            Text("Mail has a space of its own")
                .font(.system(size: 17, weight: .medium))
                .padding(.top, 16)
            Text("\(account) is in. Newest first, so what needs you shows in a minute; older mail keeps coming in behind it.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 8) {
                way(icon: "envelope", "The mail pin, among your pins")
                HStack(spacing: 8) {
                    Symbol("keyboard", size: 12).foregroundStyle(.secondary).frame(width: 16)
                    Text("From anywhere")
                    KeyGlyphs(keys: Keymap.shared.text(.mail), size: 13, tint: nil, rest: 0.6)
                }
                way(icon: "number", "Codes, under the box that asks for one")
            }
            .multilineTextAlignment(.leading)
            .fixedSize()
            .padding(.top, 16)
            // Whether the AI connected may read it: asked here, once, both
            // off until turned on (MailConsent).
            if PlanText.any { MailConsentList().padding(.top, 16) }
            HStack(spacing: 8) {
                Button("Done") { center.landingSeen() }
                    .settingsButton(.quiet)
                Button("Open Mail") {
                    center.landingSeen()
                    if !browser.inMail { browser.enterMail() }
                    Links.window?.makeKeyAndOrderFront(nil)
                }
                .settingsButton(.primary)
            }
            .padding(.top, 20)
        }
    }

    private func way(icon: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Symbol(icon, size: 12).foregroundStyle(.secondary).frame(width: 16)
            Text(text)
        }
    }
}

// MARK: - marks

/// Mail's tile, where the mail comes from at its corner, cut into it as
/// Extensions' mark wears the browser it brings from: the account's face,
/// or Google's G for one not known yet. Its edge runs while Google is
/// asked, and closes in green, with a tick, once it answered.
struct MailMark: View {
    enum Badge: Equatable {
        case person(String, URL?)
        case google
        /// Where mail beyond Gmail comes from: its site's own icon.
        case site(String)

        var key: String {
            switch self {
            case .person(let email, _): return email
            case .google: return "google"
            case .site(let host): return "site:" + host
            }
        }
    }

    let badge: Badge?
    let working: Bool
    let ticked: Bool
    @MailStill private var still
    private let size: CGFloat = 56

    var body: some View {
        let corner = (size * 0.42).rounded()
        FeatureTile(icon: SettingsPage.mail.icon, tint: SettingsPage.mail.tint ?? .systemBlue, side: size)
            .overlay { Seam(size: size, corner: size * 0.26, working: working, ticked: ticked) }
            .notched(ticked || badge != nil, side: corner, radius: corner / 2, offset: corner * 0.28, gap: 2.5)
            .overlay(alignment: .bottomTrailing) {
                Group {
                    if ticked {
                        Symbol("checkmark", size: corner * 0.5, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: corner, height: corner)
                            .background(Circle().fill(Color.green))
                            .transition(.scale(scale: 0.2).combined(with: .opacity))
                    } else if let badge {
                        Group {
                            switch badge {
                            case .person(let email, let photo): MailFace(email: email, photo: photo, side: corner)
                            case .google:
                                Text("G")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Palette.ink)
                                    .frame(width: corner, height: corner)
                                    .background(Circle().fill(Palette.ink.opacity(0.08)))
                            case .site(let host): MailSiteMark(host: host, side: corner)
                            }
                        }
                        .id(badge.key)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                .offset(x: corner * 0.28, y: corner * 0.28)
            }
            .animation(still ? nil : .snappy(duration: 0.24, extraBounce: 0), value: badge?.key)
            .animation(still ? nil : .snappy(duration: 0.24, extraBounce: 0), value: ticked)
            .accessibilityHidden(true)
    }
}

/// An account's face: its Google photo, or its first letter as mail's own
/// people wear theirs (MailPane's mark).
struct MailFace: View {
    let email: String
    let photo: URL?
    let side: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.14))
            Text(String(email.first.map { $0.uppercased() } ?? "?"))
                .font(.system(size: side > 40 ? (side * 0.4).rounded() : side > 24 ? 12 : 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            if let photo {
                AsyncImage(url: photo) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
