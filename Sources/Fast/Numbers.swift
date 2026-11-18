import AppKit
import SwiftUI

/// ⌘ held on its own for a moment: each tab ⌘1 to ⌘9 reaches, pinned, kept
/// or today's, shows its number in place of its letter or icon, and its letter again the moment ⌘
/// is let go of. The wait is what keeps it quiet: ⌘ goes down hundreds of
/// times a day on the way to ⌘C or ⌘T, and none of those should flash.
@MainActor
final class KeyNumbers: ObservableObject {
    static let shared = KeyNumbers()

    @Published private(set) var shown = false

    private var monitor: Any?
    private var wait: DispatchWorkItem?
    private var began: TimeInterval?
    private var presses: UInt32 = 0
    private var chord = false
    private let now: () -> TimeInterval
    private let keyPresses: () -> UInt32
    private let commandAlone: () -> Bool
    private let pointer: () -> CGPoint
    /// Where the pointer was when ⌘ went down.
    private var from: CGPoint = .zero

    /// How far the pointer goes with ⌘ held before the hold reads as
    /// aiming a ⌘-click rather than counting tabs.
    static let aim: CGFloat = 8

    /// Long enough that a chord typed at speed never reaches it.
    private static let delay: TimeInterval = 0.45

    init(now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         keyPresses: @escaping () -> UInt32 = {
             CGEventSource.counterForEventType(.combinedSessionState, eventType: .keyDown)
         },
         commandAlone: @escaping () -> Bool = {
             CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]) == .maskCommand
         },
         pointer: @escaping () -> CGPoint = { NSEvent.mouseLocation }) {
        self.now = now
        self.pointer = pointer
        self.keyPresses = keyPresses
        self.commandAlone = commandAlone
    }

    func watch() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]
        ) { [weak self] event in
            self?.hear(event)
            return event
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.drop() }
    }

    func hear(_ event: NSEvent) {
        guard event.type == .flagsChanged else {
            // A key or a click with ⌘ down is a chord or ⌘-click picking
            // tabs: nothing to count off.
            chord = event.modifierFlags.contains(.command)
            drop()
            return
        }
        // The main thread may read ⌘'s event after macOS already took Space.
        let lastPress = ProcessInfo.processInfo.systemUptime
            - CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        modifiers(event.modifierFlags, inBrowser: event.window === Links.window,
                  keyPressedSinceCommand: lastPress > event.timestamp)
    }

    func modifiers(_ flags: NSEvent.ModifierFlags, inBrowser: Bool, keyPressedSinceCommand: Bool = false) {
        let flags = flags.intersection([.command, .option, .control, .shift])
        if !flags.contains(.command) { chord = false }
        else if keyPressedSinceCommand { chord = true }
        guard flags == .command, inBrowser else {
            if flags.contains(.command) { chord = true }
            drop()
            return
        }
        guard !chord, began == nil else { return }
        began = now()
        presses = keyPresses()
        from = pointer()
        pollSoon()
    }

    /// macOS consumes system shortcuts before a local monitor sees them.
    /// Count presses, without reading their keys or requiring an event tap:
    /// even a swallowed ⌘Space cancels the hint for this whole ⌘ hold.
    func checkHold() {
        guard let began else { return }
        // ⌘ held while the pointer travels is a ⌘-click being aimed at a
        // link: the numbers flashed in place of the icons on the way to
        // it (feedback #1898). Moved, nothing more for this hold.
        let at = pointer()
        guard commandAlone(), keyPresses() == presses,
              hypot(at.x - from.x, at.y - from.y) <= Self.aim else {
            chord = true
            drop()
            return
        }
        if !shown, now() - began >= Self.delay {
            counted = [:]
            withAnimation(Motion.quick) { shown = true }
        }
    }

    private func pollSoon() {
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.wait = nil
            self.checkHold()
            if self.began != nil { self.pollSoon() }
        }
        wait = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: item)
    }

    /// The bench's ⌘ held, without a key: shown at once, or let go.
    func hold(_ on: Bool) {
        if on {
            wait?.cancel()
            wait = nil
            began = nil
            counted = [:]
            shown = true
        } else {
            chord = false
            drop()
        }
    }

    private func drop() {
        wait?.cancel()
        wait = nil
        began = nil
        // Gone at once: the key it points to has just been pressed, or ⌘ let go.
        if shown { shown = false }
        counted = [:]
    }

    /// Each window's numbers while ⌘ is held, worked out once for all its
    /// rows rather than once a row.
    private var counted: [ObjectIdentifier: [UUID: Int]] = [:]

    /// What ⌘ and a digit reach this tab by, if anything: the very tab
    /// `Browser.select(number:)` goes to for that digit, so a number is
    /// never on a tab its key would not open.
    static func number(of tab: Tab, in browser: Browser) -> Int? {
        let key = ObjectIdentifier(browser)
        if let known = shared.counted[key] { return known[tab.id] }
        let tabs = browser.tabs
        var numbers: [UUID: Int] = [:]
        // Only the digits that still go to a tab: ⌘1 given to Go to Space 1
        // in Settings › Shortcuts puts no 1 on a tab (register 1163).
        let digits = Set((1...9).filter { number in
            Shortcut.numbered("tab", number).flatMap { Keymap.shared.keys($0) } == Hotkey(String(number), .command)
        })
        for (at, number) in Self.numbers(among: browser.numberable(), digits: digits) {
            numbers[tabs[at].id] = number
        }
        if shared.shown { shared.counted[key] = numbers }
        return numbers[tab.id]
    }

    /// Row place to digit, as ⌘1 to ⌘9 land (BrowserMenuCommands): ⌘1 to
    /// ⌘8 the first eight tabs you can be on, ⌘9 the last of them. A tab two
    /// digits reach, the last of only a few, wears the lower one.
    nonisolated static func numbers(among open: [Int], digits: Set<Int> = Set(1...9)) -> [Int: Int] {
        var numbers: [Int: Int] = [:]
        for number in 1...9 where digits.contains(number) {
            if let at = Browser.tabIndex(for: number, among: open), numbers[at] == nil {
                numbers[at] = number
            }
        }
        return numbers
    }
}

/// A tab's mark, or its number while ⌘ is held. The browser is not watched:
/// a row that watched it was drawn again on anything it said (SideRow), and
/// the number is read afresh each time ⌘ is held.
struct PinNumber<Mark: View>: View {
    let browser: Browser
    @ObservedObject var tab: Tab
    var size: CGFloat
    var tint: Color
    @ViewBuilder var mark: () -> Mark

    @ObservedObject private var numbers = KeyNumbers.shared

    var body: some View {
        ZStack {
            if numbers.shown, let number = KeyNumbers.number(of: tab, in: browser) {
                Text("\(number)")
                    .font(.system(size: size, weight: .medium).monospacedDigit())
                    .foregroundStyle(tint)
                    .transition(.opacity)
            } else {
                mark().transition(.opacity)
            }
        }
    }
}
