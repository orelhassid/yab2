import AppKit
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct WelcomeAgentTests {
    @Test func everyTourSceneContinuesToSetup() {
        let stage = WelcomeStage.shared
        for beat in WelcomeSample.beats(stage) {
            let moment = WelcomeMoment(beat: beat)
            #expect(beat.chapter == 1)
            #expect(WelcomeSample.words(moment, stage).scene == beat)
            #expect(WelcomeSample.press(.primary, moment, stage) == .chapter(3))
        }
    }

    @Test func aFreshWelcomeStartsInTheDefaultBrowsersLayout() {
        for bundle in [TabImport.arc, TabImport.dia] {
            var look = WelcomeHeldLook(sidebar: false)
            look.adoptDefaultBrowser(bundle, welcomed: false)
            #expect(look.sidebar)
        }
        for bundle in ["com.google.Chrome", "com.google.Chrome.beta", "com.brave.Browser",
                       "com.brave.Browser.nightly", "com.apple.Safari", "org.mozilla.firefox", "com.microsoft.edgemac"] {
            var look = WelcomeHeldLook(sidebar: true)
            look.adoptDefaultBrowser(bundle, welcomed: false)
            #expect(!look.sidebar)
        }
    }

    @Test func anUnknownBrowserOrYabKeepsThePreference() {
        let bundles: [String?] = [nil, "", "unknown", "dev.serafim.fast", "dev.serafim.fast.dev"]
        for saved in [false, true] {
            for bundle in bundles {
                var look = WelcomeHeldLook(sidebar: saved)
                look.adoptDefaultBrowser(bundle, welcomed: false)
                #expect(look.sidebar == saved)
            }
        }
    }

    @Test func reopeningWelcomeAndExplicitLookPicksWinOverDetection() {
        for saved in [false, true] {
            var look = WelcomeHeldLook(sidebar: saved)
            look.adoptDefaultBrowser(saved ? "com.apple.Safari" : TabImport.dia, welcomed: true)
            #expect(look.sidebar == saved)
            look.tabsChosen = true
            look.adoptDefaultBrowser(saved ? "com.apple.Safari" : TabImport.arc, welcomed: false)
            #expect(look.sidebar == saved)
        }
        // Picking the already selected tile still counts as an explicit choice.
        let stage = WelcomeStage.shared
        let held = stage.held
        defer { stage.held = held }
        stage.held = WelcomeHeldLook(sidebar: false)
        WelcomeYours.pickTabs(false, stage)
        stage.held.adoptDefaultBrowser(TabImport.dia, welcomed: false)
        #expect(!stage.held.sidebar && stage.held.tabsChosen)
    }

    @Test func bothTabLayoutsKeepEveryPullRequestOnStage() throws {
        let stage = WelcomeStage.shared
        let held = stage.held
        defer { stage.held = held }
        for side in [false, true] {
            stage.held.sidebar = side
            for beat in [WelcomeStage.Beat.watch, .results] {
                let board = WelcomeSample.board(WelcomeMoment(beat: beat), stage)
                func flattened(_ parts: [StagePart]) -> [StagePart] { parts.flatMap { [$0] + flattened($0.children) } }
                let all = flattened(board.parts)
                for key in ["a-482", "a-479", "a-476", "f-agent", "chat", "pg-pr"] {
                    #expect(all.contains { $0.key == key })
                }
                #expect(!all.contains { $0.key == "fold" || $0.key.hasPrefix("step-") })
                let chat = try #require(board.parts.first { $0.key == "chat" })
                let page = try #require(board.parts.first { $0.key == "pg-pr" })
                #expect(page.frame.maxX + 16 == chat.frame.minX)
                #expect(chat.frame.maxY <= 676)
                if side {
                    let column = try #require(board.parts.first { $0.key == "col" })
                    #expect(column.plate != nil)
                    #expect(column.frame.width == 230)
                    for child in column.children {
                        #expect(child.frame.minX >= 0 && child.frame.maxX <= column.frame.width)
                        #expect(child.frame.minY >= 0 && child.frame.maxY <= column.frame.height)
                    }
                    #expect(all.contains { $0.key == "p-docs" })
                }
            }
        }
    }

    @Test func theLiveStatusDoesNotSetTheNamePlatesWidth() {
        #expect(WelcomeChatMetrics.nameWidth(in: 280) == 160)
        #expect(WelcomeChatMetrics.nameWidth(in: 320) == 160)
        #expect(WelcomeChatMetrics.nameWidth(in: 380, title: String(repeating: "Long ", count: 20)) == 260)
    }
}
