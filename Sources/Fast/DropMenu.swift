import AppKit
import SwiftUI

// A choice in Settings, Raycast's: the answer bare with ⌄ after it, a plate
// under it while the pointer is on it, and on a click a list of its own
// under it, not the system's menu: the answer in use lit, the arrows and ↩
// to pick, Esc to put it away, and a search on top when there are many.

/// One answer: its words, and what it is; a picture beside the words when
/// the answers are told apart by one, a line under them saying what it does.
struct DropOption<Value: Hashable> {
    var title: String
    var value: Value
    var picture: NSImage? = nil
    var note: String? = nil
    var head: String? = nil
}

enum DropFace {
    /// From the plate's edge to the words, in a settings row.
    static let inset: CGFloat = 8
}

/// The list's last line, under a line of its own: not an answer but the way
/// to a page further in, with a chevron as a row that opens one has.
struct DropLink {
    var title: String
    var go: () -> Void
}

struct DropMenu<Value: Hashable>: View {
    let title: String
    var faceTitle: String? = nil
    var cellHeight: CGFloat?
    var fillsField = false
    var showsCheck = false
    let options: [DropOption<Value>]
    @Binding var selection: Value
    /// From the plate's edge to the words: a table cell's, or a row's.
    var inset: CGFloat = DropFace.inset
    /// The chosen picture's size beside its words, when answers have one.
    var small: NSSize? = nil
    /// Where a line goes across the list: before this answer.
    var divideBefore: Value? = nil
    /// The list hangs from the face's right edge, for a face at a row's end.
    var trailing = false
    /// A way out of the list to the page behind the choice.
    var link: DropLink? = nil

    @State private var hovering = false
    @State private var shown = false
    @State private var place = DropAnchor.Place()

    init(_ title: String, options: [DropOption<Value>], selection: Binding<Value>,
         inset: CGFloat = DropFace.inset, small: NSSize? = nil, divideBefore: Value? = nil, trailing: Bool = false,
         link: DropLink? = nil, faceTitle: String? = nil, showsCheck: Bool = false, fillsField: Bool = false, cellHeight: CGFloat? = nil) {
        self.cellHeight = cellHeight
        self.title = title
        self.faceTitle = faceTitle
        self.showsCheck = showsCheck
        self.fillsField = fillsField
        self.options = options
        self._selection = selection
        self.inset = inset
        self.small = small
        self.divideBefore = divideBefore
        self.trailing = trailing
        self.link = link
    }

    init(_ title: String, options: [(title: String, value: Value)], selection: Binding<Value>,
         inset: CGFloat = DropFace.inset, divideBefore: Value? = nil, trailing: Bool = false) {
        self.init(title, options: options.map { DropOption(title: $0.title, value: $0.value) },
                  selection: selection, inset: inset, divideBefore: divideBefore, trailing: trailing)
    }

    private var chosen: DropOption<Value>? { options.first { $0.value == selection } }

    var body: some View {
        HStack(spacing: 6) {
            if let small, let picture = chosen?.picture {
                Image(nsImage: picture)
                    .resizable()
                    // A drawn mark, in the words' ink.
                    .renderingMode(picture.isTemplate ? .template : .original)
                    .frame(width: small.width, height: small.height)
            }
            Text(faceTitle ?? chosen?.title ?? "")
                .lineLimit(1)
                .truncationMode(.tail)
            if fillsField { Spacer(minLength: 0) }
            Symbol("chevron.down", size: 8, weight: .semibold) // design: the size of MenuCell's ⌃⌄ before it
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, inset)
        .frame(maxWidth: cellHeight == nil ? nil : .infinity, alignment: trailing ? .trailing : .leading)
        .frame(height: cellHeight ?? TableCell.height)
        .background(
            RoundedRectangle(cornerRadius: cellHeight == nil ? Radius.control : 0, style: .continuous)
                .fill(Color.primary.opacity(shown ? 0.1 : hovering || fillsField ? 0.06 : 0))
        )
        .overlay(DropAnchor(place: place, title: title, value: chosen?.title ?? "", press: open, hover: { hovering = $0 }))
        .animation(.easeOut(duration: 0.12), value: hovering)
        .accessibilityElement()
        .accessibilityLabel(title)
        .accessibilityValue(chosen?.title ?? "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }

    private func open() {
        guard let view = place.view, view.window != nil else { return }
        var lines = options.map { DropList.Line(title: $0.title, picture: $0.picture, note: $0.note, head: $0.head) }
        if let link { lines.append(DropList.Line(title: link.title, picture: nil, note: nil, opens: true)) }
        let list = DropList(
            options: lines,
            chosen: options.firstIndex { $0.value == selection } ?? 0,
            divideBefore: link != nil ? options.count : divideBefore.flatMap { cut in options.firstIndex { $0.value == cut } },
            inset: inset,
            showsCheck: showsCheck
        )
        let values = options.map(\.value)
        shown = true
        DropPopup.show(list, under: view, trailing: trailing) { index in
            shown = false
            if let index, values.indices.contains(index) { selection = values[index] }
            if index == values.count { link?.go() }
        }
    }
}

// MARK: - where it opens from

/// The view under the menu's face: where the list hangs from, and the press
/// that opens it, on the way down as a pop-up button opens.
struct DropAnchor: NSViewRepresentable {
    let place: Place
    let title: String
    var value = ""
    let press: () -> Void
    let hover: (Bool) -> Void

    final class Place {
        weak var view: NSView?
    }

    func makeNSView(context: Context) -> Anchor {
        let view = Anchor()
        view.press = press
        view.hover = hover
        view.title = title
        view.value = value
        place.view = view
        return view
    }

    func updateNSView(_ view: Anchor, context: Context) {
        view.press = press
        view.hover = hover
        view.title = title
        view.value = value
        place.view = view
    }

    final class Anchor: NSView {
        var press: () -> Void = {}
        var hover: (Bool) -> Void = { _ in }
        var title = ""
        /// The answer in use, for the bench.
        var value = ""

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                           owner: self, userInfo: nil))
        }
        override func mouseEntered(with event: NSEvent) { hover(true) }
        override func mouseExited(with event: NSEvent) { hover(false) }
        override func mouseDown(with event: NSEvent) {
            // A press on the face of the list just put away closes it, as a
            // pop-up button's second click does.
            if DropPopup.closed(from: self) { return }
            press()
        }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
}

// MARK: - the list

/// What the list shows and where the keys are in it.
@MainActor
final class DropList: ObservableObject {
    struct Line {
        var title: String
        var picture: NSImage?
        var note: String?
        /// A small grey title over this line, starting a part of the list
        /// that runs to the next one.
        var head: String? = nil
        /// A box before the words, ticked or not, when many can be on.
        var checked: Bool? = nil
        /// A number at the row's end: how many it leads to.
        var count: Int? = nil
        /// The number in the warning's ink, for a count that is trouble.
        var warns = false
        /// A chevron at the row's end: it goes to a page further in.
        var opens = false
    }

    @Published private(set) var lines: [Line]
    let chosen: Int
    let showsCheck: Bool
    let divideBefore: Int?
    let inset: CGFloat
    /// The search's words while it is empty.
    let searchWords: String
    /// A search on top however few the answers: the small window's spaces,
    /// found by name as Arc's are.
    let alwaysSearch: Bool
    @Published var query = "" {
        didSet {
            spot = shown.first ?? 0
            changed()
        }
    }
    /// Told when the search changes how many answers there are, so the
    /// window fits them.
    var changed: () -> Void = {}
    @Published var spot: Int
    /// Set by the keys, so the list scrolls to them; never by the pointer.
    @Published var scrollTo: Int?
    var pick: (Int?) -> Void = { _ in }

    /// Told when a box is ticked or cleared, with every line that is on:
    /// a list of boxes stays open while they change.
    var ticked: ((Set<Int>) -> Void)?
    /// How tall it grows before it scrolls.
    let tallest: CGFloat
    /// The keys it answers to, along its foot.
    let showsKeys: Bool

    /// More than this many and a search sits on top.
    static let searchFrom = 8

    init(options: [Line], chosen: Int, divideBefore: Int?, inset: CGFloat,
         searchWords: String = "Search\u{2026}", alwaysSearch: Bool = false,
         tallest: CGFloat = 360, showsKeys: Bool = false, showsCheck: Bool = false) {
        self.lines = options
        self.chosen = chosen
        self.showsCheck = showsCheck
        self.divideBefore = divideBefore
        self.inset = inset
        self.searchWords = searchWords
        self.alwaysSearch = alwaysSearch
        self.tallest = tallest
        self.showsKeys = showsKeys
        self.spot = chosen
        self.scrollTo = chosen
    }

    var on: Set<Int> { Set(lines.indices.filter { lines[$0].checked == true }) }

    func toggle(_ index: Int) {
        guard lines.indices.contains(index), let checked = lines[index].checked else { return }
        lines[index].checked = !checked
        ticked?(on)
    }

    /// The first line of the part `index` is in.
    func part(of index: Int) -> Int {
        (0...index).last { lines[$0].head != nil } ?? 0
    }

    /// Every line from `head` to the next head.
    func lines(from head: Int) -> [Int] {
        let next = lines.indices.first { $0 > head && lines[$0].head != nil } ?? lines.count
        return Array(head..<next)
    }

    /// Clears every box in the part that starts at `head`.
    func clear(from head: Int) {
        for index in lines(from: head) where lines[index].checked == true { lines[index].checked = false }
        ticked?(on)
    }

    /// Whether `index` is shown with its part's head over it: the first
    /// line of its part that the search leaves.
    func headed(_ index: Int, in shown: [Int]) -> Bool {
        let head = part(of: index)
        guard lines[head].head != nil else { return false }
        return shown.first { part(of: $0) == head } == index
    }

    var searches: Bool { alwaysSearch ? lines.count > 1 : lines.count > Self.searchFrom }

    var shown: [Int] {
        let words = query.lowercased().split(separator: " ")
        guard !words.isEmpty else { return Array(lines.indices) }
        return lines.indices.filter { index in
            let text = lines[index].title.lowercased()
            return words.allSatisfy { text.contains($0) }
        }
    }

    func move(_ by: Int) {
        let shown = shown
        guard !shown.isEmpty else { return }
        let at = shown.firstIndex(of: spot) ?? 0
        spot = shown[max(0, min(shown.count - 1, at + by))]
        scrollTo = spot
    }

    /// A letter typed with no search: the next answer starting with it.
    func jump(_ letter: String) {
        let letter = letter.lowercased()
        let order = Array(lines.indices)
        let from = (order.firstIndex(of: spot) ?? -1) + 1
        let next = (order[from...] + order[..<from]).first { lines[$0].title.lowercased().hasPrefix(letter) }
        if let next {
            spot = next
            scrollTo = next
        }
    }

    func take() {
        guard shown.contains(spot) else { return }
        if ticked != nil { toggle(spot) } else { pick(spot) }
    }

    var hasPictures: Bool { lines.contains { $0.picture != nil } }

    func height(of index: Int) -> CGFloat {
        let line = lines[index]
        let words: CGFloat = line.note == nil ? DropListView.row : DropListView.row + 14 // design: a note's line under the words
        return max(words, (line.picture?.size.height ?? 0) + 8) // design: a picture's room above and below in its row
    }
}

struct DropListView: View {
    @ObservedObject var list: DropList
    let width: CGFloat

    static let row: CGFloat = 28
    static let pad: CGFloat = 6
    static let gap: CGFloat = 2
    static let search: CGFloat = 40
    /// A part's small grey title, and the line and room over every one
    /// after the first.
    static let head: CGFloat = 26
    static let between: CGFloat = 9
    static let foot: CGFloat = 34

    var body: some View {
        VStack(spacing: 0) {
            if list.searches {
                PickerSearch(text: $list.query, placeholder: list.searchWords,
                             move: { list.move($0) }, side: { _ in },
                             pick: { list.take() }, close: { list.pick(nil) })
                    .frame(height: 20)
                    .padding(.horizontal, 12)
                    .frame(height: Self.search)
                Divider()
            }
            ScrollViewReader { scroller in
                ThreadScrollView(.vertical) {
                    VStack(spacing: Self.gap) {
                        let shown = list.shown
                        ForEach(shown, id: \.self) { index in
                            if index == list.divideBefore, list.query.isEmpty {
                                Divider().padding(.horizontal, 4)
                            }
                            if list.headed(index, in: shown) {
                                if index != shown.first {
                                    Divider().padding(.horizontal, 4).padding(.vertical, 4)
                                }
                                head(list.part(of: index))
                            }
                            row(index).id(index)
                        }
                    }
                    .padding(Self.pad)
                }
                .scrollIndicators(.never)
                .onAppear { if let to = list.scrollTo { scroller.scrollTo(to, anchor: .center) } }
                .onChange(of: list.scrollTo) { _, to in
                    if let to { scroller.scrollTo(to) }
                }
            }
            if list.showsKeys {
                Divider()
                HStack(spacing: 12) {
                    keys("↑↓", "Move")
                    keys("↩", "Toggle")
                    keys("esc", "Close")
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12)
                .frame(height: Self.foot - 1)
            }
        }
        .frame(width: width, height: DropPopup.height(of: list))
        .modifier(PickerPlate())
        // Lifted off the page by its own shadow, its window casting none
        // (DropPopup.room).
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6) // design: a menu's lift, inside DropPopup.room
    }

    private func keys(_ keys: String, _ does: String) -> some View {
        HStack(spacing: 4) {
            KeyGlyphs(keys: keys, size: 10)
            Text(does)
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
    }

    private func head(_ index: Int) -> some View {
        HStack {
            Text(list.lines[index].head ?? "")
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if list.lines(from: index).contains(where: { list.lines[$0].checked == true }) {
                Button("Clear") { list.clear(from: index) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .frame(height: Self.head, alignment: .center)
    }

    private func row(_ index: Int) -> some View {
        let line = list.lines[index]
        return HStack(spacing: 8) {
            if list.showsCheck {
                Symbol("checkmark", size: 10, weight: .semibold)
                    .frame(width: 12)
                    .opacity(index == list.chosen ? 1 : 0)
            }
            if let checked = line.checked {
                DropBox(on: checked)
            }
            if let picture = line.picture {
                Image(nsImage: picture)
                    .resizable()
                    // A drawn mark, a tick, in the words' ink.
                    .renderingMode(picture.isTemplate ? .template : .original)
                    .frame(width: picture.size.width, height: picture.size.height)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.title)
                    .lineLimit(1)
                if let note = line.note {
                    Text(note)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let count = line.count {
                Text("\(count)")
                    .font(.system(size: 12, weight: line.warns && count > 0 ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(line.warns && count > 0 ? Color.orange : Color.secondary.opacity(0.7))
            }
            if line.opens { SettingsChevron() }
        }
        .font(.system(size: 13))
        .padding(.horizontal, list.inset)
        .frame(height: list.height(of: index))
        .background(
            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                .fill(Color.primary.opacity(list.spot == index ? 0.1 : 0))
        )
        .contentShape(Rectangle())
        .onHover { if $0 { list.spot = index } }
        .onTapGesture { if list.ticked != nil { list.toggle(index) } else { list.pick(index) } }
        .accessibilityAddTraits(line.checked == true || (list.showsCheck && index == list.chosen) ? .isSelected : [])
    }
}

/// A row's box: a rounded square outline, filled in the words' ink with a
/// tick in the plate's when on.
struct DropBox: View {
    let on: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
            .strokeBorder(Color.primary.opacity(on ? 0 : 0.28), lineWidth: 1.5)
            .background(RoundedRectangle(cornerRadius: Radius.small, style: .continuous).fill(Color.primary.opacity(on ? 0.9 : 0)))
            .overlay {
                if on {
                    Symbol("checkmark", size: 8, weight: .bold)
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                }
            }
            .frame(width: 14, height: 14)
    }
}

// MARK: - the window it is in

/// The list's own window, hung under the face in the window the face is in,
/// taking the keys while it is open and gone when anything else is pressed.
@MainActor
enum DropPopup {
    private static var panel: DropPanel?
    private static var anchor: NSView?
    private static var done: ((Int?) -> Void)?
    /// Room round the plate in its window for the plate's shadow: as far
    /// as PickerPlate's lifted shadow reaches (radius 30, 12 down).
    static let room: CGFloat = 44
    /// When and from what the last list was put away by a press outside it.
    private static var lastClose: (from: NSView?, at: Date)?

    /// `corner`: the plate's top right on the screen, over the face rather
    /// than under it (the small window's spaces, hung from its corner as
    /// Little Arc's are). `fade`: in over 0.12 s, or there in one frame.
    /// `trailing`: the plate's right edge under the face's, for a face at
    /// a row's end.
    static func show(_ list: DropList, under view: NSView, corner: NSPoint? = nil, width asked: CGFloat? = nil,
                     trailing: Bool = false, fade: Bool = true, done: @escaping (Int?) -> Void) {
        close(nil)
        guard let window = view.window else { return }
        let face = window.convertToScreen(view.convert(view.bounds, to: nil))
        let height = DropPopup.height(of: list)
        let width = asked ?? max(face.width + 2 * DropListView.pad, widest(list) + 2 * DropListView.pad, 180)
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        // The words in the list stand under the words on the face, the
        // list running past the window's edge if it must.
        var x = trailing ? face.maxX + DropListView.pad - width : face.minX - DropListView.pad
        x = min(max(x, screen.minX + 8), screen.maxX - width - 8)
        var y = face.minY - 4 - height
        let up = corner == nil && y < screen.minY + 8
        if up { y = face.maxY + 4 }
        if let corner {
            x = corner.x - width
            y = corner.y - height
        }

        // The window runs past the plate by `room` on every side and casts
        // no shadow of its own: the window server's shadow of a clear
        // window with glass in it is cut square, a dark frame behind the
        // round corners. The plate's own shadow is drawn in that room.
        let plate = NSRect(x: x, y: y, width: width, height: height)
        let panel = DropPanel(contentRect: plate.insetBy(dx: -room, dy: -room),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = window.level
        panel.isReleasedWhenClosed = false
        panel.list = list
        panel.room = room
        let host = NSHostingView(rootView: DropListView(list: list, width: width).padding(room))
        // Yab sets this window's frame; SwiftUI keeping it inside the content's
        // least and greatest size after each window layout can loop (crash #112).
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host
        panel.closes = { close(nil, pressedOutside: true) }

        list.pick = { index in close(index) }
        // A search that leaves fewer answers shortens the list from below,
        // or from above where it opened over its face.
        list.changed = { [weak panel] in
            guard let panel else { return }
            var frame = panel.frame
            let tall = DropPopup.height(of: list) + 2 * room
            if !up { frame.origin.y = frame.maxY - tall }
            frame.size.height = tall
            panel.setFrame(frame, display: true)
        }
        self.panel = panel
        self.anchor = view
        self.done = done
        window.addChildWindow(panel, ordered: .above)
        panel.alphaValue = fade ? 0 : 1
        panel.makeKeyAndOrderFront(nil)
        // The search takes the keyboard as the list comes up, so typing
        // filters at once.
        host.layoutSubtreeIfNeeded()
        panel.focusSearch()
        guard fade else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
    }

    /// Whether this press is the one that just put the list away from the
    /// same face: then it opens nothing.
    static func closed(from view: NSView) -> Bool {
        guard let last = lastClose, last.from === view else { return false }
        lastClose = nil
        return Date().timeIntervalSince(last.at) < 0.3
    }

    static func close(_ index: Int?, pressedOutside: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        let finish = done
        done = nil
        if pressedOutside { lastClose = (anchor, Date()) }
        let window = anchor?.window
        anchor = nil
        panel.closes = {}
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        window?.makeKey()
        finish?(index)
    }

    /// As tall as the answers shown, up to a height that scrolls.
    static func height(of list: DropList) -> CGFloat {
        let shown = list.shown
        let heads = shown.filter { list.headed($0, in: shown) }
        let rows = shown.reduce(CGFloat(0)) { $0 + list.height(of: $1) }
            + CGFloat(max(0, shown.count - 1)) * DropListView.gap
            + (list.divideBefore.map(shown.contains) == true && list.query.isEmpty ? DropListView.gap + 1 : 0)
            + CGFloat(heads.count) * (DropListView.head + DropListView.gap)
            + CGFloat(max(0, heads.count - (heads.first == shown.first ? 1 : 0))) * (DropListView.between + DropListView.gap)
        let search = list.searches ? DropListView.search + 1 : 0
        let foot = list.showsKeys ? DropListView.foot : 0
        return min(rows + 2 * DropListView.pad + search, list.tallest - foot) + foot
    }

    private static func widest(_ list: DropList) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 13)
        let note = NSFont.systemFont(ofSize: 11)
        return list.lines.map { line in
            let words = max((line.title as NSString).size(withAttributes: [.font: font]).width,
                            ((line.note ?? "") as NSString).size(withAttributes: [.font: note]).width)
            // Room over the measure for the words' own drawing, which runs
            // a little wider than AppKit's measure of them.
            return words + (line.picture.map { $0.size.width + 8 } ?? 0) + (line.checked == nil ? 0 : 22)
                + (list.showsCheck ? 20 : 0)
                + (line.count.map { ("\($0)" as NSString).size(withAttributes: [.font: font]).width + 12 } ?? 0)
                + (line.opens ? 16 : 0) + 2 * list.inset + 16
        }.max() ?? 0
    }
}

final class DropPanel: NSPanel {
    var actionKey: ((NSEvent) -> Bool)?
    /// A key held with ⌘ or ⌃, asked before the app's menus are: a line's
    /// own key (ActionMenuList.press).
    var actionKeyEquivalent: ((NSEvent) -> Bool)?
    var actionFlags: ((NSEvent.ModifierFlags) -> Void)?
    var actionMouse: ((NSEvent) -> Bool)?
    var list: DropList?
    var closes: () -> Void = {}
    /// The clear room round the plate, for its shadow.
    var room: CGFloat = 0

    /// A press in the room round the plate is a press beside the list:
    /// it puts the list away and goes on to the window under it, as one
    /// anywhere else does.
    override func sendEvent(_ event: NSEvent) {
        if actionMouse?(event) == true { return }
        if event.type == .flagsChanged { actionFlags?(event.modifierFlags) }
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let content = contentView,
           !content.bounds.insetBy(dx: room, dy: room).contains(content.convert(event.locationInWindow, from: nil)) {
            let under = parent
            let screen = convertPoint(toScreen: event.locationInWindow)
            closes()
            if let under, let passed = NSEvent.mouseEvent(
                with: event.type, location: under.convertPoint(fromScreen: screen), modifierFlags: event.modifierFlags,
                timestamp: event.timestamp, windowNumber: under.windowNumber, context: nil,
                eventNumber: event.eventNumber, clickCount: event.clickCount, pressure: event.pressure) {
                NSApp.postEvent(passed, atStart: true)
            }
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeKey: Bool { true }

    /// The list's search, when it has one.
    var search: PickerSearch.Field? {
        func find(_ view: NSView) -> PickerSearch.Field? {
            if let field = view as? PickerSearch.Field { return field }
            for sub in view.subviews { if let found = find(sub) { return found } }
            return nil
        }
        return contentView.flatMap(find)
    }

    /// The keyboard to the search, unless it has it already.
    @discardableResult
    func focusSearch() -> Bool {
        guard let field = search else { return false }
        if !field.isEditing(in: self) { makeFirstResponder(field) }
        return field.isEditing(in: self)
    }

    override func becomeKey() {
        super.becomeKey()
        focusSearch()
    }

    override func resignKey() {
        super.resignKey()
        closes()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, actionKeyEquivalent?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if actionKey?(event) == true { return }
        guard let list else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 125: list.move(1) // down
        case 126: list.move(-1) // up
        case 36, 76, 49: list.take() // return, enter, space
        case 53: list.pick(nil) // escape
        default:
            if list.searches, let typed = event.characters, !typed.isEmpty,
               event.modifierFlags.intersection([.command, .control]).isEmpty,
               typed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && $0.value < 0xF700 }),
               focusSearch(), let editor = firstResponder as? NSTextView {
                // Typed while the search somehow lacked the keyboard: it
                // goes there, never lost.
                editor.insertText(typed, replacementRange: editor.selectedRange())
            } else if let letter = event.charactersIgnoringModifiers, letter.count == 1,
               letter.rangeOfCharacter(from: .alphanumerics) != nil {
                list.jump(letter)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

extension DropPopup {
    /// The bench's hand on a menu in Settings: "title" finds its face,
    /// "hover" lights it, "open" presses it; "key" (down, up, return, esc)
    /// and "type" (into the search) go to the list that is open. Answers
    /// the list's window and the face's, for pictures of each.
    static func bench(_ request: [String: Any]) -> [String: Any] {
        var face: DropAnchor.Anchor?
        if let title = request["title"] as? String {
            func find(_ view: NSView) -> DropAnchor.Anchor? {
                if let anchor = view as? DropAnchor.Anchor, anchor.title == title { return anchor }
                for sub in view.subviews { if let found = find(sub) { return found } }
                return nil
            }
            face = NSApp.windows.lazy.compactMap { $0.contentView.flatMap(find) }.first
            guard let face else { return ["error": "no menu titled \(title)"] }
            if let hover = request["hover"] as? Bool { face.hover(hover) }
            if request["open"] as? Bool == true { face.press() }
        }
        if let panel, let list = panel.list {
            // "press": letters, and "keys" (down, up, return, esc), as the
            // keyboard sends them: posted to the app, so they go wherever
            // the keyboard is, the search or the list. Read back on the
            // next request, once the app has taken them.
            let named: [String: (UInt16, String)] = [
                "return": (36, "\r"), "esc": (53, "\u{1b}"),
                "down": (125, String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))),
                "up": (126, String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))),
            ]
            var presses = (request["press"] as? String ?? "").map { (UInt16(0), String($0)) }
            presses += (request["keys"] as? [String] ?? []).compactMap { named[$0] }
            for (code, characters) in presses {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    if let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: panel.windowNumber, context: nil, characters: characters,
                                                    charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) {
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
            if let type = request["type"] as? String { list.query = type }
            // "tick": boxes to toggle, by their words, as a press on each.
            for title in request["tick"] as? [String] ?? [] {
                if let index = list.lines.firstIndex(where: { $0.title == title }) { list.toggle(index) }
            }
            switch request["key"] as? String {
            case "down": list.move(1)
            case "up": list.move(-1)
            case "return": list.take()
            case "esc": list.pick(nil)
            default: break
            }
        }
        var answer: [String: Any] = ["open": panel != nil]
        if let panel {
            answer["panel"] = panel.windowNumber
            let plate = panel.frame.insetBy(dx: panel.room, dy: panel.room)
            answer["frame"] = [plate.minX, plate.minY, plate.width, plate.height]
            // The same, from the top left of the screen with the menu bar,
            // for a capture of the screen there (screencapture -R).
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            answer["plate"] = [plate.minX, top - plate.maxY, plate.width, plate.height]
            answer["spot"] = panel.list?.spot ?? -1
            answer["chosen"] = panel.list?.chosen ?? -1
            answer["selectionChecks"] = panel.list?.showsCheck ?? false
            answer["key"] = panel.isKeyWindow
            answer["searches"] = panel.list?.searches ?? false
            answer["focus"] = panel.search.map { $0.isEditing(in: panel) } ?? false
            answer["query"] = panel.list?.query ?? ""
            answer["shown"] = panel.list?.shown.map { panel.list?.lines[$0].title ?? "" } ?? []
            answer["on"] = panel.list.map { list in list.on.sorted().map { list.lines[$0].title } } ?? []
            answer["heads"] = panel.list?.lines.compactMap(\.head) ?? []
        }
        if let face, let window = face.window {
            answer["window"] = window.windowNumber
            answer["value"] = face.value
            let rect = window.convertToScreen(face.convert(face.bounds, to: nil))
            answer["face"] = [rect.minX, rect.minY, rect.width, rect.height]
        }
        return answer
    }
}
