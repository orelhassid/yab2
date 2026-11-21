import AppKit
import SwiftUI
import Testing
@testable import Fast

/// The column's field shows every chat, one at a time: words typed for one
/// and left unsent stay that chat's. Another chat brought in shows its own
/// field, and the first has its words back when it returns (feedback #1238:
/// a draft followed the person into another agent's chat and went there).
@MainActor
@Suite(.serialized)
struct ChatDraftTests {
    @MainActor final class Shown: ObservableObject {
        @Published var chat: Chat?
    }

    private struct Host: View {
        let browser: Browser
        @ObservedObject var shown: Shown
        var body: some View {
            ChatComposer(browser: browser, chat: shown.chat, live: false, asking: nil, attach: browser.chatAttach)
                .frame(width: 420, height: 160, alignment: .bottom)
        }
    }

    private static func chat(_ id: String) -> Chat {
        Chat(id: id, title: id, began: .field, cli: "claude", items: [], state: "done", answer: "",
             started: Date(), updated: Date())
    }

    @Test func projectContinuationMovesRichDraftAndMergesAttachments() {
        let attach = ChatAttach()
        let file = URL(fileURLWithPath: "/tmp/dashboard.swift")
        let mention = DevelopmentMention(name: "dashboard.swift", detail: "dashboard.swift", symbol: "doc", attachment: .file(file))
        let rich = NSMutableAttributedString(string: "Filter ")
        rich.append(DevelopmentDraft.chip(mention))
        attach.keepProjectDraft(rich, for: nil)
        attach.keep(DevelopmentDraft.plain(rich), for: nil)
        attach.set([.file(file)])
        attach.keep("Earlier draft", for: "destination")
        attach.moveProjectDraft(from: nil, to: "destination")
        #expect(attach.words(for: "destination") == "Earlier draft\n\nFilter @dashboard.swift")
        #expect(attach.items(for: "destination") == [.file(file)])
        #expect(attach.projectDraft(for: "destination").map { DevelopmentDraft.mentioned(in: $0).first?.id } == mention.id)
        #expect(attach.words(for: nil).isEmpty && attach.items(for: nil).isEmpty && attach.projectDraft(for: nil) == nil)
    }

    @Test func namedSessionLeavesCoordinatorResumable() throws {
        var details = try JSONDecoder().decode(DevelopmentDetails.self, from: Data(#"{"name":"Yab","icon":"","folder":"","chatID":"original"}"#.utf8))
        #expect(details.selectedChatID == "original")
        details.chatSelection = DevelopmentDetails.newChat
        #expect(details.selectedChatID == nil)
        details.selectedChatID = "dashboard"
        #expect(details.sessionIDs == ["dashboard"])
        #expect(details.selectedChatID == "dashboard")
        details.chatSelection = nil
        #expect(details.selectedChatID == "original")
        let session = Self.chat("Dashboard prototype")
        #expect(DevelopmentDetails.suggestedChat(for: "Add dashboard filters", among: [session])?.id == session.id)
        #expect(DevelopmentDetails.suggestedChat(for: "What about this?", among: [session]) == nil)
    }

    private func settle() async {
        for _ in 0..<8 {
            await Task.yield()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// The field's editable text: a text field, or its own text view.
    private func field(in view: NSView) -> NSView? {
        var stack: [NSView] = [view]
        while let next = stack.popLast() {
            if let text = next as? NSTextField, text.isEditable { return text }
            if let text = next as? NSTextView, text.isEditable, !text.isFieldEditor { return text }
            stack.append(contentsOf: next.subviews)
        }
        return nil
    }

    private func shownWords(_ field: NSView, in window: NSWindow) -> String {
        if let editor = window.firstResponder as? NSTextView,
           editor === field || (editor.isFieldEditor && editor.delegate as? NSView === field) {
            return editor.string
        }
        return (field as? NSTextField)?.stringValue ?? (field as? NSTextView)?.string ?? ""
    }

    private func withComposer(_ body: (Browser, Shown, NSWindow) async throws -> Void) async throws {
        try #require(Store.testing)
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let shown = Shown()
        let window = NSWindow(contentRect: NSRect(x: -8000, y: -8000, width: 420, height: 160),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Host(browser: browser, shown: shown))
        defer {
            window.contentView = nil
            window.close()
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            browser.letGo()
        }
        try await body(browser, shown, window)
    }

    @Test func wordsTypedForOneChatStayThatChats() async throws {
        try await withComposer { _, shown, window in
            shown.chat = Self.chat("chat-a")
            await settle()
            let content = try #require(window.contentView)
            let text = try #require(field(in: content))
            // Typed into as the keys type: the field's editor, at once,
            // before the composer's focus (closed column here) lets it go.
            try #require(window.makeFirstResponder(text))
            let editor = try #require(window.firstResponder as? NSTextView)
            editor.insertText("Only for chat A", replacementRange: NSRange(location: NSNotFound, length: 0))
            await settle()
            #expect(shownWords(text, in: window) == "Only for chat A")

            shown.chat = Self.chat("chat-b")
            await settle()
            #expect(shownWords(text, in: window) == "", "chat B shows its own field, not A's draft")

            shown.chat = nil
            await settle()
            #expect(shownWords(text, in: window) == "", "a new chat shows its own field too")

            shown.chat = Self.chat("chat-a")
            await settle()
            #expect(shownWords(text, in: window) == "Only for chat A", "A has its words back")
        }
    }

    /// Words put in from outside (an edit, a page's Ask with words) are the
    /// draft of the chat they are for, even while another is still shown.
    @Test func wordsForANewChatWaitForIt() async throws {
        try await withComposer { browser, shown, window in
            shown.chat = Self.chat("chat-a")
            await settle()
            let content = try #require(window.contentView)
            let text = try #require(field(in: content))
            browser.chatShown = "chat-a"
            browser.chatFresh = false
            browser.newChat()
            browser.chatDraft = "Summarize this page"
            await settle()
            #expect(shownWords(text, in: window) == "", "chat A's field keeps its own words")
            shown.chat = nil
            await settle()
            #expect(shownWords(text, in: window) == "Summarize this page")
            shown.chat = Self.chat("chat-a")
            await settle()
            #expect(shownWords(text, in: window) == "")
        }
    }
}
