import AppKit
import SwiftUI
import SyncKit

// Change Icon…, as Arc has it: a popover off the pin, the tab's row or the
// folder, with Emoji and Icon over a search, every emoji eight to a row, and
// the parts along its foot. What is picked is on at once and closes it.
// Choose Image…, and Restore Site Icon once the icon is your own, stand by
// the search. The concept, with the two variants not built:
// work/design/icon-picker-2026-10-07.

/// Which pin, row or folder has the picker open: one at a time.
@MainActor
final class IconPicking: ObservableObject {
    static let shared = IconPicking()

    enum Target: Hashable {
        case tab(UUID)
        case nest(UUID)
    }

    @Published var target: Target?
    private(set) var pending: Target?
    private var generation = 0
    var isHolding: Bool { target != nil || pending != nil }

    /// From the menu's Change Icon…: once the menu has gone, so its own end
    /// doesn't take the popover with it.
    func open(_ target: Target) {
        generation += 1
        let current = generation
        pending = target
        DispatchQueue.main.async {
            guard self.generation == current else { return }
            self.target = target
            self.pending = nil
        }
    }
}

/// One Customize Folder visit. Immediate edits persist, but make only one
/// window undo step when the popover closes.
@MainActor
final class FolderCustomizeSession {
    let folder: Nest
    weak var browser: Browser?
    let openingColor: String?
    let openingMark: String?
    var choosingImage = false
    private var finished = false

    init(folder: Nest, browser: Browser) {
        self.folder = folder
        self.browser = browser
        openingColor = folder.color
        openingMark = folder.customMark
    }

    func color(_ tint: FolderTint) {
        folder.color = tint.stored
        persist()
    }

    func mark(_ value: String?) {
        folder.customMark = value
        persist()
    }

    func cancel() {
        folder.color = openingColor
        folder.customMark = openingMark
        persist()
        finish()
    }

    func finish() {
        guard !finished, !choosingImage else { return }
        finished = true
        folder.previewTint = nil
        guard folder.color != openingColor || folder.customMark != openingMark else { return }
        let oldColor = openingColor
        let oldMark = openingMark
        let browser = browser
        let folder = folder
        browser?.did { [weak browser, weak folder] in
            guard let folder else { return }
            folder.color = oldColor
            folder.customMark = oldMark
            browser?.folderBook.emptyChanged(folder)
            browser?.writeSession(now: true)
        }
    }

    private func persist() {
        browser?.folderBook.emptyChanged(folder)
        browser?.writeSession(now: true)
    }
}

extension View {
    @ViewBuilder
    func splitMateIconPicker(_ mate: Tab?, in browser: Browser) -> some View {
        if let mate { self.iconPicker(mate, in: browser) } else { self }
    }

    /// Change Icon's picker for a pinned or kept tab, hanging from this
    /// view, or from `anchor` in it: the mark's square in a row.
    func iconPicker(_ tab: Tab, in browser: Browser, at anchor: CGRect? = nil) -> some View {
        modifier(IconPickerHang(target: .tab(tab.id), anchor: anchor, mark: { tab.customMark }) { [weak browser] mark in
            tab.customMark = mark
            browser?.writeSession(now: true)
        })
    }

    /// The same for a folder of yours.
    func iconPicker(_ nest: Nest, in browser: Browser) -> some View {
        modifier(IconPickerHang(target: .nest(nest.id), anchor: nil, mark: { nest.customMark }, folder: nest, browser: browser) { [weak browser] mark in
            nest.customMark = mark
            browser?.folderBook.emptyChanged(nest)
            browser?.writeSession(now: true)
        })
        .id(browser.prefs.sidebar ? "folder-\(browser.prefs.sideFlank.rawValue)" : "folder-top")
    }
}

/// The popover, shown while its pin, row or folder is the one picked.
private struct IconPickerHang: ViewModifier {
    let target: IconPicking.Target
    let anchor: CGRect?
    let mark: () -> String?
    var folder: Nest? = nil
    var browser: Browser? = nil
    let set: (String?) -> Void
    @State private var shown = false
    @State private var session: FolderCustomizeSession?

    private var edge: Edge {
        guard folder != nil else { return .bottom }
        guard browser?.prefs.sidebar == true else { return .top }
        return browser?.prefs.sideFlank == .right ? .leading : .trailing
    }

    func body(content: Content) -> some View {
        content
            .popover(isPresented: $shown, attachmentAnchor: anchor.map { PopoverAttachmentAnchor.rect(.rect($0)) } ?? .rect(.bounds), arrowEdge: edge) {
                IconPicker(mark: mark(), folder: folder, pick: { picked in
                    if let session { session.mark(picked) } else { set(picked) }
                    if folder == nil { shown = false }
                }, close: { shown = false }, cancel: {
                    session?.cancel()
                    shown = false
                }, setColor: { tint in
                    session?.color(tint)
                }, chooseImage: {
                    if let session {
                        session.choosingImage = true
                        CustomMarks.chooseImage { image in
                            if let image { session.mark(image) }
                            session.choosingImage = false
                            session.finish()
                            shown = false
                        }
                    } else {
                        shown = false
                        CustomMarks.chooseImage { if let image = $0 { set(image) } }
                    }
                })
            }
            // Every row hears it; only the one it names changes.
            .onReceive(IconPicking.shared.$target) { picked in
                let mine = picked == target
                if mine != shown { shown = mine }
            }
            .onChange(of: shown) { _, now in
                if now, let folder, let browser {
                    session = FolderCustomizeSession(folder: folder, browser: browser)
                } else if !now {
                    session?.finish()
                    if IconPicking.shared.target == target { IconPicking.shared.target = nil }
                }
            }
    }
}

/// Every emoji in Unicode's own order, under the eight parts Apple's picker
/// and Arc's have (Resources/emoji-groups.dat, packed by
/// Resources/emoji-groups-pack.py from Unicode's emoji-test.txt).
enum EmojiParts {
    struct Part {
        let title: String
        /// Its drawing in the bar (IconMarks).
        let mark: String
        var emoji: [(glyph: String, name: String)] = []
    }

    static let all: [Part] = {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let places = [Bundle.main.resourceURL?.appendingPathComponent("emoji-groups.dat"), repo.appendingPathComponent("Resources/emoji-groups.dat")]
        guard let file = places.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let packed = try? Data(contentsOf: file),
              let raw = try? (packed as NSData).decompressed(using: .zlib) as Data,
              let text = String(data: raw, encoding: .utf8)
        else { return [] }
        let marks = ["Smileys & People": "emoji.smileys", "Animals & Nature": "emoji.nature", "Food & Drink": "emoji.food",
                     "Activity": "emoji.activity", "Travel & Places": "emoji.travel", "Objects": "emoji.objects",
                     "Symbols": "emoji.symbols", "Flags": "emoji.flags"]
        var out: [Part] = []
        for line in text.split(separator: "\n") {
            if line.hasPrefix("#") {
                let title = String(line.dropFirst())
                out.append(Part(title: title, mark: marks[title] ?? "emoji.symbols"))
                continue
            }
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2, !out.isEmpty else { continue }
            out[out.count - 1].emoji.append((String(parts[0]), String(parts[1])))
        }
        return out
    }()
}

/// The picker itself: Emoji and Icon, the search with Choose Image… and
/// Restore Site Icon, the grid and, under the emoji, their parts.
/// A space's well has it too (`space`): its offered emoji ahead of the
/// parts, the Icon tab's symbols a space can wear (SpaceSymbols), and no
/// image of your own, which an iPhone could not show.
/// An emoji typed or pasted into the search is the one picked.
struct IconPicker: View {
    let mark: String?
    var folder: Nest? = nil
    /// A space's: the emoji it is offered, first.
    var space: [String]? = nil
    let spaceName: String?
    let bookmark: Bookmark?
    let profile: (id: UUID, name: String)?
    let rename: ((String) -> Void)?
    @State private var spacePreview: FolderTint?
    private var showsPalette: Bool { folder != nil || spaceName != nil || bookmark != nil }
    private var customizing: Bool { showsPalette || profile != nil }
    let pick: (String?) -> Void
    let close: () -> Void
    var cancel: (() -> Void)? = nil
    var setColor: ((FolderTint) -> Void)? = nil
    var chooseImage: (() -> Void)? = nil
    /// Emoji alone, with no Icon page: a project's face.
    var emojiOnly = false

    private enum Kind: Hashable { case emoji, icon }

    /// One square of the grid: what it puts on, an emoji or "icon:<name>".
    private struct Item: Identifiable, Hashable {
        let id: String
        /// "suggested" for a space's offered one, which its part has again.
        var part = ""
    }

    @State private var kind: Kind
    @State private var words = ""
    /// The square the arrows are on, once one has been pressed.
    @State private var at: Int?
    /// The part the grid is scrolled to, lit in the bar.
    @State private var part = 0
    /// Bumped when the meanings come in: what the words find, found again.
    @State private var meanings = 0
    @State private var colorAt: Int?
    @State private var onColors = false
    @State private var chosenColor: FolderTint?
    @FocusState private var typing: Bool
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let across = 8
    private static let side: CGFloat = 32

    init(mark: String?, folder: Nest? = nil, space: [String]? = nil, spaceName: String? = nil, spaceTint: FolderTint? = nil, pick: @escaping (String?) -> Void, close: @escaping () -> Void,
         cancel: (() -> Void)? = nil, setColor: ((FolderTint) -> Void)? = nil, chooseImage: (() -> Void)? = nil,
         emojiOnly: Bool = false, bookmark: Bookmark? = nil, profile: (id: UUID, name: String)? = nil,
         rename: ((String) -> Void)? = nil) {
        self.bookmark = bookmark
        self.profile = profile
        self.rename = rename
        self.mark = mark
        self.emojiOnly = emojiOnly
        self.folder = folder
        self.space = space
        self.spaceName = spaceName
        self.pick = pick
        self.close = close
        self.cancel = cancel
        self.setColor = setColor
        self.chooseImage = chooseImage
        _chosenColor = State(initialValue: folder.map { FolderTint(stored: $0.color) } ?? spaceTint)
        let icon = space == nil ? (mark?.hasPrefix("icon:") == true || mark?.hasPrefix("space:") == true) : !Spaces.isEmoji(mark ?? "")
        _kind = State(initialValue: icon && !emojiOnly ? .icon : .emoji)
    }

    /// A space's offered emoji, two rows of them.
    private var suggested: [Item] {
        let first = profile != nil ? ["🦊", "🐻", "🐼", "🦉", "🐰", "🐱", "🐶", "🐺", "🦁", "🐨", "🐧", "🐸"] : (space ?? [])
        return first.filter(Spaces.isEmoji).prefix(2 * Self.across).map { Item(id: $0, part: "suggested") }
    }

    var body: some View {
        let sections = self.sections
        let items = sections.flatMap(\.items)
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if customizing {
                    Group {
                        if let profile {
                            CustomizeHeader(name: profile.name, tint: nil, rename: rename, allowsEmptyName: true) { _ in
                                ProfilePicture(profile: profile.id, size: 48)
                            }
                        } else if let folder {
                            FolderCustomizeHeader(folder: folder)
                        } else if let name = bookmark?.title ?? spaceName {
                            CustomizeHeader(name: name, tint: spacePreview ?? chosenColor, rename: rename) { _ in
                                SpaceMark(icon: mark ?? "folder", size: 40)
                            }
                        }
                    }
                    .padding(.vertical, 12)
                    if showsPalette {
                        palette
                            .padding(.horizontal, 12)
                            .padding(.bottom, 12)
                    }
                    Divider()
                }
                HStack(spacing: 6) {
                    field(items)
                    if space == nil {
                        Button {
                            if let chooseImage { chooseImage() }
                            else {
                                let pick = self.pick
                                close()
                                CustomMarks.chooseImage { if let image = $0 { pick(image) } }
                            }
                        } label: {
                            Symbol("photo", size: 11)
                        }
                        .buttonStyle(.yab(.raised, .regular, icon: .square))
                        .keyTip("Choose Image…")
                        if (folder?.customMark ?? mark) != nil {
                            Button { pick(nil) } label: { art("restore", side: 15) }
                                .buttonStyle(.yab(.raised, .regular, icon: .square))
                                .keyTip(profile != nil ? "Reset to Default" : folder == nil ? "Restore Site Icon" : "Restore Folder Icon")
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)
                ThreadScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.side), spacing: 0), count: Self.across), alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.key) { section in
                            // A part of its own starts a row of its own.
                            Section {
                                ForEach(Array(section.items.enumerated()), id: \.element) { offset, item in
                                    Cell(item: item.id, current: item.id == mark,
                                         at: at == section.start + offset && (!customizing || !onColors)) { pick(item.id) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
                // Under the emoji the bar takes the room the icons' grid has.
                .frame(height: kind == .emoji ? 168 : 209)
                // Each catalog starts at its own top. An offset far down
                // the emoji list can leave the much shorter icon grid blank.
                .id(kind)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in follow(y) }
                .onChange(of: at) { _, now in
                    guard let now, items.indices.contains(now) else { return }
                    proxy.scrollTo(items[now], anchor: nil)
                }
                if kind == .emoji {
                    Divider()
                    bar(proxy)
                }
                if !emojiOnly {
                    Divider()
                    kindSelector
                }
            }
            .frame(width: CGFloat(Self.across) * Self.side + 24)
        }
        .onChange(of: words) { _, words in
            at = nil
            if let glyph = Emoji.typed(in: words) { pick(glyph) }
        }
        .onChange(of: kind) { _, _ in
            at = nil
            onColors = false
            preview(nil)
            words = ""
            part = 0
        }
        .onAppear {
            typing = true
            // What the emoji mean, for the words: made once, off the main thread.
            Emoji.warm { meanings += 1 }
        }
    }

    // MARK: what the grid holds

    private struct Block {
        let key: String
        /// Where its first square is among them all, for the arrows.
        let start: Int
        let items: [Item]
    }

    private var sections: [Block] {
        _ = meanings
        let needles = words.lowercased().split(separator: " ").map(String.init)
        switch (kind, needles.isEmpty) {
        case (.icon, _):
            return [Block(key: "icons", start: 0, items: icons(matching: words).map { Item(id: $0) })]
        case (.emoji, true):
            let suggested = self.suggested
            var start = suggested.count
            return (suggested.isEmpty ? [] : [Block(key: "suggested", start: 0, items: suggested)]) + EmojiParts.all.map { part in
                defer { start += part.emoji.count }
                return Block(key: part.title, start: start, items: part.emoji.map { Item(id: $0.glyph) })
            }
        case (.emoji, false):
            return [Block(key: "found", start: 0, items: Self.emoji(matching: words, first: space).map { Item(id: $0) })]
        }
    }

    /// Tabs and folders store the shared art under its own namespace. Old
    /// icon: marks stay readable through CustomMarks without being rewritten.
    func icons(matching words: String) -> [String] {
        Self.spaceIcons(matching: words, forFolder: space == nil)
    }

    /// Custom marks use the space catalog with a namespace; Space sync
    /// keeps its existing unprefixed symbol keys.
    @MainActor static func spaceIcons(matching words: String, forFolder: Bool) -> [String] {
        SpaceDraft.symbols(matching: words).map { forFolder ? "space:" + $0 : $0 }
    }

    /// What the words find, by name and by meaning as the field's Emoji
    /// finds them, then what only Unicode's names have, the flags'
    /// countries; a space's offered ones (`first`) a little ahead.
    /// The new-space tray's search too.
    @MainActor static func emoji(matching words: String, first: [String]? = nil) -> [String] {
        let needles = words.lowercased().split(separator: " ").map(String.init)
        guard !needles.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        let found = first.map { Emoji.search(words, first: $0) } ?? Emoji.find(words)
        for one in found where seen.insert(Emoji.bare(one.glyph)).inserted {
            out.append(one.glyph)
        }
        for part in EmojiParts.all {
            for emoji in part.emoji where !seen.contains(Emoji.bare(emoji.glyph)) {
                let name = emoji.name.lowercased()
                guard needles.allSatisfy({ name.contains($0) }) else { continue }
                seen.insert(Emoji.bare(emoji.glyph))
                out.append(emoji.glyph)
            }
        }
        return out
    }

    /// The part at the grid's top, scrolled `y` down: each part starts a
    /// row of its own.
    private func follow(_ y: CGFloat) {
        guard kind == .emoji, words.isEmpty else { return }
        var top = CGFloat((suggested.count + Self.across - 1) / Self.across) * Self.side
        var now = 0
        for (index, part) in EmojiParts.all.enumerated() {
            if top <= y + Self.side / 2 { now = index }
            top += CGFloat((part.emoji.count + Self.across - 1) / Self.across) * Self.side
        }
        if now != part { part = now }
    }

    // MARK: the search

    private func field(_ items: [Item]) -> some View {
        HStack(spacing: 6) {
            Symbol("magnifyingglass", size: 10.5).foregroundStyle(Palette.muted(on: tone))
            TextField("", text: $words, prompt: Text("Search\u{2026}").foregroundStyle(Palette.muted(on: tone)))
                .textFieldStyle(.plain)
                .foregroundStyle(Palette.strong(on: tone))
                .font(.system(size: 13))
                .focused($typing)
                // Down goes into the grid and moves a row; up, left and
                // right move there once in it, and the caret otherwise.
                // Return puts on the square the arrows are on, or the first.
                .onKeyPress(keys: [.downArrow, .upArrow, .leftArrow, .rightArrow, .return, .escape, .tab], phases: .down) { press in
                    guard press.modifiers.isEmpty else { return .ignored }
                    switch press.key {
                    case .return:
                        if customizing, onColors {
                            let tint = FolderTint.allCases[colorAt ?? 0]
                            chosenColor = tint
                            setColor?(tint)
                            close()
                            return .handled
                        }
                        guard let item = items.indices.contains(at ?? 0) ? items[at ?? 0] : nil else { return .handled }
                        pick(item.id)
                        if customizing { close() }
                    case .escape:
                        if words.isEmpty { (cancel ?? close)() } else { words = "" }
                    case .tab:
                        guard showsPalette else { return .ignored }
                        onColors.toggle()
                        if onColors { colorAt = colorAt ?? FolderTint.allCases.firstIndex(of: chosenColor ?? .black) }
                        else { at = at ?? 0; preview(nil) }
                    case .downArrow:
                        if customizing, onColors { onColors = false; at = 0; preview(nil) }
                        else { move(at == nil ? 0 : Self.across, in: items.count) }
                    default:
                        if customizing, onColors {
                            let step = press.key == .leftArrow || press.key == .upArrow ? -1 : 1
                            colorAt = min(max((colorAt ?? 0) + step, 0), FolderTint.allCases.count - 1)
                            preview(FolderTint.allCases[colorAt ?? 0])
                            return .handled
                        }
                        guard at != nil else { return .ignored }
                        move(press.key == .upArrow ? -Self.across : press.key == .leftArrow ? -1 : 1, in: items.count)
                    }
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .frame(height: ButtonSize.regular.height)
        .background(RoundedRectangle(cornerRadius: 8).fill(tone.map { Palette.resting(on: $0, hovering: false) } ?? Palette.ground)) // design: shared picker search input follows the approved 8 pt folder field
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tone.map { Color(nsColor: SpaceSurface.rim(on: $0)) } ?? Palette.hairline, lineWidth: 1)) // design: search input border, not a card
    }

    private func move(_ step: Int, in count: Int) {
        guard count > 0 else { return }
        at = min(max((at ?? 0) + step, 0), count - 1)
    }

    private func preview(_ tint: FolderTint?) {
        if let folder { folder.previewTint = tint } else { spacePreview = tint }
    }

    private var palette: some View {
        HStack(spacing: 6) {
            ForEach(Array(FolderTint.allCases.enumerated()), id: \.element) { index, tint in
                Button {
                    chosenColor = tint
                    setColor?(tint)
                } label: {
                    ZStack {
                        if tint == .black {
                            Image(systemName: "circle.slash")
                                .font(.system(size: 17, weight: .light))
                                .foregroundStyle(Palette.muted)
                        } else {
                            Circle().fill(tint.swatch).frame(width: 18, height: 18)
                        }
                    }
                    .frame(width: 26, height: 26)
                    .overlay {
                        Circle().strokeBorder(tint == .black ? Palette.muted : tint.swatch,
                                              lineWidth: chosenColor == tint ? 2 : 0)
                    }
                    .overlay {
                        Circle().strokeBorder(Color.accentColor, lineWidth: colorAt == index && onColors ? 2 : 0)
                            .padding(-3)
                    }
                }
                .buttonStyle(.plain)
                .onHover { on in
                    withAnimation(Motion.quick) { preview(on ? tint : nil) }
                }
                .accessibilityLabel("\(tint.title) \(spaceName == nil ? "folder" : "space") color")
                .accessibilityValue(chosenColor == tint ? "Selected" : "")
            }
        }
    }

    /// Full-width footer shared by the tab, folder and space pickers.
    private var kindSelector: some View {
        HStack(spacing: 8) {
            kindButton("Emoji", kind: .emoji)
            kindButton("Icon", kind: .icon)
        }
        .padding(12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon type")
    }

    private func kindButton(_ title: String, kind target: Kind) -> some View {
        Button {
            kind = target
        } label: {
            Text(title).font(.system(size: 12, weight: .medium))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .contentShape(Rectangle())
                .background(RoundedRectangle(cornerRadius: 9).fill(kind == target ? tone.map { Palette.wash(on: $0) } ?? Palette.ground : Color.clear)) // design: the selected Finder-style footer button is 9 pt
                .shadow(color: .black.opacity(kind == target ? 0.12 : 0), radius: 3, y: 1) // design: the selected picker tab lifts by one point
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(target == .icon ? "icon-picker-tab-icon" : "icon-picker-tab-emoji")
        .accessibilityAddTraits(kind == target ? .isSelected : [])
    }

    // MARK: the parts' bar

    private func bar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(EmojiParts.all.enumerated()), id: \.offset) { index, one in
                Button {
                    words = ""
                    part = index
                    // After the grid has its parts back, if words had it.
                    DispatchQueue.main.async {
                        guard let first = one.emoji.first else { return }
                        withAnimation(reduceMotion ? nil : Motion.quick) { proxy.scrollTo(Item(id: first.glyph), anchor: .top) }
                    }
                } label: {
                    art(one.mark, side: 16)
                }
                .buttonStyle(.yab(.quiet, .small, tint: index == part && words.isEmpty ? Palette.ink : nil, icon: .square))
                .keyTip(one.title, side: .above)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func art(_ name: String, side: CGFloat) -> some View {
        Group {
            if let image = IconMarks.art(name) {
                Image(nsImage: image).renderingMode(.template).resizable()
            }
        }
        .frame(width: side, height: side)
    }

    /// An emoji or an icon, lit while the pointer is on it; the one on now
    /// a step grayer, and the arrows' one ringed.
    private struct Cell: View {
        let item: String
        let current: Bool
        let at: Bool
        let pick: () -> Void
        @Environment(\.tone) private var tone
        @State private var hovering = false

        var body: some View {
            Button(action: pick) {
                Group {
                    if item.hasPrefix("icon:"), let image = IconMarks.art(String(item.dropFirst(5))) {
                        Image(nsImage: image).renderingMode(.template).resizable()
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Palette.strong(on: tone))
                    } else if item.hasPrefix("space:") || SpaceSymbols.isSymbol(item) {
                        // The same approved drawing for folders and spaces.
                        SpaceMark(icon: item.hasPrefix("space:") ? String(item.dropFirst(6)) : item, size: 15)
                            .foregroundStyle(Palette.strong(on: tone))
                    } else {
                        Text(item).font(.system(size: 20))
                    }
                }
                .frame(width: IconPicker.side, height: IconPicker.side)
                .background(
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(tone == nil ? Palette.ink.opacity(current ? 0.1 : hovering ? 0.06 : 0)
                            : current ? Palette.wash(on: tone) : hovering ? Palette.hover(on: tone) : .clear)
                )
                .overlay {
                    if at {
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressStyle(scale: 0.9))
            .accessibilityIdentifier("icon-picker-\(item)")
            .onHover { hovering = $0 }
        }
    }
}

private struct FolderCustomizeHeader: View {
    @ObservedObject var folder: Nest
    var body: some View {
        let tint = folder.previewTint ?? folder.color.flatMap(FolderTint.init(rawValue:))
        CustomizeHeader(name: folder.name, tint: tint) { ink in
            if let image = CustomMarks.image(folder.customMark) {
                Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original)
                    .resizable().scaledToFit()
            } else {
                Face(pose: .seen, size: 48, tint: ink, folder: true, unfolded: false, folderTint: tint == .black ? nil : tint)
            }
        }
    }
}

private struct CustomizeHeader<Mark: View>: View {
    let name: String
    let tint: FolderTint?
    var rename: ((String) -> Void)? = nil
    var allowsEmptyName = false
    @State private var draft = ""
    @State private var editing = false
    @FocusState private var fieldFocused: Bool

    private func commit(_ rename: (String) -> Void) {
        editing = false
        let clean = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if (allowsEmptyName || !clean.isEmpty) && clean != name { rename(clean) }
    }
    @ViewBuilder let mark: (Color) -> Mark
    @Environment(\.tone) private var tone
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let ink = tint.flatMap { $0 == .black ? nil : $0.ink(dark: scheme == .dark) } ?? Palette.strong(on: tone)
        VStack(spacing: 6) {
            mark(ink).frame(width: 48, height: 48)
            if let rename, editing {
                TextField("Name", text: $draft)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 200)
                    .focused($fieldFocused)
                    .onChange(of: fieldFocused) { _, focused in
                        if !focused && editing { commit(rename) }
                    }
                    .onAppear { fieldFocused = true }
                    .onChange(of: name) { _, new in if !editing { draft = new } }
                    .onSubmit {
                        commit(rename)
                    }
                    .onKeyPress(.escape) {
                        draft = name
                        editing = false
                        return .handled
                    }
                    .accessibilityLabel("Name")
            } else if rename != nil {
                Button(name) { draft = name; editing = true }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                    .accessibilityLabel("Edit name")
            } else {
                Text(name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity)
    }
}

/// One visit to an existing Space, from its menu or its Settings icon well.
@MainActor
final class SpaceCustomizeSession: ObservableObject {
    let browser: Browser
    let space: Space
    @Published private(set) var name: String
    let openingIcon: String
    let openingPaint: SpacePaint
    @Published private(set) var icon: String
    @Published private(set) var paint: SpacePaint
    private var finished = false

    init(browser: Browser, space: Space) {
        self.browser = browser
        self.space = space
        name = space.name
        openingIcon = space.icon
        openingPaint = space.id == browser.spaceID ? SpacePaint(browser.prefs) : space.paint ?? SpacePaint(browser.prefs)
        icon = openingIcon
        paint = openingPaint
    }

    func rename(_ value: String) {
        browser.renameSpace(space.id, to: value)
        name = value
    }

    func mark(_ picked: String?) {
        guard let picked, picked != icon else { return }
        icon = picked
        browser.setSpaceIcon(space.id, to: picked)
    }

    func color(_ tint: FolderTint) {
        if tint == .black {
            paint.wearPlain()
        } else {
            paint.swatch = Swatch.custom.rawValue
            paint.color = NSColor(tint.swatch).hex
            paint.colors = []
        }
        browser.setSpacePaint(space.id, to: paint)
    }

    func cancel() {
        guard !finished else { return }
        finished = true
        if icon != openingIcon { browser.setSpaceIcon(space.id, to: openingIcon) }
        if paint != openingPaint { browser.setSpacePaint(space.id, to: openingPaint) }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        let previousIcon = icon == openingIcon ? nil : openingIcon
        let previousPaint = paint == openingPaint ? nil : openingPaint
        guard previousIcon != nil || previousPaint != nil else { return }
        let id = space.id
        browser.did { [weak browser] in
            if let previousIcon { browser?.setSpaceIcon(id, to: previousIcon) }
            if let previousPaint { browser?.setSpacePaint(id, to: previousPaint) }
        }
    }
}

struct SpaceCustomizer: View {
    @StateObject var session: SpaceCustomizeSession
    let close: () -> Void

    var body: some View {
        let suggested = SpaceDraft.guess(session.name).more + Spaces.icons + SpaceDraft.all
        var seen = Set<String>()
        let offered = ([session.openingIcon] + suggested).filter { seen.insert($0).inserted }
        let paint = session.paint
        let tint = paint.picked == .plain ? FolderTint.black : FolderTint.allCases.first {
            $0 != .black && paint.colors.isEmpty && paint.picked == .custom && NSColor($0.swatch).hex == paint.color
        }
        let rename: ((String) -> Void)?
        if session.space.id == Space.mailID { rename = nil } else { rename = { session.rename($0) } }
        return IconPicker(mark: session.icon, space: offered, spaceName: session.name, spaceTint: tint,
                          pick: session.mark, close: close, cancel: { session.cancel(); close() }, setColor: session.color,
                          rename: rename)
            .onDisappear { session.finish() }
    }
}
