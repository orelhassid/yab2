import AppKit
import SwiftUI
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct RadialMenuTests {
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    private final class NativePage: NSView {
        private(set) var contextPresses = 0

        override func rightMouseDown(with event: NSEvent) {
            contextPresses += 1
        }
    }

    @Test func nestedRingTracksEverySpaceAndCancelsInCenter() {
        for count in [1, 3, 12] {
            var selection = RadialSelection()
            selection.move(CGPoint(x: 48, y: -80), childCount: count)
            #expect(selection.showsChildren)
            for index in 0..<count {
                let angle = -.pi / 3 + 2 * Double.pi * Double(index) / Double(count)
                selection.move(CGPoint(x: 160 * cos(angle), y: 160 * sin(angle)), childCount: count)
                #expect(selection.child == index)
            }
            selection.move(.zero, childCount: count)
            #expect(selection.child == nil && selection.wedge == nil)
        }
    }

    @Test func eightDirectionsKeepNavigationAlignedAndExtraCommandsSurviveResizing() {
        let store = Store.settings
        let keys = [RadialPreferences.slotsKey, RadialPreferences.extraKey, RadialPreferences.countKey]
        let previous = keys.map { store.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { store.set(value, forKey: key) } }
        store.set(8, forKey: RadialPreferences.countKey)
        var eight = RadialPreferences.slots("", extra: "", count: 8)
        eight[2] = .command(.settings)
        RadialPreferences.save(eight)
        var selection = RadialSelection(slots: eight)
        for index in eight.indices {
            let angle = Double(index) * .pi / 4
            selection.move(CGPoint(x: 92 * cos(angle), y: 92 * sin(angle)), childCount: 3)
            #expect(selection.wedge == index)
        }
        #expect(eight[0] == .command(.forward) && eight[4] == .command(.back))
        #expect(selection.showsChildren)
        selection.move(CGPoint(x: 115, y: -115), childCount: 3)
        #expect(selection.child == 0)
        store.set(6, forKey: RadialPreferences.countKey)
        #expect(RadialPreferences.saved == RadialSelection.commands)
        store.set(8, forKey: RadialPreferences.countKey)
        #expect(RadialPreferences.saved == eight)
    }

    @Test func reassignedSpacesUsesItsNewDirectionInBothLayouts() {
        let slots: [RadialItem] = [.spaces, .command(.downloads), .command(.back), .command(.reload), .command(.newTab), .command(.forward)]
        let saved = RadialPreferences.decode(RadialPreferences.encode(slots))
        var selection = RadialSelection(slots: saved)
        selection.move(CGPoint(x: 90, y: 0), childCount: 3)
        selection.move(CGPoint(x: 160, y: 0), childCount: 3)
        #expect(selection.child == 0)
        let browser = Browser(windowID: UUID())
        let rows = RadialDropdownRow.commands(saved, browser: browser)
        #expect(rows.map(\.title) == slots.map(\.title))
        #expect(rows.first?.children == true)
        #expect(rows.allSatisfy { !$0.icon.isEmpty })
    }

    @Test func tenSlotsAndSubmenuAssignmentsRoundTripAcrossSizes() {
        let store = Store.settings
        let keys = [RadialPreferences.slotsKey, RadialPreferences.extraKey, RadialPreferences.additionalKey, RadialPreferences.countKey]
        let previous = keys.map { store.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { store.set(value, forKey: key) } }
        let original = RadialPreferences.slots("forward|downloads|newTab|back|reload|radial.spaces",
                                               extra: "bookmarks|history", count: 10)
        var submenu = RadialSubmenu()
        submenu.count = 10
        submenu.commands[9] = .downloads
        var ten = original
        ten[1] = .submenu(submenu)
        ten[6] = .command(.history)
        RadialPreferences.save(ten)
        for count in [6, 8] {
            store.set(count, forKey: RadialPreferences.countKey)
            #expect(!RadialPreferences.saved.contains(.submenu(submenu)))
            #expect(RadialPreferences.saved.count == count)
        }
        store.set(10, forKey: RadialPreferences.countKey)
        #expect(RadialPreferences.saved == ten)
        #expect(RadialPreferences.validated(RadialPreferences.encode(ten), count: 10) == ten)
        #expect(RadialPreferences.validated("radial.menu|made-up", count: 2) == nil)
        #expect(RadialPreferences.validated("radial.menu", count: 1) == [.submenu(RadialSubmenu())])
        var selection = RadialSelection(slots: ten)
        for index in ten.indices {
            let angle = Double(index) * .pi / 5
            selection.move(CGPoint(x: 92 * cos(angle), y: 92 * sin(angle)), childCount: 10)
            #expect(selection.wedge == index)
        }
    }

    @Test func rightClickOpensAndSelectsInBothLayouts() async throws {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let tab = browser.open(URL(string: "about:blank#radial-menu-test")!, foreground: true)
        let window = KeyWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                               styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.page
        BrowserWindows.shared.register(window, for: browser)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); browser.tabs.forEach { $0.close() } }
        RadialMenuInput.shared.install()

        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            NSApp.sendEvent(event)
        }
        let keys = [RadialPreferences.layoutKey, RadialPreferences.slotsKey, RadialPreferences.countKey,
                    RadialPreferences.sensitivityKey, "mouse.gestures.enabled"]
        let previous = keys.map { Store.settings.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { Store.settings.set(value, forKey: key) } }
        Store.settings.set("wheel", forKey: RadialPreferences.layoutKey)
        Store.settings.set(6, forKey: RadialPreferences.countKey)
        Store.settings.set(true, forKey: "mouse.gestures.enabled")
        Store.settings.removeObject(forKey: RadialPreferences.sensitivityKey)
        var slots = RadialSelection.commands
        slots[5] = .command(.newTab)
        RadialPreferences.save(slots)

        try mouse(.rightMouseDown, x: 30, y: 230)
        try mouse(.rightMouseDragged, x: 30, y: 238)
        let immediateMenu = try #require(tab.page.subviews.compactMap { $0 as? RadialMenuHost }.first)
        #expect(immediateMenu.rootView.selection.wedge == 5)
        try mouse(.rightMouseUp, x: 30, y: 239)
        #expect(immediateMenu.superview == nil)
        #expect(browser.editing && browser.asked == .tab)
        browser.editing = false
        browser.select(tab)
        Store.settings.set(40, forKey: RadialPreferences.sensitivityKey)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try mouse(.rightMouseDragged, x: 320, y: 258)
        #expect(!tab.page.subviews.contains { $0 is RadialMenuHost })
        try mouse(.rightMouseDragged, x: 320, y: 285)
        #expect(tab.page.subviews.contains { $0 is RadialMenuHost })
        try mouse(.rightMouseUp, x: 320, y: 285)
        #expect(browser.editing && browser.asked == .tab)
        browser.editing = false
        Store.settings.removeObject(forKey: RadialPreferences.sensitivityKey)
        RadialPreferences.save(RadialSelection.commands)

        try mouse(.rightMouseDown, x: 320, y: 240)
        try await Task.sleep(for: .milliseconds(450))
        let wheel = try #require(window.contentView?.subviews.compactMap { $0 as? RadialMenuHost }.first)
        try mouse(.rightMouseDragged, x: 367, y: 159)
        #expect(wheel.rootView.selection.wedge == 1)
        #expect(browser.active === tab)
        try mouse(.rightMouseUp, x: 367, y: 159)
        #expect(wheel.superview == nil)
        #expect(browser.active?.libraryPage == .downloads)

        browser.select(tab)
        var custom = RadialSubmenu()
        custom.commands[0] = .downloads
        slots = RadialSelection.commands
        slots[1] = .submenu(custom)
        RadialPreferences.save(slots)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try mouse(.rightMouseDragged, x: 367, y: 159)
        let submenuWheel = try #require(tab.page.subviews.compactMap { $0 as? RadialMenuHost }.first)
        #expect(submenuWheel.rootView.rows.first?.title == Command.downloads.title)
        try mouse(.rightMouseDragged, x: 400, y: 101)
        #expect(submenuWheel.rootView.selection.child == 0)
        try mouse(.rightMouseUp, x: 400, y: 101)
        #expect(browser.active?.libraryPage == .downloads)

        browser.select(tab)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try mouse(.rightMouseDragged, x: 367, y: 159)
        try mouse(.rightMouseUp, x: 367, y: 159)
        #expect(tab.page.subviews.contains { $0 is RadialMenuHost })
        try mouse(.mouseMoved, x: 400, y: 101)
        try mouse(.leftMouseDown, x: 400, y: 101)
        #expect(browser.active?.libraryPage == .downloads)

        browser.select(tab)
        Store.settings.set("dropdown", forKey: RadialPreferences.layoutKey)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try await Task.sleep(for: .milliseconds(450))
        try mouse(.rightMouseUp, x: 320, y: 240)
        let list = try #require(window.contentView?.subviews.compactMap { $0 as? RadialDropdownHost }.first)
        func downloadsRow(_ host: RadialDropdownHost) -> CGPoint {
            let y = RadialDropdown.inset + RadialDropdown.rowHeight * 1.5
            return host.convert(CGPoint(x: 60, y: host.isFlipped ? y : host.bounds.height - y), to: nil)
        }
        let row = downloadsRow(list)
        try mouse(.mouseMoved, x: row.x, y: row.y)
        #expect(list.rootView.selected == 1)

        let child = try #require(tab.page.subviews.compactMap { $0 as? RadialDropdownHost }.first { $0 !== list })
        let childPoint = child.convert(CGPoint(x: 60, y: child.isFlipped ? 25 : child.bounds.height - 25), to: nil)
        try mouse(.mouseMoved, x: childPoint.x, y: childPoint.y)
        #expect(child.rootView.selected == 0)
        child.rootView.choose(0)
        #expect(browser.active?.libraryPage == .downloads)
        #expect(child.superview == nil && list.superview == nil)
        browser.select(tab)
        RadialPreferences.save(RadialSelection.commands)

        // Repeat the hold over native content and release directly on Downloads.
        let nativePage = NativePage(frame: window.contentView!.bounds)
        window.contentView = nativePage
        RadialMenuInput.shared.registerPage(nativePage)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try await Task.sleep(for: .milliseconds(450))
        let nativeMenu = try #require(nativePage.subviews.compactMap { $0 as? RadialDropdownHost }.first)
        let nativeRow = downloadsRow(nativeMenu)
        try mouse(.rightMouseDragged, x: nativeRow.x, y: nativeRow.y)
        #expect(nativeMenu.rootView.selected == 1)
        try mouse(.rightMouseUp, x: nativeRow.x, y: nativeRow.y)
        #expect(browser.active?.libraryPage == .downloads)
        #expect(nativeMenu.superview == nil)

        try mouse(.rightMouseDown, x: 320, y: 240)
        try mouse(.rightMouseUp, x: 320, y: 240)
        #expect(nativePage.contextPresses == 1)
        #expect(!nativePage.subviews.contains { $0 is RadialDropdownHost })

        browser.select(tab)
        browser.enterDevelopment()
        let project = browser.developmentProject
        let pane = NSHostingView(rootView: DevelopmentPane(browser: browser, project: project, entries: [:])
            .environment(browser))
        window.contentView = pane
        pane.layoutSubtreeIfNeeded()
        Store.settings.set("wheel", forKey: RadialPreferences.layoutKey)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try mouse(.rightMouseUp, x: 320, y: 240)
        let projectWheel = try #require(pane.subviews.compactMap { $0 as? RadialMenuHost }.first)
        try mouse(.mouseMoved, x: 367, y: 159)
        #expect(projectWheel.rootView.selection.wedge == 1)
        try mouse(.leftMouseDown, x: 367, y: 159)
        #expect(projectWheel.superview == nil)
        #expect(browser.active?.libraryPage == .downloads)
    }
}
