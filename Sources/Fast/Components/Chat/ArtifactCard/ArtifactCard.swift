import AppKit
import SwiftUI

// The card a turn shows for a page its agent published with Claude Code's
// Artifact tool (docs/artifact-cards.md; the concept's variant A with B's
// live update, docs/artifact-cards/concept.html): a still of the page, its
// title, "Version 2" once published again, and Split View. A click looks
// at it in Peek over the page you are on, ⌥-click or the button puts it
// beside that page, ⌘-click opens it as a tab, as every link in Yab. The
// page is Yab's own copy (ArtifactPages): no claude.ai, no sign-in.
//
// What Yab can't draw itself, a claude.ai canvas or a JSX file, gets the
// same card with the artifact's icon in place of the still, and opens on
// claude.ai with the space's sign-in. So does a page whose copy and file
// are both gone. Right-click: the three ways to open, Copy Link (the
// claude.ai address), Share… (the file itself), Show in Finder.

struct ArtifactCard: View {
    let browser: Browser
    let chat: String
    let ref: ArtifactRef
    @State private var image: NSImage?

    /// The thumbnail's height, the page's top at the card's width.
    static let still: CGFloat = 150
    /// Claude's own color, the artifact's tile.
    static let claude = Color(red: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255)

    var body: some View {
        let pages = ArtifactPages.shared
        let kept = pages.state(ref, chat: chat)
        let page = ref.local && (kept != nil || ArtifactCard.there(ref.path))
        let shot = page ? pages.still(ref, chat: chat) : nil
        VStack(alignment: .leading, spacing: 10) {
            if page { thumb }
            row(page: page, fresh: page && pages.fresh(ref, chat: chat))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .restingCardFrame()
        .contentShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .onTapGesture { ArtifactOpen.open(ref, chat: chat, how: ArtifactOpen.How(ArtifactOpen.flags), in: browser) }
        .overlay { ArtifactMenuArea(ref: ref, chat: chat, browser: browser) }
        .background { if Bench.spotting { ArtifactCardAnchorView(ref: ref, chat: chat, page: page, still: shot?.file) } }
        .padding(.top, 4) // design: 12 under the answer's tail, as the concept stands the card
        .task(id: "\(ref.key).\(ref.seq)") { pages.take(ref, chat: chat) }
        .task(id: shot.map { "\($0.file.path).\(pages.changes)" } ?? "") { image = await ArtifactCard.load(shot?.file) }
    }

    /// The page's top, as Yab drew it off screen: as wide as the card,
    /// cut at the still's height.
    private var thumb: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Palette.ink.opacity(image == nil ? 0.05 : 0)
            .frame(height: Self.still)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .top) {
                if let image { Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill) }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.hairline, lineWidth: 1)) // design: the still's ring, the concept's thumb, not a card
    }

    private func row(page: Bool, fresh: Bool) -> some View {
        HStack(spacing: 10) {
            tile(big: !page)
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(page ? (ref.seq > 1 ? "Version \(ref.seq)" : "Page") : "Opens on claude.ai")
                    .font(.system(size: 12))
                    .foregroundStyle(fresh ? Palette.ink : Palette.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if page {
                Button { ArtifactOpen.open(ref, chat: chat, how: .beside, in: browser) } label: {
                    HStack(spacing: 6) {
                        Symbol("rectangle.split.2x1", size: 9)
                        Text("Split View")
                    }
                }
                .buttonStyle(.yab(.quiet, .small))
                .focusable(false)
                .keyTip("Open in Split View", keys: "\u{2325}", side: .above)
            }
        }
    }

    /// The card's tile as a tab's mark (Tab.ownIcon): the artifact's icon,
    /// white, on Claude's color, as the concept's tab rows wear it.
    @MainActor static func tile(_ word: String?, side: CGFloat = 16) -> NSImage {
        let named = glyph(word)
        let name = Glyphs.art(named) != nil ? named : "doc.text"
        let mark = Glyphs.image(name, size: (side * 0.8 / Glyphs.scale).rounded(), color: .white)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor(srgbRed: 0xD9 / 255, green: 0x77 / 255, blue: 0x57 / 255, alpha: 1).setFill()
            NSBezierPath(roundedRect: rect, xRadius: side / 4, yRadius: side / 4).fill()
            if let mark {
                let at = NSRect(x: (side - mark.size.width) / 2, y: (side - mark.size.height) / 2, width: mark.size.width, height: mark.size.height)
                mark.draw(in: at)
            }
            return true
        }
        return image
    }

    /// Where each artifact's one card stands in a chat, by turn: in the
    /// turn that published its newest version, as the concept draws
    /// Version 2, the earlier turns' cards folding into it. Until the new
    /// version's still is taken the card stays the one before, in its turn,
    /// so no card ever shows another version's picture.
    @MainActor static func placement(_ turns: [[ChatItem]]) -> [Int: [ArtifactRef]] {
        let pages = ArtifactPages.shared
        var published: [String: [(turn: Int, ref: ArtifactRef)]] = [:]
        var order: [String] = []
        for (index, turn) in turns.enumerated() {
            for ref in ArtifactRef.cards(in: turn) {
                if published[ref.key] == nil { order.append(ref.key) }
                published[ref.key, default: []].append((index, ref))
            }
        }
        var out: [Int: [ArtifactRef]] = [:]
        for key in order {
            guard let all = published[key], let newest = all.last else { continue }
            let shown = all.last(where: { pages.ready($0.ref) }) ?? newest
            out[shown.turn, default: []].append(shown.ref)
        }
        return out
    }

    /// The artifact's icon on Claude's color: small beside a still, the
    /// card's well where it stands alone.
    private func tile(big: Bool) -> some View {
        let side: CGFloat = big ? CardFrame.well : 28
        return Symbol(Self.glyph(ref.icon), size: big ? 13.5 : 11)
            .foregroundStyle(Color.white)
            .frame(width: side, height: side)
            .background(Self.claude, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }

    /// The Artifact tool's icon word as one of Yab's glyphs; a page's for
    /// a word with none.
    static func glyph(_ word: String?) -> String {
        let named: [String: String] = [
            "chart": "chart.bar", "graph": "chart.xyaxis.line", "dashboard": "gauge.with.dots.needle.33percent",
            "code": "chevron.left.forwardslash.chevron.right", "map": "mappin", "chat": "bubble", "books": "book",
            "document": "doc.text", "doc": "doc.text", "page": "doc.text", "gallery": "photo", "image": "photo",
            "list": "list.bullet", "table": "application.table", "plan": "checklist", "mail": "envelope",
            "design": "paintpalette", "palette": "paintpalette", "film": "video", "phone": "iphone",
            "search": "magnifyingglass", "settings": "gearshape", "money": "creditcard", "people": "person.2",
            "check": "checkmark", "canvas": "square.grid.2x2", "game": "gamecontroller", "music": "music.note",
        ]
        let word = (word ?? "").lowercased()
        if let found = named[word] { return found }
        if !word.isEmpty, Glyphs.art(word) != nil || NSImage(systemSymbolName: word, accessibilityDescription: nil) != nil { return word }
        return "doc.text"
    }

    /// Whether the tool's file is still where it wrote it, asked once a
    /// path, again when a card is opened.
    @MainActor private static var seen: [String: Bool] = [:]
    @MainActor static func there(_ path: String?) -> Bool {
        guard let path else { return false }
        if let known = seen[path] { return known }
        let found = FileManager.default.fileExists(atPath: path)
        seen[path] = found
        return found
    }

    @MainActor static func forget(_ path: String?) { if let path { seen[path] = nil } }

    /// A still read off the main thread, once a file.
    private static let kept = NSCache<NSString, NSImage>()

    static func load(_ file: URL?) async -> NSImage? {
        guard let file else { return nil }
        let stamp = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let name = "\(file.path).\(stamp)" as NSString
        if let hit = kept.object(forKey: name) { return hit }
        let made: NSImage? = await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                  let picture = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return NSImage(cgImage: picture, size: NSSize(width: picture.width / 2, height: picture.height / 2))
        }.value
        if let made { kept.setObject(made, forKey: name) }
        return made
    }
}

/// What opening a card does, by the keys held, as a link's click does.
@MainActor
enum ArtifactOpen {
    enum How {
        /// Over the page in front, in Peek.
        case peek
        /// Beside it, in Split View.
        case beside
        /// A tab of its own.
        case tab

        init(_ flags: NSEvent.ModifierFlags) {
            if flags.contains(.command) { self = .tab } else if flags.contains(.option) { self = .beside } else { self = .peek }
        }
    }

    /// The keys held as the card was pressed (ArtifactMenuView hears the
    /// press go by), else with the click being handled, else the keyboard's.
    static var flags: NSEvent.ModifierFlags {
        if let held, Date().timeIntervalSince(held.at) < 2 { return held.flags }
        if let event = NSApp.currentEvent, event.type == .leftMouseUp || event.type == .leftMouseDown { return event.modifierFlags }
        return NSEvent.modifierFlags
    }
    static var held: (flags: NSEvent.ModifierFlags, at: Date)?
    /// The card's menu while it is up, and what Share… last handed the
    /// share picker, for the bench (agent-artifact-cards).
    static var shown: NSMenu?
    static var shared: Any?

    /// Yab's copy of the page; a copy made first if the file is still
    /// there; else its claude.ai address.
    static func open(_ ref: ArtifactRef, chat: String, how: How, in browser: Browser) {
        let pages = ArtifactPages.shared
        let shift = flags.contains(.shift)
        if let url = pages.address(ref, chat: chat) {
            pages.opened(ref)
            return go(url, how, shift: shift, in: browser)
        }
        ArtifactCard.forget(ref.path)
        if ref.local, ArtifactCard.there(ref.path) {
            pages.take(ref, chat: chat) {
                if let url = pages.address(ref, chat: chat) {
                    pages.opened(ref)
                    go(url, how, shift: shift, in: browser)
                } else if let remote = URL(string: ref.url) {
                    go(remote, how, shift: shift, in: browser)
                }
            }
            return
        }
        if let remote = URL(string: ref.url) { go(remote, how, shift: shift, in: browser) }
    }

    private static func go(_ url: URL, _ how: How, shift: Bool, in browser: Browser) {
        guard let source = browser.active else {
            _ = browser.open(url, foreground: true)
            return
        }
        switch how {
        case .peek:
            if browser.peeking != nil { browser.hidePeek() }
            browser.peek(url, from: source)
        case .beside:
            if browser.peeking != nil { browser.closePeek() }
            browser.splitLink(url, from: source)
        case .tab:
            _ = browser.open(url, foreground: shift, from: source)
        }
    }

    /// The card's right-click menu, as the concept draws it.
    static func menu(_ ref: ArtifactRef, chat: String, in browser: Browser, from view: NSView, at point: NSPoint) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        // The click a way to open answers to, in gray at the row's end, as the
        // concept writes it: words, as a menu writes keys, not key plates.
        func item(_ title: String, mark: String? = nil, badge: String? = nil, act: @escaping () -> Void) {
            let made = PageMenuItem(title, act: act)
            MenuMark.put(mark, on: made)
            if let badge {
                let font = NSFont.menuFont(ofSize: 0)
                let style = NSMutableParagraphStyle()
                style.tabStops = [NSTextTab(textAlignment: .right, location: 200)]
                let words = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: style])
                words.append(NSAttributedString(string: "\t" + badge, attributes: [.font: font, .paragraphStyle: style,
                                                                                    .foregroundColor: NSColor.secondaryLabelColor]))
                made.attributedTitle = words
                made.representedObject = badge
            }
            menu.addItem(made)
        }
        item("Open in Peek", mark: "yab.window") { open(ref, chat: chat, how: .peek, in: browser) }
        item("Open in Split View", badge: "\u{2325} Click") { open(ref, chat: chat, how: .beside, in: browser) }
        item("Open as Tab", badge: "\u{2318} Click") { open(ref, chat: chat, how: .tab, in: browser) }
        menu.addItem(.separator())
        item("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ref.url, forType: .string)
            browser.announce("Link copied", mark: "link")
        }
        let file = ArtifactPages.shared.file(ref, chat: chat).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        item("Share\u{2026}", mark: "yab.share") { [weak view] in
            guard let view else { return }
            let shared: Any = file ?? URL(string: ref.url) ?? ref.url
            ArtifactOpen.shared = shared
            NSSharingServicePicker(items: [shared]).show(relativeTo: NSRect(origin: point, size: .zero), of: view, preferredEdge: .minY)
        }
        if let file { item("Show in Finder", mark: "yab.folder.search") { NSWorkspace.shared.activateFileViewerSelecting([file]) } }
        return menu
    }
}

/// The card's right-click, in AppKit for its menu's badges ("⌥ Click"):
/// a view over the card that takes only a right-click or a control-click,
/// every other press going through to the card.
private struct ArtifactMenuArea: NSViewRepresentable {
    let ref: ArtifactRef
    let chat: String
    let browser: Browser

    func makeNSView(context: Context) -> ArtifactMenuView { ArtifactMenuView() }

    func updateNSView(_ view: ArtifactMenuView, context: Context) {
        let ref = ref, chat = chat, browser = browser
        view.made = { view, point in ArtifactOpen.menu(ref, chat: chat, in: browser, from: view, at: point) }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArtifactMenuView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class ArtifactMenuView: NSView {
    var made: ((NSView, NSPoint) -> NSMenu)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent else { return nil }
        // A press on the card goes through to it; the keys held with it are
        // what it opens by, whenever the card's tap comes to be handled.
        if event.type == .leftMouseDown, !event.modifierFlags.contains(.control), frame.contains(point) {
            MainActor.assumeIsolated { ArtifactOpen.held = (event.modifierFlags, Date()) }
        }
        let menu = event.type == .rightMouseDown || event.type == .rightMouseUp
            || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        return menu ? super.hitTest(point) : nil
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        made?(self, convert(event.locationInWindow, from: nil))
    }

    /// A right-click on a card in a window behind is still its menu.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menu(for: event) else { return super.rightMouseDown(with: event) }
        pop(menu, event)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control), let menu = menu(for: event) else { return super.mouseDown(with: event) }
        pop(menu, event)
    }

    private func pop(_ menu: NSMenu, _ event: NSEvent) {
        MainActor.assumeIsolated { ArtifactOpen.shown = menu }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
        MainActor.assumeIsolated { if ArtifactOpen.shown === menu { ArtifactOpen.shown = nil } }
    }
}

// MARK: - the bench's look at the cards

/// Where each card is in its window, for the bench (agent-artifact-cards):
/// a view behind the card that takes no press.
private struct ArtifactCardAnchorView: NSViewRepresentable {
    let ref: ArtifactRef
    let chat: String
    let page: Bool
    let still: URL?

    func makeNSView(context: Context) -> ArtifactCardAnchor { ArtifactCardAnchor() }

    func updateNSView(_ view: ArtifactCardAnchor, context: Context) {
        view.ref = ref
        view.chat = chat
        view.page = page
        view.still = still
        ArtifactCardAnchor.all.add(view)
    }
}

final class ArtifactCardAnchor: NSView {
    @MainActor static let all = NSHashTable<ArtifactCardAnchor>.weakObjects()
    var ref: ArtifactRef?
    var chat = ""
    var page = false
    var still: URL?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated { if window != nil { Self.all.add(self) } }
    }
}

extension Bench {
    static let artifactVerbs: [String: AgentHandler] = [
        "agent-artifact-cards": { $0.handleArtifactCards($1) },
    ]

    /// The artifact cards on screen and the page they opened, for
    /// evals/artifact-card: each card's title, version, frame (window
    /// points from the top left), still and copy; the Peek's address,
    /// words and scroll; how many cookies the pages' store holds.
    /// "act": "close-tabs" closes every tab on an artifact's page,
    /// "peek-scroll" scrolls the Peek's page to "y". A test run's only.
    /// A mark's color a point in from its left edge, half way down, as hex.
    static func edge(_ image: NSImage) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let rep = Optional(NSBitmapImageRep(cgImage: cg)),
              let color = rep.colorAt(x: max(1, rep.pixelsWide / 16), y: rep.pixelsHigh / 2)?.usingColorSpace(.sRGB) else { return "" }
        return String(format: "%02X%02X%02X", Int((color.redComponent * 255).rounded()), Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }

    func handleArtifactCards(_ c: AgentCall) {
        let browser = c.browser
        let answer = c.answer
        guard Store.testing else { answer(["error": "agent-artifact-cards only works on a --test run"]); return }
        switch c.request["act"] as? String {
        case "close-tabs":
            for tab in browser.tabs where ArtifactPages.isPage(tab.address) { browser.close(tab) }
        case "peek-scroll":
            let y = c.request["y"] as? Double ?? 0
            browser.peeking?.webKitOnly("WebKit artifact scroll runtime", build: false)?.evaluateJavaScript("window.scrollTo(0, \(y))")
        case "menu":
            // The card's menu while it is up: each item's title and badge.
            break
        case "menu-pick":
            // One of the card's menu items chosen by its title, as a click on it.
            guard let menu = ArtifactOpen.shown, let title = c.request["title"] as? String,
                  let index = menu.items.firstIndex(where: { $0.title.split(separator: "\t").first.map(String.init) == title }) else { answer(["error": "no menu up with that item"]); return }
            menu.cancelTracking()
            DispatchQueue.main.async { menu.performActionForItem(at: index) }
        case "press", "right-press":
            // A click on a card's title line, with "mods" held ("option",
            // "cmd", "shift"), or a right-click there ("right-press"), handed
            // to the window as the mouse's, the window made key first, as a
            // hand's first click finds it.
            // "item": the card's step; "title": the newest card of that title.
            let item = c.request["item"] as? String, title = c.request["title"] as? String
            let shown = ArtifactCardAnchor.all.allObjects.filter { $0.window === Links.window && $0.window != nil }
                .sorted { $0.convert($0.bounds, to: nil).minY > $1.convert($1.bounds, to: nil).minY }
            guard let window = Links.window,
                  let anchor = shown.last(where: { (item != nil && $0.ref?.item == item) || (item == nil && title != nil && $0.ref?.title == title) })
            else { answer(["error": "no such card on screen"]); return }
            // Into view first, clear of the column's head and its field, as
            // a hand scrolls to it.
            anchor.scrollToVisible(anchor.bounds.insetBy(dx: 0, dy: -150))
            let flags = Bench.flags(c.request["mods"])
            let right = c.request["act"] as? String == "right-press"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if right {
                    // Into the app's queue, as the mouse's own come, so the
                    // press is the app's current event when the menu's view is
                    // asked whether it takes it; its menu tracks from there,
                    // the bench still heard.
                    let rect = anchor.convert(anchor.bounds, to: nil)
                    let at = NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + CardFrame.inset + 18)
                    if !window.isKeyWindow { window.makeKey() }
                    if let event = NSEvent.mouseEvent(with: .rightMouseDown, location: at, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                        NSApp.postEvent(event, atStart: false)
                    }
                    return
                }
                // On its title, by the card's foot.
                let rect = anchor.convert(anchor.bounds, to: nil)
                let at = NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + CardFrame.inset + 18)
                // Straight to the window, made key without the app coming
                // forward: SwiftUI takes no first click in a window that
                // isn't (Bench's drag, "direct"). The keys go as the press's own.
                if !window.isKeyWindow { window.makeKey() }
                ArtifactOpen.held = (flags, Date())
                for (index, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
                    guard let event = NSEvent.mouseEvent(with: type, location: at, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                                         windowNumber: window.windowNumber, context: nil, eventNumber: index, clickCount: 1,
                                                         pressure: type == .leftMouseUp ? 0 : 1) else { continue }
                    window.sendEvent(event)
                }
            }
        default: break
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let pages = ArtifactPages.shared
            let window = Links.window
            let height = window?.contentView?.bounds.height ?? 0
            var cards: [[String: Any]] = []
            for anchor in ArtifactCardAnchor.all.allObjects where anchor.window === window && window != nil {
                guard let ref = anchor.ref else { continue }
                let rect = anchor.convert(anchor.bounds, to: nil)
                let shot = anchor.still
                let stamp = shot.flatMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                cards.append([
                    "item": ref.item, "chat": anchor.chat, "title": ref.title, "seq": ref.seq, "key": ref.key,
                    "kind": anchor.page ? "page" : "remote", "url": ref.url,
                    "frame": [rect.minX, height - rect.maxY, rect.width, rect.height].map { Double($0) },
                    "still": shot?.path ?? "", "stillStamp": stamp.map { $0.timeIntervalSince1970 } ?? 0,
                    "stillMs": pages.stillMs(ref.key, seq: ref.seq) ?? 0,
                    "copy": pages.file(ref, chat: anchor.chat)?.path ?? "",
                ])
            }
            cards.sort { (($0["frame"] as? [Double])?[1] ?? 0) < (($1["frame"] as? [Double])?[1] ?? 0) }
            ArtifactPages.store.httpCookieStore.getAllCookies { cookies in
                MainActor.assumeIsolated {
                    var out: [String: Any] = ["cards": cards, "cookies": cookies.count,
                                              "window": [Double(window?.contentView?.bounds.width ?? 0), Double(height)],
                                              "pasteboard": NSPasteboard.general.string(forType: .string) ?? "",
                                              "shared": ArtifactOpen.shared.map { String(describing: $0) } ?? "",
                                              // Each tab on an artifact's page: its mark's color, at its left edge's middle.
                                              "tabs": browser.tabs.filter { ArtifactPages.isPage($0.address) }.map { tab -> [String: Any] in
                                                  ["id": Bench.short(tab), "icon": tab.icon != nil, "color": tab.icon.map(Self.edge) ?? ""]
                                              }]
                    if let menu = ArtifactOpen.shown {
                        out["menu"] = menu.items.map { item -> [String: Any] in
                            ["title": item.isSeparatorItem ? "-" : String(item.title.split(separator: "\t").first ?? ""), "badge": item.representedObject as? String ?? "", "enabled": item.isEnabled]
                        }
                    }
                    guard let web = browser.peeking?.webKitOnly("WebKit artifact scroll runtime", build: false) else { answer(out); return }
                    out["peek"] = ["url": web.url?.absoluteString ?? ""]
                    web.evaluateJavaScript("JSON.stringify({text: document.body ? document.body.innerText : '', y: window.scrollY})") { result, _ in
                        MainActor.assumeIsolated {
                            if let text = result as? String, let data = text.data(using: .utf8),
                               let said = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                                out["peek"] = ["url": web.url?.absoluteString ?? "", "text": said["text"] ?? "", "scrollY": said["y"] ?? 0]
                            }
                            answer(out)
                        }
                    }
                }
            }
        }
    }
}
