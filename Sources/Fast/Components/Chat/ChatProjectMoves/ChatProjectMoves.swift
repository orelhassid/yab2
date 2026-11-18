import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Putting a chat in a project (docs/chat-projects.md, concept states
// "Swipe", "Long Press", "Move to Project"): a row's right click with
// Move to Project › and its list of projects, ⌃⌘P on the chat in the
// column, two fingers across a row for Project, Pin and Archive, or the
// row dragged onto a project's circle. Every way ends in ChatMoves.move.

@MainActor
enum ChatMoves {
    /// Into a project, or out of one; a routine's chat takes its routine
    /// with it, so its next run lands there too.
    static func move(_ ids: [String], to project: String?) {
        let target = project.flatMap { Projects.shared.project($0)?.id }
        guard project == nil || target != nil else { return }
        for id in ids {
            if let routine = Routines.shared.all.first(where: { $0.chat == id }) {
                Routines.shared.move(routine.id, to: target)
            }
        }
        Chats.shared.move(ids, to: target)
    }

    /// "🧳  Lisbon Trip": a project's emoji before its name, as a space's
    /// is in a menu (ActionMenu draws it in the marks' column).
    static func title(_ project: Project) -> String { project.emoji + "  " + project.name }

    /// The menu for ⌃⌘P and a row's Project button: every project, a tick
    /// on the one it is in, then New Project… and Remove from Project.
    static func menu(for chat: Chat, browser: Browser) -> NSMenu {
        let menu = NSMenu(title: "Move to Project")
        for project in Projects.shared.listed {
            let item = ClosureItem(title(project)) { move([chat.id], to: project.id) }
            item.state = chat.project == project.id ? .on : .off
            menu.addItem(item)
        }
        if !Projects.shared.listed.isEmpty { menu.addItem(.separator()) }
        let new = ClosureItem("New Project\u{2026}") { newProject(with: [chat.id], browser: browser) }
        new.image = MenuMark.image("folder.badge.plus")
        menu.addItem(new)
        if Projects.shared.project(chat.project) != nil {
            let out = ClosureItem("Remove from Project") { move([chat.id], to: nil) }
            out.image = MenuMark.image("folder")
            menu.addItem(out)
        }
        return menu
    }

    /// New Project's sheet, these chats ticked in it.
    static func newProject(with ids: [String], browser: Browser) {
        ChatNewProjectSheet.preset = Set(ids)
        if !browser.chatOpen { browser.moveChat(open: true) }
        if !browser.chatHistory { browser.chatHistory = true }
        browser.chatProjectSheet = true
    }

    /// ⌃⌘P: the chat in the column, its menu under the head.
    static func ask(in browser: Browser) {
        guard browser.chatOpen, !browser.chatHistory, let chat = Chats.shared.chat(browser.chatID),
              let column = browser.chatColumnView, let window = column.window else { return }
        let frame = window.convertToScreen(column.convert(column.bounds, to: nil))
        // Under the chat's name, as its ⋯ menu stands under ⋯.
        let at = NSPoint(x: frame.midX - 110, y: frame.maxY - ChatHead.height)
        ActionMenu.show(menu(for: chat, browser: browser), in: window, at: at)
    }

    /// What a row carries when it is dragged: its chat's id, for a circle.
    static let dragPrefix = "yab-chat:"

    static func dragged(_ chat: Chat) -> NSItemProvider {
        NSItemProvider(object: (dragPrefix + chat.id) as NSString)
    }

    /// A row let go over a project's circle or row: it goes in.
    static func drop(_ providers: [NSItemProvider], on project: String) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { text, _ in
            guard let text = text as? String, text.hasPrefix(dragPrefix) else { return }
            let id = String(text.dropFirst(dragPrefix.count))
            DispatchQueue.main.async {
                MainActor.assumeIsolated { move([id], to: project) }
            }
        }
        return true
    }
}

/// An NSMenuItem that runs a closure.
final class ClosureItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}

/// The right click's Move to Project ›, its projects and New Project….
struct ChatMoveMenu: View {
    let browser: Browser
    let chat: Chat

    var body: some View {
        Menu("Move to Project", mark: "folder") {
            ForEach(Projects.shared.listed) { project in
                Button(ChatMoves.title(project)) { ChatMoves.move([chat.id], to: project.id) }
                    .disabled(chat.project == project.id)
            }
            if !Projects.shared.listed.isEmpty { Divider() }
            Button("New Project\u{2026}", mark: "folder.badge.plus") { ChatMoves.newProject(with: [chat.id], browser: browser) }
            if Projects.shared.project(chat.project) != nil {
                Button("Remove from Project", mark: "folder") { ChatMoves.move([chat.id], to: nil) }
            }
        }
    }
}

// MARK: - two fingers across a row

/// A row slid open by two fingers across it, as Messages' rows are: Project,
/// Pin and Archive under it. One row at a time; a press anywhere shuts it.
@MainActor
final class ChatSwipe: ObservableObject {
    static let shared = ChatSwipe()

    /// The row slid, and how far (negative: to the left).
    @Published private(set) var id: String?
    @Published private(set) var offset: CGFloat = 0
    /// Each row's own view, to find the one under the fingers.
    var rows: [String: ChatViewAnchor] = [:]
    private var tracking: String?
    private var monitor: Any?
    private var watchers = 0

    static let button: CGFloat = 66
    static let width: CGFloat = button * 3

    func shut() {
        guard id != nil else { return }
        withAnimation(Motion.chatQuick) { offset = 0; id = nil }
    }

    /// Watched while a list of rows is out.
    func watch() {
        watchers += 1
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.take(event) }
        }
    }

    func unwatch() {
        watchers = max(0, watchers - 1)
        guard watchers == 0, let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        tracking = nil
        offset = 0
        id = nil
    }

    private func row(at event: NSEvent) -> String? {
        rows.first { _, box in
            guard let view = box.view, view.window === event.window else { return false }
            return view.bounds.contains(view.convert(event.locationInWindow, from: nil))
        }?.key
    }

    private func take(_ event: NSEvent) -> NSEvent? {
        if event.type == .leftMouseDown {
            // A press on the open row's buttons is theirs; anywhere else shuts it.
            if let id, row(at: event) != id { shut() }
            return event
        }
        // Momentum after the fingers left: the row has settled already.
        if event.momentumPhase != [] { return tracking != nil ? nil : event }
        switch event.phase {
        case .began:
            tracking = nil
            return event
        case .changed:
            if tracking == nil {
                // Across, not down the list, and over a row.
                guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5, let hit = row(at: event) else {
                    if id != nil, abs(event.scrollingDeltaY) > 2 { shut() }
                    return event
                }
                tracking = hit
                if id != hit { offset = 0 }
                id = hit
            }
            let next = offset + event.scrollingDeltaX
            // Past the buttons it gives, as a rubber band.
            offset = next < -Self.width ? -Self.width + (next + Self.width) / 3 : min(0, next)
            return nil
        case .ended, .cancelled:
            guard tracking != nil else { return event }
            tracking = nil
            withAnimation(Motion.chatQuick) {
                if offset < -Self.width / 2 { offset = -Self.width } else { offset = 0; id = nil }
            }
            return nil
        default:
            return event
        }
    }

    /// Slid open, as the fingers would (the bench's).
    func open(_ chat: String) {
        withAnimation(Motion.chatQuick) { id = chat; offset = -Self.width }
    }
}

/// Project, Pin and Archive under a slid row, in Messages' colors.
struct ChatSwipeActions: View {
    let browser: Browser
    let chat: Chat
    let shown: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            action("Project", symbol: "folder", color: Color(red: 0x5E / 255.0, green: 0x5C / 255.0, blue: 0xE6 / 255.0)) { view in
                ChatSwipe.shared.shut()
                if let view { ActionMenu.show(ChatMoves.menu(for: chat, browser: browser), under: view) }
            }
            action(chat.pinned ? "Unpin" : "Pin", symbol: chat.pinned ? "pin.slash" : "pin",
                   color: Color(red: 1, green: 0x9F / 255.0, blue: 0x0A / 255.0)) { _ in
                ChatSwipe.shared.shut()
                Chats.shared.pin(chat.id, !(Chats.shared.chat(chat.id)?.pinned ?? chat.pinned))
            }
            action("Archive", symbol: "archivebox", color: Color(red: 0x8E / 255.0, green: 0x8E / 255.0, blue: 0x93 / 255.0)) { _ in
                ChatSwipe.shared.shut()
                ChatColumn.putAway(chat, browser: browser)
            }
        }
        .frame(width: max(shown, 0), alignment: .trailing)
        .clipped()
    }

    private func action(_ title: String, symbol: String, color: Color, run: @escaping (NSView?) -> Void) -> some View {
        SwipeButton(title: title, symbol: symbol, color: color, run: run)
            .frame(width: max(ChatSwipe.button, shown / 3))
    }
}

/// One of a slid row's buttons; it knows its own view, for a menu under it.
private struct SwipeButton: View {
    let title: String
    let symbol: String
    let color: Color
    let run: (NSView?) -> Void
    @State private var anchor = ChatViewAnchor()

    var body: some View {
        Button { run(anchor.view) } label: {
            VStack(spacing: 4) {
                Symbol(symbol, size: 15)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(ChatProjectAnchorView(box: anchor))
        .accessibilityLabel(title)
    }
}

final class ChatViewAnchor {
    weak var view: NSView?
}

struct ChatProjectAnchorView: NSViewRepresentable {
    let box: ChatViewAnchor

    func makeNSView(context: Context) -> NSView {
        let view = PassView()
        box.view = view
        return view
    }

    /// Only a place to measure from: every press goes through it.
    final class PassView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func updateNSView(_ view: NSView, context: Context) { box.view = view }
}

extension View {
    /// A project's circle or row takes a chat's row let go over it.
    func takesChats(into project: String, over: Binding<Bool>) -> some View {
        onDrop(of: [.plainText, .utf8PlainText], isTargeted: over) { providers in
            ChatMoves.drop(providers, on: project)
        }
    }
}
