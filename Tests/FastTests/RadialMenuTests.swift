import AppKit
import Testing
@testable import Fast

@MainActor
struct RadialMenuTests {
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @Test func nestedRingTracksEverySpaceAndCancelsInCenter() {
        for count in [1, 3, 12] {
            var selection = RadialSelection()
            selection.move(CGPoint(x: 48, y: -80), spaceCount: count)
            #expect(selection.showsSpaces)
            for index in 0..<count {
                let angle = -.pi / 3 + 2 * Double.pi * Double(index) / Double(count)
                selection.move(CGPoint(x: 160 * cos(angle), y: 160 * sin(angle)), spaceCount: count)
                #expect(selection.space == index)
            }
            selection.move(.zero, spaceCount: count)
            #expect(selection.space == nil && selection.wedge == nil)
        }
    }

    @Test func eightDirectionsKeepNavigationAlignedAndExtraCommandsSurviveResizing() {
        let store = Store.settings
        let keys = [RadialPreferences.slotsKey, RadialPreferences.extraKey, RadialPreferences.countKey]
        let previous = keys.map { store.object(forKey: $0) }
        defer { for (key, value) in zip(keys, previous) { store.set(value, forKey: key) } }
        store.set(8, forKey: RadialPreferences.countKey)
        var eight = RadialPreferences.slots("", extra: "", count: 8)
        eight[2] = .settings
        RadialPreferences.save(eight)
        var selection = RadialSelection(slots: eight)
        for index in eight.indices {
            let angle = Double(index) * .pi / 4
            selection.move(CGPoint(x: 92 * cos(angle), y: 92 * sin(angle)), spaceCount: 3)
            #expect(selection.wedge == index)
        }
        #expect(eight[0] == .forward && eight[4] == .back)
        #expect(selection.showsSpaces)
        selection.move(CGPoint(x: 115, y: -115), spaceCount: 3)
        #expect(selection.space == 0)
        store.set(6, forKey: RadialPreferences.countKey)
        #expect(RadialPreferences.saved == RadialSelection.commands)
        store.set(8, forKey: RadialPreferences.countKey)
        #expect(RadialPreferences.saved == eight)
    }

    @Test func reassignedSpacesUsesItsNewDirectionInBothLayouts() {
        let slots: [Command?] = [nil, .downloads, .back, .reload, .newTab, .forward]
        let saved = RadialPreferences.decode(RadialPreferences.encode(slots))
        var selection = RadialSelection(slots: saved)
        selection.move(CGPoint(x: 90, y: 0), spaceCount: 3)
        selection.move(CGPoint(x: 160, y: 0), spaceCount: 3)
        #expect(selection.space == 0)
        let browser = Browser(windowID: UUID())
        let rows = RadialDropdownRow.commands(saved, browser: browser)
        #expect(rows.map(\.title) == slots.map { $0?.title ?? "Spaces" })
        #expect(rows.first?.children == true)
        #expect(rows.allSatisfy { !$0.icon.isEmpty })
    }

    @Test func rightHoldOpensWheelAndReleaseOpensDownloads() async throws {
        let browser = Browser(windowID: UUID())
        let tab = browser.open(URL(string: "about:blank#radial-menu-test")!, foreground: true)
        let window = KeyWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                               styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.page
        BrowserWindows.shared.register(window, for: browser)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); browser.tabs.forEach { $0.close() } }
        MouseGestureInput.shared.install()

        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            NSApp.sendEvent(event)
        }
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
        let previous = Store.settings.object(forKey: RadialPreferences.layoutKey)
        defer {
            Store.settings.set(previous, forKey: RadialPreferences.layoutKey)
        }
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

        // Repeat the hold over native content and release directly on Downloads.
        let nativePage = NSView(frame: window.contentView!.bounds)
        window.contentView = nativePage
        MouseGestureInput.shared.registerPage(nativePage)
        try mouse(.rightMouseDown, x: 320, y: 240)
        try await Task.sleep(for: .milliseconds(450))
        let nativeMenu = try #require(nativePage.subviews.compactMap { $0 as? RadialDropdownHost }.first)
        let nativeRow = downloadsRow(nativeMenu)
        try mouse(.rightMouseDragged, x: nativeRow.x, y: nativeRow.y)
        #expect(nativeMenu.rootView.selected == 1)
        try mouse(.rightMouseUp, x: nativeRow.x, y: nativeRow.y)
        #expect(browser.active?.libraryPage == .downloads)
        #expect(nativeMenu.superview == nil)
    }
}
