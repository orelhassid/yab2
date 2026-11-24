import AppKit
import SwiftUI
import Testing
@testable import Fast

// This suite uses APIs already present on the untouched base. Copy this
// file alone for a baseline presentation run; the new hover APIs live in
// ActionMenuVariantFHoverTests.swift. A red result is only claimed after a run.
@MainActor
final class VariantFMenuTarget: NSObject {
    var received: [String] = []

    @objc func invoke(_ sender: NSMenuItem) {
        received.append(sender.representedObject as? String ?? sender.title)
    }
}

@MainActor
enum VariantFMenuFixture {
    static func menu(_ items: [NSMenuItem]) -> NSMenu {
        _ = NSApplication.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        return menu
    }

    static func item(_ title: String, target: VariantFMenuTarget, id: String? = nil,
                     enabled: Bool = true, key: String = "", flags: NSEvent.ModifierFlags = []) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(VariantFMenuTarget.invoke(_:)), keyEquivalent: key)
        item.target = target
        item.representedObject = id ?? title
        item.isEnabled = enabled
        item.keyEquivalentModifierMask = flags
        return item
    }

    static func submenu(_ title: String, _ children: NSMenu, image: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = children
        item.image = image
        return item
    }

    static func tab(_ visible: [NSMenuItem], extras: NSMenu) -> NSMenu {
        menu(visible + [submenu(ActionMenu.tabSearchActions, extras)])
    }
}

@MainActor @Suite(.serialized)
struct ActionMenuVariantFPresentationTests {
    @Test(arguments: [0.0, 0.25, 0.5, 0.75])
    func openingTallSubmenuKeepsRootRowsAtTheSameScreenPosition(fraction: CGFloat) async throws {
        let target = VariantFMenuTarget()
        let destinations = VariantFMenuFixture.menu((0..<8).map {
            VariantFMenuFixture.item("Destination \($0)", target: target)
        })
        let root = ActionMenuList(menu: VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Rename Space", target: target),
            VariantFMenuFixture.submenu("New Live Folder", destinations),
            VariantFMenuFixture.item("Space Settings", target: target)
        ]), falls: true)
        let child = ActionMenuList(menu: destinations, falls: true, nested: true)
        let plate = CGRect(x: -20_000 + fraction, y: -20_000 + fraction,
                           width: root.width, height: ActionMenuView.height(root))
        let layout = ActionMenuLayout()
        let window = NSWindow(contentRect: plate, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        layout.place([root], frames: [plate], in: window, room: ActionMenu.room)
        let host = NSHostingView(rootView: ActionMenuStack(layout: layout, tone: nil))
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: window.frame.size)
        host.autoresizingMask = [.width, .height]
        defer { window.close() }
        func settle() async throws {
            for _ in 0..<6 {
                host.layoutSubtreeIfNeeded()
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await settle()
        let initial = try #require(root.wordFrames[0])
        let anchor = window.frame.maxY - initial.minY
        for _ in 0..<4 {
            let row = try #require(root.frames[1])
            let childTop = window.frame.maxY - row.minY + ActionMenuView.pad
            let tall = ActionMenuView.height(child)
            let childPlate = CGRect(x: plate.maxX + 4, y: childTop - tall, width: child.width, height: tall)
            layout.place([root, child], frames: [plate, childPlate], in: window, room: ActionMenu.room)
            try await settle()
            let open = try #require(root.wordFrames[0])
            #expect(abs(window.frame.maxY - open.minY - anchor) < 0.1)
            layout.place([root], frames: [plate], in: window, room: ActionMenu.room)
            try await settle()
            let closed = try #require(root.wordFrames[0])
            #expect(abs(window.frame.maxY - closed.minY - anchor) < 0.1)
        }
    }

    @Test func checkedSignInChoiceFitsWithoutTruncation() async throws {
        let target = VariantFMenuTarget()
        let shared = VariantFMenuFixture.item("Shared", target: target)
        shared.state = .on
        let list = ActionMenuList(menu: VariantFMenuFixture.menu([
            shared, VariantFMenuFixture.item("Its Own", target: target)
        ]), falls: true, nested: true)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: list.width, height: ActionMenuView.height(list)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ActionMenuView(list: list))
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: window.frame.size)
        defer { window.close() }
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            if list.wordFrames.count == 2 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        for line in list.lines {
            let words = try #require(list.wordFrames[line.id])
            let fullWidth = (line.name as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
            #expect(words.width >= floor(fullWidth))
        }
    }

    @Test func hiddenAlternatesDoNotWidenTheOrdinaryMenu() {
        let target = VariantFMenuTarget()
        let copy = VariantFMenuFixture.item("Copy Link", target: target, key: "C", flags: .command)
        let alternate = VariantFMenuFixture.item("Copy Markdown Link", target: target, key: "C", flags: [.command, .option])
        let root = VariantFMenuFixture.tab([copy], extras: VariantFMenuFixture.menu([alternate]))
        let list = ActionMenuList(menu: root, falls: true)
        let ordinary = ActionMenuList(menu: VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Copy Link", target: target, key: "C", flags: .command)
        ]), falls: true)
        let width = list.width
        #expect(width == ordinary.width)
        list.modifiers(.option)
        #expect(list.lines.first?.title == "Copy Markdown Link")
        #expect(list.width > width)
        list.modifiers([])
        #expect(list.width == width)
        list.query = "markdown"
        #expect(list.lines.first?.title == "Copy Markdown Link")
        #expect(list.width > width)
        list.query = ""
        #expect(list.width == width)
    }

    @Test(arguments: [false, true])
    func smallMenusExposeSearchBeforeTypingAndAfterClearing(tab: Bool) {
        let target = VariantFMenuTarget()
        let copy = VariantFMenuFixture.item("Copy Link", target: target)
        let extras = VariantFMenuFixture.menu([VariantFMenuFixture.item("Put Tab to Sleep", target: target)])
        let menu = tab ? VariantFMenuFixture.tab([copy], extras: extras) : VariantFMenuFixture.menu([copy])
        let list = ActionMenuList(menu: menu, falls: true)
        #expect(list.searchVisible)
        #expect(list.lines.map(\.title) == ["Copy Link"])
        list.query = "copy"
        #expect(list.searchVisible)
        list.query = ""
        #expect(list.searchVisible)
        #expect(list.lines.map(\.title) == ["Copy Link"])
    }

    @Test func querySelectsFirstEnabledMatchAndReturnDispatchesOriginalMenuItem() throws {
        let target = VariantFMenuTarget()
        let menu = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Unrelated", target: target, id: "wrong-unfiltered-index"),
            .separator(),
            VariantFMenuFixture.item("Copy Disabled", target: target, id: "disabled", enabled: false),
            VariantFMenuFixture.item("Copy Link", target: target, id: "copy-link"),
            VariantFMenuFixture.item("Copy Markdown Link", target: target, id: "copy-markdown"),
        ])
        let list = ActionMenuList(menu: menu, falls: true)
        var closed = 0
        list.close = { closed += 1 }
        list.query = "copy"
        #expect(list.lines.map(\.title) == ["Copy Disabled", "Copy Link", "Copy Markdown Link"])
        let selected = try #require(list.lines.indices.contains(list.spot) ? list.lines[list.spot] : nil)
        #expect(selected.title == "Copy Link")
        #expect(selected.menu === menu)
        #expect(selected.index == 3)
        list.take()
        #expect(target.received == ["copy-link"])
        #expect(closed == 1)
    }

    @Test func visibleTabSearchFindsHiddenNestedCommandAndKeepsItsOriginalDispatch() throws {
        let target = VariantFMenuTarget()
        let maintenance = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Inspect State", target: target, id: "wrong-extra-index"),
            .separator(),
            VariantFMenuFixture.item("Put Tab to Sleep", target: target, id: "sleep"),
        ])
        let extras = VariantFMenuFixture.menu([VariantFMenuFixture.submenu("Maintenance", maintenance)])
        let menu = VariantFMenuFixture.tab([VariantFMenuFixture.item("Pin", target: target)], extras: extras)
        let list = ActionMenuList(menu: menu, falls: false)
        #expect(list.searchVisible)
        #expect(list.lines.map(\.title) == ["Pin"])
        list.query = "sleep"
        let match = try #require(list.lines.first)
        #expect(list.lines.count == 1)
        #expect(match.title == "Put Tab to Sleep")
        #expect(match.menu === maintenance)
        #expect(match.index == 2)
        list.take()
        #expect(target.received == ["sleep"])
    }

    @Test func ordinaryMenuSearchKeepsSameNamedDestinationsUnderDistinctParents() throws {
        let target = VariantFMenuTarget()
        let folders = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Personal", target: target, id: "wrong-folder-index"),
            VariantFMenuFixture.item("Work", target: target, id: "folder-work"),
        ])
        let spaces = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Home", target: target, id: "wrong-space-index"),
            VariantFMenuFixture.item("Work", target: target, id: "space-work"),
        ])
        let menu = VariantFMenuFixture.menu([
            VariantFMenuFixture.submenu("Move to Folder", folders),
            VariantFMenuFixture.submenu("Move to Space", spaces),
        ])
        let list = ActionMenuList(menu: menu, falls: true)
        list.query = "work"
        #expect(list.lines.count == 2)
        #expect(list.lines.map(\.title) == ["Work", "Work"])
        #expect(list.lines.map(\.from) == ["Move to Folder", "Move to Space"])
        let folderMatch = try #require(list.lines.first)
        let spaceMatch = try #require(list.lines.last)
        #expect(folderMatch.menu === folders)
        #expect(spaceMatch.menu === spaces)
        list.take(0)
        list.take(1)
        #expect(target.received == ["folder-work", "space-work"])
    }

    @Test func shortcutMetadataDistinguishesBackspaceFromForwardDelete() {
        let target = VariantFMenuTarget()
        let menu = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Remove Previous", target: target, key: "\u{7f}", flags: .command),
            VariantFMenuFixture.item("Remove Next", target: target,
                                     key: String(UnicodeScalar(NSDeleteFunctionKey)!), flags: .command),
        ])
        let list = ActionMenuList(menu: menu, falls: true)
        #expect(list.lines.map(\.keys) == ["⌘⌫", "⌘⌦"])
        #expect(target.received.isEmpty)
    }

    @Test func escapeClearsQueryWithoutDismissingOrHidingSearch() {
        let target = VariantFMenuTarget()
        let menu = VariantFMenuFixture.tab(
            [VariantFMenuFixture.item("Copy Link", target: target), VariantFMenuFixture.item("Pin", target: target)],
            extras: VariantFMenuFixture.menu([]))
        let list = ActionMenuList(menu: menu, falls: true)
        var closed = 0
        list.close = { closed += 1 }
        list.query = "copy"
        #expect(list.lines.count == 1)
        list.escape()
        #expect(list.query.isEmpty)
        #expect(list.searchVisible)
        #expect(list.lines.map(\.title) == ["Copy Link", "Pin"])
        #expect(closed == 0)
        list.escape()
        #expect(closed == 1)
        #expect(target.received.isEmpty)
    }

    @Test func separatorsRemainVisibleBetweenOrdinaryActionGroups() throws {
        let target = VariantFMenuTarget()
        let plain = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Pin", target: target),
            VariantFMenuFixture.item("Rename", target: target),
        ])
        let divided = VariantFMenuFixture.menu([
            VariantFMenuFixture.item("Pin", target: target), .separator(),
            VariantFMenuFixture.item("Rename", target: target),
        ])
        let plainList = ActionMenuList(menu: plain, falls: true)
        let dividedList = ActionMenuList(menu: divided, falls: true)
        #expect(dividedList.lines.map(\.title) == plainList.lines.map(\.title))
        let last = try #require(dividedList.lines.last)
        #expect(last.boundary == .line)
        #expect(ActionMenuView.listHeight(dividedList) > ActionMenuView.listHeight(plainList))
        dividedList.query = "rename"
        #expect(dividedList.lines.map(\.title) == ["Rename"])
        #expect(dividedList.lines.first?.boundary == nil)
    }

    @Test(arguments: [false, true])
    func renderedRowsAndPlainShortcutUseApprovedSearchAndRowGeometry(tab: Bool) async throws {
        let target = VariantFMenuTarget()
        let copy = VariantFMenuFixture.item("Copy Markdown Link", target: target, key: "C", flags: [.option, .command])
        let pin = VariantFMenuFixture.item("Pin", target: target)
        let menu = tab ? VariantFMenuFixture.tab([copy, pin], extras: VariantFMenuFixture.menu([]))
                       : VariantFMenuFixture.menu([copy, pin])
        let list = ActionMenuList(menu: menu, falls: true)
        let window = NSWindow(contentRect: CGRect(x: -20_000, y: -20_000, width: list.width, height: ActionMenuView.height(list)),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ActionMenuView(list: list))
        window.contentView = host
        host.frame = CGRect(origin: .zero, size: window.frame.size)
        defer { window.close() }
        // No window is ordered onscreen. Geometry callbacks are delivered
        // over the next main-actor turns, as in the live panel's layout.
        for _ in 0..<30 {
            host.layoutSubtreeIfNeeded()
            if list.frames.count >= 2, list.keyFrames[0] != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let first = try #require(list.frames[0])
        let second = try #require(list.frames[1])
        let key = try #require(list.keyFrames[0])
        let native = NSMenu()
        native.addItem(withTitle: "One", action: nil, keyEquivalent: "")
        let one = native.size.height
        native.addItem(withTitle: "Two", action: nil, keyEquivalent: "")
        let nativeRow = native.size.height - one
        #expect(abs(first.height - nativeRow) < 0.5)
        #expect(abs(second.height - nativeRow) < 0.5)
        #expect(abs(second.minY - first.maxY) < 0.5)
        #expect(abs(ActionMenuView.height(list) - ActionMenuView.listHeight(list) - 31) < 0.5)
        #expect(list.lines[0].keys == "⌥⇧⌘C")
        let nativeWidth = (list.lines[0].keys as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        #expect(abs(key.width - nativeWidth) < 4)
        let words = try #require(list.wordFrames[0])
        #expect(key.minX > words.maxX)
        #expect(target.received.isEmpty)
    }
}
