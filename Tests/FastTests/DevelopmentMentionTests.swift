import AppKit
import Testing
@testable import Fast

@MainActor
struct DevelopmentMentionTests {
    @Test func findsTheTokenAtTheCaretWithoutTakingTheRestOfTheDraft() throws {
        let draft = "🙂 Read @script then explain"
        let caret = ("🙂 Read @scr" as NSString).length
        let token = try #require(DevelopmentMentionToken.at(NSRange(location: caret, length: 0), in: draft))
        #expect(token.query == "scr")
        #expect((draft as NSString).substring(with: token.range) == "@scr")
        #expect(DevelopmentMentionToken.at(NSRange(location: 8, length: 0), in: "a@pl.com") == nil)
        #expect(DevelopmentMentionToken.at(NSRange(location: caret, length: 1), in: draft) == nil)
        #expect(DevelopmentMentionToken.at(NSRange(location: 5, length: 0), in: "@tag\n") == nil)
    }

    @Test func deletingAChipRemovesItsContextAndKeepsOtherRanges() throws {
        let file = URL(fileURLWithPath: "/tmp/check.txt")
        let skill = DevelopmentReference(kind: .skill, name: "Review", path: "/tmp/SKILL.md")
        let draft = NSMutableAttributedString(string: "🙂 ")
        draft.append(DevelopmentDraft.chip(DevelopmentMention(name: "check.txt", detail: "", symbol: "doc", attachment: .file(file))))
        draft.append(NSAttributedString(string: " with "))
        draft.append(DevelopmentDraft.chip(DevelopmentMention(name: skill.name, detail: "", symbol: "book", reference: skill)))

        let message = DevelopmentDraft.message(draft)
        #expect(message.text == "🙂 @check.txt with @Review")
        #expect(message.spans.map { (message.text as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) } == ["@check.txt", "@Review"])
        #expect(DevelopmentDraft.mentioned(in: draft).compactMap(\.attachment) == [.file(file)])

        draft.deleteCharacters(in: NSRange(location: ("🙂 " as NSString).length, length: 1))
        #expect(DevelopmentDraft.mentioned(in: draft).compactMap(\.reference) == [skill])
        #expect(DevelopmentDraft.mentioned(in: draft).compactMap(\.attachment).isEmpty)
    }
}
