import AppKit
import SwiftUI

/// A list embedded outside its Space still runs Sidebar commands against its owning row.
@MainActor struct SidebarSpaceActions {
    let browser: Browser
    let id: UUID

    func run(_ action: () -> Void, stay: Bool = false) {
        guard browser.spaceID != id else { action(); return }
        let origin = browser.spaceID
        let still = SpaceTurn.still
        SpaceTurn.still = true
        defer { SpaceTurn.still = still }
        browser.switchSpace(to: id)
        guard browser.spaceID == id else { return }
        action()
        if !stay && browser.spaceID == id { browser.switchSpace(to: origin) }
    }
}

extension Optional where Wrapped == SidebarSpaceActions {
    @MainActor func perform(stay: Bool = false, _ action: () -> Void) {
        if let scope = self { scope.run(action, stay: stay) } else { action() }
    }
}

private struct SidebarSpaceActionsKey: EnvironmentKey {
    static let defaultValue: SidebarSpaceActions? = nil
}

extension EnvironmentValues {
    var sidebarSpaceActions: SidebarSpaceActions? {
        get { self[SidebarSpaceActionsKey.self] }
        set { self[SidebarSpaceActionsKey.self] = newValue }
    }
}

/// A right-click menu that holds still while the row it hangs from redraws.
///
/// SwiftUI's `.contextMenu` puts new lines in an open menu each time the
/// view it is on updates, even when nothing in the menu changed, and a line
/// replaced under the pointer drops its open submenu, which AppKit brings
/// back a beat later: a tab's Edit Kept Page, Move to Folder and Move to
/// Space blinking while the page in it kept its row busy (alpha report,
/// Slumdog8). Here the menu is AppKit's with SwiftUI's lines in it
/// (NSHostingMenu), made at the press from the menu's own view alone: only
/// a change to what the menu itself shows touches it, and then only that
/// line. The right button and ⌃-click open it, as they open `.contextMenu`.
extension View {
    /// `actions`: the lines in ⌘K's list with a search, not AppKit's menu
    /// (ActionMenu.swift).
    func steadyMenu<Lines: View>(actions: Bool = false, @ViewBuilder _ lines: @escaping () -> Lines) -> some View {
        overlay { SteadyMenuSpot(make: { NSHostingMenu(rootView: lines()) }, actions: actions) }
    }

    /// The menu of the half the press is in, `true` for the left: a split
    /// row's two tabs side by side in one row, each its own menu.
    func steadyMenu<Lines: View>(actions: Bool = false, halves lines: @escaping (Bool) -> Lines) -> some View {
        overlay { SteadyMenuSpot(make: { NSHostingMenu(rootView: lines(true)) }, half: { NSHostingMenu(rootView: lines($0)) }, actions: actions) }
    }
}

private struct SteadyMenuSpot: NSViewRepresentable {
    let make: @MainActor () -> NSMenu
    var half: (@MainActor (Bool) -> NSMenu)? = nil
    var actions = false

    func makeNSView(context: Context) -> SteadyMenuView {
        let view = SteadyMenuView()
        view.make = make
        view.half = half
        view.scope = context.environment.sidebarSpaceActions
        view.actions = actions
        return view
    }

    func updateNSView(_ view: SteadyMenuView, context: Context) {
        view.make = make
        view.half = half
        view.scope = context.environment.sidebarSpaceActions
        view.actions = actions
    }
}

/// Takes only a press asking for a menu: every other press, the pointer's
/// hover and drags go through it to the row beneath, as if it weren't there.
final class SteadyMenuView: NSView {
    var scope: SidebarSpaceActions?
    var make: (@MainActor () -> NSMenu)?
    /// Made for the half pressed in, left or not, when there are halves.
    var half: (@MainActor (Bool) -> NSMenu)?
    var actions = false
    /// Stepped aside while looking for a menu under this one.
    private var aside = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !aside, BookmarkBar.asksForMenu(NSApp.currentEvent) else { return nil }
        guard let hit = super.hitTest(point) else { return nil }
        return within() ?? hit
    }

    /// The menu of something inside this one: it lies under this one's
    /// overlay, so the band's address menu answered for the pinned
    /// extensions in the band, which have their own. Only one drawn in the
    /// same SwiftUI host: a menu under it in another host is something
    /// else's, behind it. A pin over the column's rows gave way to the
    /// folder row scrolled under it, and its right click offered Close
    /// Folder and Remove Folder and Tab instead of the pin's own lines
    /// (owner, 2026-11-05). Or Yab quit: the row's menu gave way
    /// back to the pin's, and SwiftUI's hit test of the row's host, handed
    /// a view of the pin's host, tested again, and the two went in circles
    /// until the main thread's stack ran out (11 crashes on 0.46.x, #1313).
    private func within() -> SteadyMenuView? {
        guard let event = NSApp.currentEvent, event.window === window,
              let root = window?.contentView?.superview, let host = Self.host(of: self) else { return nil }
        aside = true
        defer { aside = false }
        guard let under = root.hitTest(event.locationInWindow) as? SteadyMenuView, under.isDescendant(of: host) else { return nil }
        return under
    }

    /// The SwiftUI host a view is drawn in: the nearest NSHostingView over
    /// it (a column's cell is one of its own).
    private static func host(of view: NSView) -> NSView? {
        var next = view.superview
        while let each = next {
            if hosts(each) { return each }
            next = each.superview
        }
        return nil
    }

    /// An NSHostingView of any root view: the class is generic, so by name.
    private static func hosts(_ view: NSView) -> Bool {
        var kind: AnyClass? = type(of: view)
        while let each = kind {
            if NSStringFromClass(each).contains("NSHostingView") { return true }
            kind = class_getSuperclass(each)
        }
        return false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let left = convert(event.locationInWindow, from: nil).x < bounds.midX
        let makeMenu = { self.half?(left) ?? self.make?() }
        guard let scope, scope.id != scope.browser.spaceID else { return makeMenu() }
        var menu: NSMenu?
        scope.run { menu = makeMenu(); menu?.update() }
        return menu
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return super.rightMouseDown(with: event) }
        pop(menu, with: event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control), let menu = menu(for: event) else { return super.mouseDown(with: event) }
        pop(menu, with: event)
    }

    private func pop(_ menu: NSMenu, with event: NSEvent) {
        if actions {
            ActionMenu.show(menu, from: self, with: event, scope: scope)
        } else {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }
}
