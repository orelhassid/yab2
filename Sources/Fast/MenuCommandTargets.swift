import AppKit
import SwiftUI

/// Named destinations are commands too. Their ids bind an operation to a
/// concrete destination; execution rebuilds the list to reject stale ids.
struct MenuCommandTarget {
    let id: String
    let operation: Command
    let title: String
    var aliases: [String] = []
    var symbol = "command"
    var shortcut: Shortcut.Action?
    var opens = false
    let run: @MainActor (Browser) -> Void

    @MainActor var offer: Suggestion {
        let keys = shortcut.map { Keymap.shared.text($0) } ?? ""
        return Suggestion(key: title, title: keys, url: nil, kind: .page("menu:" + id))
    }

    func score(_ text: String) -> Double? {
        if matchesExactly(text) { return 4 }
        return Wording.score(text, title: ([title] + aliases).joined(separator: " "), words: "")
    }

    func matchesExactly(_ text: String) -> Bool {
        let typed = Command.normalizedName(text)
        return ([title] + aliases).contains { Command.normalizedName($0) == typed }
    }
}

extension MenuCommands {
    /// Availability is cheap: do not build every folder's search strings
    /// repeatedly while checking the static catalog on each key.
    @MainActor static func hasTargets(_ operation: Command, in browser: Browser) -> Bool {
        switch operation {
        case .moveToWindow:
            return canMoveWindow(browser) && BrowserWindows.shared.openWindows().contains {
                $0.browser !== browser && $0.browser.spaceID == browser.spaceID && !$0.browser.privateBrowsing
            }
        case .moveToSpace:
            return browser.spacesShown && !browser.privateBrowsing
                && browser.turnOrder.contains { $0.id != browser.spaceID && $0.id != Space.mailID }
                && browser.chosen.contains { browser.sendable($0) && $0.everywhere == nil }
        case .moveToFolder:
            return !browser.privateBrowsing && browser.nests.contains { nest in
                !nest.today && browser.chosen.contains { $0.keepable && $0.nest !== nest }
            }
        case .openFolder: return (!browser.privateBrowsing || browser.windowPurpose == .privateOnly) && browser.nests.contains { !$0.open }
        case .closeFolder: return (!browser.privateBrowsing || browser.windowPurpose == .privateOnly) && browser.nests.contains { $0.open }
        case .renameFolder, .customizeFolder: return !browser.privateBrowsing && browser.nests.contains { !$0.today }
        case .newFolderInside: return !browser.privateBrowsing && browser.nests.contains { !$0.today && $0.depth < Nest.deepest }
        case .ungroupFolder: return !browser.privateBrowsing && !browser.nests.isEmpty
        case .moveFolder:
            guard !browser.privateBrowsing, let source = browser.folderHere else { return false }
            return source.parent != nil || browser.nests.contains { browser.canPut(source, in: $0) }
                || (browser.spacesShown && browser.turnOrder.contains { $0.id != browser.spaceID && $0.id != Space.mailID })
        case .updateLiveFolder:
            return !browser.privateBrowsing && browser.prefs.usesLiveFolders && browser.nests.contains {
                $0.live != nil && !LiveFolders.shared.reading.contains($0.id) && !LiveFolders.shared.checking($0)
            }
        case .stopLiveFolder: return !browser.privateBrowsing && browser.prefs.usesLiveFolders && browser.nests.contains { $0.live != nil }
        default: return false
        }
    }

    @MainActor static func targets(_ operation: Command? = nil, in browser: Browser) -> [MenuCommandTarget] {
        guard browser.fieldGuest == nil else { return [] }
        let projects = ChatProjectCommands.targets(operation, in: browser)
        var out: [MenuCommandTarget] = []
        func add(_ action: Command, _ id: String, _ title: String, _ aliases: [String] = [],
                 symbol: String = "command", key: Shortcut.Action? = nil, opens: Bool = false,
                 run: @escaping @MainActor (Browser) -> Void) {
            guard operation == nil || operation == action else { return }
            out.append(MenuCommandTarget(id: action.rawValue + ":" + id, operation: action,
                                         title: title, aliases: aliases, symbol: symbol,
                                         shortcut: key, opens: opens, run: run))
        }
        func folderToggle(_ nest: Nest, id: String, name: String) {
            let action: Command = nest.open ? .closeFolder : .openFolder
            add(action, id, "\(nest.open ? "Close" : "Open") Folder \(name)",
                nest.open ? [] : ["open \(name)", "folder \(name)"], symbol: "folder", opens: !nest.open) {
                $0.folderBook.toggle(nest.key)
            }
        }
        if browser.spacesShown && !browser.privateBrowsing {
            for (index, space) in browser.switcherSpaces.enumerated() where space.id != browser.sidebarSpaceID {
                let id = space.id.uuidString
                var aliases = ["focus on \(space.name)", "go to space \(space.name)"]
                if space.id == Space.allTabs.id { aliases += ["All Tabs", space.name] }
                add(.switchSpace, id, "Switch to \(space.name)", aliases,
                    symbol: "square.2.layers.3d", key: Shortcut.numbered("space", index + 1), opens: true) {
                    $0.switchSpace(to: space.id)
                }
                if space.id != Space.allTabs.id, space.id != browser.spaceID, space.id != Space.mailID, browser.chosen.contains(where: { browser.sendable($0) && $0.everywhere == nil }) {
                    add(.moveToSpace, id, "Move \(tabsWord(browser)) to \(space.name)",
                        ["move tab to space \(space.name)", "move tabs to space \(space.name)"],
                        symbol: "square.2.layers.3d", key: Shortcut.numbered("sendSpace", index + 1)) {
                        $0.moveTabs($0.chosen, to: space.id)
                    }
                    if let nest = browser.folderHere {
                        add(.moveFolder, "space:" + id + ":" + nest.id.uuidString,
                            "Move Folder \(nest.name) to \(space.name)", symbol: "folder") {
                            _ = $0.moveFolder(nest, to: space.id)
                        }
                    }
                }
            }
        }
        // Only this private window's ephemeral folders; a private tab in
        // a normal window still cannot list personal destinations.
        if browser.windowPurpose == .privateOnly {
            for nest in browser.nests {
                let name = nest.chain.map { $0.name.isEmpty ? "Untitled Folder" : $0.name }.joined(separator: " / ")
                folderToggle(nest, id: nest.id.uuidString, name: name)
            }
        }
        if !browser.privateBrowsing {
            for nest in browser.nests {
                let id = nest.id.uuidString
                let name = nest.chain.map { $0.name.isEmpty ? "Untitled Folder" : $0.name }.joined(separator: " / ")
                if !nest.today {
                    if browser.chosen.contains(where: { $0.keepable && $0.nest !== nest }) {
                        add(.moveToFolder, id, "Move \(tabsWord(browser)) to Folder \(name)",
                            ["move to \(name)", "pin to \(name)", "move tab to \(name)"], symbol: "folder") {
                            $0.file($0.chosen, in: nest)
                        }
                    }
                    add(.renameFolder, id, "Rename Folder \(name)…", symbol: "pencil", opens: true) {
                        $0.folderBook.naming = nest.id
                    }
                    add(.customizeFolder, id, "Customize Folder \(name)…", symbol: "slider.horizontal.3", opens: true) { _ in
                        IconPicking.shared.open(.nest(nest.id))
                    }
                    if nest.depth < Nest.deepest {
                        add(.newFolderInside, id, "New Folder Inside \(name)…", symbol: "folder.badge.plus", opens: true) {
                            $0.newFolder(inside: nest)
                        }
                    }
                    if let source = browser.folderHere, browser.canPut(source, in: nest) {
                        add(.moveFolder, id, "Move Folder \(source.name) into \(name)", symbol: "folder") {
                            $0.file(source, in: nest)
                        }
                    }
                }
                folderToggle(nest, id: id, name: name)
                add(.ungroupFolder, id, "Remove Folder \(name), Keep Tabs", ["ungroup \(name)"], symbol: "folder") {
                    LiveFolders.shared.removed(nest, in: $0)
                    $0.ungroup(nest)
                }
                if nest.live != nil, browser.prefs.usesLiveFolders {
                    if !LiveFolders.shared.reading.contains(nest.id), !LiveFolders.shared.checking(nest) {
                        add(.updateLiveFolder, id, "Update Live Folder \(name)", ["refresh \(name)", "update \(name)"], symbol: "arrow.clockwise") {
                            LiveFolders.shared.read(nest, in: $0)
                        }
                    }
                    add(.stopLiveFolder, id, "Stop Updating Live Folder \(name)", symbol: "pause") {
                        LiveNestMenu.stop(nest, in: $0)
                    }
                }
            }
            if let nest = browser.folderHere, nest.parent != nil {
                add(.moveFolder, nest.id.uuidString + ":out", "Move Folder \(nest.name) Out of Folder", symbol: "folder") {
                    $0.file(nest, in: nest.parent?.parent)
                }
            }
            if browser.prefs.usesLiveFolders {
                for source in LiveSource.all where LiveGitService.of(source.id) == nil && source.id != "feed" && source.id != "github.search" {
                    // Pull Requests already has a Command of its own.
                    guard source.id != "github.pulls" || operation != nil else { continue }
                    add(.newLiveFolder, source.id, "New \(source.title) Folder",
                        ["live folder \(source.title)"], symbol: "folder.badge.gearshape") {
                        $0.folderBook.unfoldSpace()
                        LiveFolders.shared.make(source.id, in: $0)
                    }
                }
            }
        }
        if canMoveWindow(browser), let tab = browser.active {
            for destination in BrowserWindows.shared.openWindows()
                where destination.browser !== browser && destination.browser.spaceID == browser.spaceID && !destination.browser.privateBrowsing {
                add(.moveToWindow, destination.id.uuidString, "Move Tab to Window \(destination.title)", symbol: "macwindow") {
                    _ = BrowserWindows.shared.move(tab, from: $0, to: destination.browser)
                }
            }
        }
        if browser.active.map({ !$0.isBlank }) == true {
            for pane in DevTab.allCases {
                let route = pane.pane
                // Console and Elements already have named Commands.
                guard pane != .console, pane != .elements else { continue }
                add(.developerPanel, "pane:" + pane.title, "Open \(pane.title) Panel",
                    [pane.title, "\(pane.title) panel", "developer \(pane.title)"], symbol: "hammer", opens: true) {
                    $0.openDevTools(route)
                }
            }
            let panels = Set(DevTab.allCases.map { $0.title.lowercased() })
            for tool in DevTool.allCases where tool != .console && !panels.contains(tool.rawValue.lowercased()) {
                let title = tool == .search ? "Search Developer Tools" :
                    tool == .autofill ? "Open Autofill Developer Tool" : "Open \(tool.rawValue)"
                let aliases = tool == .search || tool == .autofill ? ["developer \(tool.rawValue)"] : [tool.rawValue]
                add(.developerPanel, "tool:" + tool.rawValue, title,
                    aliases, symbol: "hammer", opens: true) { $0.showTool(tool) }
            }
        }
        if (operation == nil || operation == .collectionColumn), browser.inCollections, !browser.privateBrowsing,
           browser.currentRecord == nil, !browser.creatingCollection, !browser.creatingCollectionRecord {
            let library = CollectionLibrary.shared
            if let collection = library.collections.first(where: { $0.id == browser.collectionID }) ?? library.collections.first,
               let view = collection.views.first(where: { $0.id == collection.selectedView }) ?? collection.views.first {
                let rtl = NSApp.userInterfaceLayoutDirection == .rightToLeft
                for property in view.visibleProperties(collection.properties) {
                    for action in CollectionColumnAction.allCases where view.supports(action, column: property.id, properties: collection.properties) {
                        let name = action.title(rtl: rtl)
                        add(.collectionColumn, "\(collection.id):\(view.id):\(property.id):\(action.rawValue)",
                            "\(name) · \(property.title)", [name, name + " " + property.title], symbol: property.type.symbol) { _ in
                            guard let i = library.collections.firstIndex(where: { $0.id == collection.id }),
                                  let j = library.collections[i].views.firstIndex(where: { $0.id == view.id }) else { return }
                            let schema = library.collections[i].properties
                            library.collections[i].views[j].apply(action, column: property.id, properties: schema)
                        }
                    }
                }
            }
        }
        out += projects
        return out.filter { browser.prefs.menuCommands || MenuCommands.everyone.contains($0.operation) }
    }

    @MainActor static func choose(_ command: Command, in browser: Browser) {
        // Preserve the existing choice UI, its keyboard navigation and search.
        // The field is already gone when this menu appears.
        DispatchQueue.main.async {
            guard let window = Self.window(browser), let view = window.contentView else { return }
            let menu = NSMenu(title: command.title)
            for target in targets(command, in: browser) {
                let item = PageMenuItem(target.title) {
                    _ = runTarget(target.id, in: browser)
                }
                if let shortcut = target.shortcut, let key = Keymap.shared.keys(shortcut) { item.shortcut(key) }
                menu.addItem(item)
            }
            if command == .newLiveFolder, !browser.prefs.usesLiveFolders {
                menu.addItem(PageMenuItem("Turn On Live Folders…") { browser.openSettings(.liveFolders) })
            }
            guard !menu.items.isEmpty else { return }
            ActionMenu.show(menu, in: window, at: NSPoint(x: view.bounds.midX, y: view.bounds.midY))
        }
    }

    @MainActor @discardableResult static func runTarget(_ id: String, in browser: Browser) -> Bool {
        guard let name = id.split(separator: ":").first, let operation = Command(rawValue: String(name)),
              let target = targets(operation, in: browser).first(where: { $0.id == id }) else { return false }
        target.run(browser)
        return true
    }

    @MainActor static func tabsWord(_ browser: Browser) -> String { browser.several ? "Tabs" : "Tab" }
}

extension Suggestion {
    var menuTargetID: String? {
        guard case .page(let id) = kind, id.hasPrefix("menu:") else { return nil }
        return String(id.dropFirst(5))
    }
    var isMenuCommand: Bool {
        if case .command = kind { return true }
        return menuTargetID != nil
    }
}

extension Browser {
    /// The page-copy card already owns reading and writing the page. Raise it
    /// first, then use its own operation; a Markdown document is not a URL.
    func copyWholePageForCommand(save: Bool) {
        guard let tab = active, let web = tab.builtPage, !tab.isBlank, !fieldShowing,
              !save || !tab.shy else { return }
        pageCopy.offer(tab: tab.id, web: web, words: 0, canSave: !tab.shy, transcript: false)
        // offer makes its stage visible on the next main-queue turn.
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab, self.activeID == tab.id else { return }
            if save { self.savePageForAgent() } else { self.copyPageMarkdown() }
        }
    }

    func captureForCommand(whole: Bool, portrait: Bool = false) {
        DispatchQueue.main.async {
            if self.capture.shown { self.capture.close(quick: true) }
            if portrait { self.capture.model.style.shape = .tall }
            self.capture.start()
            if whole { self.capture.take(.whole) }
        }
    }
}
