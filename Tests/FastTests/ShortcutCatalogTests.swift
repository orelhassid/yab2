import Testing
import AppKit
@testable import Fast

struct ShortcutCatalogTests {
    @MainActor @Test func customSpaceArrowsKeepBrowserPriorityWithoutReadingTheKeyboardLayout() throws {
        let previous = Hotkey("←", [.command, .option])
        let next = Hotkey("→", [.command, .option])
        // Resolve only this inert active binding inventory. Enumerating the
        // whole catalog would validate the global small-window key through
        // TIS and read Settings-dependent menu titles.
        let resolved = Keymap.resolve([
            .init(action: .previousSpace, key: previous, priority: 2, order: 0),
            .init(action: .nextSpace, key: next, priority: 2, order: 1),
        ])
        #expect(resolved[.previousSpace] == previous)
        #expect(resolved[.nextSpace] == next)
        let owners: [Hotkey: Shortcut.Action] = [previous: .previousSpace, next: .nextSpace]
        // Named arrow keys never call UCKeyTranslate or the current IME.
        let board = KeyBoard(layout: nil, typesASCII: true, ascii: nil)
        for (code, expected) in [(UInt16(123), Shortcut.Action.previousSpace), (UInt16(124), .nextSpace)] {
            let flags: NSEvent.ModifierFlags = [.command, .option, .numericPad, .function, .capsLock]
            let readings = Hotkey.readings(code: code, flags: flags, on: board)
            let reading = try #require(readings.first)
            let action = try #require(Keymap.mappedBrowserAction(for: reading, owners: owners))
            #expect(action == expected)
            #expect(Shortcut.reservesPageKey(action, readAs: reading))
        }
        let disabled = Keymap.resolve([
            .init(action: .nextSpace, key: next, priority: 2, order: 1),
        ])
        #expect(disabled[.previousSpace] == nil)
        #expect(disabled[.nextSpace] == next)
        #expect(Keymap.mappedBrowserAction(for: Hotkey("←", .option), owners: owners) == nil)
    }

    @Test func pageOwnedCommandsAndSecondaryAliasesKeepTheirExistingPriority() {
        // Arc's ahead of the page (evals/reserved-keys); ⌘R, ⌘F, ⌘Y the page's first, as in Arc and Chrome.
        #expect(Shortcut.reservesPageKey(.back, readAs: Hotkey("[", .command)))
        #expect(Shortcut.reservesPageKey(.forward, readAs: Hotkey("]", .command)))
        #expect(Shortcut.reservesPageKey(.column, readAs: Hotkey("s", .command)))
        #expect(!Shortcut.reservesPageKey(.find, readAs: Hotkey("f", .command)))
        #expect(!Shortcut.reservesPageKey(.history, readAs: Hotkey("y", .command)))
        #expect(!Shortcut.reservesPageKey(.inspector, readAs: Hotkey("f12", [])))
        #expect(Shortcut.reservesPageKey(.nextTab, readAs: Hotkey("]", [.command, .shift])))
        #expect(Shortcut.reservesPageKey(.space1, readAs: Hotkey("1", .control)))
    }

    @MainActor @Test func extensionShortcutsCanBeFoundByTheirSavedAlias() {
        if #available(macOS 15.4, *) {
            let entry = Extensions.CommandEntry(extensionID: "fixture.extension", command: "capture", title: "Capture area",
                                                keys: nil, kept: .init(alias: "snap", off: false))
            #expect(entry.matches("  SNAP  "))
            #expect(entry.matches("area capture"))
            #expect(!entry.matches("another-alias"))
            #expect(entry.matches(""))
        }
    }

    @MainActor @Test func shortcutSearchFindsDisabledAliasesWithoutChangingTheirState() {
        if #available(macOS 15.4, *) {
            let entry = Extensions.CommandEntry(extensionID: "fixture.extension", command: "capture", title: "Capture area",
                                                keys: Hotkey("s", .command), kept: .init(alias: "snap", off: true))
            #expect(entry.matches("snap"))
            #expect(entry.matches("⌘S"))
            #expect(!entry.matches("⌘P"))
            #expect(entry.kept.off && entry.kept.alias == "snap")
        }
    }

    @MainActor
    @Test func keyNamesForCodes() throws {
        #expect(KeyLayout.key(17) == "t")
        #expect(KeyLayout.key(13) == "w")
        #expect(KeyLayout.key(18) == "1")
        #expect(KeyLayout.key(10) == "keycode10")
        #expect(KeyLayout.code(for: "keycode10") == 10)
        #expect(KeyLayout.code(for: "↩") == 36)
        #expect(KeyLayout.code(typing: "л", in: [37: "л"]) == 37)
        #expect(KeyLayout.key(37) == "l")
        let abc = try #require(KeyBoard("com.apple.keylayout.ABC"))
        #expect(KeyLayout.code(for: "w", on: abc) == 13)
        let dvorak = try #require(KeyBoard("com.apple.keylayout.Dvorak"))
        #expect(KeyLayout.code(for: "t", on: dvorak) == 40)
    }

    @MainActor
    @Test func translatedCharactersDoNotChangeTheShortcut() throws {
        // A press is read by its key code on a layout, never by the
        // characters the event carries.
        let russian = try #require(KeyBoard("com.apple.keylayout.Russian"))
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                                  timestamp: 0, windowNumber: 0, context: nil,
                                                  characters: "ц", charactersIgnoringModifiers: "ц",
                                                  isARepeat: false, keyCode: 13))
        #expect(Hotkey.readings(event, on: russian).first == Hotkey("w", .command))
    }

    @MainActor @Test func controlDHasOneDeveloperModeOwnerAndCanBeRemapped() throws {
        let action = try #require(Shortcut.Action(rawValue: "devMode"))
        let key = Hotkey("d", .control)
        #expect(Shortcut.byAction[action]?.key == key)
        #expect(Keymap.valid(key, for: action))
        let defaults = Keymap.resolved(chosen: [:])
        #expect(defaults[action] == key)
        #expect(defaults[.keepTab] == Hotkey("d", .command))
        let owners = Dictionary(uniqueKeysWithValues: defaults.compactMap { action, key in
            Shortcut.context(action) == .browser ? (key, action) : nil
        })
        #expect(Keymap.mappedBrowserAction(for: key, owners: owners) == action)
        let custom = Hotkey("d", [.control, .shift])
        #expect(Keymap.resolved(chosen: [action.rawValue: custom.stored])[action] == custom)
        #expect(Keymap.resolved(chosen: [action.rawValue: ""])[action] == nil)
    }

    @Test func everyActionIsShownInShortcuts() {
        let listed = Shortcut.items.compactMap(\.action)
        #expect(Set(listed) == Set(Shortcut.Action.allCases))
        #expect(listed.count == Set(listed).count)
    }

    @Test func defaultsAreUniqueWithinEachWindowContext() {
        let groups = Dictionary(grouping: Shortcut.items.compactMap { item -> (Shortcut.Context, Hotkey, Shortcut.Action)? in
            guard let action = item.action, let key = item.key else { return nil }
            return (Shortcut.context(action), key, action)
        }, by: { $0.0 })
        // One key may name two of mail's actions that are never heard in the
        // same place (Keymap.apart): ⇧⌘A selects every row in the list and
        // puts free slots in a draft.
        for bindings in groups.values {
            for (index, one) in bindings.enumerated() {
                for other in bindings[(index + 1)...] where one.1 == other.1 {
                    #expect(Keymap.apart(one.2, other.2), "\(one.2.rawValue) and \(other.2.rawValue) share a key")
                }
            }
        }
    }

    @MainActor
    @Test func everyDefaultIsValidAndSurvivesResolution() {
        let defaults = Shortcut.items.enumerated().compactMap { order, item -> Keymap.Binding? in
            guard let action = item.action, let key = item.key else { return nil }
            #expect(Keymap.valid(key, for: action), "Invalid default for \(action.rawValue)")
            return Keymap.Binding(action: action, key: key, priority: 1, order: order)
        }
        let resolved = Keymap.resolve(defaults)
        for binding in defaults {
            #expect(resolved[binding.action] == binding.key,
                    "Default lost during resolution: \(binding.action.rawValue)")
        }
    }

    /// ⌘` is macOS's walk through an app's windows: kept from every action
    /// but the tab switcher, which Arc and Dia let take it (feedback #148).
    @MainActor
    @Test func onlyTheTabSwitcherTakesCommandBacktick() {
        let walk = Hotkey("`", .command), back = Hotkey("`", [.shift, .command])
        #expect(Keymap.valid(walk, for: .recentTab))
        #expect(Keymap.valid(back, for: .recentTabReverse))
        #expect(!Keymap.valid(walk, for: .newTab))
        #expect(!Keymap.valid(Hotkey("q", .command), for: .recentTab))
        #expect(Shortcut.kept(walk, from: nil))
        #expect(!Shortcut.kept(walk, from: .recentTab))
    }

    @MainActor
    @Test func importedAndChosenBindingsResolveDeterministically() {
        let key = Hotkey("y", .command)
        let bindings = [
            Keymap.Binding(action: .history, key: key, priority: 1, order: 0),
            Keymap.Binding(action: .downloads, key: key, priority: 2, order: 1),
            Keymap.Binding(action: .bookmarks, key: key, priority: 3, order: 2),
        ]
        let resolved = Keymap.resolve(bindings)
        #expect(resolved[.bookmarks] == key)
        #expect(resolved[.history] == nil)
        #expect(resolved[.downloads] == nil)
    }

    @MainActor
    @Test func resetFindsAllIndependentContextsBlockingADefault() {
        let commandY = Hotkey("y", .command)
        let current: [Shortcut.Action: Hotkey] = [
            .mailCommands: commandY,
            .fieldActions: commandY,
        ]
        #expect(Set(Keymap.displacedByReset(.history, in: current)) == [.mailCommands, .fieldActions])
        #expect(Keymap.displacedByReset(.history, in: [.fieldShow: commandY]).isEmpty)
    }

    @MainActor
    @Test func contextualDefaultsAndChangedKeysHaveDifferentConflictRules() {
        let commandOne = Hotkey("1", .command)
        let commandR = Hotkey("r", .command)
        let commandT = Hotkey("t", .command)
        #expect(!Keymap.conflicts(.mailAccount1, commandOne, .tab1, commandOne))
        #expect(!Keymap.conflicts(.selectionRetry, commandR, .reload, commandR))
        #expect(!Keymap.conflicts(.fieldAnswerAgain, commandR, .reload, commandR))
        let commandReturn = Hotkey("↩", .command)
        #expect(!Keymap.conflicts(.agentHandBack, commandReturn, .fieldCopy, commandReturn))
        #expect(Keymap.conflicts(.mailCommands, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.agentAsk, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.answerRewrite, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.fieldAnswerTask, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.captureSave, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.chatDone, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.chatDone, commandT, .agentAsk, commandT))
        #expect(Keymap.conflicts(.pageCopyMarkdown, commandT, .newTab, commandT))
        #expect(Keymap.conflicts(.chatDone, commandT, .mailCommands, commandT))
        #expect(Keymap.conflicts(.agentHandBack, commandT, .fieldActions, commandT))
        #expect(Keymap.keysOverlap(Hotkey("+", .command), Hotkey("=", .command)))
        #expect(Keymap.keysOverlap(Hotkey("+", .command), Hotkey("=", [.command, .shift])))
    }

    @MainActor
    @Test func recordingRejectsKeysConsumedByContextNavigation() {
        #expect(!Keymap.valid(Hotkey("c", []), for: .mailCommands))
        #expect(!Keymap.valid(Hotkey("c", []), for: .mailWriteDraft))
        #expect(Keymap.valid(Hotkey("space", []), for: .mailWriteDraft))
        #expect(!Keymap.valid(Hotkey("↩", []), for: .mailReply))
        #expect(!Keymap.valid(Hotkey("↑", []), for: .captureWhole))
        #expect(Keymap.valid(Hotkey("↑", .command), for: .captureWhole))
        #expect(!Keymap.valid(Hotkey("s", []), for: .captureSave))
        #expect(!Keymap.valid(Hotkey("d", []), for: .chatDone))
        #expect(!Keymap.valid(Hotkey("f", []), for: .fieldCopy))
        #expect(!Keymap.valid(Hotkey("r", []), for: .answerRewrite))
        #expect(!Keymap.valid(Hotkey("y", []), for: .confirmDanger))
        #expect(Keymap.valid(Hotkey("⌫", []), for: .fieldDone))
        // A bare letter after ⌘A was the page's typing (Gmail's F): the
        // offer's keys come with nothing held only if chosen with one.
        #expect(!Keymap.valid(Hotkey("m", []), for: .pageCopyMarkdown))
        #expect(Keymap.valid(Hotkey("m", .option), for: .pageCopyMarkdown))
        #expect(Keymap.valid(Hotkey("1", []), for: .agentChoice1))
        #expect(!Keymap.valid(Hotkey("keycode10", .command), for: .newTab))
        #expect(!Keymap.valid(Hotkey("j", []), for: .agentAsk))
        #expect(!Keymap.valid(Hotkey(".", []), for: .agentTakeWheel))
        #expect(!Keymap.valid(Hotkey("↩", []), for: .agentHandBack))
        #expect(Keymap.valid(Hotkey("esc", .shift), for: .closeChat))
        #expect(!Keymap.valid(Hotkey("x", []), for: .peekClose))
    }

    @MainActor
    @Test func functionKeysAloneAreShortcuts() {
        // Nothing is typed with an F key, so one alone may be a shortcut,
        // a letter alone still may not.
        #expect(Hotkey("f5", []).isFunctionKey)
        #expect(!Hotkey("f", []).isFunctionKey)
        #expect(!Hotkey("keycode10", []).isFunctionKey)
        #expect(Keymap.valid(Hotkey("f5", []), for: .reload))
        #expect(Keymap.valid(Hotkey("f1", []), for: .newTab))
        #expect(!Keymap.valid(Hotkey("r", []), for: .reload))
        #expect(Hotkey.readings(code: 111, flags: .function, on: .current) == [Hotkey("f12", [])])
        // F12 is Developer Tools too, while nothing else has it.
        #expect(Shortcut.also[Hotkey("f12", [])] == .inspector)
        #expect(Shortcut.byAction[.inspector]?.key?.isFunctionKey == false)
    }

    @MainActor
    @Test func macOSAppShortcutPriorityRequiresActiveBrowserOwner() {
        let zoom = Hotkey("+", .command)
        let pressed = Hotkey("=", [.command, .shift])
        let owners: [Hotkey: Shortcut.Action] = [zoom: .zoomIn]
        let current: [Shortcut.Action: Hotkey] = [.zoomIn: zoom]
        #expect(Keymap.systemBrowserAction(for: pressed, owners: owners, current: current,
                                           system: [.zoomIn: zoom]) == .zoomIn)
        #expect(Keymap.systemBrowserAction(for: pressed, owners: owners, current: current,
                                           system: [:]) == nil)
        #expect(Keymap.systemBrowserAction(for: pressed, owners: owners, current: [:],
                                           system: [.zoomIn: zoom]) == nil)
        let other = Hotkey("=", [.command, .shift])
        #expect(Keymap.systemBrowserAction(for: pressed, owners: [zoom: .zoomIn, other: .history],
                                           current: [.zoomIn: zoom, .history: other],
                                           system: [.zoomIn: zoom]) == nil)
    }

    @MainActor @Test func sideClosingHasNoDefaultAndKeepsChosenKeysAheadOfThePage() {
        let keymap = Keymap.shared
        let actions: [Shortcut.Action] = [.closeBefore, .closeAfter]
        // The chosen key can be masked by a conflicting or system binding;
        // restore the stored choice, not only whichever key currently wins.
        let saved = actions.map { keymap.chosen[$0.rawValue] }
        defer {
            for (action, stored) in zip(actions, saved) {
                if let stored { keymap.set(Hotkey(stored: stored), for: action) }
                else { keymap.reset(action) }
            }
        }
        for (index, action) in actions.enumerated() {
            #expect(Shortcut.byAction[action]?.key == nil)
            #expect(Shortcut.first.contains(action))
            let key = Hotkey(index == 0 ? "b" : "a", [.control, .option, .command])
            #expect(Keymap.valid(key, for: action))
            keymap.set(key, for: action)
            #expect(keymap.keys(action) == key)
            #expect(keymap.action(for: key) == action)
            #expect((action == .closeBefore ? Command.closeBefore : .closeAfter).keys == key.text)
            #expect(Hotkeys.shared.keys(default: "") == "")
            keymap.reset(action)
            #expect(keymap.keys(action) == nil)
            #expect(keymap.isDefault(action))
        }
    }

    @MainActor @Test func sideClosingAppShortcutsSurviveLayoutChanges() {
        let oldSidebar = Store.settings.object(forKey: "sidebar")
        let system = Hotkeys.userKeys()
        let keymap = Keymap.shared
        defer {
            Store.settings.set(oldSidebar, forKey: "sidebar")
            keymap.take(system: system)
        }
        for sidebar in [false, true] {
            Store.settings.set(sidebar, forKey: "sidebar")
            let titles = Shortcut.titles
            #expect(titles[.closeBefore] == (sidebar ? "Close Tabs Above" : "Close Tabs to the Left"))
            #expect(titles[.closeAfter] == (sidebar ? "Close Tabs Below" : "Close Tabs to the Right"))
            for (before, after) in [("Close Tabs to the Left", "Close Tabs to the Right"), ("Close Tabs Above", "Close Tabs Below")] {
                keymap.take(system: [before: "^~@b", after: "^~@a"])
                #expect(keymap.keys(.closeBefore) == Hotkey("b", [.control, .option, .command]))
                #expect(keymap.keys(.closeAfter) == Hotkey("a", [.control, .option, .command]))
                #expect(Shortcut.titled[before] == .closeBefore)
                #expect(Shortcut.titled[after] == .closeAfter)
                #expect(Hotkeys.action(forTitle: before) == .closeBefore)
                #expect(Hotkeys.action(forTitle: after) == .closeAfter)
            }
            keymap.take(system: ["Close Tabs to the Left": "^~@b", "Close Tabs Above": "^~@a"])
            #expect(keymap.keys(.closeBefore) == Hotkey(sidebar ? "a" : "b", [.control, .option, .command]))
        }
    }

    /// Tabs › Share Page… is a row of Settings › Shortcuts with no key out of
    /// the box, and takes ⌃S, as the reporter has Share in Arc (register
    /// 2675, 1567): a key no Yab default or reservation holds. A key
    /// another action has is taken from it, as for every row.
    @MainActor @Test func sharePageHasNoDefaultAndTakesAChosenKey() throws {
        let address = try #require(Shortcut.all.first { $0.title == "Address" })
        let item = try #require(address.items.first { $0.action == .sharePage })
        #expect(item.key == nil)
        #expect(Shortcut.context(.sharePage) == .browser)
        // The menu item's title, so an App Shortcut given it is its key too.
        #expect(Shortcut.titles[.sharePage] == "Share Page\u{2026}")
        #expect(Shortcut.titled["Share Page\u{2026}"] == .sharePage)
        #expect(Hotkeys.action(forTitle: "Share Page\u{2026}") == .sharePage)

        let controlS = Hotkey("s", .control)
        #expect(Keymap.valid(controlS, for: .sharePage))
        #expect(!Shortcut.kept(controlS, from: .sharePage))
        #expect(controlS.menu != nil)
        let defaults = Keymap.resolved(chosen: [:])
        #expect(defaults[.sharePage] == nil)
        #expect(!defaults.values.contains { Keymap.keysOverlap($0, controlS) })
        let chosen = Keymap.resolved(chosen: [Shortcut.Action.sharePage.rawValue: controlS.stored])
        #expect(chosen[.sharePage] == controlS)
        for (action, key) in defaults { #expect(chosen[action] == key, "\(action.rawValue) lost its key") }
        #expect(Keymap.resolved(chosen: [Shortcut.Action.sharePage.rawValue: ""])[.sharePage] == nil)
        // A key without ⌘, ⌥ or ⌃ would be the page's typing.
        #expect(!Keymap.valid(Hotkey("s", []), for: .sharePage))

        // ⌘S given to it is no longer the sidebar's.
        let commandS = Hotkey("s", .command)
        let taken = Keymap.resolved(chosen: [Shortcut.Action.sharePage.rawValue: commandS.stored])
        #expect(taken[.sharePage] == commandS)
        #expect(taken[.column] == nil)

        let keymap = Keymap.shared
        let saved = keymap.chosen[Shortcut.Action.sharePage.rawValue]
        defer {
            if let saved { keymap.set(Hotkey(stored: saved), for: .sharePage) } else { keymap.reset(.sharePage) }
        }
        #expect(keymap.clash(controlS, for: .sharePage) == nil)
        keymap.set(controlS, for: .sharePage)
        #expect(keymap.keys(.sharePage) == controlS)
        #expect(keymap.action(for: controlS) == .sharePage)
        #expect(Hotkeys.shared.keys("Share Page\u{2026}") == "⌃S")
        keymap.reset(.sharePage)
        #expect(keymap.keys(.sharePage) == nil)
        #expect(keymap.isDefault(.sharePage))
    }

    @Test func folderWithTabsIsControlCommandN() throws {
        let item = try #require(Shortcut.byAction[.folderWithTabs])
        #expect(item.key == Hotkey("n", [.control, .command]))
        #expect(Shortcut.titled["New Folder with Tabs"] == .folderWithTabs)
        let others = Shortcut.items.filter { $0.action != .folderWithTabs && Shortcut.context($0.action ?? .newTab) == .browser }
        #expect(!others.contains { $0.key == item.key })
    }

    /// File › New Window is ⌘N, as in Arc and Dia (feedback #285); ⌘T
    /// stays New Tab and ⇧⌘N New Private Tab.
    @Test func newWindowIsCommandN() throws {
        let window = try #require(Shortcut.byAction[.newWindow])
        #expect(window.key == Hotkey("n", .command))
        #expect(Shortcut.titled["New Window"] == .newWindow)
        #expect(Shortcut.byAction[.newTab]?.key == Hotkey("t", .command))
        #expect(Shortcut.byAction[.privateTab]?.key == Hotkey("n", [.shift, .command]))
        let others = Shortcut.items.filter { $0.action != .newWindow && Shortcut.context($0.action ?? .newTab) == .browser }
        #expect(!others.contains { $0.key == window.key })
    }

    /// Help › Send Feedback… has a key, Chrome's Report an Issue… one,
    /// kept Yab's ahead of a page's (feedback #385), and a key given it in
    /// App Shortcuts is the key the key monitor hears too.
    @MainActor @Test func sendFeedbackHasAKeyFromAnywhere() throws {
        let item = try #require(Shortcut.byAction[.sendFeedback])
        #expect(item.key == Hotkey("i", [.option, .shift]))
        #expect(Keymap.valid(item.key!, for: .sendFeedback))
        #expect(Shortcut.first.contains(.sendFeedback))
        #expect(Shortcut.titled["Send Feedback…"] == .sendFeedback)
        #expect(Hotkeys.items.contains { $0.title == "Send Feedback…" && $0.keys == "⌥⇧I" })
        let others = Shortcut.items.filter { $0.action != .sendFeedback && Shortcut.context($0.action ?? .newTab) == .browser }
        #expect(!others.contains { $0.key == item.key })
        let system = Hotkeys.userKeys()
        let keymap = Keymap.shared
        defer { keymap.take(system: system) }
        keymap.take(system: ["Send Feedback…": "^~@f"])
        #expect(keymap.keys(.sendFeedback) == Hotkey("f", [.control, .option, .command]))
        #expect(keymap.action(for: Hotkey("f", [.control, .option, .command])) == .sendFeedback)
        #expect(Command.feedback.keys == "⌃⌥⌘F")
    }

    @Test func keepTabIsFoundAmongTheTabsByEitherWord() throws {
        let tabs = try #require(Shortcut.all.first { $0.title == "Tabs" })
        let keep = try #require(tabs.items.first { $0.action == .keepTab })
        #expect(tabs.items.firstIndex { $0.action == .pin }.map { $0 + 1 } == tabs.items.firstIndex { $0.action == .keepTab })
        #expect(ShortcutsPage.says(keep.does, "keep tab"))
        #expect(ShortcutsPage.says(keep.does, "tab  keep"))
        #expect(ShortcutsPage.says(keep.does, "Release"))
        #expect(ShortcutsPage.says("Keep or release tab", "keep tab"))
        #expect(!ShortcutsPage.says(keep.does, "keep window"))
        #expect(!ShortcutsPage.says(keep.does, " "))
    }

    // MARK: ⌘D is Keep Tab (feedback #154), customs kept

    private static var commandD: Hotkey { Hotkey("d", .command) }

    /// No two actions heard in the same place answer to one key.
    @MainActor
    private func expectNoClash(_ keys: [Shortcut.Action: Hotkey], _ label: String) {
        let pairs = Array(keys)
        for (index, one) in pairs.enumerated() {
            for other in pairs[(index + 1)...] {
                #expect(!Keymap.conflicts(one.key, one.value, other.key, other.value),
                        "\(label): \(one.key.rawValue) and \(other.key.rawValue) share \(one.value.text)")
            }
        }
    }

    /// The browser's own actions on ⌘D: what a press in a page does.
    @MainActor
    private func onCommandD(_ keys: [Shortcut.Action: Hotkey]) -> [Shortcut.Action] {
        keys.filter { Shortcut.context($0.key) == .browser && $0.value == Self.commandD }.map(\.key)
    }

    @MainActor
    @Test func freshUserHasCommandDOnKeepTabAndNoBookmarkKey() {
        #expect(Shortcut.byAction[.keepTab]?.key == Self.commandD)
        #expect(Shortcut.byAction[.bookmark]?.key == nil)
        let keys = Keymap.resolved(chosen: [:])
        #expect(keys[.keepTab] == Self.commandD)
        #expect(keys[.bookmark] == nil)
        #expect(keys[.pin] == nil)
        #expect(keys[.addressBar] == Hotkey("d", [.shift, .command]))
        #expect(onCommandD(keys) == [.keepTab])
        expectNoClash(keys, "fresh")
    }

    @MainActor
    @Test func aChosenKeepTabKeyIsKept() {
        let mine = Hotkey("k", [.control, .option, .command])
        #expect(Keymap.valid(mine, for: .keepTab))
        let keys = Keymap.resolved(chosen: [Shortcut.Action.keepTab.rawValue: mine.stored])
        #expect(keys[.keepTab] == mine)
        // ⌘D, no longer the bookmark's, is nobody's.
        #expect(onCommandD(keys).isEmpty)
        #expect(keys[.bookmark] == nil)
        expectNoClash(keys, "keep tab chosen")
        // Taken away on purpose, Keep Tab stays without one.
        let none = Keymap.resolved(chosen: [Shortcut.Action.keepTab.rawValue: ""])
        #expect(none[.keepTab] == nil)
        #expect(onCommandD(none).isEmpty)
    }

    @MainActor
    @Test func aChosenBookmarkKeyIsKept() {
        let mine = Hotkey("b", [.control, .option, .command])
        #expect(Keymap.valid(mine, for: .bookmark))
        let keys = Keymap.resolved(chosen: [Shortcut.Action.bookmark.rawValue: mine.stored])
        #expect(keys[.bookmark] == mine)
        #expect(keys[.keepTab] == Self.commandD)
        expectNoClash(keys, "bookmark chosen")
        // A bookmark key taken away stays away, and Keep Tab gets ⌘D.
        let none = Keymap.resolved(chosen: [Shortcut.Action.bookmark.rawValue: ""])
        #expect(none[.bookmark] == nil)
        #expect(none[.keepTab] == Self.commandD)
        // ⌘D chosen for the bookmark itself, now that it isn't the default,
        // is stored and wins over Keep Tab's default.
        let commandD = Keymap.resolved(chosen: [Shortcut.Action.bookmark.rawValue: Self.commandD.stored])
        #expect(commandD[.bookmark] == Self.commandD)
        #expect(commandD[.keepTab] == nil)
        expectNoClash(commandD, "bookmark on ⌘D")
    }

    @MainActor
    @Test func commandDChosenForAnotherCommandStaysThere() {
        // As Settings › Shortcuts left it when ⌘D was taken from the
        // bookmark: the other command's key, and the bookmark's emptied.
        let taken = [Shortcut.Action.duplicate.rawValue: Self.commandD.stored, Shortcut.Action.bookmark.rawValue: ""]
        // And chosen without taking it, as a synced Mac might have it.
        let plain = [Shortcut.Action.duplicate.rawValue: Self.commandD.stored]
        for chosen in [taken, plain] {
            let keys = Keymap.resolved(chosen: chosen)
            #expect(keys[.duplicate] == Self.commandD)
            #expect(keys[.keepTab] == nil)
            #expect(onCommandD(keys) == [.duplicate])
            expectNoClash(keys, "duplicate on ⌘D")
        }
        // macOS App Shortcuts giving ⌘D to Add This Page win too.
        let system = Keymap.resolved(chosen: [:], system: [.bookmark: Self.commandD])
        #expect(system[.bookmark] == Self.commandD)
        #expect(system[.keepTab] == nil)
        #expect(onCommandD(system) == [.bookmark])
    }

    @MainActor
    @Test func changedKeysNeverLeaveTwoCommandsOnOneKey() {
        let mixes: [[String: String]] = [
            [Shortcut.Action.pin.rawValue: Self.commandD.stored],
            [Shortcut.Action.pin.rawValue: Self.commandD.stored, Shortcut.Action.keepTab.rawValue: Hotkey("d", [.shift, .command]).stored],
            [Shortcut.Action.bookmark.rawValue: Self.commandD.stored, Shortcut.Action.keepTab.rawValue: Self.commandD.stored],
            [Shortcut.Action.keepTab.rawValue: Hotkey("t", .command).stored],
        ]
        for chosen in mixes {
            let keys = Keymap.resolved(chosen: chosen)
            expectNoClash(keys, "\(chosen)")
            #expect(onCommandD(keys).count <= 1, "\(chosen)")
        }
        // Pin on ⌘D and Keep Tab on ⇧⌘D: the two traded.
        let traded = Keymap.resolved(chosen: mixes[1])
        #expect(traded[.pin] == Self.commandD)
        #expect(traded[.keepTab] == Hotkey("d", [.shift, .command]))
        // Keep Tab chosen onto ⌘T, New Tab's: one of them has it, never both.
        let onT = Keymap.resolved(chosen: mixes[3])
        #expect((onT[.keepTab] == Hotkey("t", .command)) != (onT[.newTab] == Hotkey("t", .command)))
    }

    @MainActor
    @Test func addressBarAndPinHaveSeparateEditableCatalogEntries() throws {
        let window = try #require(Shortcut.all.first { $0.title == "Window" })
        let tabs = try #require(Shortcut.all.first { $0.title == "Tabs" })
        let bar = try #require(window.items.first { $0.action == .addressBar })
        let pin = try #require(tabs.items.first { $0.action == .pin })
        #expect(ShortcutsPage.says(bar.does, "show hide address bar"))
        #expect(ShortcutsPage.says(pin.does, "pin tab"))
        #expect(Shortcut.items.filter { $0.action == .addressBar }.count == 1)
        #expect(Shortcut.items.filter { $0.action == .pin }.count == 1)
        let key = Hotkey("d", [.shift, .command])
        #expect(bar.key == key)
        #expect(pin.key == nil)
        let keys = Keymap.resolved(chosen: [:])
        #expect(keys[.addressBar] == key)
        #expect(keys[.pin] == nil)
        #expect(browserOn(key, keys) == [.addressBar])
        expectNoClash(keys, "address bar default")
    }

    @MainActor
    @Test func addressBarAndPinRebindingsSurviveStoredSettings() throws {
        let domain = "dev.serafim.fast.tests.address-bar." + UUID().uuidString
        let store = try #require(UserDefaults(suiteName: domain))
        defer { store.removePersistentDomain(forName: domain) }
        let bar = Hotkey("d", [.control, .option, .command])
        let pin = Hotkey("d", [.shift, .command])
        #expect(Keymap.valid(bar, for: .addressBar))
        #expect(Keymap.valid(pin, for: .pin))
        store.set([Shortcut.Action.addressBar.rawValue: bar.stored,
                   Shortcut.Action.pin.rawValue: pin.stored], forKey: "shortcuts")
        let stored = try #require(store.dictionary(forKey: "shortcuts") as? [String: String])
        let keys = Keymap.resolved(chosen: stored)
        #expect(keys[.addressBar] == bar)
        #expect(keys[.pin] == pin)
        #expect(keys[.keepTab] == Self.commandD)
        #expect(browserOn(bar, keys) == [.addressBar])
        #expect(browserOn(pin, keys) == [.pin])
        expectNoClash(keys, "address bar and pin chosen")
    }

    @MainActor
    @Test func pinCanTakeTheAddressBarKeyWithoutAConflict() {
        let key = Hotkey("d", [.shift, .command])
        let keys = Keymap.resolved(chosen: [Shortcut.Action.pin.rawValue: key.stored])
        #expect(keys[.pin] == key)
        #expect(keys[.addressBar] == nil)
        #expect(browserOn(key, keys) == [.pin])
        expectNoClash(keys, "pin takes address bar key")
        let removed = Keymap.resolved(chosen: [Shortcut.Action.addressBar.rawValue: ""])
        #expect(removed[.addressBar] == nil)
        #expect(browserOn(key, removed).isEmpty)
    }

    // MARK: ⌥↩ in the field is Split View (feedback #323), and the person's to change

    private static var optionReturn: Hotkey { Hotkey("↩", .option) }

    /// The owner's first condition: ⌥↩'s Split View is a row of Settings ›
    /// Shortcuts that can be given another key or none, and Reset to Default
    /// brings ⌥↩ back. A key taken away takes ⌥-click in the list with it.
    @MainActor
    @Test func optionReturnSplitViewIsAShortcutRowThatCanBeChangedRemovedAndReset() throws {
        let field = try #require(Shortcut.all.first { $0.title == "Field" })
        let row = try #require(field.items.first { $0.action == .fieldAlternate })
        #expect(ShortcutsPage.says(row.does, "split view"))
        #expect(row.key == Self.optionReturn)
        #expect(Keymap.resolved(chosen: [:])[.fieldAlternate] == Self.optionReturn)

        let other = Hotkey("↩", .control)
        #expect(Keymap.valid(other, for: .fieldAlternate))
        let moved = Keymap.resolved(chosen: [Shortcut.Action.fieldAlternate.rawValue: other.stored])
        #expect(moved[.fieldAlternate] == other)
        // ⌥↩ is no field action's then (Fill Form keeps its own over a page).
        #expect(!moved.contains { Shortcut.context($0.key) == .field && $0.value == Self.optionReturn })
        expectNoClash(moved, "split view moved")
        #expect(Keymap.resolved(chosen: [Shortcut.Action.fieldAlternate.rawValue: ""])[.fieldAlternate] == nil)

        #expect(Browser.clickWay(for: [.option], alternate: Self.optionReturn) == .split)
        #expect(Browser.clickWay(for: [.option], alternate: other) == .split)
        #expect(Browser.clickWay(for: [.option], alternate: nil) == .here)
        #expect(Browser.clickWay(for: [.command], alternate: nil) == .behind)

        // The live keymap, as Settings › Shortcuts drives it.
        let keymap = Keymap.shared
        let saved = keymap.chosen[Shortcut.Action.fieldAlternate.rawValue]
        defer {
            if let saved { keymap.set(saved.isEmpty ? nil : Hotkey(stored: saved), for: .fieldAlternate) }
            else { keymap.reset(.fieldAlternate) }
        }
        keymap.reset(.fieldAlternate)
        #expect(keymap.keys(.fieldAlternate) == Self.optionReturn)
        keymap.set(other, for: .fieldAlternate)
        #expect(keymap.keys(.fieldAlternate) == other)
        #expect(!keymap.isDefault(.fieldAlternate))
        keymap.set(nil, for: .fieldAlternate)
        #expect(keymap.keys(.fieldAlternate) == nil)
        #expect(keymap.chosen[Shortcut.Action.fieldAlternate.rawValue] == "")
        keymap.reset(.fieldAlternate)
        #expect(keymap.keys(.fieldAlternate) == Self.optionReturn)
        #expect(keymap.isDefault(.fieldAlternate))
    }

    /// The owner's second condition: ⌥↩ already given to another action in
    /// Settings › Shortcuts stays that action's; Split View's default never
    /// takes it back, from stored settings or the live keymap, and ⌥-click
    /// opens in place then.
    @MainActor
    @Test func optionReturnChosenForAnotherActionStaysTheirs() throws {
        let domain = "dev.serafim.fast.tests.option-return." + UUID().uuidString
        let store = try #require(UserDefaults(suiteName: domain))
        defer { store.removePersistentDomain(forName: domain) }
        for owner in [Shortcut.Action.fieldMove, .fieldAhead, .duplicate] {
            #expect(Keymap.valid(Self.optionReturn, for: owner))
            store.set([owner.rawValue: Self.optionReturn.stored], forKey: "shortcuts")
            let stored = try #require(store.dictionary(forKey: "shortcuts") as? [String: String])
            let keys = Keymap.resolved(chosen: stored)
            #expect(keys[owner] == Self.optionReturn, "\(owner.rawValue) keeps ⌥↩")
            #expect(keys[.fieldAlternate] == nil, "Split View yields ⌥↩ to \(owner.rawValue)")
            #expect(keys.filter { $0.value == Self.optionReturn }.map(\.key) == [owner])
            expectNoClash(keys, "⌥↩ chosen for \(owner.rawValue)")
            #expect(Browser.clickWay(for: [.option], alternate: keys[.fieldAlternate]) == .here)
        }

        let keymap = Keymap.shared
        let actions: [Shortcut.Action] = [.fieldMove, .fieldAlternate]
        let saved = actions.map { keymap.chosen[$0.rawValue] }
        defer {
            for (action, stored) in zip(actions, saved) {
                if let stored { keymap.set(stored.isEmpty ? nil : Hotkey(stored: stored), for: action) }
                else { keymap.reset(action) }
            }
        }
        keymap.reset(.fieldAlternate)
        keymap.set(Self.optionReturn, for: .fieldMove)
        #expect(keymap.keys(.fieldMove) == Self.optionReturn)
        #expect(keymap.keys(.fieldAlternate) == nil)
        #expect(keymap.isDefault(.fieldAlternate))
    }

    // MARK: ⇧⌘B is the bookmarks bar (feedback #160), ⌃⌘B kept

    private static var shiftCommandB: Hotkey { Hotkey("b", [.shift, .command]) }
    private static var controlCommandB: Hotkey { Hotkey("b", [.control, .command]) }

    @MainActor
    private func browserOn(_ key: Hotkey, _ keys: [Shortcut.Action: Hotkey]) -> [Shortcut.Action] {
        keys.filter { Shortcut.context($0.key) == .browser && $0.value == key }.map(\.key)
    }

    @MainActor
    @Test func freshUserHasShiftCommandBOnTheBookmarksBarAndBccInADraft() {
        #expect(Shortcut.byAction[.bookmarksBar]?.key == Self.shiftCommandB)
        let keys = Keymap.resolved(chosen: [:])
        #expect(keys[.bookmarksBar] == Self.shiftCommandB)
        // Mail's Bcc keeps ⇧⌘B while a mail is written: two defaults heard
        // in different places, never a clash.
        #expect(keys[.mailBcc] == Self.shiftCommandB)
        #expect(!Keymap.conflicts(.bookmarksBar, Self.shiftCommandB, .mailBcc, Self.shiftCommandB))
        #expect(browserOn(Self.shiftCommandB, keys) == [.bookmarksBar])
        // ⌃⌘B, the old key, still toggles it as a second key.
        #expect(Shortcut.also[Self.controlCommandB] == .bookmarksBar)
        #expect(Keymap.alias(Self.controlCommandB, chosen: [:]) == .bookmarksBar)
        #expect(!keys.values.contains(Self.controlCommandB))
        expectNoClash(keys, "fresh")
    }

    @MainActor
    @Test func aChosenBookmarksBarKeyIsKept() {
        // Chosen before #160 (any key but ⌃⌘B was stored): stays.
        let mine = Hotkey("k", [.control, .option, .command])
        #expect(Keymap.valid(mine, for: .bookmarksBar))
        let keys = Keymap.resolved(chosen: [Shortcut.Action.bookmarksBar.rawValue: mine.stored])
        #expect(keys[.bookmarksBar] == mine)
        #expect(keys[.mailBcc] == Self.shiftCommandB)
        #expect(browserOn(Self.shiftCommandB, keys).isEmpty)
        // ⇧⌘B chosen by hand before, now the default: the same key.
        let shift = Keymap.resolved(chosen: [Shortcut.Action.bookmarksBar.rawValue: Self.shiftCommandB.stored])
        #expect(shift[.bookmarksBar] == Self.shiftCommandB)
        // Taken away on purpose: no key, and ⌃⌘B doesn't answer either.
        let none = [Shortcut.Action.bookmarksBar.rawValue: ""]
        #expect(Keymap.resolved(chosen: none)[.bookmarksBar] == nil)
        #expect(Keymap.alias(Self.controlCommandB, chosen: none) == nil)
    }

    @MainActor
    @Test func shiftCommandBChosenForAnotherCommandStaysThere() {
        let chosen = [Shortcut.Action.bookmarks.rawValue: Self.shiftCommandB.stored]
        let keys = Keymap.resolved(chosen: chosen)
        #expect(keys[.bookmarks] == Self.shiftCommandB)
        #expect(keys[.bookmarksBar] == nil)
        #expect(browserOn(Self.shiftCommandB, keys) == [.bookmarks])
        expectNoClash(keys, "show bookmarks on ⇧⌘B")
        // The bar keeps ⌃⌘B, the key it had before.
        #expect(Keymap.alias(Self.controlCommandB, chosen: chosen) == .bookmarksBar)
        // ⌃⌘B chosen for another command is that command's: the key
        // monitor asks the owners before the second keys.
        let taken = Keymap.resolved(chosen: [Shortcut.Action.rename.rawValue: Self.controlCommandB.stored])
        #expect(taken[.rename] == Self.controlCommandB)
        #expect(taken[.bookmarksBar] == Self.shiftCommandB)
        #expect(Keymap.mappedBrowserAction(for: Self.controlCommandB, owners: [Self.controlCommandB: .rename]) == .rename)
    }
}

/// Register 1163: ⌘1 to ⌘3 freed from Go to Tab could not go to Go to
/// Space, as Mail's accounts and an answer's picks still held them.
struct SpaceDigitShortcutTests {
    @MainActor @Test func digitsFreedFromTabsGoToSpaces() {
        let one = Hotkey("1", .command)
        // The pairs the tabs always shared stay shared once a space has the key.
        #expect(!Keymap.conflicts(.mailAccount1, one, .space1, one))
        #expect(!Keymap.conflicts(.answerPick1, one, .space1, one))
        #expect(!Keymap.conflicts(.space1, one, .answerPick1, one))
        // Two browser actions still can't have one key.
        #expect(Keymap.conflicts(.tab1, one, .space1, one))
        // Nor a context action moved onto a key a tab has.
        #expect(Keymap.conflicts(.answerPick2, one, .space1, one))
        // Only the spaces share the digits: another browser action doesn't.
        #expect(Keymap.conflicts(.mailAccount1, one, .duplicate, one))
        // A key no browser action has by default is still not shared.
        let j = Hotkey("9", [.command, .option])
        #expect(Keymap.conflicts(.mailAccount1, j, .space1, j))

        var chosen: [String: String] = [:]
        for n in 1...3 { chosen["tab\(n)"] = "" }
        let freed = Keymap.resolved(chosen: chosen)
        for n in 1...3 {
            let key = Hotkey(String(n), .command)
            let space = Shortcut.numbered("space", n)!
            #expect(Keymap.holders(of: key, for: space, in: freed).isEmpty, "⌘\(n) still held")
            chosen["space\(n)"] = key.stored
        }
        // Still held while the tabs have them.
        #expect(Keymap.holders(of: one, for: .space1, in: Keymap.resolved(chosen: [:])) == [.tab1])

        // As saved and read back at the next launch.
        let resolved = Keymap.resolved(chosen: chosen)
        var owners: [Hotkey: Shortcut.Action] = [:]
        for (action, key) in resolved where Shortcut.context(action) == .browser { owners[key] = action }
        for n in 1...3 {
            let key = Hotkey(String(n), .command)
            #expect(resolved[Shortcut.numbered("space", n)!] == key)
            #expect(resolved[Shortcut.numbered("tab", n)!] == nil)
            #expect(Keymap.mappedBrowserAction(for: key, owners: owners) == Shortcut.numbered("space", n))
            #expect(resolved[Shortcut.numbered("mailAccount", n)!] == key)
        }
        #expect(resolved[.answerPick1] == one)
        #expect(resolved[.tab4] == Hotkey("4", .command))
    }

    @Test func tabNumbersOnlyForDigitsThatReachTabs() {
        #expect(KeyNumbers.numbers(among: [0, 1, 2, 3], digits: [4, 5, 9]) == [3: 4])
        #expect(KeyNumbers.numbers(among: [0, 1, 2, 3], digits: [2, 9]) == [1: 2, 3: 9])
        #expect(KeyNumbers.numbers(among: [0, 1, 2, 3], digits: []).isEmpty)
    }
}
