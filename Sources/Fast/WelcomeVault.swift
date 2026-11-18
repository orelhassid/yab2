import AppKit
import SwiftUI

// Chapter 4's last beat, Passwords: the password manager to fill from,
// laid out as Bring is. The one that came with the browser brought in,
// else one found on this Mac (its app, or its extension in another
// browser), else Apple Passwords where this Yab may pair with it. Offered
// only while none is connected. One found: its icon at 128 beside a card
// of what it gives; several: their icons in a row, one picked. Connect
// connects it (its extension added first when it isn't coming already;
// Apple's code asked with the welcome stepped aside), the pen ticks the
// card's rows, and the welcome goes on by itself. Not Now goes on, and the
// manager's own Connect card isn't offered later either.

@MainActor
enum WelcomeVault: WelcomeChapter {
    /// A manager offered here: its provider id, name, where it was found.
    struct Offer: Equatable {
        let id: String
        let name: String
        let caption: String
        enum Way: Equatable {
            /// Its extension comes with Bring, or is in Yab already.
            case coming
            /// Its app on this Mac, or its extension in another browser: added from the store.
            case store
            /// Apple Passwords: paired with Passwords' code.
            case apple
        }
        let way: Way
    }

    /// Each icon's shape, measured from the pictures Yab carries
    /// (Resources/PasswordManagerIcons): its corner as a part of its side,
    /// 0.5 a circle, for the pick ring to follow; and how much of the
    /// picture is solid.
    static func corner(_ id: String) -> CGFloat {
        switch PasswordManagers.canonical(id) {
        case PasswordManagers.onePassword: return 0.5
        case PasswordManagers.bitwarden, PasswordManagers.dashlane: return 0.16
        case PasswordManagers.nordPass: return 0.24
        case PasswordManagers.lastPass: return 0.06
        default: return 0.226
        }
    }

    /// Proton Pass's two plates are diamonds: its ring is one too.
    static func diamond(_ id: String) -> Bool { PasswordManagers.canonical(id) == PasswordManagers.protonPass }

    /// How far its solid shape reaches from the middle as |dx| + |dy|, a
    /// part of the picture's side: Proton Pass's two plates, 0.57.
    static func reach(_ id: String) -> CGFloat { diamond(id) ? 0.57 : 0.5 }

    static func fill(_ id: String) -> CGFloat {
        PasswordManagers.canonical(id) == PasswordManagers.onePassword ? 0.86 : 1
    }

    /// Managers whose extension Yab adds and connects here: their store ids.
    static let offerable = [PasswordManagers.onePassword, PasswordManagers.bitwarden, PasswordManagers.protonPass,
                            PasswordManagers.nordPass, PasswordManagers.dashlane, PasswordManagers.lastPass]

    /// The one picked among several.
    private static var picked: String?
    /// Connected here, this welcome: the beat stays on the path for it.
    private static var connected: String?
    /// Connect pressed, its work under way.
    private static var connecting = false
    /// The pen's ticks drawn once, as the rows land.
    private static var ticked = false

    static func reset() {
        picked = nil
        connected = nil
        connecting = false
        ticked = false
    }

    // MARK: - who is offered

    static func offers(_ stage: WelcomeStage) -> [Offer] {
        if let pretended = stage.pretend.managers {
            return pretended.compactMap { key -> Offer? in
                switch key {
                case "apple": return Offer(id: PasswordManagers.apple, name: "Apple Passwords", caption: "On this Mac", way: .apple)
                case "1password": return Offer(id: PasswordManagers.onePassword, name: "1Password", caption: "Came from Chrome", way: .coming)
                case "bitwarden": return Offer(id: PasswordManagers.bitwarden, name: "Bitwarden", caption: "In Arc", way: .store)
                case "proton": return Offer(id: PasswordManagers.protonPass, name: "Proton Pass", caption: "App on this Mac", way: .store)
                default: return nil
                }
            }
        }
        var out: [Offer] = []
        func add(_ id: String, _ caption: String, _ way: Offer.Way) {
            guard !out.contains(where: { $0.id == id }) else { return }
            out.append(Offer(id: id, name: PasswordManagers.name(id), caption: caption, way: way))
        }
        // Brought: its extension is on its way in.
        if let from = WelcomeYours.broughtFrom(stage), let id = from.manager { add(id, "Came from \(from.name)", .coming) }
        // In Yab already, not connected.
        for item in ManagerExtensions.shared.installed where PasswordManagers.isManager(item) {
            let id = PasswordManagers.canonical(item.id)
            if offerable.contains(id) { add(id, "Extension in Yab", .coming) }
        }
        // On this Mac: its app, or its extension in another browser.
        let here = PasswordManagers.Connections.shared.here
        for id in offerable { if let words = here[id] { add(id, words, .store) } }
        // None: Apple Passwords, where this Yab may pair with it.
        if out.isEmpty, Preferences.entitledToPasskeys {
            add(PasswordManagers.apple, "On this Mac", .apple)
        }
        return out
    }

    /// The one shown: the picked, else the first.
    static func chosen(_ stage: WelcomeStage) -> Offer? {
        let all = offers(stage)
        return all.first { $0.id == picked } ?? all.first
    }

    /// Offered: something found and none connected, or one connected here.
    static func offered(_ stage: WelcomeStage) -> Bool {
        if connected != nil { return true }
        guard !offers(stage).isEmpty else { return false }
        if stage.pretend.managers != nil { return true }
        return PasswordManagers.Connections.shared.list.isEmpty
    }

    // MARK: - the chapter

    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat] {
        offered(stage) ? [.vault] : []
    }

    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords {
        guard let offer = chosen(stage) else { return WelcomeWords(title: "Fill your logins.") }
        let several = offers(stage).count > 1
        let sub = several ? "Pick the one you use. Yab fills from it, and so does your agent."
            : "Fill from \(offer.name) here, and let your agent sign in with it."
        if connected == offer.id { return WelcomeWords(title: "Fill your logins.", sub: sub, primary: "Continue") }
        if connecting {
            return WelcomeWords(title: "Fill your logins.", sub: sub, primary: "Connect \(offer.name)", busy: true)
        }
        return WelcomeWords(title: "Fill your logins.", sub: sub, primary: "Connect \(offer.name)", quiet: "Not Now")
    }

    static func arrive(_ moment: WelcomeMoment, _ stage: WelcomeStage) {
        // What is on this Mac, looked for again: an app installed meanwhile.
        if stage.pretend.managers == nil { PasswordManagers.Connections.shared.lookAround() }
    }

    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn {
        guard let offer = chosen(stage) else { return .next }
        if connecting { return .stay }
        if connected == offer.id { return .next }
        if button == .quiet {
            // A no: its own Connect card, as its extension lands, doesn't ask again.
            if stage.pretend.managers == nil { Store.settings.set(true, forKey: "passwords.offered." + offer.id) }
            return .next
        }
        if stage.pretend.managers != nil {
            land(offer, stage)
            return .stay
        }
        let connections = PasswordManagers.Connections.shared
        switch offer.way {
        case .coming:
            connections.connect(offer.id, mode: .you)
            land(offer, stage)
        case .store:
            ManagerExtensions.shared.add(offer.id, confirm: false)
            connections.connect(offer.id, mode: .you)
            land(offer, stage)
        case .apple:
            guard let browser = stage.browser else { return .stay }
            connecting = true
            // Passwords' code and Yab's card for it are over the window:
            // the welcome steps aside while they are asked, as for Google.
            stage.stepAside(for: .passwords, browser)
            Task { @MainActor in
                connections.connect(offer.id, mode: .you, pair: false)
                await ApplePasswordsPairing.pair()
                let paired = await ApplePasswords.shared.isPaired
                if !paired { connections.disconnect(offer.id) }
                connecting = false
                stage.comeBack(browser)
                if paired { land(offer, stage) } else { stage.needsRefresh() }
            }
        }
        return .stay
    }

    /// Connected: the pen ticks the rows, then on by itself, as Connect.
    private static func land(_ offer: Offer, _ stage: WelcomeStage) {
        connected = offer.id
        ticked = false
        stage.refresh()
        DispatchQueue.main.async { ticked = true; stage.refresh() }
        let drawn = VaultCard.tickAt(rows(offer).count - 1) + VaultCard.tickDuration + WelcomeConnect.afterTick
        DispatchQueue.main.asyncAfter(deadline: .now() + drawn * WelcomeMotion.pace) {
            guard stage.beat == .vault, connected == offer.id else { return }
            stage.pressPrimary()
        }
    }

    /// Another manager picked among several.
    private static func pick(_ id: String, _ stage: WelcomeStage) {
        guard connected == nil, !connecting, picked != id else { return }
        picked = id
        stage.needsRefresh()
    }

    // MARK: - the board

    /// Several: the icons' top, so icons, names, card and note stand round
    /// the room's middle as one manager's do.
    private static let rowTop: CGFloat = 236

    /// What it gives, a row each, as Bring's counts.
    static func rows(_ offer: Offer) -> [(symbol: String, tint: NSColor, words: String)] {
        [(symbol: "key", tint: .systemGray, words: "Its logins in every sign-in box"),
         (symbol: "lock", tint: .systemBlue, words: "Its one-time codes, filled for you"),
         offer.way == .apple ? (symbol: "doc", tint: .systemYellow, words: "New sign-ins kept in Passwords")
            : (symbol: "agent.face", tint: .systemBlue, words: "Your agent signs in with it")]
    }

    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        let all = offers(stage)
        guard let offer = chosen(stage) else { return WelcomeBoard() }
        let done = connected == offer.id
        let height = 8 + 38 * CGFloat(rows(offer).count)
        var parts: [StagePart] = []
        func mark(_ one: Offer) -> WelcomeIcon { .manager(one.id) }
        let cardFrame: CGRect
        if all.count == 1 {
            // Icon, name and card held round the middle of the room between
            // the sub and the footer; the card on the icon's middle.
            let frame = CGRect(x: 318, y: 330, width: 128, height: 128)
            // Alone, nothing to pick from: no pick ring round it.
            parts.append(WelcomeParts.mark("vault-" + offer.id, frame, mark(offer), tick: done, enter: .drop85))
            var name = StagePart.view("vname-" + offer.id, CGRect(x: 262, y: frame.maxY + 12, width: 240, height: 40), enter: .fade, delay: 0.06) {
                WelcomeBrowserName(name: offer.name, caption: done ? "Connected" : offer.caption, chosen: nil)
            }
            name.version = "\(done)"
            parts.append(name)
            cardFrame = CGRect(x: 494, y: frame.midY - height / 2, width: 368, height: height)
        } else {
            let pitch = WelcomeYours.browserPitch(all.count)
            for (index, one) in all.enumerated() {
                let x = 590 + (CGFloat(index) - CGFloat(all.count - 1) / 2) * pitch - 48
                let frame = CGRect(x: x, y: Self.rowTop, width: 96, height: 96)
                let chosen = one.id == offer.id
                parts.append(WelcomeParts.mark("vault-" + one.id, frame, mark(one), tick: chosen && done, dim: done && !chosen,
                                               enter: .drop85, delay: Double(index) * 0.04) { pick(one.id, stage) })
                if chosen, !done { parts.append(WelcomeParts.pick("pick-vault-" + one.id, frame, mark(one), delay: Double(index) * 0.04)) }
                var name = StagePart.view("vname-" + one.id, CGRect(x: x + 48 - (pitch - 8) / 2, y: Self.rowTop + 104, width: pitch - 8, height: 48),
                                          enter: .fade, delay: 0.06 + Double(index) * 0.04) {
                    WelcomeBrowserName(name: one.name, caption: chosen && done ? "Connected" : one.caption, chosen: chosen)
                }
                name.version = "\(one.name) \(chosen) \(done)"
                parts.append(name)
            }
            cardFrame = CGRect(x: 590 - 184, y: Self.rowTop + 172, width: 368, height: height)
            parts.append(.view("vault-note", CGRect(x: 0, y: cardFrame.maxY + 16, width: 1180, height: 16), enter: .fade, delay: 0.16) {
                Text("The others stay in Settings \u{203A} Passwords.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity)
            })
        }
        let rows = rows(offer)
        var card = StagePart.view("vault-card", cardFrame, enter: .fade, delay: 0.08) {
            VaultCard(rows: rows, ticked: done && ticked)
        }
        card.resize = .pin
        card.version = "\(offer.id) \(done && ticked)"
        parts.append(card)
        return WelcomeBoard(parts)
    }
}

/// What the manager gives, a row each, as Bring's counts card draws its
/// own: a pen tile, the words, and the pen's tick once it is connected.
struct VaultCard: View {
    let rows: [(symbol: String, tint: NSColor, words: String)]
    let ticked: Bool

    static let tickDuration = 0.26
    static func tickAt(_ row: Int) -> Double { 0.1 + 0.13 * Double(row) }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows.indices, id: \.self) { index in
                if index > 0 { Rectangle().fill(Palette.hairline).frame(height: 1) }
                HStack(spacing: 12) {
                    FeatureTile(icon: rows[index].symbol, tint: rows[index].tint, side: Omnibox.tile)
                    Text(rows[index].words)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    PenTick()
                        .trim(from: 0, to: ticked ? 1 : 0)
                        .stroke(UpdateInk.pen, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Self.tickDuration * WelcomeMotion.pace)
                            .delay(Self.tickAt(index) * WelcomeMotion.pace), value: ticked)
                    Spacer(minLength: 0)
                }
                .frame(height: 38 - (index > 0 ? 1 : 0))
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, -8) // design: the rows 4 from the card's edge, as Bring's counts card
        .cardFrame()
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
