import AppKit
import Combine
import SwiftUI

/// The bookmarks in a row, for whoever asks for them (Settings › Appearance,
/// or ⇧⌘B): on the backdrop over the page, never on the card itself. The
/// card is the site's, the address bar at its top included; what is the
/// browser's lies round it, with the tabs and the lights.
///
/// Level with the lights beside the column where they stand, under the
/// strip when the tabs run across the top. Sites with their icon and name, a
/// folder with its own mark, opening our menu of what is in it;
/// whatever doesn't fit goes into » at the end. The empty run past the last
/// one moves the window, as the strip's does.
///
/// Nothing in it moves on the frequent path: another tab is the same row.
struct BookmarkBar: View {
    @ObservedObject var browser: Browser
    @ObservedObject var bookmarks: Bookmarks
    /// The row's whole room, and where in it the line of bookmarks stands.
    let height: CGFloat
    let top: CGFloat
    /// In from the room's ends to the first and last bookmark.
    let lead: CGFloat
    let trail: CGFloat
    /// What each bookmark shows (Settings › Appearance): its icon and name,
    /// its icon alone, or a folder its name and a site its icon.
    var style: BookmarkStyle = .names

    @Environment(\.tone) private var tone
    /// How wide the offers in an empty row are, so the rest of it moves
    /// the window.
    @State private var emptyRun: CGFloat = 0
    /// How wide the empty row's place for a page was, for the page kept
    /// there to grow out of it.
    @State private var place: CGFloat = 0

    /// A bookmark's height: the address bar's site, and every other control.
    static let row: CGFloat = 24
    /// The room under the strip, or wherever there are no lights to be
    /// level with.
    static let height: CGFloat = 32
    /// The room beside the column's lights, the bookmarks' middle on theirs,
    /// half the column's top band down.
    static let besideLights: CGFloat = Metrics.strip / 2 + row / 2 + 6

    static let font = NSFont.systemFont(ofSize: 12)
    static let pad: CGFloat = 7
    static let gap: CGFloat = 2
    static let icon: CGFloat = 14
    static let iconGap: CGFloat = 5
    /// A long title gives up its end past this.
    static let longest: CGFloat = 150
    /// The » square.
    static let more: CGFloat = 24

    var body: some View {
        GeometryReader { space in
            let nodes = Self.chips(bookmarks.barRoots(in: browser.spaceID, profile: browser.space.signedInAs ?? browser.space.origin), style: style)
            let room = max(0, space.size.width - lead - trail)
            let fit = Self.fit(nodes, in: room, style: style)
            let run = Self.run(nodes.prefix(fit), more: fit < nodes.count, style: style)

            ZStack(alignment: .topLeading) {
                // Under the row, a real view: the empty part of the room
                // moves the window, the bookmarks are refused and fall
                // through to themselves.
                DragStrip(reserved: lead + (nodes.isEmpty ? emptyRun : run))

                HStack(spacing: Self.gap) {
                    if nodes.isEmpty {
                        ShelfEmpty(browser: browser) { place = $0 }
                            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { emptyRun = $0 }
                            // Gone at once when something is kept: the page
                            // kept carries the place on (see `Grow`), and
                            // bookmarks brought over come in where it was.
                            .transition(.identity)
                    } else {
                        let wave = bookmarks.arriving
                        ForEach(Array(nodes.prefix(fit).enumerated()), id: \.element.id) { index, node in
                            let fresh = bookmarks.isFresh(node.id)
                            ShelfItem(browser: browser, bookmarks: bookmarks, chip: node, named: style.named(folder: node.node.isFolder), fresh: fresh)
                                .transition(Self.arrival(
                                    fresh: fresh ? (place, Self.span(node, style: style)) : nil,
                                    wave: wave ? index : nil
                                ))
                        }
                        if fit < nodes.count {
                            More(browser: browser, nodes: nodes.dropFirst(fit).flatMap(\.nodes))
                                .transition(Self.arrival(fresh: nil, wave: wave ? fit : nil))
                        }
                    }
                }
                .frame(height: Self.row)
                // Only when the bookmarks themselves change: kept, brought
                // over, put away. Another tab is the same row, still.
                .animation(Motion.settle, value: nodes.map(\.id))
                // Another style is another row at once, not one sliding
                // into it.
                .transaction(value: style) { $0.animation = nil }
                .padding(.leading, lead)
                .padding(.top, top)
            }
        }
        .frame(height: height)
    }

    /// How a bookmark comes into the row. The one just kept into an empty
    /// row, out of the place the row offered: that place's size and dashed
    /// edge, becoming its own (see `Grow`); another browser's, one after
    /// another, twenty milliseconds apart, a hint down; one kept into a row
    /// that has others, growing in at its end.
    static func arrival(fresh: (from: CGFloat, to: CGFloat)?, wave: Int?) -> AnyTransition {
        if let fresh, fresh.from > 0 {
            return .asymmetric(
                insertion: .modifier(
                    active: Grow(done: 0, from: fresh.from, to: fresh.to),
                    identity: Grow(done: 1, from: fresh.from, to: fresh.to)
                ),
                removal: .opacity
            )
        }
        if let wave {
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(y: -3))
                    .animation(Motion.arrive.delay(Double(min(wave, 12)) * 0.02)),
                removal: .opacity
            )
        }
        return .scale(scale: 0.9, anchor: .leading).combined(with: .opacity)
    }

    /// What a bookmark is called in the row.
    static func label(_ node: Bookmark) -> String {
        if !node.title.isEmpty { return node.title }
        return node.url.flatMap(URL.init(string:)).map(Address.pretty) ?? "Untitled"
    }

    /// A run of adjacent pages of one host, or one folder or page.
    /// The first bookmark gives it a stable identity; nothing is saved.
    struct Chip: Identifiable, Equatable {
        var nodes: [Bookmark]
        var node: Bookmark { nodes[0] }
        var id: Bookmark.ID { node.id }
        var stacked: Bool { nodes.count > 1 }
        var title: String { stacked ? node.host ?? label(node) : label(node) }
        var contents: [Bookmark] { node.isFolder ? node.children ?? [] : nodes }
    }

    static func chips(_ nodes: [Bookmark], style: BookmarkStyle) -> [Chip] {
        var out: [Chip] = []
        for node in nodes {
            if style != .names, !node.isFolder, let host = node.host,
               let last = out.last, !last.node.isFolder, last.node.host == host {
                out[out.count - 1].nodes.append(node)
            } else {
                out.append(Chip(nodes: [node]))
            }
        }
        return out
    }

    static let countFont = NSFont.systemFont(ofSize: 11)
    static let stackPeek: CGFloat = 4

    static func countWidth(_ count: Int) -> CGFloat {
        ceil((String(count) as NSString).size(withAttributes: [.font: countFont]).width)
    }

    /// The same fixed widths used by the chips, before SwiftUI lays them out.
    static func span(_ chip: Chip, style: BookmarkStyle = .names) -> CGFloat {
        if chip.stacked { return pad * 2 + icon + stackPeek + iconGap + countWidth(chip.nodes.count) }
        let node = chip.node
        guard style.named(folder: node.isFolder) else { return row }
        let count = node.isFolder ? iconGap + countWidth(Bookmarks.count(node.children ?? [])) : 0
        return pad * 2 + icon + iconGap + words(node) + count
    }

    static func span(_ node: Bookmark, style: BookmarkStyle = .names) -> CGFloat {
        span(Chip(nodes: [node]), style: style)
    }

    /// How wide the title is drawn: as wide as it is, up to `longest`.
    static func words(_ node: Bookmark) -> CGFloat {
        min(longest, ceil((label(node) as NSString).size(withAttributes: [.font: font]).width))
    }

    /// Count chips, reserving room for » whenever another chip follows.
    static func fit(_ chips: [Chip], in width: CGFloat, style: BookmarkStyle = .names) -> Int {
        var used: CGFloat = 0
        for (i, chip) in chips.enumerated() {
            let wide = span(chip, style: style) + (i > 0 ? gap : 0)
            let after = i == chips.count - 1 ? 0 : gap + more
            if used + wide + after > width { return i }
            used += wide
        }
        return chips.count
    }

    static func run(_ chips: ArraySlice<Chip>, more: Bool, style: BookmarkStyle = .names) -> CGFloat {
        let items = chips.reduce(0) { $0 + span($1, style: style) } + CGFloat(max(0, chips.count - 1)) * gap
        return items + (more ? (chips.isEmpty ? 0 : gap) + Self.more : 0)
    }

    /// Keep the site's tail out of the title's ink, using the clipboard's
    /// existing site-name rules and the live pull request's short title.
    static func titleParts(_ node: Bookmark) -> (title: String, tail: String?) {
        let raw = label(node)
        let live = LiveGitHub.shortTitle(raw)
        let short = MarkdownLink.title(live, host: node.host ?? "")
        guard short != live, let range = live.range(of: short) else { return (short, nil) }
        let tail = live[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters).union(.symbols))
        return (short, tail.isEmpty ? nil : tail)
    }

    static func path(_ node: Bookmark) -> String {
        guard let url = node.url.flatMap(URL.init(string:)) else { return "" }
        return url.path.isEmpty ? "/" : url.path
    }

    /// The folder the column draws, also for menu images.
    struct FolderMark: View {
        var size: CGFloat = BookmarkBar.icon
        var tint: Color = Palette.ink

        var body: some View {
            StillFace(pose: .seen, size: size, tint: tint, folder: true)
                .frame(width: size, height: size)
        }
    }

    @MainActor private static var menuMarks: [String: NSImage] = [:]

    @MainActor
    static func image(_ node: Bookmark, scheme: ColorScheme) -> NSImage? {
        if let icon = node.savedIcon { return MenuMark.picture(icon) }
        let letter = String(label(node).prefix(1)).uppercased()
        let key = (node.isFolder ? "folder" : "letter:" + letter) + (scheme == .dark ? ":dark" : ":light")
        if let image = menuMarks[key] { return image }
        let renderer = ImageRenderer(content: Group {
            if node.isFolder {
                FolderMark(size: MenuMetrics.mark).foregroundStyle(Palette.ink)
            } else {
                Mark(icon: nil, letter: letter, size: MenuMetrics.mark)
            }
        }.frame(width: MenuMetrics.mark, height: MenuMetrics.mark).environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = renderer.nsImage
        if let image { menuMarks[key] = image }
        return image
    }

    /// Our searchable menu under a chip, in the window that owns the row;
    /// answers where the chip is on the screen.
    @MainActor @discardableResult
    static func pop(_ nodes: [Bookmark], under frame: CGRect, browser: Browser, title: String = "Bookmarks", stack: Bool = false, done: (() -> Void)? = nil) -> NSRect? {
        guard let window = BrowserWindows.shared.window(for: browser) ?? Links.window,
              let content = window.contentView else { return nil }
        browser.glance.drop()
        let menu = panelMenu(nodes, browser: browser, title: title, stack: stack,
                             scheme: window.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light)
        let y = content.isFlipped ? frame.maxY : content.bounds.height - frame.maxY
        let point = window.convertPoint(toScreen: content.convert(NSPoint(x: frame.minX, y: y), to: nil))
        ActionMenu.show(menu, in: window, at: NSPoint(x: point.x, y: point.y - 4), up: false, done: done)
        return NSRect(x: point.x, y: point.y, width: frame.width, height: frame.height)
    }

    /// One thing a bookmark's right-click menu does.
    struct Act {
        let title: String
        var mark: String?
        var enabled = true
        let run: () -> Void
    }

    /// A bookmark's right-click menu, in groups between
    /// lines: the same in the row, in », and in a folder's menu.
    @MainActor
    static func acts(for node: Bookmark, browser: Browser) -> [[Act]] {
        var out: [[Act]] = []
        if node.isFolder {
            let urls = Bookmarks.urls(node.children ?? [])
            out.append([Act(title: "Open All in New Tabs", mark: "yab.tabs.out", enabled: !urls.isEmpty) { browser.openAll(urls) }])
            // A folder with sites in it is asked about, as in Bookmarks.
            let asks = Bookmarks.count(node.children ?? []) > 0
            out.append([
                Act(title: "Rename…", mark: "pencil") { browser.editBookmark(node.id) },
                Act(title: asks ? "Delete…" : "Delete", mark: "trash") { browser.deleteBookmark(node) },
            ])
        } else if let text = node.url, let url = URL(string: text) {
            out.append([
                Act(title: "Open in New Tab", mark: "yab.tab.plus") { _ = browser.open(url, foreground: true, from: browser.active) },
                Act(title: "Copy Link", mark: "yab.copyframe.link") { browser.put(text) },
            ])
            out.append([
                Act(title: "Edit…", mark: "pencil") { browser.editBookmark(node.id) },
                Act(title: "Delete", mark: "trash") { browser.deleteBookmark(node) },
            ])
        }
        out.append([Act(title: "Show Bookmarks", mark: "bookmark") { browser.showBookmarks() }])
        return out
    }

    /// A press that asks for a menu: the right button, or the left with ⌃.
    static func asksForMenu(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp: return true
        case .leftMouseDown, .leftMouseUp: return event.modifierFlags.contains(.control)
        default: return false
        }
    }

    /// That menu, as the tab's (ActionMenu.swift), at `at` on the screen (the pointer, unless
    /// said): for a bookmark in the row (`Presses`), and for a line of »'s
    /// or a folder's menu once that menu has gone (`Line`).
    @MainActor
    static func context(_ node: Bookmark, browser: Browser, at: NSPoint = NSEvent.mouseLocation) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for (index, group) in acts(for: node, browser: browser).enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            for act in group {
                let line = Line(act.title, act: act.run)
                MenuMark.put(act.mark, on: line)
                line.isEnabled = act.enabled
                menu.addItem(line)
            }
        }
        guard let window = BrowserWindows.shared.window(for: browser) ?? Links.window else {
            menu.popUp(positioning: nil, at: at, in: nil)
            return
        }
        ActionMenu.show(menu, in: window, at: at)
    }

    @MainActor
    static func panelMenu(_ nodes: [Bookmark], browser: Browser, title: String, stack: Bool = false, scheme: ColorScheme, fetchMissing: Bool = true) -> NSMenu {
        let menu = PanelMenu(title: title)
        menu.autoenablesItems = false
        if nodes.isEmpty {
            let empty = NSMenuItem(title: "Empty", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
        for node in nodes {
            let parts = titleParts(node)
            let line = Line(node.isFolder ? label(node) : parts.title, node: node, browser: browser) {
                if let url = node.url.flatMap(URL.init(string:)) { browser.visit(url) }
            }
            line.menuDetail = node.isFolder ? String(Bookmarks.count(node.children ?? [])) : stack ? path(node) : parts.tail
            line.image = image(node, scheme: scheme)
            if node.isFolder {
                line.submenu = panelMenu(node.children ?? [], browser: browser, title: label(node), scheme: scheme, fetchMissing: fetchMissing)
            } else if fetchMissing {
                node.fetchIcon()
            }
            menu.addItem(line)
        }
        let urls = Bookmarks.urls(nodes)
        menu.addItem(.separator())
        let all = Line("Open All in New Tabs") { browser.openAll(urls) }
        all.menuDetail = String(urls.count)
        all.isEnabled = !urls.isEmpty
        MenuMark.put("yab.tabs.out", on: all)
        menu.addItem(all)
        return menu
    }

    private final class PanelMenu: NSMenu, ActionMenuContent {
        var menuPlaceholder: String { "Search " + title + "…" }
        var menuChanges: AnyPublisher<Void, Never> { Favicons.shared.changes.map { _ in () }.eraseToAnyPublisher() }
    }

    /// A menu line that runs a closure; a bookmark's opens its own
    /// right-click menu instead on a right-click or a ⌃-click.
    @MainActor
    fileprivate final class Line: NSMenuItem, ActionMenuItemContent {
        var menuDetail: String?
        override var image: NSImage? {
            get { node?.savedIcon.map(MenuMark.picture) ?? super.image }
            set { super.image = newValue }
        }
        var menuContext: ((NSPoint) -> Void)? {
            guard let node, let browser else { return nil }
            return { BookmarkBar.context(node, browser: browser, at: $0) }
        }
        private let act: () -> Void
        let node: Bookmark?
        weak var browser: Browser?

        init(_ title: String, node: Bookmark? = nil, browser: Browser? = nil, act: @escaping () -> Void = {}) {
            self.act = act
            self.node = node
            self.browser = browser
            super.init(title: title, action: node?.isFolder == true ? nil : #selector(run), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError() }

        @objc private func run() {
            // A menu takes the right button let go on a line as a click on
            // it, and opened the page: that one asks for the line's menu.
            // (A watcher hears no press while a menu is being tracked.)
            if let node, let browser, BookmarkBar.asksForMenu(NSApp.currentEvent) {
                BookmarkBar.context(node, browser: browser)
                return
            }
            act()
        }
    }
}

extension Browser {
    /// A bookmark or a folder taken out from its right-click menu, ⌘Z
    /// putting it back; a folder with sites in it is asked about first, as
    /// in Bookmarks.
    func deleteBookmark(_ node: Bookmark) {
        let inside = node.isFolder ? Bookmarks.count(node.children ?? []) : 0
        guard inside > 0 else {
            did(bookmarks.removeUndoably(node.id))
            return
        }
        Task { @MainActor in
            let yes = await Questions.shared.ask(Question(
                title: "Remove \(node.title) and \(inside == 1 ? "its bookmark" : "its \(inside.formatted()) bookmarks")?",
                detail: "Everything in the folder goes with it.",
                glyph: "trash", yes: "Remove", danger: true
            ))
            if yes { did(bookmarks.removeUndoably(node.id)) }
        }
    }

    /// Edit… or Rename… on a bookmark: Bookmarks, at its folder, writing
    /// its name and a site's address, as ⌘E there does.
    func editBookmark(_ id: Bookmark.ID) {
        guard bookmarks.node(id) != nil else { return }
        if !(fieldShowing && query.place == .bookmarks) { openPlace(.bookmarks) }
        openFolder(bookmarks.trail(to: id)?.dropLast().last?.id)
        query.spot = placeItems.firstIndex { $0.id == "bookmark." + id.uuidString } ?? 0
        beginEdit(.bookmark(id))
    }
}

/// A folder's menu comes up as the pointer rests on its chip, the next
/// folder's at once in its place, and goes when the pointer has left chip and
/// menu with nothing typed. A click keeps it: that menu is no longer this one's.
@MainActor
enum BookmarkHoverMenu {
    static let wait = 0.12
    static let linger = 0.4
    private static var shown: String?
    private static var chip = NSRect.zero
    private static var coming: DispatchWorkItem?
    private static var watch: Timer?
    private static var awaySince: TimeInterval?

    static func hover(_ key: String, _ on: Bool, open: @escaping (@escaping () -> Void) -> NSRect?) {
        coming?.cancel()
        coming = nil
        guard on, shown != key else { return }
        let work = DispatchWorkItem {
            coming = nil
            guard NSApp.isActive, NSEvent.pressedMouseButtons == 0, shown != nil || !ActionMenu.isOpen else { return }
            let frame = open { if shown == key { stop() } }
            guard let frame else { return }
            shown = key
            chip = frame
            awaySince = nil
            guard watch == nil else { return }
            watch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                MainActor.assumeIsolated { look() }
            }
        }
        coming = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (shown == nil ? wait : 0), execute: work)
    }

    private static func look() {
        let point = NSEvent.mouseLocation
        if ActionMenu.holds(point) || ActionMenu.typed || chip.insetBy(dx: -2, dy: -6).contains(point) {
            awaySince = nil
            return
        }
        let now = Date.timeIntervalSinceReferenceDate
        if now - (awaySince ?? now) >= linger { ActionMenu.close() } else if awaySince == nil { awaySince = now }
    }

    private static func stop() {
        shown = nil
        awaySince = nil
        watch?.invalidate()
        watch = nil
    }
}

/// The buttons a SwiftUI button gets wrong on a bookmark, so one watcher for
/// the app, by where each bookmark in the row is drawn. The middle one it
/// never hears: on the release, and only if it is still over the one it was
/// pressed on, as on a tab. The right one, or ⌃ with the left, it can take
/// as a click and open the bookmark, its `.contextMenu` unshown, as a press
/// queued for the window did (feedback #153): here the bookmark's menu
/// (`BookmarkBar.acts`) opens on the press, as a view's own does, the same
/// one as in » and in a folder's menu.
@MainActor
private final class Presses {
    static let shared = Presses()
    /// Each bookmark in each window's row, by the view that drew it: where
    /// it is, in its window's SwiftUI space, whose window that is, what its
    /// middle click does, and its menu.
    private var drawn: [UUID: (frame: CGRect, browser: () -> Browser?, act: () -> Void, menu: ((NSPoint) -> Void)?)] = [:]
    private var pressed: UUID?
    /// A press that asked for a bookmark's menu, not yet let go.
    private var menuPress = false
    private var monitor: Any?

    func put(by view: UUID, at frame: CGRect, in browser: Browser, act: @escaping () -> Void, menu: ((NSPoint) -> Void)? = nil) {
        drawn[view] = (frame, { [weak browser] in browser }, act, menu)
        watch()
    }

    func gone(by view: UUID) {
        drawn[view] = nil
    }

    private func under(_ event: NSEvent) -> UUID? {
        // By the screen: a press made by hand may come with no window.
        let screen = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        return drawn.first { _, row in
            guard let browser = row.browser(), let window = BrowserWindows.shared.window(for: browser) ?? Links.window,
                  window.isVisible, let content = window.contentView,
                  event.window == nil || event.window === window, window.frame.contains(screen) else { return false }
            let at = content.convert(window.convertPoint(fromScreen: screen), from: nil)
            return row.frame.contains(CGPoint(x: at.x, y: content.isFlipped ? at.y : content.bounds.height - at.y))
        }?.key
    }

    private func watch() {
        guard monitor == nil else { return }
        let kinds: NSEvent.EventTypeMask = [.otherMouseDown, .otherMouseUp, .rightMouseDown, .rightMouseUp, .leftMouseDown, .leftMouseUp]
        monitor = NSEvent.addLocalMonitorForEvents(matching: kinds) { [weak self] event in
            guard let self else { return event }
            if [.rightMouseUp, .leftMouseUp].contains(event.type), self.menuPress {
                // The let-go of the press that asked for the menu is the
                // menu's, never the button's.
                self.menuPress = false
                return nil
            }
            if [.rightMouseDown, .leftMouseDown].contains(event.type), BookmarkBar.asksForMenu(event) {
                guard let id = self.under(event), let menu = self.drawn[id]?.menu else { return event }
                self.menuPress = true
                // Its name's tip, on its way under the pointer, stays away.
                KeyTip.shared.hush()
                let at = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
                // After the press is handled: the menu's own loop is not run
                // inside a watcher. A let-go from then on is the menu's.
                DispatchQueue.main.async {
                    self.menuPress = false
                    menu(at)
                }
                return nil
            }
            guard [.otherMouseDown, .otherMouseUp].contains(event.type), event.buttonNumber == 2, let id = self.under(event) else { return event }
            if event.type == .otherMouseDown {
                self.pressed = id
                return nil
            }
            defer { self.pressed = nil }
            guard self.pressed == id else { return event }
            self.drawn[id]?.act()
            return nil
        }
    }
}

/// A page kept into an empty row, on its way out of the place offered for
/// it: that place's width and dashed edge at the start, its own width and
/// none at the end, its name coming up as the edge goes.
private struct Grow: ViewModifier, Animatable {
    var done: CGFloat
    let from: CGFloat
    let to: CGFloat

    var animatableData: CGFloat {
        get { done }
        set { done = newValue }
    }

    func body(content: Content) -> some View {
        content
            .opacity(Double(done))
            .frame(width: from + (to - from) * done, alignment: .leading)
            .clipped()
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(Palette.ink.opacity(0.16 * (1 - done)), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
            }
    }
}

/// One bookmark in the row: a site, into the tab you are on, or with ⌘ or
/// the middle button a new one behind it, ⇧⌘ in front; or a folder, its
/// menu under it, or everything in it opened at once with ⌘ or the middle
/// button. Its name beside its icon, or its icon alone on a square, the
/// name then in its hover card.
private struct ShelfItem: View {
    let browser: Browser
    let bookmarks: Bookmarks
    let chip: BookmarkBar.Chip
    var node: Bookmark { chip.node }
    let named: Bool

    @Environment(\.tone) private var tone
    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @State private var icon: NSImage?
    /// This view, to `Presses`.
    @State private var drawer = UUID()
    /// The icon's size, small for one just kept and sprung up to its own,
    /// where the + of the place it came out of was.
    @State private var pop: CGFloat

    init(browser: Browser, bookmarks: Bookmarks, chip: BookmarkBar.Chip, named: Bool = true, fresh: Bool = false) {
        self.browser = browser
        self.bookmarks = bookmarks
        self.chip = chip
        self.named = named
        _pop = State(initialValue: fresh ? 0.3 : 1)
    }

    var body: some View {
        Button { tap() } label: {
            HStack(spacing: BookmarkBar.iconGap) {
                if node.isFolder {
                    BookmarkBar.FolderMark(tint: Palette.ink.opacity(0.8))
                } else {
                    ZStack(alignment: .leading) {
                        if chip.stacked { mark.offset(x: BookmarkBar.stackPeek).opacity(0.45) }
                        mark
                    }
                    .frame(width: BookmarkBar.icon + (chip.stacked ? BookmarkBar.stackPeek : 0), height: BookmarkBar.icon)
                    .scaleEffect(pop)
                    .opacity(Double(min(1, pop * 1.4)))
                }
                if named && !chip.stacked {
                    Text(BookmarkBar.label(node))
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .frame(width: BookmarkBar.words(node), alignment: .leading)
                }
                if chip.stacked || named && node.isFolder {
                    Text(String(chip.stacked ? chip.nodes.count : Bookmarks.count(chip.contents)))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted(on: tone))
                }
            }
            .padding(.horizontal, named || chip.stacked ? BookmarkBar.pad : 0)
            .frame(width: named || chip.stacked ? nil : BookmarkBar.row, height: BookmarkBar.row)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(hovering ? Palette.hover(on: tone) : .clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(chip.stacked ? "\(chip.title), \(chip.nodes.count) bookmarks" : BookmarkBar.label(node))
        .benchSpot("bookmark " + BookmarkBar.label(node))
        .onHover { on in
            hovering = on
            guard node.isFolder else {
                browser.glance.hoverBookmark(glanceKey, on)
                return
            }
            BookmarkHoverMenu.hover(glanceKey, on) { done in
                BookmarkBar.pop(chip.contents, under: frame, browser: browser, title: chip.title, done: done)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            frame = $0
            put()
        }
        // Renamed or filled where it stands, the same place does the new.
        .onChange(of: chip) {
            icon = node.savedIcon
            put()
        }
        .onReceive(Favicons.shared.changes) { host in
            if host == node.iconSite { icon = node.savedIcon }
        }
        .onDisappear {
            Presses.shared.gone(by: drawer)
            browser.glance.removeBookmark(glanceKey)
        }
        // For VoiceOver's Show Menu: a right-click or ⌃-click never gets
        // here, `Presses` opens the same menu first.
        .contextMenu { menu }
        .onAppear {
            if pop < 1 {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.6)) { pop = 1 }
            }
            // A bookmark whose site has never been open here: its icon,
            // fetched once, quietly.
            node.fetchIcon()
        }
    }

    private var glanceKey: String { "bookmark:" + drawer.uuidString }

    private var mark: some View {
        Mark(icon: icon ?? node.savedIcon,
             letter: String(BookmarkBar.label(node).prefix(1)).uppercased(), size: BookmarkBar.icon)
    }

    /// Where it is drawn, to `Presses` and the shared hover card.
    private func put() {
        browser.glance.putBookmark(glanceKey, chip: chip, frame: frame)
        Presses.shared.put(by: drawer, at: frame, in: browser) { [self] in tap(middle: true) } menu: { [self] at in
            BookmarkBar.context(node, browser: browser, at: at)
        }
    }

    /// A click; or the middle button's (`Presses`), which opens what a ⌘-click
    /// does.
    private func tap(middle: Bool = false) {
        browser.glance.drop()
        let apart = middle || Browser.beside(NSApp.currentEvent) != nil
        if node.isFolder || chip.stacked {
            // A folder ⌘-clicked opens everything in it.
            if apart {
                browser.openAll(Bookmarks.urls(chip.contents))
            } else {
                BookmarkBar.pop(chip.contents, under: frame, browser: browser, title: chip.title, stack: chip.stacked)
            }
        } else if let text = node.url, let url = URL(string: text) {
            browser.visit(url, middle: middle)
        }
    }

    @ViewBuilder
    private var menu: some View {
        let groups = BookmarkBar.acts(for: node, browser: browser)
        ForEach(groups.indices, id: \.self) { index in
            if index > 0 { Divider() }
            ForEach(groups[index].indices, id: \.self) { at in
                let act = groups[index][at]
                Button(act.title, mark: act.mark, action: act.run)
                    .disabled(!act.enabled)
            }
        }
    }
}

/// », and our menu of whatever did not fit.
private struct More: View {
    let browser: Browser
    let nodes: [Bookmark]

    @Environment(\.tone) private var tone
    @State private var hovering = false
    @State private var frame: CGRect = .zero
    @State private var drawer = UUID()
    private var glanceKey: String { "bookmark:" + drawer.uuidString }

    var body: some View {
        Button { tap() } label: {
            Symbol("chevron.right.2", size: 10)
                .foregroundStyle(hovering ? Palette.ink : Palette.muted(on: tone))
                .frame(width: BookmarkBar.more, height: BookmarkBar.row)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(hovering ? Palette.hover(on: tone) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel("More Bookmarks")
        .benchSpot("bookmark more")
        .onHover { on in
            hovering = on
            BookmarkHoverMenu.hover(glanceKey, on) { done in
                BookmarkBar.pop(nodes, under: frame, browser: browser, done: done)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
            frame = $0
            put()
        }
        .onChange(of: nodes) { put() }
        .onDisappear {
            browser.glance.removeBookmark(glanceKey)
            Presses.shared.gone(by: drawer)
        }
    }

    private func tap(middle: Bool = false) {
        browser.glance.drop()
        if middle || Browser.beside(NSApp.currentEvent) != nil { browser.openAll(Bookmarks.urls(nodes)) }
        else { BookmarkBar.pop(nodes, under: frame, browser: browser) }
    }

    private func put() {
        let folder = Bookmark(id: drawer, title: "More Bookmarks", url: nil, children: nodes)
        browser.glance.putBookmark(glanceKey, chip: BookmarkBar.Chip(nodes: [folder]), frame: frame)
        Presses.shared.put(by: drawer, at: frame, in: browser, act: { tap(middle: true) })
    }
}

/// An empty row: the two ways to fill it. The page you are on, a click
/// away; and the bookmarks you already have, in the browser you came
/// from, when one on this Mac keeps any.
private struct ShelfEmpty: View {
    @ObservedObject var browser: Browser
    /// How wide the place for a page is, told to the row.
    let measured: (CGFloat) -> Void
    @ObservedObject private var elsewhere = Elsewhere.shared

    @Environment(\.tone) private var tone

    var body: some View {
        HStack(spacing: BookmarkBar.gap + 4) {
            if let url = browser.active?.address, Bookmark.keepable(url) {
                Offer(dashed: true, action: { browser.bookmarkCurrent() }) {
                    Symbol("plus", size: 10)
                        .foregroundStyle(Palette.muted(on: tone))
                        .frame(width: BookmarkBar.icon, height: BookmarkBar.icon)
                    Text("Add this page")
                        .foregroundStyle(Palette.ink)
                    Text(Keymap.shared.text(.bookmark))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.muted(on: tone))
                }
                .keyTip("Keep this page up here")
                // The page kept grows out of here (see `BookmarkBar.arrival`).
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measured($0) }
            }
            if let found = elsewhere.found {
                Offer(dashed: false, action: bring) {
                    if let icon = found.source.icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: BookmarkBar.icon + 2, height: BookmarkBar.icon + 2)
                    }
                    Text(elsewhere.bringing ? "Bringing them over…" : "Bring from \(found.source.name)")
                        .foregroundStyle(Palette.ink)
                }
                .disabled(elsewhere.bringing)
                .keyTip("Your \(found.source.name) bookmarks, bar and folders, here")
            }
        }
        .font(.system(size: 12))
        .onAppear { elsewhere.look() }
    }

    private func bring() {
        guard let found = elsewhere.found else { return }
        elsewhere.bringing = true
        browser.takeBookmarks(from: found.source.authorizingImport()) { _ in
            elsewhere.bringing = false
            elsewhere.found = nil
        }
    }
}

/// One offer in an empty row: a bookmark's size, drawn as a place to put
/// one, dashed, or as a button.
private struct Offer<Label: View>: View {
    let dashed: Bool
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    @Environment(\.tone) private var tone
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: BookmarkBar.iconGap) { label() }
                .lineLimit(1)
                // Its own width whatever frame it is given: growing into a
                // bookmark, it is cut at the edge rather than ending in "…".
                .fixedSize()
                .padding(.horizontal, BookmarkBar.pad)
                .frame(height: BookmarkBar.row, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .background {
                    let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    if dashed {
                        shape.fill(hovering ? Palette.hover(on: tone) : .clear)
                        shape.strokeBorder(Palette.ink.opacity(hovering ? 0.28 : 0.16), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                    } else {
                        shape.fill(hovering ? Palette.hover(on: tone) : Palette.ink.opacity(0.05))
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .opacity(enabled ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
    }
}

/// The browser on this Mac whose bookmarks someone starting here most
/// likely means: of those that keep any, the one open right now, then the
/// default, then the one whose bookmarks changed last. Looked for once, off
/// the main thread, the first time an empty row is shown.
@MainActor
final class Elsewhere: ObservableObject {
    static let shared = Elsewhere()

    struct Found {
        let source: Chromium.Source
        let count: Int
    }

    @Published var found: Found?
    @Published var bringing = false
    private var looked = false

    func look() {
        guard !looked else { return }
        looked = true
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        DispatchQueue.global(qos: .utility).async {
            let sources = Chromium.installed()
            let source = sources.first { running.contains($0.bundle) } ?? sources.first
            let found = source.map { Found(source: $0, count: 0) }
            DispatchQueue.main.async { self.found = found }
        }
    }
}
