import AppKit
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct ChatRestorationTests {
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: 1000, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func savedPageFocusReturnsWithoutChangingTheWindow() throws {
        let window = makeWindow(), page = UUID()
        defer { window.close() }
        let original = NSTextView(frame: .zero), chat = NSTextView(frame: .zero)
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(chat)
        try #require(window.makeFirstResponder(original))
        let frame = window.frame
        let saved = ChatRestoration(in: window, page: page, field: false)
        try #require(window.makeFirstResponder(chat))
        #expect(saved.restore(in: window, page: page, field: false))
        #expect(window.firstResponder === original)
        #expect(window.frame == frame)
    }

    @Test func sharedFieldEditorReturnsToItsOriginalControlAndSelection() throws {
        let window = makeWindow(), page = UUID()
        defer { window.close() }
        let original = NSTextField(string: "a draft query"), chat = NSTextField(string: "an unsent message")
        original.frame = NSRect(x: 10, y: 10, width: 300, height: 30)
        chat.frame = NSRect(x: 400, y: 10, width: 300, height: 30)
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(chat)
        try #require(window.makeFirstResponder(original))
        let editor = try #require(original.currentEditor() as? NSTextView)
        let selected = NSRange(location: 2, length: 5)
        editor.setSelectedRange(selected)
        let saved = ChatRestoration(in: window, page: page, field: true)
        try #require(window.makeFirstResponder(chat))
        #expect(window.firstResponder === editor, "AppKit reuses the editor for chat")
        #expect(saved.restore(in: window, page: page, field: true))
        let restored = try #require(original.currentEditor() as? NSTextView)
        #expect(restored.delegate === original && window.firstResponder === restored)
        #expect(restored.selectedRange() == selected)
        #expect(original.stringValue == "a draft query")
        #expect(chat.stringValue == "an unsent message")
    }

    @Test func changedPageFieldModeOrWindowRejectsTheOldFocus() throws {
        let window = makeWindow(), other = makeWindow(), page = UUID()
        defer { window.close(); other.close() }
        let original = NSTextView(frame: .zero), chat = NSTextView(frame: .zero)
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(chat)
        try #require(window.makeFirstResponder(original))
        let saved = ChatRestoration(in: window, page: page, field: false)
        try #require(window.makeFirstResponder(chat))
        #expect(!saved.restore(in: window, page: UUID(), field: false))
        #expect(!saved.restore(in: window, page: page, field: true))
        #expect(!saved.restore(in: other, page: page, field: false))
        #expect(window.firstResponder === chat)
        original.removeFromSuperview()
        #expect(!saved.restore(in: window, page: page, field: false))
        #expect(window.firstResponder === chat)
    }

    @Test func aClosedRoomReturnsAllItsWidthOnEitherSide() {
        for leading in [false, true] {
            for card in [false, true] {
                let bounds = CGRect(x: 13, y: 27, width: 1000, height: 700)
                var room = ChatRoom(open: false, rim: DevRoom.Rim(card: card), width: 380, leading: leading)
                let before = room.pageFrame(in: bounds)
                room.open = true
                #expect(room.pageFrame(in: bounds).width == bounds.width - ChatRoom.room(room.rim, width: room.width))
                room.width = 510
                room.open = false
                #expect(room.pageFrame(in: bounds) == before)
                let resized = CGRect(x: 13, y: 27, width: 800, height: 600)
                #expect(room.pageFrame(in: resized) == resized, "closing uses the current window, not a saved frame")
            }
        }
    }

    @Test func homeAndThePageReserveTheSameShellPanelRoom() {
        let rim = DevRoom.Rim(card: false)
        for width in [340.0, 510, 760, 1000, 1600] {
            let bounds = CGRect(x: 13, y: 27, width: width, height: 700)
            for leading in [false, true] {
                let layout = ChatRoom(open: true, rim: rim, width: 510, leading: leading)
                let taken = layout.reservation(in: bounds.width)
                let page = layout.pageFrame(in: bounds)
                #expect(taken + page.width == bounds.width)
                #expect(page.width >= min(240, bounds.width / 2))
                if leading {
                    #expect(page.minX == bounds.minX + taken)
                } else {
                    #expect(page.maxX == bounds.maxX - taken)
                }
            }
        }
    }

    private func withBrowser(_ body: (Browser) async throws -> Void) async throws {
        try #require(Store.testing && Store.world != nil && Store.settings !== UserDefaults.standard)
        let keys = ["mail", "search.suggest", "sidebar", "sidebar.shut", "sidebar.width", "sidebar.flank"]
        let values = keys.map { Store.settings.object(forKey: $0) }
        let dragged = ChatLook.dragged
        let foldersBrowser = Folders.shared.browser
        Store.settings.set(false, forKey: "mail")
        Store.settings.set(false, forKey: "search.suggest")
        let browser = Browser(windowID: UUID())
        defer {
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            browser.letGo()
            browser.dropSpare()
            Folders.shared.browser = foldersBrowser
            ChatLook.dragged = dragged
            for (key, value) in zip(keys, values) {
                if let value { Store.settings.set(value, forKey: key) }
                else { Store.settings.removeObject(forKey: key) }
            }
        }
        try await body(browser)
    }

    private func settle(_ browser: Browser) async throws {
        for _ in 0..<300 {
            if !browser.chatMoving { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("chat movement did not finish")
    }

    @Test(arguments: [false, true])
    func closeRestoresOnlyTheStateBorrowedByOpen(hidden: Bool) async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = true
            browser.prefs.sideShut = hidden
            browser.prefs.sideWidth = 253
            browser.prefs.sideFlank = hidden ? .right : .left
            browser.chatWidth = 417
            browser.editing = true
            browser.query.typed = "keep this query"
            browser.chatAttach.words = "keep this chat draft"
            browser.chatAttach.set([.quote("keep this attachment")])
            let side = browser.sideShown, focus = browser.focusRequest
            browser.moveChat(open: true)
            let saved = try #require(browser.chatRestoration)
            browser.moveChat(open: true)
            #expect(browser.chatRestoration === saved)
            try await settle(browser)
            try #require(browser.chatOpen)
            browser.chatAttach.typing = true
            browser.chatAttach.menu = true
            browser.chatAttach.finishableChatID = "finished"
            browser.hideChat()
            browser.hideChat()
            try await settle(browser)
            #expect(!browser.chatOpen && !browser.chatMoving && browser.chatRestoration == nil)
            #expect(!browser.chatAttach.typing && !browser.chatAttach.menu && browser.chatAttach.finishableChatID == nil)
            #expect(browser.focusRequest == focus + 1, "the existing field gets its keys back")
            #expect(browser.editing && browser.typed == "keep this query")
            #expect(browser.chatAttach.words == "keep this chat draft")
            #expect(browser.chatAttach.items(for: nil) == [.quote("keep this attachment")])
            #expect(browser.prefs.sideShut == hidden && browser.prefs.sideWidth == 253)
            #expect(browser.prefs.sideFlank == (hidden ? .right : .left))
            #expect(browser.sideShown == side && browser.chatWidth == 417)
            let returned = browser.focusRequest
            browser.hideChat()
            #expect(browser.focusRequest == returned, "another close must not take focus again")
        }
    }

    @Test func closingPreservesWidthsAndSidebarChangesMadeWhileChatWasOpen() async throws {
        try await withBrowser { browser in
            browser.prefs.sidebar = true
            browser.prefs.sideShut = false
            browser.moveChat(open: true)
            try await settle(browser)
            browser.prefs.sideShut = true
            browser.prefs.sideWidth = 271
            browser.chatWidth = 493
            browser.hideChat()
            try await settle(browser)
            #expect(browser.prefs.sideShut && browser.prefs.sideWidth == 271)
            #expect(browser.chatWidth == 493)
        }
    }

    @Test func cancelledTransitionsDoNotLoseOrRestoreTheWrongSnapshot() async throws {
        try await withBrowser { browser in
            let focus = browser.focusRequest
            browser.moveChat(open: true)
            #expect(browser.chatRestoration != nil)
            browser.hideChat()
            #expect(browser.chatRestoration == nil && !browser.chatMoving)
            try await Task.sleep(for: .milliseconds(60))
            #expect(!browser.chatOpen && browser.focusRequest == focus)

            browser.moveChat(open: true)
            try await settle(browser)
            let saved = try #require(browser.chatRestoration)
            browser.hideChat()
            browser.moveChat(open: true)
            try await Task.sleep(for: .milliseconds(60))
            #expect(browser.chatOpen && !browser.chatMoving)
            #expect(browser.chatRestoration === saved && browser.focusRequest == focus)
            browser.hideChat()
            try await settle(browser)
            #expect(browser.chatRestoration == nil && !browser.chatOpen)

            browser.moveChat(open: true)
            try await settle(browser)
            browser.hideChat()
            try await Task.sleep(for: .milliseconds(60))
            try #require(!browser.chatOpen)
            let returned = browser.focusRequest
            browser.moveChat(open: true)
            let reopened = try #require(browser.chatRestoration)
            try await settle(browser)
            #expect(browser.chatOpen && browser.chatRestoration === reopened)
            #expect(browser.focusRequest == returned, "the old departure cannot return focus after reopening")
            browser.hideChat()
            try await settle(browser)
        }
    }

    @Test func askingDuringAQueuedCloseKeepsTheOpenSession() async throws {
        // askInChat stands down with no model to ask (AIUse.offers, since
        // 4802102d1); this test is about the queued close, so it has one.
        let oldReady = Agents.assumedInTests
        Agents.assumedInTests = true
        defer { Agents.assumedInTests = oldReady }
        try await withBrowser { browser in
            let tab = Tab(bench: true)
            tab.restore(url: URL(string: "https://chat.example.test/")!, title: "Chat context")
            browser.lay([tab])
            browser.activeID = tab.id
            browser.moveChat(open: true)
            try await settle(browser)
            let saved = try #require(browser.chatRestoration)
            browser.hideChat()
            try #require(browser.chatMovement.target == false && browser.chatOpen)
            browser.askInChat(about: tab)
            #expect(browser.chatMovement.target != false, "the latest ask must cancel the queued close")
            try await settle(browser)
            #expect(browser.chatOpen, "a superseded close must not hide the new ask")
            #expect(browser.chatRestoration === saved, "reversing a queued close keeps the original borrowed state")
            browser.hideChat()
            try await settle(browser)
            #expect(!browser.chatOpen && browser.chatRestoration == nil)
        }
    }

    @Test func showingChatDuringAQueuedCloseKeepsTheOpenSession() async throws {
        try await withBrowser { browser in
            browser.moveChat(open: true)
            try await settle(browser)
            let saved = try #require(browser.chatRestoration)
            browser.hideChat()
            try #require(browser.chatMovement.target == false && browser.chatOpen)
            let focus = browser.chatFocus
            browser.showChat(nil)
            #expect(browser.chatMovement.target != false)
            #expect(browser.chatFocus == focus + 1, "the cancelled opening callback cannot focus the reopened column")
            try await settle(browser)
            #expect(browser.chatOpen && browser.chatRestoration === saved)
            browser.hideChat()
            try await settle(browser)
        }
    }


    @Test(arguments: [0, 30, 80])
    func sixRapidTogglesReleaseTheFinalClosedSession(gap: Int) async throws {
        try await withBrowser { browser in
            for _ in 0..<6 {
                browser.toggleChat()
                if gap > 0 { try await Task.sleep(for: .milliseconds(gap)) }
            }
            try await settle(browser)
            #expect(!browser.chatOpen && !browser.chatMoving)
            #expect(browser.chatMovement.target == nil && browser.chatRestoration == nil)
        }
    }

    @Test func savedFocusKeepsAWindowMovedAndResizedByTheUser() throws {
        let window = makeWindow(), page = UUID()
        defer { window.close() }
        let original = NSTextView(frame: .zero), chat = NSTextView(frame: .zero)
        window.contentView?.addSubview(original)
        window.contentView?.addSubview(chat)
        try #require(window.makeFirstResponder(original))
        let saved = ChatRestoration(in: window, page: page, field: false)
        try #require(window.makeFirstResponder(chat))
        var changed = window.frame
        changed.origin.x += 40
        changed.origin.y += 25
        changed.size.width += 120
        changed.size.height += 50
        window.setFrame(changed, display: false)
        #expect(saved.restore(in: window, page: page, field: false))
        #expect(window.firstResponder === original)
        #expect(window.frame == changed)
    }

}
