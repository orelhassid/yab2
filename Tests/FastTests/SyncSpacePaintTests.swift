import AppKit
import Foundation
import SwiftUI
import Testing
import SyncKit
@testable import Fast

/// Row 1368: only a space's paint is shared. A window's selected space and
/// color defaults stay local, including when an older Mac sends its look
/// as settings. Row 1384 also keeps each local window's wash and gradient
/// turn apart. Runs real switches, receive and adopt with registered windows.
@MainActor @Suite(.serialized)
struct SyncSpacePaintTests {
    private static let otherID = UUID(uuidString: "D31DDAA3-66C2-4276-9518-371368000001")!
    private static let emptyID = UUID(uuidString: "D31DDAA3-66C2-4276-9518-371368000002")!
    private static let red = SpacePaint(swatch: .custom, color: NSColor(hex: "D9463B")!, grain: 0.1,
                                        colors: ["D9463B", "F3B29D"], transparency: 0.15)
    private static let green = SpacePaint(swatch: .sage, color: NSColor(hex: "16845F")!, grain: 0.2,
                                          colors: ["16845F", "96C9AB"], transparency: 0.25)
    private static let blue = SpacePaint(swatch: .sky, color: NSColor(hex: "2F6FD8")!, grain: 0.7,
                                         colors: ["2F6FD8", "8DBAF0"], transparency: 0.55,
                                         shift: true, site: true, mode: "dark", glass: true)
    private static let gold = SpacePaint(swatch: .custom, color: NSColor(hex: "C58B22")!, grain: 0.3,
                                         colors: ["C58B22", "F2D897"], transparency: 0.35)
    private static let paintKeys = ["backdrop.swatch", "backdrop.color", "backdrop.transparency",
                                    "backdrop.grain.amount", "backdrop.grain", "backdrop.colors",
                                    "backdrop.shift", "backdrop.site-tint", "backdrop.drawings",
                                    "backdrop.drawings.strength", "backdrop.mode", "backdrop.glass"]

    @MainActor private final class World {
        let center = SyncCenter()
        let spaces: [Space]
        private let previousSpaces: [Space]
        private let previousSharing: Set<UUID>
        private let saved: [String: Any]
        private var windows: [(Browser, NSWindow)] = []

        private static var keys: Set<String> {
            Set(SyncSpacePaintTests.paintKeys + ["spaces", "space.current", "backdrop", "quit.warn", SyncCategory.preferenceKey])
        }

        init() throws {
            try #require(Store.testing && Store.unitTests)
            _ = NSApplication.shared
            SyncShapes.register()
            previousSpaces = Spaces.read()
            previousSharing = Spaces.sharing
            saved = Store.settings.dictionaryRepresentation().filter { Self.keys.contains($0.key) }
            for (key, value) in SyncSpacePaintTests.defaults(SyncSpacePaintTests.red) {
                Store.settings.set(value, forKey: key)
            }
            Store.settings.set(Space.firstID.uuidString, forKey: "space.current")
            Store.settings.set(true, forKey: "spaces")
            Store.settings.set(true, forKey: "quit.warn")
            Store.settings.set([], forKey: SyncCategory.preferenceKey)
            spaces = [
                Space(id: Space.firstID, name: "Receiver", icon: "📁", ownSignIns: false, paint: SyncSpacePaintTests.red),
                Space(id: SyncSpacePaintTests.otherID, name: "Other", icon: "📁", ownSignIns: false, paint: SyncSpacePaintTests.green),
                Space(id: SyncSpacePaintTests.emptyID, name: "Legacy", icon: "📁", ownSignIns: false),
            ]
            Spaces.write(spaces)
        }

        func browser(_ space: UUID) -> Browser {
            let id = UUID()
            Store.settings.set(space.uuidString, forKey: "window.\(id.uuidString).space")
            let browser = Browser(windowID: id)
            let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: 800, height: 600),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            BrowserWindows.shared.register(window, for: browser)
            windows.append((browser, window))
            return browser
        }

        func close() {
            for (browser, window) in windows {
                window.close()
                browser.letGo()
                browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
                if let id = browser.windowID {
                    Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
                    for suffix in [""] + spaces.map({ "-" + $0.id.uuidString }) {
                        try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString)\(suffix).json"))
                    }
                }
            }
            windows = []
            Spaces.write(previousSpaces)
            Spaces.sharing = previousSharing
            for key in Self.keys { Store.settings.set(saved[key], forKey: key) }
        }
    }

    private static func defaults(_ paint: SpacePaint, spaces: Bool = true) -> [String: Any] {
        ["spaces": spaces, "backdrop": "color", "backdrop.swatch": paint.swatch,
         "backdrop.color": paint.color, "backdrop.transparency": paint.transparency,
         "backdrop.grain.amount": paint.grain, "backdrop.grain": paint.grain > 0,
         "backdrop.colors": paint.colors, "backdrop.shift": paint.shift, "backdrop.site-tint": paint.site,
         "backdrop.drawings": paint.drawings, "backdrop.drawings.strength": paint.drawingsStrength,
         "backdrop.mode": paint.mode, "backdrop.glass": paint.glass, "quit.warn": false]
    }

    /// An older Mac's settings (blue, its space's look) and, when given,
    /// its spaces, through the real receive and adopt.
    @discardableResult
    private func deliver(_ world: World, spaces: Bool = true, replacing: [Space]? = nil,
                         withSettings: Bool = true, removing: Bool = false) throws -> Journal {
        let sender = try Journal(path: nil, device: "paint-sender")
        let receiver = try Journal(path: nil, device: "paint-receiver")
        if withSettings {
            var values = Self.defaults(Self.blue, spaces: spaces)
            values["space.current"] = Self.otherID.uuidString
            // Bypass today's allowlist to exercise records older clients wrote.
            var settings = SyncShapes.settings(values, addons: false)
            for key in Self.paintKeys + ["space.current"] {
                if let value = values[key].flatMap({ SyncShapes.plist($0) }) { settings[key] = ["value": value] }
            }
            try sender.reconcile(SyncShapes.setting, settings)
            if removing { try sender.reconcile(SyncShapes.setting, [:]) }
        }
        if let replacing { try sender.reconcile(SyncShapes.space, SyncShapes.spaces(replacing, orders: [:])) }
        let records = sender.all(SyncShapes.setting) + sender.all(SyncShapes.space)
        let changed = try SyncCenter.receive(records.map { ($0, 1) }, into: receiver, localRows: nil, device: "paint-receiver")
        world.center.adopt(changed, from: receiver)
        return receiver
    }

    private func wears(_ prefs: Preferences, _ paint: SpacePaint) -> Bool {
        SpacePaint(prefs) == paint
    }

    private func expectDefaults(_ values: [String: Any]) {
        for key in Self.paintKeys + ["space.current"] {
            #expect(Store.settings.object(forKey: key).flatMap { SyncShapes.plist($0) }
                    == values[key].flatMap { SyncShapes.plist($0) })
        }
    }

    @Test(arguments: [false, true])
    func aLocalSpaceSwitchLeavesTheOtherWindowsColorAlone(reverse: Bool) throws {
        let world = try World(); defer { world.close() }
        let first: Browser, second: Browser
        if reverse {
            second = world.browser(Self.otherID)
            first = world.browser(Space.firstID)
        } else {
            first = world.browser(Space.firstID)
            second = world.browser(Self.otherID)
        }
        first.setSpacePaint(Self.emptyID, to: Self.blue)
        let firstBackdrop = WindowBackdropView(frame: .zero), secondBackdrop = WindowBackdropView(frame: .zero)
        let firstWash = WashView(frame: .zero), secondWash = WashView(frame: .zero)
        firstBackdrop.bind(to: first.spaceWash); firstWash.bind(to: first.spaceWash)
        secondBackdrop.bind(to: second.spaceWash); secondWash.bind(to: second.spaceWash)
        firstBackdrop.wear(try #require(SpaceWash.worn(first.prefs)))
        secondBackdrop.wear(try #require(SpaceWash.worn(second.prefs)))
        let secondPaint = SpaceWash.grounded(in: second)
        let colors = secondBackdrop.coating.gradient.colors as? [CGColor]
        let opacity = secondBackdrop.coating.layer?.opacity

        first.switchSpace(to: Self.emptyID)
        #expect(first.spaceID == Self.emptyID && wears(first.prefs, Self.blue))
        #expect(second.spaceID == Self.otherID && wears(second.prefs, Self.green))
        #expect(SpaceWash.grounded(in: second) == secondPaint)
        #expect((secondBackdrop.coating.gradient.colors as? [CGColor]) == colors)
        #expect(secondBackdrop.coating.layer?.opacity == opacity)
        #expect(secondWash.layer?.animation(forKey: "wash") == nil)
        #expect(first.spaceWash !== second.spaceWash)
        #expect(first.spaceWash.backdrop === firstBackdrop && second.spaceWash.backdrop === secondBackdrop)

        second.switchSpace(to: Space.firstID)
        #expect(second.spaceID == Space.firstID && wears(second.prefs, Self.red))
        #expect(first.spaceID == Self.emptyID && wears(first.prefs, Self.blue))
    }

    private func wornStep(_ browser: Browser) -> Int {
        var result = -1
        let view = LookWorn(browser: browser) { _, step -> EmptyView in
            result = step
            return EmptyView()
        }
        _ = view.body
        return result
    }

    @Test func gradientTurnsAndTabCountsBelongToTheirWindow() throws {
        let world = try World(); defer { world.close() }
        let first = world.browser(Space.firstID), second = world.browser(Self.otherID)
        let card = LookCard.shared
        var green = Self.green
        green.shift = true
        first.setSpacePaint(Self.otherID, to: green)
        for browser in [first, second] {
            browser.prefs.lookShift = true
            browser.lay([])
            card.counted(browser)
        }
        first.lay(first.tabs + [Tab(), Tab()])
        card.counted(first)
        #expect(wornStep(first) == 2 && wornStep(second) == 0)
        second.lay(second.tabs + [Tab()])
        card.counted(second)
        #expect(wornStep(first) == 2 && wornStep(second) == 1)
        _ = card.bench(["step": true], first)
        #expect(card.report(first)["step"] as? Int == 3)
        #expect(card.report(second)["step"] as? Int == 1)
        #expect(wornStep(first) == 3 && wornStep(second) == 1)

        first.switchSpace(to: Self.otherID)
        card.counted(first)
        card.counted(second)
        #expect(wornStep(first) == 3 && wornStep(second) == 1)
        first.lay(first.tabs + [Tab()])
        card.counted(first)
        #expect(wornStep(first) == 4 && wornStep(second) == 1)
    }

    @Test func openingSharedLibrariesPreservesTheSpaceAppearance() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Space.firstID)
        let card = LookCard.shared
        browser.prefs.lookShift = true
        browser.lay([])
        card.counted(browser)
        for page in [LibraryPage.downloads, .bookmarks] {
            browser.showLibrary(page)
            card.counted(browser)
            #expect(browser.active?.libraryPage == page)
            #expect(browser.dresser == nil && browser.lookStep == 0)
        }
    }

    @Test func switchingSpacesNeverWritesWindowSettings() throws {
        let journal = try Journal(path: nil, device: "paint-sender")
        let windowKey = "window.\(UUID().uuidString).space"
        var values = Self.defaults(Self.red)
        values["space.current"] = Space.firstID.uuidString
        values[windowKey] = Space.firstID.uuidString
        let keys = Self.paintKeys + ["space.current", windowKey]
        for key in keys {
            #expect(!SyncShapes.syncs(key))
            #expect(SyncShapes.settings(values)[key] == nil)
        }
        _ = try SyncShapes.reconcileSettings(journal, values, addons: false)
        let before = journal.all(SyncShapes.setting)
        values.merge(Self.defaults(Self.blue)) { _, incoming in incoming }
        values["space.current"] = Self.otherID.uuidString
        values[windowKey] = Self.otherID.uuidString
        _ = try SyncShapes.reconcileSettings(journal, values, addons: false)
        #expect(journal.all(SyncShapes.setting) == before)
    }

    @Test func windowsKeepTheirSpacesPaintWhenAnotherMacSwitches() throws {
        let world = try World(); defer { world.close() }
        let first = world.browser(Space.firstID), second = world.browser(Self.otherID)
        try #require(wears(first.prefs, Self.red) && wears(second.prefs, Self.green))
        let beforeDefaults = Store.settings.dictionaryRepresentation()
        let receiver = try deliver(world)
        #expect(wears(first.prefs, Self.red))
        #expect(wears(second.prefs, Self.green))
        #expect(first.spaceID == Space.firstID && second.spaceID == Self.otherID)
        expectDefaults(beforeDefaults)
        // Neither echo nor remove the older Mac's defaults on the next flush.
        let keys = Self.paintKeys + ["space.current"]
        let before = keys.map { receiver.record(.init(collection: SyncShapes.setting, id: $0)) }
        _ = try SyncShapes.reconcileSettings(receiver, Store.settings.dictionaryRepresentation(), addons: false)
        for (key, record) in zip(keys, before) {
            #expect(receiver.record(.init(collection: SyncShapes.setting, id: key)) == record)
        }
    }

    @Test func aSpaceWithoutPaintKeepsLocalDefaults() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Self.emptyID)
        try #require(wears(browser.prefs, Self.red))
        let before = Store.settings.dictionaryRepresentation()
        try deliver(world)
        #expect(wears(browser.prefs, Self.red))
        #expect(browser.spaceID == Self.emptyID)
        expectDefaults(before)
        let reopened = world.browser(Self.emptyID)
        #expect(wears(reopened.prefs, Self.red))
    }

    @Test func spacesTurnedOffKeepLocalDefaults() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Space.firstID)
        try #require(wears(browser.prefs, Self.red))
        try deliver(world, spaces: false)
        #expect(!browser.prefs.usesSpaces)
        #expect(wears(browser.prefs, Self.red))
        #expect(browser.spaceID == Space.firstID)
    }

    @Test func legacyRemovalsLeaveLocalSelectionAndPaintAlone() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Self.emptyID)
        let before = Store.settings.dictionaryRepresentation()
        try deliver(world, removing: true)
        expectDefaults(before)
        #expect(browser.spaceID == Self.emptyID)
        #expect(wears(browser.prefs, Self.red))
    }

    @Test func anEditOfTheShownSpacesPaintStillComes() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Space.firstID)
        try #require(wears(browser.prefs, Self.red))
        var edited = world.spaces
        edited[0].paint = Self.gold
        edited[1].paint = Self.blue
        try deliver(world, replacing: edited)
        #expect(browser.space.paint == Self.gold)
        #expect(wears(browser.prefs, Self.gold))
        #expect(browser.spaceID == Space.firstID)
        #expect(browser.spaces.first { $0.id == Self.otherID }?.paint == Self.blue)
    }

    @Test func anEditOfAnotherSpacesPaintDoesNotRepaintThisWindow() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Space.firstID)
        var edited = world.spaces
        edited[1].paint = Self.blue
        try deliver(world, replacing: edited, withSettings: false)
        #expect(browser.spaces.first { $0.id == Self.otherID }?.paint == Self.blue)
        #expect(browser.spaceID == Space.firstID)
        #expect(wears(browser.prefs, Self.red))
    }

    @Test func activeProfileChangeRetainsPinIdentity() throws {
        let previousCurrent = Spaces.current
        let world = try World()
        let browser = Browser()
        defer { world.close(); browser.letGo(); Spaces.current = previousCurrent }
        let id = UUID()
        browser.tabs.forEach { $0.close() }
        browser.spaces = world.spaces + [Space(id: id, name: "Pinned profile", icon: "📌", ownSignIns: false)]
        Spaces.write(browser.spaces)
        browser.spaceID = id
        browser.pinsShared = false // This fixture checks a per-Space pin.
        let page = Store.file("profile-pin-" + id.uuidString + ".html")
        try "<title>Kept pin</title>".write(to: page, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: page) }
        let pin = Tab(later: Spaces.store(for: id))
        pin.restore(url: page, title: "Kept pin")
        pin.pin = "P"
        browser.showRow([pin], active: pin.id)
        browser.setSpaceSignIns(id, own: true)
        let back = try #require(browser.tabs.first)
        #expect(back.id == pin.id)
        #expect(back.pin == "P")
        #expect(browser.activeID == pin.id)
        #expect(pin.gone)
    }

    @Test func unchangedSyncedMembershipKeepsImportProvenance() throws {
        let world = try World(); defer { world.close() }
        var local = world.spaces
        local[1].ownSignIns = true
        local[1].signedInAs = "Arc:Profile 1"
        Spaces.write(local)
        try deliver(world, replacing: local, withSettings: false)
        #expect(Spaces.read().first { $0.id == Self.otherID }?.signedInAs == "Arc:Profile 1")
        local[1].signInWith = UUID()
        try deliver(world, replacing: local, withSettings: false)
        #expect(Spaces.read().first { $0.id == Self.otherID }?.signedInAs == nil)
    }

    @Test func remoteProfileLinkAndExplicitClearReachEveryWindow() throws {
        let world = try World(); defer { world.close() }
        let first = world.browser(Self.otherID)
        let second = world.browser(Self.otherID)
        var edited = world.spaces
        edited[1].ownSignIns = true
        edited[1].signInWith = Self.emptyID
        edited[2].ownSignIns = true
        try deliver(world, replacing: edited, withSettings: false)
        #expect(first.space.profileID == Self.emptyID)
        #expect(second.space.profileID == Self.emptyID)
        #expect(Spaces.store(for: Self.otherID) === Spaces.store(for: Self.emptyID))
        edited[1].signInWith = nil
        try deliver(world, replacing: edited, withSettings: false)
        #expect(first.space.signInWith == nil)
        #expect(second.space.signInWith == nil)
        #expect(first.space.profileID == Self.otherID)
        #expect(Spaces.store(for: Self.otherID) !== Spaces.store(for: Self.emptyID))
        #expect(first.space.paint == Self.green)
        #expect(second.space.paint == Self.green)
    }

    @Test func ownEditsStillSaveAfterwards() throws {
        let world = try World(); defer { world.close() }
        let browser = world.browser(Space.firstID)
        try deliver(world)
        #expect(!browser.prefs.warnsOnQuit)
        browser.prefs.swatch = Self.gold.picked
        browser.prefs.backdropColor = Self.gold.own
        #expect(Store.settings.string(forKey: "backdrop.swatch") == Self.gold.swatch)
        #expect(Store.settings.string(forKey: "backdrop.color") == Self.gold.color)
    }
}
