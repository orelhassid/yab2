import AppKit
import Foundation
import Testing
@testable import Fast

/// Row 1133 (#677): ⌘ held numbers every tab ⌘1 to ⌘9 would open, kept and
/// today's as well as pinned, in the order the keys take them.
@MainActor
@Suite(.serialized)
struct KeyNumbersTests {
    @Test func typingBeforeCommandDoesNotSuppressTheNextHold() throws {
        var time: TimeInterval = 0
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { true })
        defer { numbers.hold(false) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
            characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0))
        numbers.hear(event)
        numbers.modifiers(.command, inBrowser: true)
        time = 0.5
        numbers.checkHold()
        #expect(numbers.shown)
    }

    @Test func localCommandChordDoesNotRearmUntilCommandIsReleased() throws {
        var time: TimeInterval = 0
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { true })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil,
            characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        numbers.hear(event)
        numbers.modifiers(.command, inBrowser: true)
        time = 0.6
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func commandAloneStillShowsHintsAfterTheDelay() {
        var time: TimeInterval = 0
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { true })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        time = 0.4
        numbers.checkHold()
        #expect(!numbers.shown)
        time = 0.5
        numbers.checkHold()
        #expect(numbers.shown)
        numbers.modifiers([], inBrowser: true)
        #expect(!numbers.shown)
    }

    /// Feedback #1898: ⌘ held while the pointer goes to a link to ⌘-click
    /// it put numbers in place of the icons; aiming is not counting tabs.
    @Test func thePointerTravellingWithCommandHeldShowsNoNumbers() {
        var time: TimeInterval = 0
        var at = CGPoint(x: 100, y: 100)
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { true }, pointer: { at })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        time = 0.2
        at = CGPoint(x: 100 + KeyNumbers.aim + 20, y: 140)
        numbers.checkHold()
        time = 0.6
        numbers.checkHold()
        #expect(!numbers.shown)
        // A hand resting on the trackpad, the pointer a point or two off.
        numbers.modifiers([], inBrowser: true)
        numbers.modifiers(.command, inBrowser: true)
        time = 1.0
        at.x += 2
        numbers.checkHold()
        time = 1.5
        numbers.checkHold()
        #expect(numbers.shown)
        // Shown, then the pointer sets off for a link: gone.
        at.x += 40
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func systemShortcutWithoutLocalKeyDownCancelsPendingHints() {
        var time: TimeInterval = 0
        var presses: UInt32 = 10
        let numbers = KeyNumbers(now: { time }, keyPresses: { presses }, commandAlone: { true })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        // macOS handled ⌘Space: Yab receives no keyDown, but the session
        // key-press counter advances, even if Space is already released.
        presses += 1
        time = 0.6
        numbers.checkHold()
        #expect(!numbers.shown)
        // A repeated modifier event must not rearm the same hold.
        numbers.modifiers(.command, inBrowser: true)
        time = 1.2
        numbers.checkHold()
        #expect(!numbers.shown)
        // A fresh ⌘ hold still works after letting go.
        numbers.modifiers([], inBrowser: true)
        numbers.modifiers(.command, inBrowser: true)
        time = 1.8
        numbers.checkHold()
        #expect(numbers.shown)
    }

    @Test func systemShortcutBeforeTheModifierEventIsReadDoesNotArmHints() {
        var time: TimeInterval = 0
        let numbers = KeyNumbers(now: { time }, keyPresses: { 11 }, commandAlone: { true })
        defer { numbers.hold(false) }
        // The event counter already includes Space when the main thread
        // receives the earlier Command flagsChanged event.
        numbers.modifiers(.command, inBrowser: true, keyPressedSinceCommand: true)
        time = 0.6
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func systemShortcutAlsoDismissesAlreadyVisibleHints() {
        var time: TimeInterval = 0
        var presses: UInt32 = 10
        let numbers = KeyNumbers(now: { time }, keyPresses: { presses }, commandAlone: { true })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        time = 0.5
        numbers.checkHold()
        #expect(numbers.shown)
        presses += 1
        numbers.checkHold()
        #expect(!numbers.shown)
        numbers.modifiers([.command, .shift], inBrowser: true)
        numbers.modifiers(.command, inBrowser: true)
        time = 1
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func releasingCommandOutsideTheAppCancelsPendingHints() {
        var time: TimeInterval = 0
        var down = true
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { down })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: true)
        down = false
        time = 0.5
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func modifierChordsAndOtherWindowsDoNotShowHints() {
        var time: TimeInterval = 0
        let numbers = KeyNumbers(now: { time }, keyPresses: { 10 }, commandAlone: { true })
        defer { numbers.hold(false) }
        numbers.modifiers(.command, inBrowser: false)
        time = 1
        numbers.checkHold()
        #expect(!numbers.shown)
        numbers.modifiers([.command, .shift], inBrowser: true)
        numbers.modifiers(.command, inBrowser: true)
        time = 2
        numbers.checkHold()
        #expect(!numbers.shown)
    }

    @Test func inputSourceChordDoesNotOwnTheNumberedTabShortcuts() {
        let keys = Keymap.resolved(chosen: [:])
        for n in 1...9 {
            let action = Shortcut.numbered("tab", n)!
            #expect(keys[action] == Hotkey(String(n), .command))
        }
        #expect(!keys.values.contains(Hotkey("space", .command)))
    }

    @Test func digitsLandWhereTheKeysDo() {
        // Ten tabs you can be on: ⌘1 to ⌘8 the first eight, ⌘9 the last.
        let ten = KeyNumbers.numbers(among: Array(0..<10))
        #expect(ten == [0: 1, 1: 2, 2: 3, 3: 4, 4: 5, 5: 6, 6: 7, 7: 8, 9: 9])
        // Three: ⌘3 and ⌘9 both reach the last, which wears the 3.
        #expect(KeyNumbers.numbers(among: [0, 1, 2]) == [0: 1, 1: 2, 2: 3])
        // A shut folder's two rows (2 and 3) are passed over, as ⌘ and a
        // digit pass them.
        let shut = KeyNumbers.numbers(among: [0, 1, 4, 5])
        #expect(shut == [0: 1, 1: 2, 4: 3, 5: 4])
        for (at, number) in shut {
            #expect(Browser.tabIndex(for: number, among: [0, 1, 4, 5]) == at)
        }
    }

    @Test func keptAndTodaysTabsAreNumberedLikePins() {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        defer { browser.letGo() }
        let tabs = (0..<4).map { n -> Tab in
            let tab = Tab()
            tab.restore(url: URL(string: "https://row\(n).keynumbers.test/")!, title: "Row \(n)")
            browser.prepare(tab)
            return tab
        }
        tabs[0].pin = "P"
        tabs[1].kept = true
        tabs[2].kept = true
        browser.lay(tabs)
        #expect(browser.numberable() == [0, 1, 2, 3])
        #expect(tabs.map { KeyNumbers.number(of: $0, in: browser) } == [1, 2, 3, 4])
        // Each number opens the tab that wears it.
        for (n, tab) in tabs.enumerated() {
            browser.select(number: n + 1)
            #expect(browser.activeID == tab.id)
        }
    }
}
