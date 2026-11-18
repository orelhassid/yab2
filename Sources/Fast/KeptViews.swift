import AppKit
import SwiftUI

// How the kept tabs are drawn (Kept.swift): the line under them in the
// column and the stroke after them on top, and a folder of yours, a row in
// the column and a pill on top, the same as a task's folder but for the
// face: its mark the folder alone, opening and shutting on Core Animation's
// clock as a task's does.

/// The line under the kept tabs, a strip shorter than a row, as Arc's
/// (SideBar.line). Its words fade in while the pointer is anywhere over
/// the column; their places stay reserved when only the line is showing.
struct KeptLine: View {
    @ObservedObject var browser: Browser
    /// The column's own line, not one coming in under a drag or drawn in a
    /// space on its way: it says where it is, for Clear's dust.
    var reports = false
    /// The persistent boundary cell may have no line while today's is empty.
    var visible = true
    @State private var measuredFrame: CGRect = .zero
    @Environment(\.sidebarSpaceActions) private var scope
    @State private var overLine = false
    @State private var onWord = false
    @State private var onTidy = false
    @Environment(\.tone) private var tone

    var body: some View {
        let _ = SpacePager.touched()
        // Lit New Tab under it too: Arc keeps it while ⌘T asks.
        // While Tidy waits for its answer the words go and the line waves,
        // as Arc's does (TidyTabs.swift).
        let hovered = scope == nil ? browser.columnHovered : overLine
        let tidying = browser.tabsTidying
        let clears = browser.canTidyNow && !tidying
        let sorts = clears && browser.canTidyTabs
        let density = Density.current
        // The line stops short of the word rather than running under a
        // plate: the word has no ground of its own, only brightens.
        HStack(spacing: 0) {
            TidyWave(on: tidying)
            HStack(spacing: 0) {
                if sorts {
                    // Tidy, left of Clear and as faint, as in Arc.
                    Button { scope.perform(stay: true) { browser.tidyTabs() } } label: {
                        HStack(spacing: 4) {
                            Broom(sweep: 0, big: 0, small: 0)
                                .frame(width: 11, height: 11)
                            Text("Tidy")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(onTidy ? Palette.ink : Palette.faint(on: tone))
                        .padding(.horizontal, 6)
                        .frame(height: SideBar.line + SideBar.gap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { onTidy = $0 }
                    .keyTip("Organize Today's Tabs")
                    .opacity(hovered ? 1 : 0)
                    .allowsHitTesting(hovered)
                    .accessibilityHidden(!hovered)
                }
                if clears {
                    Button { scope.perform(stay: true) { browser.tidyNow() } } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                        // As faint as New Tab's words under it, as Arc has it.
                        .foregroundStyle(onWord ? Palette.ink : Palette.faint(on: tone))
                        .padding(.horizontal, 6)
                        .frame(height: SideBar.line + SideBar.gap)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .onHover { onWord = $0 }
                    .opacity(hovered ? 1 : 0)
                    .allowsHitTesting(hovered)
                    .accessibilityHidden(!hovered)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            // Continue the stroke through the reserved word slots while
            // they are quiet. No width, position or row height changes.
            .background {
                TidyWave(on: false)
                    .padding(.trailing, 6)
                    .opacity(clears && !hovered ? 1 : 0)
            }
        }
        .animation(Motion.quick, value: hovered)
        // From the rows' icons to as far in from the other end; the word's
        // letters end there too.
        .padding(.leading, SideBar.inner)
        .padding(.trailing, clears ? 4 : SideBar.inner) // design: the word's own 6-pt inset brings its letters to the line's end
        // The stroke 10 under the row over it and 12 over New Tab's, as
        // Arc draws it, the word centered on it.
        .offset(y: density.lineDrop + 0.5 - density.line / 2)
        .frame(height: SideBar.line)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { on in
            if scope != nil { overLine = on }
            // The dust's shader, built under the pointer, well before the
            // word can be pressed.
            if on, browser.canTidyNow { Dust.shared.warm() }
            if on, browser.canTidyTabs { TidyTabs.warm() }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { [browser, reports] in
            guard reports else { return }
            measuredFrame = $0
            browser.keptLine = visible ? $0 : nil
        }
        // Built in the background a while after the line first shows, for
        // Clear from the line's menu too, which comes without hovering.
        .onChange(of: visible, initial: true) { _, visible in
            guard reports else { return }
            browser.keptLine = visible && measuredFrame.width > 0 ? measuredFrame : nil
            if visible { DispatchQueue.main.asyncAfter(deadline: .now() + 5) { Dust.shared.warm() } }
        }
        .steadyMenu(actions: true) {
            KeptFolderItems(browser: browser)
            if browser.canTidyTabs { Button("Tidy", mark: "yab.folder.bolt") { browser.tidyTabs() } }
            Button("Clear", mark: "broom") { browser.tidyNow() }
                .disabled(!browser.canTidyNow)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Kept tabs above, today's below")
    }
}

/// New Folder and New Live Folder among the kept, from the line's menu and
/// the space's name's. A space folded under its name opens first, for the
/// new folder's name to be typed where it is seen.
struct KeptFolderItems: View {
    let browser: Browser

    var body: some View {
        Button("New Folder", mark: "yab.folder.plus") {
            browser.folderBook.unfoldSpace()
            browser.newEmptyFolder()
        }
        // A live one, kept up to date from a site (LiveFolders.swift).
        Menu("New Live Folder", mark: "yab.folder.refresh") {
            if browser.prefs.usesLiveFolders {
                ForEach(LiveSource.all.filter { LiveGitService.of($0.id) == nil && $0.id != "feed" && $0.id != "github.search" }, id: \.id) { source in
                    Button(source.title) {
                        browser.folderBook.unfoldSpace()
                        LiveFolders.shared.make(source.id, in: browser)
                    }
                }
            } else {
                Button("Turn On Live Folders…", mark: "yab.folder.refresh") { SettingsWindow.shared.show(.liveFolders, for: browser) }
            }
        }
    }
}

/// A click on a folder's row opens or shuts it at once; a second click soon
/// after puts it back as it was and names it, so a double-click renames the
/// way Finder's does without the single click waiting to see.
struct NestClick: ViewModifier {
    @Environment(\.sidebarSpaceActions) private var scope
    let nest: Nest
    let naming: Bool
    /// The window's folders (Browser.folderBook).
    var folders: Folders = .shared

    func body(content: Content) -> some View {
        content.onTapGesture {
            guard !naming else { return }
            let tap = { folders.tap(nest, immediately: scope != nil); folders.focused = nest.id }
            if let scope { scope.run(tap) } else { tap() }
        }
    }
}

/// The stroke after the kept tabs on top.
struct KeptDivider: View {
    static let width: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Palette.ink.opacity(0.1))
            .frame(width: 1, height: 16)
            .frame(width: Self.width, height: Metrics.row)
            .allowsHitTesting(false)
    }
}

/// A folder of yours in the column: its mark and its name.
/// A click opens or shuts it; a double-click, or Rename…, names it.
struct NestRow: View {
    @Environment(\.sidebarSpaceActions) private var scope
    @ObservedObject var browser: Browser
    @ObservedObject var nest: Nest
    let count: Int
    /// A tab held over it, to go in when let go.
    var aimed = false
    /// In the hand, its tabs folded under it.
    var lifted = false
    /// An agent's finished work in one of its tabs you haven't come to:
    /// the tick at its end, as a task's folder has (Folders.Folder.over).
    var over: FacePose? = nil
    /// Watched: every window's folders tell the first window's
    /// (Folders.init(sharing:)); this window's are read.
    @ObservedObject private var watched = Folders.shared
    private var folders: Folders { browser.folderBook }
    @Environment(\.tabTitleSize) private var titleSize
    @Environment(\.tone) private var tone
    @Environment(\.colorScheme) private var colorScheme
    /// In a cell of the AppKit column: where it stands is the page's to say.
    @Environment(\.columnHosted) private var hosted
    @State private var hoverState = RowLocalState(false)
    /// The column's word in the AppKit column (SideRow's `columnPointed`),
    /// which also tells the preview (ColumnPage.point).
    @Environment(\.columnPointed) private var columnPointed
    private var hovering: Bool {
        get { columnPointed ?? hoverState[nest.id] }
        nonmutating set { hoverState[nest.id] = newValue }
    }

    private var naming: Bool { folders.naming == nest.id }
    private var tint: FolderTint? {
        let value = nest.previewTint ?? nest.color.flatMap(FolderTint.init(rawValue:))
        return value == .black ? nil : value
    }
    private var color: Color { tint?.ink(dark: colorScheme == .dark) ?? Palette.strong(on: tone) }

    var body: some View {
        let _ = SpacePager.touched()
        let peeks = folders.peeks(nest)
        // A peeking one's end is its minus (FolderUnpeek).
        let closing = nest.today && hovering && !lifted && !naming && !peeks
        HStack(spacing: SideBar.markGap) {
            Group {
                if let linked = LinkFolders.mark(nest, in: browser) {
                    // A ⌘-click's: the page's site, as Dia's group wears it,
                    // or of more than one site the emoji its name came with.
                    LinkFolderMark(tab: linked.tab, mark: linked.emoji, landed: nest.renamed == nil ? nest.named : nil, size: SideBar.mark, tint: color)
                } else if let image = CustomMarks.image(nest.customMark) {
                    Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original).resizable().scaledToFit()
                        .foregroundStyle(color)
                } else if nest.live?.source == "routine" {
                    RoutineFolderFace(nest: nest, tint: color)
                } else {
                    Face(pose: .seen, size: SideBar.folder, tint: color, folder: true, unfolded: nest.open, weight: SideBar.folderWeight, folderTint: tint)
                        .overlay { if peeks { FolderPeekDots(tint: color, folderTint: tint).transition(.opacity) } }
                        .animation(Motion.quick, value: peeks)
                }
            }
                .frame(width: SideBar.mark, height: SideBar.mark)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    browser.folderBook.focused = nest.id
                    IconPicking.shared.open(.nest(nest.id))
                }
            if naming {
                NestNameField(nest: nest, folders: folders)
                    .frame(height: titleSize + 4)
            } else if nest.unnamed {
                LinkFolderPlaceholder()
            } else {
                // A step heavier than a tab's, in the space's deepest shade,
                // as Arc writes its folders.
                FadingTitle(text: nest.name, font: .system(size: titleSize, weight: .medium), color: color, clear: 0, fade: 28)
                    .equatable()
                    .modifier(LinkFolderShimmer(landed: nest.renamed == nil ? nest.named : nil))
                    .modifier(RenameReveal(since: nest.renamed, tint: Rename.tint(tone)))
                // A live folder that can't read, or holds more that need
                // you than come out from under it (LiveViews.swift).
                LiveNestWords(browser: browser, nest: nest)
                MeetingLeftWords(nest: nest)
                if let over {
                    Face(pose: over, size: 15, tint: Palette.muted(on: tone))
                        .frame(width: 15, height: 15)
                        .transition(.opacity)
                }
                if peeks, hovering, !lifted {
                    Spacer(minLength: 0)
                    FolderUnpeek { folders.unpeek(nest) }
                }
            }
            // A folder of today's tabs (Tidy's among them): under the
            // pointer, a task's folder's own cross (FolderRow) takes the
            // end and closes its tabs as its menu's Close N Tabs (⌘W)
            // does, ⌘⇧T bringing them back. A kept folder's tabs aren't
            // closed but put to sleep, so it has none.
            if closing {
                Spacer(minLength: 0)
                FolderCross {
                    let close = { browser.glance.drop(); browser.close(browser.tabs(in: nest)) }
                    if let scope { scope.run(close) } else { close() }
                }
                    .transition(.opacity)
            }
        }
        .animation(Motion.quick, value: over)
        .animation(Motion.quick, value: closing)
        .padding(.leading, 10)
        .padding(.trailing, naming ? SideBar.inner : SideBar.endInset)
        .frame(height: SideBar.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        // From the row's far edge, out over the page, not from its mark.
        .iconPicker(nest, in: browser)
        .background {
            if lifted {
                // Its tabs folded under it: two sheets showing at its foot,
                // as a stack of picked rows has them.
                ZStack {
                    ForEach([2, 1], id: \.self) { sheet in
                        GroundFill(shape: RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous), browser: browser)
                            .overlay {
                                RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous)
                                    .strokeBorder(tone == nil ? Palette.hairline : Palette.ink.opacity(0.12), lineWidth: 1) // design: a folded row's edge under a held folder, not a card; on a color the ink let through
                            }
                            .padding(.horizontal, CGFloat(sheet) * 6)
                            .offset(y: CGFloat(sheet) * 4)
                    }
                    GroundFill(shape: RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous), browser: browser)
                    RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous)
                        .fill(Palette.wash(on: tone))
                }
                .shadow(color: .black.opacity(0.14), radius: 12, y: 4) // design: the lift a held row casts (Stack)
            } else {
                if let tint {
                    RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous)
                        .fill(tint.wash(dark: colorScheme == .dark))
                }
                if aimed || naming {
                    SelectionPlate(corner: SideBar.radius, state: .selected, prefs: browser.prefs)
                } else if hovering {
                    SelectionPlate(corner: SideBar.radius, state: .hover)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous))
        .globalFrame(!hosted) { [hosted] frame in
            if !hosted { browser.glance.folderFrames[nest.key] = frame }
        }
        .modifier(NestClick(nest: nest, naming: naming, folders: folders))
        // Rested on, shut, its preview comes out beside the column.
        .modifier(RowHover(on: columnPointed == nil) { on in hovering = on; browser.glance.hoverFolder(nest.key, on && !naming && !lifted) })
        .onChange(of: naming) { _, value in if value { browser.glance.drop() } }
        .steadyMenu(actions: true) { NestMenu(browser: browser, nest: nest) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nest.name), folder, \(count) \(count == 1 ? "tab" : "tabs")")
        .accessibilityValue(nest.open ? "open" : "closed")
    }
}

/// A shut folder's three dots on its front while a tab of it shows under
/// it, half open, as Arc's: where an agent's folder wears its eyes
/// (FolderGrid.eyes), in the folder's line.
private struct FolderPeekDots: View {
    let tint: Color
    let folderTint: FolderTint?
    @Environment(\.self) private var environment

    var body: some View {
        let ink = Color(cgColor: Face.paint(pose: .seen, tint: tint, folder: true, folderTint: folderTint, in: environment).ink)
        Canvas { context, size in
            let k = size.width / 24, r = 1.2 * k
            for x in [8.2, 12, 15.8] as [CGFloat] {
                context.fill(Path(ellipseIn: CGRect(x: x * k - r, y: FolderGrid.eyes * k - r, width: 2 * r, height: 2 * r)), with: .color(ink))
            }
        }
        .frame(width: SideBar.folder, height: SideBar.folder)
        .allowsHitTesting(false)
    }
}

/// The minus at the end of a folder that peeks, under the pointer only, as
/// Arc's: it puts the tab showing under the folder out of sight.
private struct FolderUnpeek: View {
    let action: () -> Void
    @State private var pressed = false
    @State private var on = false
    @Environment(\.tone) private var tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let plate = RowPlate.column
        Button(action: action) {
            MinusCross(open: 0)
                .stroke(style: StrokeStyle(lineWidth: plate.cross / 8, lineCap: .round))
                .frame(width: plate.cross, height: plate.cross)
                .foregroundStyle(on ? Palette.ink.opacity(0.75) : Palette.muted(on: tone))
                .frame(width: plate.side, height: plate.side)
                .background { if on { plate.square() } }
                .contentShape(RoundedRectangle(cornerRadius: plate.radius, style: .continuous))
                .scaleEffect(pressed && !reduceMotion ? 0.9 : 1)
                .animation(pressed ? Press.down : Press.up, value: pressed)
        }
        .buttonStyle(Held(pressed: $pressed))
        .focusable(false)
        .onHover { on = $0 }
        // Its square concentric with the row, as a tab's cross is.
        .padding(.trailing, plate.inset - SideBar.endInset)
        .keyTip("Hide Tab")
        .accessibilityLabel("Hide Tab")
    }
}

/// A folder of yours on top: the mark and the name, as a task's is. Open,
/// its tabs come out to its right in a wash.
struct NestPill: View {
    @ObservedObject var browser: Browser
    @ObservedObject var nest: Nest
    let count: Int
    let width: CGFloat
    var aimed = false
    /// The tick while one of its tabs holds an agent's work you haven't
    /// come to, shown while it is shut, as a task's folder's (NestRow).
    var over: FacePose? = nil
    /// Drawn into one picture with the next space's row (StripComing): its
    /// faces at rest (StillFace).
    var still = false
    /// Watched: every window's folders tell the first window's
    /// (Folders.init(sharing:)); this window's are read.
    @ObservedObject private var watched = Folders.shared
    private var folders: Folders { browser.folderBook }
    @Environment(\.tone) private var tone
    @Environment(\.colorScheme) private var colorScheme
    @State private var hovering = false

    private var naming: Bool { folders.naming == nest.id }
    private var tint: FolderTint? {
        let value = nest.previewTint ?? nest.color.flatMap(FolderTint.init(rawValue:))
        return value == .black ? nil : value
    }
    private var color: Color { tint?.ink(dark: colorScheme == .dark) ?? Palette.strong(on: tone) }
    private var compact: Bool { !nest.open && width < Metrics.tabTitled }

    var body: some View {
        let _ = StripRenderMeter.folder()
        HStack(spacing: compact ? 2 : 6) {
            Group {
                if let image = CustomMarks.image(nest.customMark) {
                    Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original).resizable().scaledToFit()
                        .foregroundStyle(color)
                } else if still {
                    StillFace(pose: .seen, size: 15, tint: color, folder: true, unfolded: nest.open, folderTint: tint)
                } else {
                    Face(pose: .seen, size: 15, tint: color, folder: true, unfolded: nest.open, folderTint: tint)
                }
            }
                .frame(width: 15, height: 15)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    browser.folderBook.focused = nest.id
                    IconPicking.shared.open(.nest(nest.id))
                }
                .iconPicker(nest, in: browser)
            if naming {
                NestNameField(nest: nest, folders: folders)
                    .frame(height: 16)
            } else if compact {
                Text(String(nest.name.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(color)
            } else if !compact {
                FadingTitle(text: nest.name, font: .system(size: 12.5, weight: .medium), color: color, clear: 0, fade: 28)
                    .equatable()
                if let over, !nest.open {
                    Group {
                        if still { StillFace(pose: over, size: 15, tint: Palette.muted(on: tone)) } else { Face(pose: over, size: 15, tint: Palette.muted(on: tone)) }
                    }
                        .frame(width: 15, height: 15)
                }
            }
        }
        .padding(.leading, compact && !naming ? 0 : 11)
        .padding(.trailing, compact && !naming ? 0 : 7) // design: a task's folder's pill's insets (FolderPill)
        .padding(.vertical, 6)
        .frame(width: width, alignment: compact && !naming ? .center : .leading)
        .background {
            // Inside its folder's wash, concentric with it: the wash's rim on
            // the leading side too, as over and under the pill.
            let shape = RoundedRectangle(cornerRadius: SideBar.radius - NestedWash.rim, style: .continuous)
            Group {
                if let tint { shape.fill(tint.wash(dark: colorScheme == .dark)) }
                if hovering || aimed || naming {
                    shape.fill(aimed || naming ? Palette.wash(on: tone) : Palette.hover(on: tone))
                }
            }
            .padding(.leading, NestedWash.rim)
        }
        .contentShape(RoundedRectangle(cornerRadius: SideBar.radius, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            browser.glance.folderFrames[nest.key] = frame
        }
        .modifier(NestClick(nest: nest, naming: naming, folders: folders))
        .onHover { on in hovering = on; browser.glance.hoverFolder(nest.key, on && !naming) }
        .onChange(of: naming) { _, value in if value { browser.glance.drop() } }
        .steadyMenu(actions: true) { NestMenu(browser: browser, nest: nest) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(nest.name), folder, \(count) \(count == 1 ? "tab" : "tabs")")
        .accessibilityValue(nest.open ? "open" : "closed")
    }
}

/// A routine's folder's face: it reads while its routine looks
/// (LiveFolders.checking). Only these watch LiveFolders, not every folder.
private struct RoutineFolderFace: View {
    @ObservedObject var nest: Nest
    let tint: Color
    @ObservedObject private var live = LiveFolders.shared

    var body: some View {
        Face(pose: live.checking(nest) ? .read : .seen, size: SideBar.folder, tint: tint, folder: true, unfolded: nest.open, weight: SideBar.folderWeight,
             folderTint: nest.previewTint ?? nest.color.flatMap(FolderTint.init(rawValue:)))
    }
}

/// What a right-click on a folder of yours offers.
struct NestMenu: View {
    let browser: Browser
    @ObservedObject var nest: Nest

    var body: some View {
        // Every tab under it, its folders' too.
        let tabs = browser.tabs(in: nest)
        let n = tabs.count
        let inner = browser.nests.filter { $0 !== nest && $0.within(nest) }
        Button(nest.open ? "Close Folder" : "Open Folder", mark: nest.open ? "yab.folder.closed" : "yab.folder.open") { browser.folderBook.toggle(nest.key) }
        Divider()
        if !inner.isEmpty {
            // ⌥-click on its row does the same.
            let all = nest.open && inner.allSatisfy(\.open)
            Button(all ? "Close All Inside" : "Open All Inside", mark: "yab.chevupdown") { browser.folderBook.openAll(nest, !all) }
        }
        if !nest.today {
            Button("New Tab in Folder", mark: "plus.tab") { browser.newTab(in: nest) }
            Button("New Folder Inside", mark: "yab.folder.plus") { browser.newFolder(inside: nest) }
                .disabled(nest.depth >= Nest.deepest)
        }
        Divider()
        Button("Rename…", mark: "pencil") { browser.folderBook.naming = nest.id }
        Button("Customize Folder…", mark: "slider.horizontal.3") { IconPicking.shared.open(.nest(nest.id)) }
            .keyboardShortcut("i", modifiers: .command)
        if nest.live != nil {
            Divider()
            LiveNestMenu(browser: browser, nest: nest)
        } else if !nest.today, n > 0 {
            // A routine keeps it from now on (Routines.keepFolder).
            Divider()
            Button("Keep Up to Date…", mark: "arrow.clockwise") { Routines.shared.keepFolder(nest, in: browser) }
        }
        Divider()
        // One Move to, as a tab's: Space, then Folder.
        let filing = !nest.today && NestMove.offers(browser, nest)
        if browser.spacesShown, !filing {
            // Space is the only group: Move to Space, not Move to › Space.
            NestSpaceSend(browser: browser, nest: nest, alone: true)
        } else if !browser.spacesShown, filing {
            NestMove(browser: browser, nest: nest)
        } else if browser.spacesShown || filing {
            Menu("Move to", mark: "arrow.right") {
                NestSpaceSend(browser: browser, nest: nest, title: "Space")
                if filing { NestMove(browser: browser, nest: nest, title: "Folder") }
            }
        }
        // Dia's Chat with Group: a new chat about every tab under it.
        if Agents.ready, !ChatAttachment.tabs(of: nest, in: browser).isEmpty {
            Button("Chat with Folder", mark: "bubble.sparkle") { browser.chatWith(nest) }
        }
        // Arc's Copy All Links and Copy All Links as Markdown: every tab
        // under it, its folders' too, in the row's order.
        let links = tabs.filter { $0.address != nil }.count
        let pages = tabs.filter { MarkdownLink.page($0) != nil }.count
        if links > 0 {
            Divider()
            Button(links == 1 ? "Copy Link" : "Copy \(links) URLs", mark: "link") { browser.copyLinks(tabs) }.shortcut(.copyAddress)
            if pages > 0 {
                Button(pages == 1 ? "Copy Markdown Link" : "Copy \(pages) Markdown Links", mark: "markdown") { browser.copyMarkdownLink(tabs) }
            }
        }
        Divider()
        if nest.today {
            // A search's, among today's: taken apart, or closed as today's
            // tabs close, ⌘⇧T bringing them back.
            Button(n == 1 ? "Put Tab to Sleep" : "Put \(n) Tabs to Sleep", mark: "yab.sleepa") { browser.sleep(tabs, byHand: true) }
                .disabled(!browser.canSleep(tabs, byHand: true))
            Button("Ungroup", mark: "yab.folder.up") { browser.ungroupSearch(nest) }
            Button(n == 1 ? "Close Tab" : "Close \(n) Tabs", mark: "yab.tabs.x") { browser.close(tabs) }.shortcut(.closeTab)
        } else if n == 0 {
            if nest.live != nil, browser.prefs.usesLiveFolders {
                Button("Stop Updating", mark: "yab.folder.pause") { LiveNestMenu.stop(nest, in: browser) }
            }
            Button("Remove Folder", mark: "trash") {
                LiveFolders.shared.removed(nest, in: browser)
                browser.arranging { browser.folderBook.removeEmpty(nest) }
            }
        } else {
        Button(n == 1 ? "Put Tab to Sleep" : "Put \(n) Tabs to Sleep", mark: "yab.sleepa") { browser.sleep(tabs, byHand: true) }
            .disabled(!browser.canSleep(tabs, byHand: true))
        if nest.live != nil, browser.prefs.usesLiveFolders {
            Button("Stop Updating", mark: "yab.folder.pause") { LiveNestMenu.stop(nest, in: browser) }
        }
        Button("Remove Folder, Keep Tabs", mark: "yab.folder.minus") {
            LiveFolders.shared.removed(nest, in: browser)
            browser.ungroup(nest)
        }
        Button(n == 1 ? "Remove Folder and Tab" : "Remove Folder and \(n) Tabs", mark: "trash") {
            LiveFolders.shared.removed(nest, in: browser)
            browser.removeFolder(nest, with: tabs)
        }
        }
    }
}

/// Move to Folder for a folder: any other of yours among the kept, as deep
/// as each is, that it can go in (Browser.canPut), or one step out of the
/// one it is in.
struct NestMove: View {
    let browser: Browser
    @ObservedObject var nest: Nest
    var title = "Move to Folder"

    /// Any folder to go in, or one to step out of: else no submenu at all.
    static func offers(_ browser: Browser, _ nest: Nest) -> Bool {
        nest.parent != nil || browser.nests.contains { !$0.today && !$0.within(nest) }
    }

    var body: some View {
        let others = browser.nests.filter { !$0.today && !$0.within(nest) }
        Menu(title, mark: "yab.folder.right") {
            ForEach(others) { other in
                Button(NestMove.indented(other), mark: "yab.folder.right") { browser.file(nest, in: other) }
                    .disabled(other === nest.parent || !browser.canPut(nest, in: other))
            }
            if nest.parent != nil {
                if !others.isEmpty { Divider() }
                Button("Move Out of Folder", mark: "yab.folder.up") { browser.file(nest, in: nest.parent?.parent) }
            }
        }
        .disabled(others.isEmpty && nest.parent == nil)
    }

    /// A folder's name in a menu of folders, stepped in an em's width for
    /// each folder it is in, as Finder's Move To lists them.
    static func indented(_ nest: Nest) -> String {
        String(repeating: "\u{2003}", count: max(0, nest.depth - 1)) + nest.name
    }
}

/// Move to Space for a folder, as Arc's Move to: each other space, then
/// New Space… that takes the folder whole. It keeps its section there
/// (Browser.moveFolder). Picked, the rows close up on Arc's clock, a beat
/// after the menu has gone. Only when there are spaces.
struct NestSpaceSend: View {
    @ObservedObject var browser: Browser
    @ObservedObject var nest: Nest
    var title = "Move to Space"
    /// The only group of its Move to: the row says Move to, not just Space.
    var alone = false

    var body: some View {
        let others = browser.spaces.filter { $0.id != browser.spaceID }
        if browser.spacesShown, others.isEmpty {
            // New Space… is all there is: the row is that, not a submenu.
            Button(alone ? "Move to New Space\u{2026}" : "New Space\u{2026}", mark: "square.2.layers.3d") { SpaceTray.open(browser, folder: nest) }
        } else if browser.spacesShown {
            Menu(alone ? "Move to Space" : title, mark: "square.2.layers.3d") {
                ForEach(others) { space in
                    Button(space.marked("  ")) {
                        let hand = Browser.handMade
                        DispatchQueue.main.asyncAfter(deadline: .now() + Browser.folderLeavesAfter) {
                            browser.moveFolder(nest, to: space.id, hand: hand)
                        }
                    }
                }
                Divider()
                Button("New Space\u{2026}", mark: "square.2.layers.3d") { SpaceTray.open(browser, folder: nest) }
            }
        }
    }
}

/// The folder's name, typed in place. Return or a click elsewhere keeps
/// what was typed, Escape what it was; empty keeps what it was.
struct NestNameField: NSViewRepresentable {
    @ObservedObject var nest: Nest
    /// The window's folders (Browser.folderBook).
    var folders: Folders = .shared

    func makeCoordinator() -> Coordinator { Coordinator(nest: nest, folders: folders) }

    static func dismantleNSView(_ field: NSTextField, coordinator: Coordinator) {
        coordinator.stopWatching()
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NameBox()
        field.delegate = context.coordinator
        field.coordinator = context.coordinator
        context.coordinator.field = field
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: context.environment.tabTitleSize)
        field.textColor = Palette.NS.ink
        field.cell?.usesSingleLineMode = true
        field.cell?.wraps = false
        // A long name scrolls under the caret, as a tab's does (#380).
        field.cell?.isScrollable = true
        field.isAutomaticTextCompletionEnabled = false
        field.stringValue = nest.name
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let font = NSFont.systemFont(ofSize: context.environment.tabTitleSize)
        if field.font != font {
            field.font = font
            field.currentEditor()?.font = font
        }
        let coordinator = context.coordinator
        coordinator.nest = nest
        field.appearance = context.environment.tone?.appearance
        coordinator.claim()
    }

    /// The field, which takes the keys when it comes into a window. Tried
    /// once, a turn after the row was drawn, and given up if the row was
    /// not in its window yet (a long session's column is slower than
    /// that), the name was left open in a field with no keys and no watch
    /// for a click away, and the folder could not be named again (feedback
    /// #1910; a tab's name, TabAddressField, #1899 and #1902).
    final class NameBox: NSTextField {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.claim()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var nest: Nest
        let folders: Folders
        weak var field: NSTextField?
        /// The keys taken, once: a click away answered by its own end.
        private(set) var claimed = false
        private var claiming = false
        private var done = false
        private var clicks: Any?

        init(nest: Nest, folders: Folders) {
            self.nest = nest
            self.folders = folders
        }

        /// The keys for the field, once it is in a window; refused there,
        /// the name is put down rather than left open where nobody types.
        func claim(tries: Int = 5) {
            guard let field, field.window != nil, !field.isHiddenOrHasHiddenAncestor,
                  !claimed, !claiming, !done, folders.naming == nest.id else { return }
            claiming = true
            DispatchQueue.main.asyncAfter(deadline: .now() + (tries == 5 ? 0 : 0.05)) { [weak self] in
                guard let self else { return }
                self.claiming = false
                guard let field = self.field, let window = field.window, !self.claimed, !self.done,
                      self.folders.naming == self.nest.id else { return }
                guard window.makeFirstResponder(field), let editor = field.currentEditor() as? NSTextView else {
                    if tries > 1 { return self.claim(tries: tries - 1) }
                    return self.finish(nil, clearFocus: false)
                }
                self.claimed = true
                self.watch(field)
                editor.selectedTextAttributes = [
                    .backgroundColor: NSColor(Palette.ink.opacity(0.11)),
                    .foregroundColor: Palette.NS.ink,
                ]
                editor.selectAll(nil)
            }
        }

        func watch(_ field: NSTextField) {
            guard clicks == nil else { return }
            clicks = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self, weak field] event in
                guard let self, let field, let window = field.window else { return event }
                if event.window !== window || !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
                    self.finish(field.stringValue, clearFocus: false)
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }

        func stopWatching() {
            if let clicks { NSEvent.removeMonitor(clicks) }
            clicks = nil
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
            switch command {
            case #selector(NSResponder.insertNewline(_:)):
                finish(control.stringValue)
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                finish(nil)
                return true
            default:
                return false
            }
        }

        func controlTextDidEndEditing(_ note: Notification) {
            finish((note.object as? NSTextField)?.stringValue, clearFocus: false)
        }

        private func finish(_ typed: String?, clearFocus: Bool = true) {
            guard !done else { return }
            done = true
            stopWatching()
            let nest = nest, folders = folders
            DispatchQueue.main.async {
                if let typed = typed?.trimmingCharacters(in: .whitespacesAndNewlines), !typed.isEmpty, typed != nest.name {
                    if let browser = folders.browser { browser.arranging { nest.name = typed } } else { nest.name = typed }
                }
                if folders.naming == nest.id { folders.naming = nil }
                folders.emptyChanged(nest)
                folders.browser?.writeSession(now: true)
                if clearFocus { NSApp.keyWindow?.makeFirstResponder(nil) }
            }
        }
    }
}
