import Testing
@testable import Fast

struct OpenUIReplyTests {
    @Test func preservesMarkdownAndRecognizesTheOptionalBlock() {
        let text = "Monthly sales rose.\n\n```openui\nroot = Card([])\n```\n\nFigures are in USD."
        let reply = OpenUIReply(text)
        #expect(reply.prose == "Monthly sales rose.\n\n\nFigures are in USD.")
        #expect(reply.program == "root = Card([])")
        #expect(reply.complete)
    }

    @Test func rendersAnUnfinishedProgramAsItStreams() {
        let reply = OpenUIReply("Here is a comparison.\n```openui\nroot = Card([chart])")
        #expect(reply.prose == "Here is a comparison.")
        #expect(reply.program == "root = Card([chart])")
        #expect(!reply.complete)
    }

    @Test func leavesOrdinaryCodeExamplesAlone() {
        let text = "````markdown\n```openui\nroot = Card([])\n```\n````\n\n```swift\nlet total = 42\n```"
        let reply = OpenUIReply(text)
        #expect(reply.prose == text)
        #expect(reply.program == nil)
    }

    @Test func leavesAnOrdinaryResponseUnchanged() {
        let text = "The sample total is **42**."
        let reply = OpenUIReply(text)
        #expect(reply.prose == text)
        #expect(reply.program == nil)
    }
}
