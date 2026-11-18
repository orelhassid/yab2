import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// Chapter 4, Make it yours. From here the parts hold only what is yours.
//
// Bring from X, when a browser with data is on this Mac: its own icon at
// its own size, what it holds counted on a card beside it (read from the
// welcome's first frame, off the main thread: Bringing), one press. macOS
// asks for the keychain only then, and once it has said yes the welcome goes
// on at once, the import coming in behind it. The peak: the card and the
// other browsers leave, the window-to-be grows in, the browser's icon flies
// on an arc to where the pins go, and your pins pour in, a tap each, the
// last one firm, the folders after them. Start Fresh goes on with one New
// Tab.
//
// Look: the window-to-be, holding what came or three sample tabs with ⌘T's
// field open over the page, beside picture tiles for where the tabs go,
// what the page sits on (edge to edge, or a card on the color) and which
// field ⌘T opens; each pick re-poses the window at once. Color, after
// either page: the editor grows out of the picked tile, the window paints
// large as the dot moves.
// What is picked is held on the stage and written only before Finish's
// motion. The bench pretends every branch with the prototype's browsers
// (Dia, Chrome Beta, Arc): nothing is ever really brought from it.

@MainActor
enum WelcomeYours: WelcomeChapter {
    static let title = "Bring your browser."

    /// Continue on Bring from X seen again, after Bring: Look is simply
    /// there, nothing pours a second time.
    private static var calm = false
    /// Brought, and the pen going down the counts card's rows, ticking
    /// what came, before Look.
    private static var ticking = false
    /// "A color" picked on the default gray: sage is shown instead, and
    /// gray comes back if the page goes back to another way.
    private static var lent = false
    /// The space on screen, when spaces came with colors of their own.
    fileprivate static var space = 0
    /// Bumped when a chip sets the color: the editor follows.
    private static var chipped = 0
    private static var watch: AnyCancellable?

    static func beats(_ stage: WelcomeStage) -> [WelcomeStage.Beat] {
        watchToast(stage)
        var beats: [WelcomeStage.Beat] = []
        if browsersFound(stage) { beats.append(.move) }
        beats.append(.look)
        if stage.held.backdrop != .site || WelcomeStage.siteColorTakesGrain { beats.append(.color) }
        return beats
    }

    /// A browser with data is on this Mac (or the bench says so).
    static func browsersFound(_ stage: WelcomeStage) -> Bool {
        !found(stage).isEmpty
    }

    // MARK: - the browsers found

    /// A browser as the chapter shows it: one of this Mac's, from Bringing,
    /// or one of the prototype's (the bench's `browsers=`).
    struct Found {
        /// Every import category wears an existing pen drawing on paper.
        struct Mark {
            let symbol: String
            let tint: NSColor
        }

        struct Row {
            let mark: Mark
            let words: String
        }

        let id: String
        let name: String
        let caption: String
        let icon: NSImage?
        var mark: WelcomeIcon { icon.map { .picture($0) } ?? .letter(name) }
        /// What it holds, each only when there is some.
        let rows: [Row]
        /// Its places' colors, each with the place's name.
        let colors: [(name: String, color: NSColor)]
        /// How many places it keeps: spaces, or profiles.
        let places: Int
        let placeWord: String
        /// It keeps its tabs down the side (Arc): Look starts there.
        let sidebar: Bool
        /// This Mac's browser, or the prototype's.
        let source: Chromium.Source?
        let sample: Sample?
        /// A password manager among its extensions, not connected here yet:
        /// offered first on Passwords (WelcomeVault), its extension coming.
        var manager: String? = nil
        /// Its ad blockers that run in Yab, by id and name: they come turned
        /// off, and Bring's "Block ads with Yab" line answers which blocks.
        var blockers: [(id: String, name: String)] = []
        /// Bring's lines under the counts.
        var extras: Int { blockers.isEmpty ? 0 : 1 }
    }

    /// One of the prototype's browsers: what the bench pretends was found.
    struct Sample {
        let bundle: String
        let pins: [WelcomeSite]
        let folders: [(name: String, count: Int)]
    }

    /// The bench's browsers, not this Mac's.
    static func pretending(_ stage: WelcomeStage) -> Bool { stage.pretend.browsers != nil }

    /// The browsers found, the default first, then the one used last.
    static func found(_ stage: WelcomeStage) -> [Found] {
        if let pretended = stage.pretend.browsers {
            switch pretended {
            case .none: return []
            case .dia: return [sample("dia")]
            case .three: return ["dia", "chromebeta", "arc"].map(sample)
            case .arc: return [sample("arc")]
            }
        }
        // Discovery is enough to offer Bring In; inspecting credentials to
        // decide whether a browser deserves a button is not permitted.
        return stage.bringing.sources.map { found($0, stage.bringing) }
    }

    /// An abandoned data directory alone isn't a browser to bring from.
    /// A bookmark-only browser still counts even without a History file.
    static func offers(_ counts: Bringing.Counts, used: Date?) -> Bool {
        used != nil || counts.pinned > 0 || counts.open > 0 || counts.folders > 0 ||
        [counts.signIns, counts.cookies, counts.passwords, counts.cards, counts.addresses,
         counts.memory, counts.chats, counts.bookmarks, counts.places].contains { ($0 ?? 0) > 0 } ||
        !(counts.extensions ?? []).isEmpty || !counts.colors.isEmpty
    }

    /// The one picked.
    static func chosen(_ stage: WelcomeStage) -> Found? {
        let all = found(stage)
        guard !all.isEmpty else { return nil }
        if !pretending(stage), let id = stage.sourceID, let held = all.first(where: { $0.id == id }) { return held }
        return all[min(max(stage.source, 0), all.count - 1)]
    }

    /// What was brought from: pressed Bring, or pretended so.
    static func broughtFrom(_ stage: WelcomeStage) -> Found? {
        let brought = stage.pretend.bring.map { $0 == .brought } ?? stage.brought
        return brought ? chosen(stage) : nil
    }

    /// Its places come as spaces: Keep its spaces on, or spaces on here.
    private static func spacesCome(_ stage: WelcomeStage, _ found: Found) -> Bool {
        guard found.places > 1 else { return false }
        return stage.keepSpaces || (!pretending(stage) && stage.browser?.prefs.usesSpaces == true)
    }

    /// Keep its spaces is offered: several places, and spaces off here.
    private static func offersKeep(_ stage: WelcomeStage, _ found: Found) -> Bool {
        // Unknown counts must not hide the person's import choice.
        (found.places > 1 || (found.source != nil && !stage.brought))
            && (pretending(stage) || stage.browser?.prefs.usesSpaces != true)
    }

    /// Where Color's paint comes from: nothing brought, its colors, or its spaces'.
    static func colorSource(_ stage: WelcomeStage) -> WelcomePretend.ColorSource {
        if let set = stage.pretend.colorSource { return set }
        guard let from = broughtFrom(stage), !from.colors.isEmpty else { return .nothing }
        return spacesCome(stage, from) ? .spaces : .colors
    }

    /// The old browser's colors, for Color's chips: what came, or, pretended
    /// without it, Arc's.
    static func paints(_ stage: WelcomeStage) -> [(name: String, color: NSColor)] {
        if let colors = broughtFrom(stage)?.colors, !colors.isEmpty { return colors }
        return pretending(stage) || stage.pretend.colorSource != nil ? sample("arc").colors : []
    }

    private static func found(_ source: Chromium.Source, _ bringing: Bringing) -> Found {
        let counts = bringing.counts[source.id] ?? Bringing.Counts()
        var rows: [Found.Row] = []
        let pinned = counts.pinned, folders = counts.folders
        if pinned > 0 {
            rows.append(Found.Row(mark: .init(symbol: "bookmark", tint: .systemOrange), words: folders > 0 ? "\(counted(pinned, "pinned tab")) and \(counted(folders, "folder"))" : counted(pinned, "pinned tab")))
        }
        if counts.open > 0 {
            rows.append(Found.Row(mark: .init(symbol: "rectangle.split.3x1", tint: .systemBlue), words: counted(counts.open, "open tab")))
        }
        if let sites = counts.signIns, sites > 0 { rows.append(Found.Row(mark: .init(symbol: "person", tint: .systemBlue), words: "Signed in to \(counted(sites, "site"))")) }
        if let passwords = counts.passwords, passwords > 0 { rows.append(Found.Row(mark: .init(symbol: "key", tint: .systemGray), words: counted(passwords, "password"))) }
        if let cards = counts.cards, cards > 0 { rows.append(Found.Row(mark: .init(symbol: "creditcard", tint: .systemGreen), words: counted(cards, "card"))) }
        if let addresses = counts.addresses, addresses > 0 { rows.append(Found.Row(mark: .init(symbol: "person.text.rectangle", tint: .systemOrange), words: "\(addresses) \(addresses == 1 ? "address" : "addresses")")) }
        if let memory = counts.memory, memory > 0 { rows.append(Found.Row(mark: .init(symbol: "brain", tint: .systemBrown), words: counted(memory, "memory note"))) }
        if let chats = counts.chats, chats > 0 { rows.append(Found.Row(mark: .init(symbol: "bubble", tint: .systemBlue), words: counted(chats, "archived chat"))) }
        let bookmarks = counts.bookmarks ?? 0, history = counts.places ?? 0
        if bookmarks > 0 {
            rows.append(Found.Row(mark: .init(symbol: "clock", tint: .systemOrange), words: history > 0 ? "\(counted(bookmarks, "bookmark")), and your history" : counted(bookmarks, "bookmark")))
        } else if history > 0 {
            rows.append(Found.Row(mark: .init(symbol: "clock", tint: .systemOrange), words: "Your history"))
        }
        if let extensions = counts.extensions?.count, extensions > 0 {
            rows.append(Found.Row(mark: .init(symbol: "puzzlepiece.extension", tint: .systemIndigo), words: counted(extensions, "extension")))
        }
        let places = counts.holding
        let extensions = counts.extensions ?? []
        let manager = extensions.first { extensionsManager($0.id) }.map { PasswordManagers.canonical($0.id) }
        var blockers: [(id: String, name: String)] = []
        if #available(macOS 15.4, *) {
            blockers = extensions.compactMap { one in
                Blockers.known[one.id].flatMap { one.id == Blockers.classic ? nil : (id: one.id, name: $0) }
            }
        }
        return Found(id: source.id, name: source.name, caption: bringing.caption(source), icon: bringing.icons[source.id], rows: rows,
                     colors: counts.colors, places: places.count, placeWord: places.first?.isProfile == true ? "profiles" : "spaces",
                     sidebar: DefaultBrowserImport.sidebar(for: source.bundle) == true, source: source, sample: nil,
                     manager: manager, blockers: blockers)
    }

    /// A password manager's extension Bring offers to connect: one Yab
    /// knows, not Apple's (its helper is Settings' own), not connected yet.
    private static func extensionsManager(_ id: String) -> Bool {
        guard let provider = PasswordManagers.provider(id), provider.id != PasswordManagers.apple else { return false }
        return PasswordManagers.Connections.shared.connection(provider.id) == nil
    }

    /// The prototype's browsers, as its panel has them.
    private static func sample(_ id: String) -> Found {
        func row(_ mark: Found.Mark, _ words: String) -> Found.Row { Found.Row(mark: mark, words: words) }
        let pin = Found.Mark(symbol: "bookmark", tint: .systemOrange), signed = Found.Mark(symbol: "person", tint: .systemBlue)
        let key = Found.Mark(symbol: "key", tint: .systemGray), clock = Found.Mark(symbol: "clock", tint: .systemOrange)
        let puzzle = Found.Mark(symbol: "puzzlepiece.extension", tint: .systemIndigo)
        switch id {
        case "chromebeta":
            let sample = Sample(bundle: "com.google.Chrome.beta", pins: [.mail, .calendar, .docs, .news], folders: [])
            return Found(id: "chromebeta", name: "Chrome Beta", caption: "Used today", icon: appIcon(sample.bundle),
                         rows: [row(pin, "4 pinned tabs"), row(signed, "Signed in to 37 sites"), row(key, "96 passwords"),
                                row(clock, "140 bookmarks, and your history"), row(puzzle, "3 extensions")],
                         colors: [], places: 1, placeWord: "profiles", sidebar: false, source: nil, sample: sample)
        case "arc":
            let sample = Sample(bundle: "company.thebrowser.Browser", pins: [.mail, .calendar, .code, .tracker, .docs, .music, .photo, .chat, .book],
                                folders: [(name: "Design", count: 4), (name: "Reading", count: 3), (name: "Research", count: 2)])
            return Found(id: "arc", name: "Arc", caption: "Used this week", icon: appIcon(sample.bundle),
                         rows: [row(pin, "12 pinned tabs and 3 folders"), row(signed, "Signed in to 61 sites"), row(key, "150 passwords"),
                                row(clock, "Your history"), row(puzzle, "2 extensions")],
                         colors: [(name: "Work", color: hex(0xA9BDEB)), (name: "Personal", color: hex(0xE8B9A5))],
                         places: 2, placeWord: "profiles", sidebar: true, source: nil, sample: sample,
                         manager: PasswordManagers.bitwarden)
        default:
            let sample = Sample(bundle: "company.thebrowser.dia", pins: [.mail, .calendar, .code, .video, .music, .docs, .photo, .chat, .book],
                                folders: [(name: "Work", count: 5), (name: "Reading", count: 3)])
            return Found(id: "dia", name: "Dia", caption: "Your default browser", icon: appIcon(sample.bundle),
                         rows: [row(pin, "9 pinned tabs and 2 folders"), row(signed, "Signed in to 84 sites"), row(key, "212 passwords"),
                                row(clock, "318 bookmarks, and your history"), row(puzzle, "6 extensions")],
                         colors: [], places: 1, placeWord: "profiles", sidebar: true, source: nil, sample: sample,
                         manager: PasswordManagers.onePassword, blockers: [(id: "ddkjiahejlhfcafbddmgiahcphecmpfh", name: "uBlock Origin Lite")])
        }
    }

    private static var appIcons: [String: NSImage] = [:]

    /// An app's icon by its bundle, once; an app's plain icon when it isn't
    /// on this Mac.
    private static func appIcon(_ bundle: String) -> NSImage? {
        if let hit = appIcons[bundle] { return hit }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .applicationBundle)
        appIcons[bundle] = icon
        return icon
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// "1 pinned tab", "1,212 passwords".
    private static func counted(_ count: Int, _ noun: String) -> String {
        "\(count.formatted(.number.locale(Locale(identifier: "en_US")))) \(noun)\(count == 1 ? "" : "s")"
    }

    // MARK: - what is yours

    /// What is yours in the window-to-be: the pins that came (nine at most,
    /// their own icons) and the folders with their counts, or nothing.
    static func yours(_ stage: WelcomeStage) -> WelcomeYoursThings {
        guard let from = broughtFrom(stage) else { return WelcomeYoursThings() }
        if let sample = from.sample {
            return WelcomeYoursThings(pins: sample.pins.prefix(Browser.pinLimit).map { WelcomeMark.site($0) }, folders: sample.folders)
        }
        guard let source = from.source, let counts = stage.bringing.counts[source.id] else { return WelcomeYoursThings() }
        let things = Bringing.yours(counts, spaces: spacesCome(stage, from))
        return WelcomeYoursThings(pins: things.pins, folders: things.folders)
    }

    /// The window-to-be as the look held has it, in the window's own look:
    /// the color as a dark window wears it when the look is dark, and the
    /// space on screen's color when spaces came with colors of their own.
    static func windowLook(_ stage: WelcomeStage) -> WelcomeWindowLook {
        let dark = isDark(stage)
        let held = stage.held
        var look = WelcomeWindowLook(sidebar: held.sidebar, backdrop: held.backdrop, color: held.swatch.color(dark: dark, custom: held.color), grain: held.grain, transparency: held.transparency)
        look.colors = held.colors.compactMap(NSColor.init(hex:)).map { dark ? $0.deepened : $0 }
        look.step = turned
        look.drawings = held.drawings
        look.strength = held.strength
        if colorSource(stage) == .spaces {
            let colors = paints(stage)
            if !colors.isEmpty {
                look.spaces = colors.map { Swatch.custom.color(dark: dark, custom: $0.color) }
                look.space = min(space, colors.count - 1)
                look.grain = 0
            }
        }
        return look
    }

    private static func isDark(_ stage: WelcomeStage) -> Bool {
        stage.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// "A color"'s picture: the color the editor opens on (sage for the
    /// default gray), or the space on screen's.
    private static func tilePaint(_ stage: WelcomeStage) -> WelcomeThumb.Paint {
        if colorSource(stage) == .spaces {
            let colors = paints(stage)
            if !colors.isEmpty {
                let color = colors[min(space, colors.count - 1)].color
                return WelcomeThumb.Paint(light: color, dark: Swatch.custom.color(dark: true, custom: color))
            }
        }
        let swatch = stage.held.swatch == .gray ? Swatch.sage : stage.held.swatch
        return WelcomeThumb.Paint(light: swatch.color(dark: false, custom: stage.held.color), dark: swatch.color(dark: true, custom: stage.held.color))
    }

    // MARK: - words

    static func words(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeWords {
        switch moment.beat {
        case .move:
            guard let from = chosen(stage) else { return WelcomeWords(title: title) }
            let several = found(stage).count > 1
            let sub = several ? "Bring everything from the browser you use. It all stays on this Mac."
                : "Bring everything from \(from.name) in one go. It all stays on this Mac."
            let failed = stage.bringFailure != nil
            let primary = failed ? "Try Again" : stage.brought && !ticking ? "Continue" : "Bring from \(from.name)"
            return WelcomeWords(title: title, sub: sub, primary: primary, busy: stage.bringing.asking && !pretending(stage),
                                quiet: stage.brought && !failed ? nil : "Start Fresh", failure: stage.bringFailure)
        case .color:
            let sub = colorSource(stage) == .spaces ? "Each space came with its own color." : "Choose a color and texture. See each change in the window beside you."
            return WelcomeWords(title: "Color your space.", sub: sub)
        default:
            return WelcomeWords(title: "Shape your workspace.", sub: "Choose where tabs sit, how pages fit, and how much the command field shows.")
        }
    }

    // MARK: - arriving

    static func arrive(_ moment: WelcomeMoment, _ stage: WelcomeStage) {
        switch moment.beat {
        case .move:
            // The picked browser is the one counted and brought.
            guard !pretending(stage) else { break }
            guard let source = chosen(stage)?.source else { break }
            stage.sourceID = source.id
            if stage.bringing.chosen != source { stage.bringing.chosen = source }
        case .look, .color:
            lendSage(stage)
        default:
            break
        }
    }

    /// A color opens on sage, never the default gray.
    private static func lendSage(_ stage: WelcomeStage) {
        guard stage.held.backdrop == .color, stage.held.swatch == .gray else { return }
        stage.held.swatch = .sage
        lent = true
    }

    // MARK: - pressing

    static func press(_ button: WelcomeButton, _ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeTurn {
        guard moment.beat == .move else { return .next }
        if ticking { return .stay }
        if button == .quiet { return startFresh(stage) }
        if stage.brought, stage.bringFailure == nil {
            calm = true
            return .next
        }
        guard let from = chosen(stage) else { return .next }
        if pretending(stage) || stage.pretend.bring != nil { return pretendBring(from, stage) }

        // Really: macOS asks for the key now, and the welcome goes on the
        // moment it has said yes.
        guard let browser = stage.browser, !stage.bringing.asking, let source = from.source else { return .stay }
        stage.bringFailure = nil
        if stage.bringing.chosen != source { stage.bringing.chosen = source }
        stage.bringing.asSpaces = stage.keepSpaces
        stage.bringing.bring(into: browser) { [weak stage] answer in
            guard let stage, stage.beat == .move, !stage.fresh, !stage.brought else { return false }
            switch answer {
            case .failed(let words):
                stage.bringFailure = words
                stage.refresh()
                return false
            case .allowed:
                // Counts and extensions become known during this import,
                // not when its button was drawn. Use those fresh facts.
                let imported = chosen(stage) ?? from
                // Decide ahead only for a blocker choice that was actually
                // shown before this press. Newly found blockers ask later.
                settle(from, stage)
                tick(imported, stage)
                return true
            }
        }
        return .stay
    }

    /// Bring, pretended: the failure asked for said on the first press,
    /// Try Again brings.
    private static func pretendBring(_ from: Found, _ stage: WelcomeStage) -> WelcomeTurn {
        if stage.bringFailure == nil, let bring = stage.pretend.bring, bring == .locked || bring == .unreadable {
            stage.bringFailure = bring == .locked ? "The keychain is locked" : "Couldn\u{2019}t read \(from.name)\u{2019}s tabs"
            return .stay
        }
        stage.pretend.bring = .brought
        stage.pretend.colorSource = nil
        tick(from, stage)
        return .stay
    }

    /// Brought: the pen ticks each row that came, one after another, as
    /// the site ticks what Yab kept from Arc, and then Look. With Reduce
    /// Motion, straight on.
    private static func tick(_ from: Found, _ stage: WelcomeStage) {
        brought(from, stage)
        guard !stage.reduceMotion else {
            stage.go(.look)
            return
        }
        ticking = true
        stage.refresh()
        let rows = from.rows.count + (from.colors.isEmpty ? 0 : 1) + from.extras
        let drawn = WelcomeCountsCard.tickAt(max(rows - 1, 0)) + WelcomeCountsCard.tickDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + (drawn + 0.22) * WelcomeMotion.pace) { [weak stage] in
            ticking = false
            guard let stage, stage.beat == .move, stage.brought else { return }
            stage.go(.look)
        }
    }

    /// Brought: Look shows what came, in the layout it came in.
    private static func brought(_ from: Found, _ stage: WelcomeStage) {
        stage.brought = true
        stage.fresh = false
        stage.bringFailure = nil
        calm = false
        if from.sidebar, !stage.held.tabsChosen { stage.held.sidebar = true }
    }

    private static func startFresh(_ stage: WelcomeStage) -> WelcomeTurn {
        stage.fresh = true
        stage.brought = false
        stage.bringFailure = nil
        if stage.pretend.bring != nil || pretending(stage) {
            stage.pretend.bring = .fresh
            stage.pretend.colorSource = nil
        }
        return .go(.look)
    }

    // MARK: - picking

    /// Another browser picked: its counts, and the button says its name.
    static func pick(_ index: Int, _ stage: WelcomeStage) {
        let all = found(stage)
        guard all.indices.contains(index), !stage.bringing.asking,
              chosen(stage)?.id != all[index].id else { return }
        stage.source = index
        stage.sourceID = all[index].id
        stage.bringFailure = nil
        stage.brought = false
        if pretending(stage) {
            stage.pretend.colorSource = nil
        } else {
            stage.bringing.chosen = all[index].source
        }
        stage.needsRefresh()
    }

    static func keep(_ on: Bool, _ stage: WelcomeStage) {
        guard stage.keepSpaces != on else { return }
        stage.keepSpaces = on
        if pretending(stage) {
            stage.pretend.keepSpaces = on
            stage.pretend.colorSource = nil
        }
        stage.needsRefresh()
    }

    static func blocks(_ on: Bool, _ stage: WelcomeStage) {
        guard stage.yabBlocks != on else { return }
        stage.yabBlocks = on
        stage.needsRefresh()
    }

    /// Bring's line, done once Bring is allowed: the blockers' question
    /// answered ahead (Blockers.decideAhead), so its card doesn't ask after
    /// the welcome. The browser's password manager is Passwords' to offer.
    private static func settle(_ from: Found, _ stage: WelcomeStage) {
        if #available(macOS 15.4, *), !from.blockers.isEmpty {
            Blockers.decideAhead(builtIn: stage.yabBlocks, among: from.blockers.map(\.id))
        }
    }

    static func pickTabs(_ sidebar: Bool, _ stage: WelcomeStage) {
        stage.held.tabsChosen = true
        guard stage.held.sidebar != sidebar else { return }
        stage.held.sidebar = sidebar
        stage.needsRefresh()
    }

    static func pickPage(_ page: Backdrop, _ stage: WelcomeStage) {
        guard stage.held.backdrop != page else { return }
        if stage.held.backdrop == .color, lent {
            if stage.held.swatch == .sage { stage.held.swatch = .gray }
            lent = false
        }
        stage.held.backdrop = page
        lendSage(stage)
        stage.needsRefresh()
    }

    static func pickField(_ compact: Bool, _ stage: WelcomeStage) {
        guard stage.held.compactField != compact else { return }
        stage.held.compactField = compact
        stage.needsRefresh()
    }

    static func pickSpace(_ index: Int, _ stage: WelcomeStage) {
        guard space != index else { return }
        space = index
        stage.needsRefresh()
    }

    /// One of the old browser's colors, as the color.
    static func pickChip(_ color: NSColor, _ stage: WelcomeStage) {
        stage.held.color = color
        stage.held.swatch = .custom
        lent = false
        chipped += 1
        stage.needsRefresh()
    }

    // MARK: - the drag

    /// The color the editor shows: yours, or a preset's bright one.
    static func editing(_ stage: WelcomeStage) -> NSColor {
        stage.held.swatch == .custom ? stage.held.color : stage.held.swatch.color(dark: false, custom: stage.held.color)
    }

    /// The dot or the wave moved: held at once, and the backdrop painted,
    /// the window-to-be's plate and nothing else.
    static func dragColor(_ color: NSColor, _ stage: WelcomeStage) {
        stage.held.color = color
        stage.held.swatch = .custom
        lent = false
        stage.view.paint("wtb", fill: Swatch.custom.color(dark: isDark(stage), custom: color).withAlphaComponent(WelcomeWindowLook.opacity(stage.held.transparency)))
        retint(stage)
    }

    static func dragTransparency(_ amount: Double, _ stage: WelcomeStage) {
        stage.held.transparency = BackdropTransparency.clamp(amount)
        let color = stage.held.swatch.color(dark: isDark(stage), custom: stage.held.color)
        stage.view.paint("wtb", fill: color.withAlphaComponent(WelcomeWindowLook.opacity(amount)))
        retint(stage)
    }

    /// The colors after the main one, moved with it or added: held, and the
    /// window-to-be's tint at once.
    static func dragColors(_ colors: [String], _ stage: WelcomeStage) {
        stage.held.colors = colors
        lent = false
        retint(stage)
    }

    /// How far Shift with tabs has turned the window-to-be's colors: a step
    /// as it is turned on, to show what it does, there being no tab to open.
    private(set) static var turned = 0

    static func shift(_ on: Bool, _ stage: WelcomeStage) {
        stage.held.shift = on
        if on, !stage.held.colors.isEmpty { turned += 1 }
        retint(stage)
        stage.needsRefresh()
    }

    static func draw(_ drawings: String, strength: Double, _ stage: WelcomeStage) {
        stage.held.drawings = drawings
        stage.held.strength = strength
        retint(stage)
    }

    /// The window-to-be's tint as held, with no board.
    private static func retint(_ stage: WelcomeStage) {
        WelcomeTintView.shown?.show(windowLook(stage))
    }

    /// The grain moved: held, and the grain's layer as thick.
    static func dragGrain(_ amount: Double, _ stage: WelcomeStage) {
        stage.held.grain = amount
        guard let layer = stage.view.layer(for: "y-grain") else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = Float(Grain.opacity(amount))
        CATransaction.commit()
    }

    // MARK: - the toast

    /// "Everything from Dia is in", in the corner, while the beat is in
    /// chapter 5 or 6 and the import is all in: nothing there says it.
    private static func watchToast(_ stage: WelcomeStage) {
        guard watch == nil else { return }
        let changes = stage.$beat.map { _ in () }
            .merge(with: stage.$words.map { _ in () }, stage.bringing.$state.map { _ in () })
        watch = changes.receive(on: DispatchQueue.main).sink { [weak stage] in
            guard let stage else { return }
            sayToast(stage)
        }
    }

    private static func sayToast(_ stage: WelcomeStage) {
        if stage.beat == .welcome {
            // A welcome from its start: what was picked here is let go.
            calm = false
            lent = false
            space = 0
        }
        var said: String?
        if let chapter = stage.beat.chapter, chapter == 5 || chapter == 6, let from = broughtFrom(stage) {
            if stage.pretend.importDone ?? stage.bringing.allIn { said = "Everything from \(from.name) is in" }
        }
        if stage.toast != said { stage.toast = said }
    }

    // MARK: - playing

    static func play(_ moment: WelcomeMoment, _ player: WelcomePlayer) async {
        let stage = player.stage
        let pours = moment.beat == .look && moment.forward && moment.from == .move && !calm && broughtFrom(stage) != nil
        calm = false
        guard pours else {
            player.show()
            return
        }
        // Peak 2: the card and the other browsers leave, the window-to-be
        // grows in, the browser's icon flies to where the pins go...
        player.show("fly")
        guard await player.wait(0.43) else { return }
        // ...and your pins pour in, 30 ms apart, each landing with a tap,
        // the last one firm; the folders after them, the Look card last.
        player.show("pour")
        let pins = yours(stage).pins.count
        if pins > 0 {
            guard await player.wait(0.22) else { return }
            for index in 0..<pins {
                if index == pins - 1 {
                    if player.alive { Knock.play() }
                } else {
                    player.haptic(.generic)
                    guard await player.wait(0.03) else { return }
                }
            }
        }
        guard await player.wait(0.5) else { return }
        player.show()
    }

    // MARK: - the boards

    static func board(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        switch moment.beat {
        case .move: return moveBoard(stage)
        case .color: return colorBoard(stage)
        default: return lookBoard(moment, stage)
        }
    }

    private static let window = CGRect(x: 56, y: 160, width: 752, height: 526)
    private static let lookFrame = CGRect(x: 824, y: 160, width: 300, height: 356)
    /// The page's two tiles inside the Look card, each a part the Color
    /// editor grows out of: Edge to edge, and Card ("A color").
    private static let edgeTile = CGRect(x: 12, y: 150, width: 84, height: 78)
    private static let colorTile = CGRect(x: 108, y: 150, width: 84, height: 78)

    // 4a: the browser (or the browsers), what it holds, the one press.
    private static func moveBoard(_ stage: WelcomeStage) -> WelcomeBoard {
        let all = found(stage)
        guard let from = chosen(stage) else { return WelcomeBoard() }
        let keep = offersKeep(stage, from)
        let height = countsHeight(from, keep: keep)
        let width: CGFloat = countsColumns(from, keep: keep) == 2 ? 600 : 368
        var parts: [StagePart] = []
        let footnote: CGFloat
        if all.count == 1 {
            let frame = CGRect(x: 318, y: 296, width: 128, height: 128)
            parts.append(WelcomeParts.mark("src-" + from.id, frame, from.mark, enter: .drop85))
            parts.append(WelcomeParts.pick("pick-src-" + from.id, frame, from.mark))
            parts.append(.view("bname-" + from.id, CGRect(x: 262, y: 436, width: 240, height: 40), enter: .fade, delay: 0.06) {
                WelcomeBrowserName(name: from.name, caption: from.caption, chosen: nil)
            })
            if height > 8 { parts.append(countsCard(from, CGRect(x: 494, y: 282, width: width, height: height), keep: keep, stage)) }
            footnote = max(282 + height + 24, 504)
        } else {
            let nameWidth: CGFloat = 154
            for (index, one) in all.enumerated() {
                let frame = browserFrame(index, count: all.count)
                parts.append(WelcomeParts.mark("src-" + one.id, frame, one.mark,
                                               enter: .drop85, delay: Double(index) * 0.04) { pick(index, stage) })
                if one.id == from.id {
                    parts.append(WelcomeParts.pick("pick-src-" + one.id, frame, one.mark, delay: Double(index) * 0.04))
                }
                var name = StagePart.view("bname-" + one.id, CGRect(x: frame.midX - nameWidth / 2, y: frame.maxY + 2, width: nameWidth, height: 48), enter: .fade, delay: 0.06 + Double(index) * 0.04) {
                    WelcomeBrowserName(name: one.name, caption: one.caption, chosen: one.id == from.id)
                }
                name.version = "\(one.name) \(one.caption) \(one.id == from.id)"
                parts.append(name)
            }
            let bottom = browserFrame(all.count - 1, count: all.count).maxY + 52
            if height > 8 { parts.append(countsCard(from, CGRect(x: 590 - width / 2, y: bottom, width: width, height: height), keep: keep, stage)) }
            footnote = bottom + height + 12
        }
        parts.append(.view("kc", CGRect(x: 0, y: footnote, width: 1180, height: 16), enter: .fade, delay: 0.16) {
            Text("macOS asks for your keychain once, when you press Bring.")
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity)
        })
        return WelcomeBoard(parts)
    }

    static func browserFrame(_ index: Int, count: Int) -> CGRect {
        let columns = min(3, max(1, count))
        let center = 590 + (CGFloat(index % columns) - CGFloat(columns - 1) / 2) * 158
        return CGRect(x: center - 29, y: 176 + CGFloat(index / columns) * 103, width: 58, height: 58)
    }

    static func browserPitch(_ count: Int) -> CGFloat {
        count > 1 ? min(140, (1100 - 96) / CGFloat(count - 1)) : 140
    }

    /// Where the footer starts on the board of several browsers: the card
    /// (from 348), its 16 gap and the 16-tall keychain line end above it.
    static let countsFloor: CGFloat = 716

    /// Two columns for many counts, or when one column would run the
    /// keychain line into the footer (Bring's lines add 64 each).
    static func countsColumns(_ found: Found, keep: Bool) -> Int {
        if found.rows.count + (found.colors.isEmpty ? 0 : 1) > 6 { return 2 }
        return 348 + countsHeight(found, keep: keep, columns: 1) + 16 + 16 < countsFloor ? 1 : 2
    }

    /// Counts pair up on a large card; colors and Keep span its width.
    static func countsHeight(_ found: Found, keep: Bool) -> CGFloat {
        countsHeight(found, keep: keep, columns: countsColumns(found, keep: keep))
    }

    private static func countsHeight(_ found: Found, keep: Bool, columns: Int) -> CGFloat {
        let rows = (found.rows.count + columns - 1) / columns
        return 8 + 38 * CGFloat(rows + (found.colors.isEmpty ? 0 : 1)) + (keep ? 58 : 0) + WelcomeCountsCard.extraLine * CGFloat(found.extras)
    }

    private static func countsCard(_ found: Found, _ frame: CGRect, keep: Bool, _ stage: WelcomeStage) -> StagePart {
        let ticked = broughtFrom(stage)?.id == found.id
        var part = StagePart.view("counts-" + found.id, frame, enter: .fade, delay: 0.08, takesClicks: keep || found.extras > 0) {
            WelcomeCountsCard(found: found, keep: keep, on: stage.keepSpaces, ticked: ticked,
                              yabBlocks: stage.yabBlocks,
                              turn: { WelcomeYours.keep($0, stage) },
                              turnBlocks: { WelcomeYours.blocks($0, stage) })
        }
        part.resize = .pin
        part.version = [found.id, found.rows.map(\.words).joined(separator: "|"), "\(found.colors.count)", "\(keep)", "\(stage.keepSpaces)", "\(ticked)",
                        found.blockers.map(\.id).joined(separator: ","), "\(stage.yabBlocks)"].joined(separator: "·")
        return part
    }

    // 4b: the window-to-be and where your tabs go, what the page sits on.
    private static func lookBoard(_ moment: WelcomeMoment, _ stage: WelcomeStage) -> WelcomeBoard {
        let from = broughtFrom(stage)
        let fly = moment.phase == "fly" && from != nil
        let pour = moment.phase == "pour" && from != nil
        let things = yours(stage)
        let look = windowLook(stage)
        var parts = [WelcomeParts.windowToBe("wtb", window, look: look, yours: things, page: .newTab, empty: fly, pour: pour ? 0 : nil,
                                             samples: true, field: fly ? nil : stage.held.compactField, enter: .grow94)]
        var exits: [String: StagePart.Exit] = [:]
        if let from {
            // The browser's icon: on its way to where the pins go, then gone
            // as they pour in.
            exits["src-" + from.id] = .fastFade
            if fly {
                let rest = WelcomeParts.windowToBe("wtb", window, look: look, yours: things, page: .newTab)
                let pin = frame(of: "y-pin-0", in: rest)
                let slot = pin.map { CGRect(x: $0.midX - 15, y: $0.midY - 15, width: 30, height: 30) }
                    ?? CGRect(x: look.sidebar ? 85 : 136, y: look.sidebar ? 212 : 165, width: 30, height: 30)
                var mark = WelcomeParts.mark("src-" + from.id, slot, from.mark)
                mark.arc = -70
                parts.append(mark)
            }
        }
        if !fly {
            let delay = pour ? Double(things.pins.count) * 0.03 + 0.1 : 0.06
            parts.append(lookCard(stage, delay: delay))
        }
        return WelcomeBoard(parts, exits: exits)
    }

    /// Where a part inside another is, in the stage's points.
    private static func frame(of key: String, in part: StagePart, origin: CGPoint = .zero) -> CGRect? {
        let rect = part.frame.offsetBy(dx: origin.x, dy: origin.y)
        if part.key == key { return rect }
        for child in part.children {
            if let found = frame(of: key, in: child, origin: rect.origin) { return found }
        }
        return nil
    }

    private static func lookCard(_ stage: WelcomeStage, delay: Double) -> StagePart {
        let held = stage.held
        let paint = tilePaint(stage)
        var card = StagePart.view("lookcard", lookFrame, enter: .rise, delay: delay, takesClicks: true) {
            WelcomeLookCard(sidebar: held.sidebar, compact: held.compactField, paint: paint,
                            tabs: { pickTabs($0, stage) }, field: { pickField($0, stage) })
        }
        card.version = "\(held.sidebar)·\(held.compactField)·\(paint.light.hex)·\(paint.dark.hex)"
        // The page's tiles are parts of their own: the editor grows out of
        // the one picked.
        var edge = StagePart.view("tile-edge", edgeTile, takesClicks: true) {
            WelcomePictureTile(kind: .edge, label: Backdrop.none.title, chosen: held.backdrop == .none, paint: paint) { pickPage(.none, stage) }
        }
        edge.version = "\(held.backdrop == .none)·\(paint.light.hex)·\(paint.dark.hex)"
        var tile = StagePart.view("tile-color", colorTile, takesClicks: true) {
            WelcomePictureTile(kind: .color, label: "Card", chosen: held.backdrop == .color, paint: paint) { pickPage(.color, stage) }
        }
        tile.version = "\(held.backdrop == .color)·\(paint.light.hex)·\(paint.dark.hex)"
        card.children = [edge, tile]
        return card
    }

    // 4c: the editor, grown out of its tile; the window-to-be moves over.
    private static func colorBoard(_ stage: WelcomeStage) -> WelcomeBoard {
        let source = colorSource(stage)
        let colors = source == .nothing ? [] : paints(stage)
        let spaces = source == .spaces && !colors.isEmpty
        let chips = source == .colors ? colors.map(\.color) : []
        // The look card's controls hug their content from the top; the part
        // is as tall as the most they take, to the stage's foot.
        let height: CGFloat = spaces
            ? 24 + 36 * CGFloat(colors.count) + 4 * CGFloat(colors.count - 1)
            : StageSpace.size.height - 160 - 12
        let from = stage.held.backdrop == .none ? "tile-edge" : "tile-color"
        var editor = StagePart.view("editor", CGRect(x: 858, y: 160, width: spaces ? 232 : WelcomeColorCard.width, height: height), enter: .grow(from: from), takesClicks: true) {
            WelcomeColorCard(stage: stage, spaces: spaces ? colors : [], chips: chips)
        }
        editor.version = "\(source)·\(colors.count)·\(chipped)·\(space)"
        return WelcomeBoard([
            WelcomeParts.windowToBe("wtb", window.offsetBy(dx: 34, dy: 0), look: windowLook(stage), yours: yours(stage), page: .newTab,
                                    samples: true, field: stage.held.compactField, enter: .grow94),
            editor,
        ])
    }
}

// MARK: - Bring from X

/// A browser's name under its icon, and how it is known: "Your default
/// browser", "Used today". Several: the picked one's name on a wash pill.
struct WelcomeBrowserName: View {
    let name: String
    let caption: String
    /// Among several: picked or not; nil when it is the only one.
    let chosen: Bool?

    var body: some View {
        VStack(spacing: chosen == nil ? 2 : 0) {
            Text(name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(chosen == false ? Palette.muted : Palette.ink)
                .lineLimit(1)
                .frame(height: 20)
                .padding(.horizontal, chosen == nil ? 0 : 8)
                .padding(.vertical, chosen == nil ? 0 : 4)
                .background {
                    if chosen == true { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).fill(Palette.wash) }
                }
            Text(caption)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// What a browser holds, a row each: its pinned tabs and folders, the sites
/// it is signed in to, passwords, bookmarks and history, extensions, its
/// colors; and Keep its spaces, for one with several places.
private struct WelcomeCountsCard: View {
    let found: WelcomeYours.Found
    let keep: Bool
    let on: Bool
    /// What came is ticked: drawn as it turns on, standing when the card
    /// comes back already brought.
    let ticked: Bool
    /// Bring's line: Yab's blocker over its own.
    var yabBlocks = true
    let turn: (Bool) -> Void
    var turnBlocks: (Bool) -> Void = { _ in }

    /// The pen's ticks: 0.13 apart, each on the pen's curve.
    static let tickDuration = 0.26
    /// Bring's lines: a title and two lines under it, with room below.
    static let extraLine: CGFloat = 64
    static func tickAt(_ row: Int) -> Double { 0.1 + 0.13 * Double(row) }

    private enum Line {
        case counts(Range<Int>)
        case colors
        case keep
        case blocker
    }

    private var lines: [Line] {
        let columns = WelcomeYours.countsColumns(found, keep: keep)
        return stride(from: 0, to: found.rows.count, by: columns).map {
            Line.counts($0..<min($0 + columns, found.rows.count))
        } + (found.colors.isEmpty ? [] : [.colors]) + (keep ? [.keep] : [])
            + (found.blockers.isEmpty ? [] : [.blocker])
    }

    /// The first tick a line after the counts and colors draws.
    private var extraTick: Int { found.rows.count + (found.colors.isEmpty ? 0 : 1) }

    var body: some View {
        let lines = lines
        VStack(spacing: 0) {
            ForEach(lines.indices, id: \.self) { index in
                if index > 0 {
                    Rectangle().fill(Palette.hairline).frame(height: 1)
                }
                line(lines[index], index)
                    .frame(height: height(of: lines[index]) - (index > 0 ? 1 : 0), alignment: .top)
            }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, -8) // design: the rows 4 from the card's edge, hairlines between them, as the prototype's counts card
        .cardFrame()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func height(of line: Line) -> CGFloat {
        switch line {
        case .keep: return 58
        case .blocker: return Self.extraLine
        case .counts, .colors: return 38
        }
    }

    @ViewBuilder
    private func line(_ line: Line, _ index: Int) -> some View {
        switch line {
        case .counts(let indices):
            HStack(spacing: 24) {
                ForEach(indices, id: \.self) { rowIndex in
                    HStack(spacing: 12) {
                        mark(found.rows[rowIndex].mark)
                        words(found.rows[rowIndex].words)
                        tick(rowIndex)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                if indices.count < WelcomeYours.countsColumns(found, keep: keep) {
                    Color.clear.frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        case .colors:
            HStack(spacing: 12) {
                mark(.init(symbol: "paintpalette", tint: .systemPurple))
                words("Its colors")
                tick(found.rows.count)
                Spacer(minLength: 0)
                ForEach(found.colors.indices, id: \.self) { index in
                    Circle()
                        .fill(Color(nsColor: found.colors[index].color))
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                        .frame(width: 12, height: 12)
                }
            }
            .frame(maxHeight: .infinity)
        case .keep:
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep its spaces")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                    Text("Its \(found.places) \(found.placeWord) come as \(found.places) spaces. Off, it all comes into one list.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.muted)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Keep its spaces", isOn: Binding(get: { on }, set: turn))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .padding(.top, 2)
            }
            .padding(.top, 8)
        case .blocker:
            let name = found.blockers[0].name
            choice(title: "Block ads with Yab", tick: extraTick,
                   detail: yabBlocks ? "\(name) comes turned off: one blocker, the same lists."
                                     : "\(name) blocks instead, and Yab\u{2019}s steps aside.",
                   on: yabBlocks, turn: turnBlocks) {
                mark(.init(symbol: "hand.raised", tint: .systemBlue))
            }
        }
    }

    /// A line with a switch, as Keep its spaces, its mark before it as the
    /// counts' and the pen's tick after its title once it came.
    private func choice<Leading: View>(title: String, tick row: Int, detail: String, on: Bool, turn: @escaping (Bool) -> Void,
                                       @ViewBuilder leading: () -> Leading) -> some View {
        HStack(alignment: .top, spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    tick(row)
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.muted)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: Binding(get: { on }, set: turn))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .padding(.top, 2)
        }
        .padding(.top, 8)
    }

    private func tick(_ row: Int) -> some View {
        PenTick()
            .trim(from: 0, to: ticked ? 1 : 0)
            .stroke(UpdateInk.pen, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 15, height: 15)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: Self.tickDuration * WelcomeMotion.pace)
                .delay(Self.tickAt(row) * WelcomeMotion.pace), value: ticked)
    }

    private func words(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Palette.ink)
            .lineLimit(1)
    }

    private func mark(_ mark: WelcomeYours.Found.Mark) -> some View {
        FeatureTile(icon: mark.symbol, tint: mark.tint, side: Omnibox.tile)
    }
}

/// The pen's tick, as yetanotherbrowser.com draws it beside what Yab kept
/// from Arc: a short stroke down, then a long one up past the box.
struct PenTick: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 1.06, x = rect.minX, y = rect.minY + s * 0.06
        var path = Path()
        path.move(to: CGPoint(x: x, y: y + s * 0.5))
        path.addQuadCurve(to: CGPoint(x: x + s * 0.38, y: y + s * 0.95), control: CGPoint(x: x + s * 0.2, y: y + s * 0.62))
        path.addQuadCurve(to: CGPoint(x: x + s * 1.06, y: y - s * 0.06), control: CGPoint(x: x + s * 0.56, y: y + s * 0.42))
        return path
    }
}

// MARK: - Look

/// Look's card: Settings' own picture tiles, where the tabs go and what the
/// page sits on. "A color" is a part of its own (WelcomeYours.lookCard), so
/// its place here is left open.
private struct WelcomeLookCard: View {
    let sidebar: Bool
    let compact: Bool
    let paint: WelcomeThumb.Paint
    let tabs: (Bool) -> Void
    let field: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Tabs")
            HStack(alignment: .top, spacing: 12) {
                WelcomePictureTile(kind: .top, label: "On top", chosen: !sidebar, paint: paint) { tabs(false) }
                WelcomePictureTile(kind: .side, label: "Sidebar", chosen: sidebar, paint: paint) { tabs(true) }
            }
            .frame(height: 78, alignment: .top)
            .padding(.top, 8)
            heading("Page")
                .padding(.top, 16)
            // The page's two tiles are parts of their own (tile-edge,
            // tile-color), for the Color editor to grow out of.
            Color.clear.frame(height: 78)
                .padding(.top, 8)
            heading("Field")
                .padding(.top, 16)
            HStack(alignment: .top, spacing: 12) {
                WelcomePictureTile(kind: .full, label: "Full", chosen: !compact, paint: paint) { field(false) }
                WelcomePictureTile(kind: .compact, label: "Compact", chosen: compact, paint: paint) { field(true) }
            }
            .frame(height: 78, alignment: .top)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardFrame()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func heading(_ words: String) -> some View {
        Text(words)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Palette.muted)
            .frame(height: 14)
    }
}

/// A picture tile and its label under it; the chosen one's picture ringed
/// in ink, its label on a wash pill.
private struct WelcomePictureTile: View {
    let kind: WelcomeThumb.Kind
    let label: String
    let chosen: Bool
    let paint: WelcomeThumb.Paint
    let pick: () -> Void

    var body: some View {
        Button(action: pick) {
            VStack(spacing: 6) {
                WelcomeThumb(kind: kind, chosen: chosen, paint: paint)
                Text(label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(chosen ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background {
                        if chosen { RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Palette.wash) }
                    }
                    .frame(height: 18)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}

/// A window in small, 84 × 54: the lights, the tabs on top or down the
/// side, the page on the plate, on a color, on the site's, or to the edges.
/// Drawn at its own size, as Settings' own pictures of the window are; the
/// numbers below are that picture's, not the app's spacing.
private struct WelcomeThumb: View {
    enum Kind { case top, side, edge, color, site, full, compact }

    /// "A color"'s paint, for a light window and a dark.
    struct Paint {
        let light: NSColor
        let dark: NSColor
    }

    let kind: Kind
    let chosen: Bool
    let paint: Paint
    @Environment(\.colorScheme) private var scheme

    private var dark: Bool { scheme == .dark }
    private func pair(_ light: UInt32, _ deep: UInt32) -> Color {
        let v = dark ? deep : light
        return Color(.sRGB, red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private var plate: Color { pair(0xE6E6E9, 0x2A2A2D) }
    private var page: Color { pair(0xFFFFFF, 0x1C1C1C) }
    private var line: Color { pair(0xE3E3E6, 0x3A3A3D) }
    private var thin: Color { pair(0xEDEDF0, 0x333336) }
    private var chip: Color { dark ? .white.opacity(0.16) : .white }
    private var veil: Color { dark ? .white.opacity(0.08) : .black.opacity(0.08) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ground
            lights
            switch kind {
            case .top:
                bar(chip)
                sheet(4, 14, 76, 36)
            case .side:
                ForEach(0..<4) { i in block(5, 14 + CGFloat(i) * 9, 17, 6, 2, i == 0 ? chip : veil) }
                sheet(27, 4, 53, 46)
            case .edge:
                bar(chip)
                block(0, 13, 84, 41, 0, page)
                block(0, 13, 84, 0.5, 0, Color.black.opacity(0.08))
                lines(8, 21)
            case .color, .site:
                bar(.white.opacity(0.85))
                sheet(4, 14, 76, 36)
            case .full:
                bar(chip)
                sheet(4, 14, 76, 36)
                box(18, 18, 48, 30, rows: 3)
            case .compact:
                bar(chip)
                sheet(4, 14, 76, 36)
                box(24, 19, 36, 18, rows: 2)
            }
        }
        .frame(width: 84, height: 54, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.ink.opacity(0.16), lineWidth: 0.5))
        .overlay {
            if chosen { RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5) }
        }
        .accessibilityHidden(true)
    }

    private var ground: Color {
        switch kind {
        case .top, .side: return plate
        case .edge, .color, .full, .compact: return Color(nsColor: dark ? paint.dark : paint.light)
        case .site: return pair(0xDCE6F4, 0x26313F)
        }
    }

    private var lights: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3) { i in
                Circle()
                    .fill([Color(red: 1, green: 0.373, blue: 0.341), Color(red: 0.996, green: 0.737, blue: 0.18), Color(red: 0.157, green: 0.784, blue: 0.251)][i])
                    .frame(width: 4, height: 4)
                    .offset(x: 5 + CGFloat(i) * 6.5, y: 5)
            }
        }
    }

    /// The tabs across the top: the live one, two more.
    private func bar(_ live: Color) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<3) { i in block(22 + CGFloat(i) * 18.5, 3.5, 16, 7, 2, i == 0 ? live : veil) }
        }
    }

    /// ⌘T's field over the page: its glass, the line typed, rows under it.
    private func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, rows: Int) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous) // design: the box's corner in the 84-point picture
                .fill(dark ? Color(white: 0.2) : .white)
                .frame(width: width, height: height)
                .shadow(color: .black.opacity(dark ? 0.4 : 0.16), radius: 2.5, y: 1) // design: the box's shadow in the 84-point picture
                .offset(x: x, y: y)
            edge(x, y, width, height, 3.5, Palette.ink.opacity(0.14))
            block(x + 4, y + 3.5, width * 0.4, 2.5, 1, Palette.ink.opacity(0.55))
            ForEach(0..<rows, id: \.self) { i in
                block(x + 3, y + 8.5 + CGFloat(i) * 5, width - 6, 4, 1.5, i == 0 ? Palette.ink.opacity(0.1) : .clear)
                block(x + 5, y + 9.5 + CGFloat(i) * 5, width * (i == 1 ? 0.4 : 0.55), 2, 1, thin)
            }
        }
    }

    /// The page, with a heading and two lines on it.
    private func sheet(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            block(x, y, width, height, 4, page)
            edge(x, y, width, height, 4, Color.black.opacity(0.08))
            lines(x + 7, y + 8)
        }
    }

    private func lines(_ x: CGFloat, _ y: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            block(x, y, 26, 3, 2, line)
            block(x, y + 7, 40, 2, 1, thin)
            block(x, y + 12, 34, 2, 1, thin)
        }
    }

    private func block(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ corner: CGFloat, _ fill: Color) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }

    /// A half-point line round a shape of the picture.
    private func edge(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ corner: CGFloat, _ ink: Color) -> some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(ink, lineWidth: 0.5)
            .frame(width: width, height: height)
            .offset(x: x, y: y)
    }
}

// MARK: - Color

/// Color's card: the look card's own controls (LookControls), as the card
/// over the window and Settings have them, with the old browser's colors
/// as chips above; no Take the site's color, whose tile is the step before
/// and whose window here has no site. Or, when its spaces came with colors
/// of their own, a row for each space and no editor.
private struct WelcomeColorCard: View {
    let stage: WelcomeStage
    /// Spaces that came, each with its color: a row each.
    let spaces: [(name: String, color: NSColor)]
    /// The old browser's colors, as chips.
    let chips: [NSColor]
    /// The look as dragged: the stage holds it without publishing, so the
    /// controls follow copies of their own.
    @State private var transparency: Double
    @State private var grain: Double
    @State private var colors: [String]
    @State private var shift: Bool
    @State private var drawings: String
    @State private var strength: Double
    @Environment(\.colorScheme) private var scheme

    init(stage: WelcomeStage, spaces: [(name: String, color: NSColor)], chips: [NSColor]) {
        self.stage = stage
        self.spaces = spaces
        self.chips = chips
        _grain = State(initialValue: stage.held.grain)
        _transparency = State(initialValue: stage.held.transparency)
        _colors = State(initialValue: stage.held.colors)
        _shift = State(initialValue: stage.held.shift)
        _drawings = State(initialValue: stage.held.drawings)
        _strength = State(initialValue: stage.held.strength)
    }

    /// The look card's width, its controls 266 inside.
    static let width: CGFloat = LookCardView.inner + 2 * CardFrame.inset

    var body: some View {
        Group {
            if spaces.isEmpty { editing } else { rows }
        }
        .cardFrame()
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var editing: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips.indices, id: \.self) { index in
                        Button { WelcomeYours.pickChip(chips[index], stage) } label: {
                            Circle()
                                .fill(Color(nsColor: chips[index]))
                                .overlay(Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Its color \(index + 1)")
                    }
                }
                .padding(.horizontal, 2)
            }
            LookControls(look: LookFields(
                color: Binding(get: { WelcomeYours.editing(stage) }, set: { WelcomeYours.dragColor($0, stage) }),
                transparency: Binding(get: { transparency }, set: { transparency = $0; WelcomeYours.dragTransparency($0, stage) }),
                grain: Binding(get: { grain }, set: { grain = $0; WelcomeYours.dragGrain($0, stage) }),
                colors: Binding(get: { colors }, set: { colors = $0; WelcomeYours.dragColors($0, stage) }),
                shift: Binding(get: { shift }, set: { shift = $0; WelcomeYours.shift($0, stage) }),
                site: .constant(false),
                drawings: Binding(get: { drawings }, set: { drawings = $0; WelcomeYours.draw($0, strength: strength, stage) }),
                strength: Binding(get: { strength }, set: { strength = $0; WelcomeYours.draw(drawings, strength: $0, stage) })),
                bare: true, offersSite: false)
                // Let go: the rest of the window-to-be catches up with the
                // color, the tabs' ink on it.
                .simultaneousGesture(DragGesture(minimumDistance: 0).onEnded { _ in stage.needsRefresh() })
        }
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(spaces.indices, id: \.self) { index in
                let on = index == min(WelcomeYours.space, spaces.count - 1)
                Button { WelcomeYours.pickSpace(index, stage) } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(nsColor: Swatch.custom.color(dark: scheme == .dark, custom: spaces[index].color)))
                            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                            .frame(width: 18, height: 18)
                        Text(spaces[index].name)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 36)
                    .background {
                        if on { RoundedRectangle(cornerRadius: Radius.surface, style: .continuous).fill(Palette.wash) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(spaces[index].name)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }
}
