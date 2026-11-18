import AppKit
import SwiftUI

// A project's own card, as a contact's in Messages (docs/chat-projects.md,
// concept KGEud9jpw3Rq4Jn9xho4hL, "About Project"): its circle and name, four
// tiles (Chat, Routine, Files, Pinned), then in inset groups what its chats
// are told, what it remembers, its files, and at the foot Archive and Delete.

struct ChatProjectCard: View {
    let browser: Browser
    let project: Project
    @ObservedObject private var chats = Chats.shared
    @ObservedObject private var routines = Routines.shared
    @State private var instructions = ""
    @State private var notes: [String] = []
    @State private var allNotes = false
    @State private var files: [URL] = []
    @FocusState private var writing: Bool

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    top
                    tiles
                    caption("Instructions")
                    group { instructionsCell }
                    caption("Memory")
                    group { memoryCells }
                    caption("Files")
                    group { fileCells }
                    group {
                        cell(project.archived == true ? "Unarchive Project" : "Archive Project") { archive() }
                        rule
                        cell("Delete Project", danger: true) { delete() }
                    }
                    .padding(.top, 20)
                    Text("Its chats go back to Chats.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.faint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
        .onChange(of: project.id) { _, _ in load() }
        .onChange(of: instructions) { _, now in
            guard now != project.instructions else { return }
            guard var changed = Projects.shared.project(project.id) else { return }
            changed.instructions = now
            Projects.shared.update(changed)
        }
        .onExitCommand { if !writing { browser.chatProjectInfo = false } else { writing = false } }
    }

    private func load() {
        instructions = project.instructions
        notes = Memory.projectNotes(project.id)
        files = Self.files(of: project)
    }

    // MARK: the head

    private var bar: some View {
        HStack {
            Button { browser.chatProjectInfo = false } label: { Symbol("chevron.left", size: 15) }
                .buttonStyle(.yab(.glass, ChatHead.button, icon: .round))
                .focusable(false)
                .keyTip(project.name, keys: "esc")
                .accessibilityLabel("Back to " + project.name)
            Spacer(minLength: 0)
            Button { browser.moveChat(open: false) } label: { Symbol("xmark", size: 14) }
                .buttonStyle(.yab(.glass, ChatHead.button, icon: .round))
                .focusable(false)
                .keyTip("Hide Chat", shortcut: "Hide Chat")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }

    private var top: some View {
        VStack(spacing: 6) {
            ProjectCircle(project: project, size: Self.circle)
            Button { rename() } label: {
                Text(project.name)
                    .font(.system(size: 22, weight: .semibold))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .pointerTip("Rename")
            .padding(.top, 4)
            Text(Self.count(chats: chats.of(project: project.id).count,
                            routines: routines.all.filter { $0.project == project.id }.count))
                .font(.system(size: 13))
                .foregroundStyle(Palette.faint)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    /// "5 chats · 1 routine".
    static func count(chats: Int, routines: Int) -> String {
        var out = chats == 1 ? "1 chat" : "\(chats) chats"
        if routines > 0 { out += routines == 1 ? " \u{00B7} 1 routine" : " \u{00B7} \(routines) routines" }
        return out
    }

    /// Chat, Routine, Files, Pinned: the four a contact's card has in its place.
    private var tiles: some View {
        HStack(spacing: 8) {
            tile("Chat", symbol: "square.and.pencil") { browser.newChat(in: project.id) }
            tile("Routine", symbol: "clock.arrow.circlepath") {
                // A routine is a chat said with its when (Routines.phrase).
                browser.newChat(in: project.id)
                browser.chatDraft = "Every morning at 8, "
            }
            tile("Files", symbol: "paperclip") { openFiles() }
            tile(project.pinned ? "Pinned" : "Pin", symbol: project.pinned ? "pin.fill" : "pin") {
                Projects.shared.pin(project.id, !project.pinned)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func tile(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Symbol(symbol, size: 17)
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tile)
            .background(Self.wash, in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
        }
        .buttonStyle(ChatMenuRow())
        .accessibilityLabel(title)
    }

    // MARK: the groups

    private func caption(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12))
            .foregroundStyle(Palette.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    /// An inset group, as Contacts and Settings on the iPhone draw them.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Self.wash, in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
            .padding(.horizontal, 12)
    }

    private var rule: some View {
        Rectangle().fill(Palette.hairline).frame(height: 0.5) // design: the group's row rule, as the iPhone's
            .padding(.leading, 12)
    }

    private func cell(_ title: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(danger ? ButtonCSS.danger : Palette.ink)
                .frame(maxWidth: .infinity, alignment: danger ? .center : .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: Self.row)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// What every chat in it is told first, typed here.
    private var instructionsCell: some View {
        TextEditor(text: $instructions)
            .font(.system(size: 13))
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .focused($writing)
            .frame(minHeight: 60)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .overlay(alignment: .topLeading) {
                if instructions.isEmpty {
                    Text("Optional. Who it\u{2019}s for, what to keep in mind, how to answer.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.faint)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel("Instructions")
    }

    @ViewBuilder
    private var memoryCells: some View {
        HStack {
            Text("Remember from these chats")
                .font(.system(size: 13.5))
            Spacer(minLength: 8)
            Toggle("", isOn: Binding(get: { project.memoryOn }, set: { on in
                var changed = project
                changed.memoryOn = on
                Projects.shared.update(changed)
            }))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: Self.row)
        let shown = allNotes ? notes : Array(notes.prefix(Self.notes))
        ForEach(shown, id: \.self) { note in
            rule
            NoteRow(note: note) {
                Memory.forget(note, project: project.id)
                notes = Memory.projectNotes(project.id)
            }
        }
        if notes.isEmpty, project.memoryOn {
            rule
            Text("What its chats learn comes here.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(minHeight: Self.row)
        }
        if notes.count > Self.notes, !allNotes {
            rule
            Button { allNotes = true } label: {
                Text("Show All \(notes.count)")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(minHeight: Self.row)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var fileCells: some View {
        ForEach(files, id: \.self) { file in
            Button { NSWorkspace.shared.open(file) } label: {
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: file.path))
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text(file.lastPathComponent)
                        .font(.system(size: 13.5))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.size(file))
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.faint)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: Self.row)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .steadyMenu {
                Button("Show in Finder", mark: "folder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
                Button("Remove from Project", mark: "trash", role: .destructive) {
                    try? FileManager.default.trashItem(at: file, resultingItemURL: nil)
                    files = Self.files(of: project)
                }
            }
            rule
        }
        Button { addFiles() } label: {
            HStack(spacing: 10) {
                Symbol("plus", size: 13)
                    .frame(width: 24, height: 24)
                    .foregroundStyle(Palette.muted)
                Text("Add Files")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Color.accentColor)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: Self.row)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: doing

    private func rename() { ChatProjectCommands.rename(project) }

    private func archive() {
        let on = project.archived != true
        Projects.shared.archive(project.id, on)
        if on { browser.openProject(nil) }
    }

    private func delete() { ChatProjectCommands.delete(project, in: browser) }

    private func openFiles() {
        try? FileManager.default.createDirectory(at: project.files, withIntermediateDirectories: true)
        NSWorkspace.shared.open(project.files)
    }

    /// Files picked, copied in: every chat in it can read them.
    private func addFiles() {
        ChatProjectCommands.addFiles(project) { files = Self.files(of: project) }
    }

    static func files(of project: Project) -> [URL] {
        let found = (try? FileManager.default.contentsOfDirectory(at: project.files, includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles])) ?? []
        return found.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    static func size(_ file: URL) -> String {
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static let circle: CGFloat = 92
    static let tile: CGFloat = 62
    static let row: CGFloat = 44
    /// The facts shown before Show All.
    static let notes = 3
    /// The groups' gray, as the concept's wash.
    static let wash = Palette.wash
}

/// One fact the project keeps, a minus to forget it under the pointer.
private struct NoteRow: View {
    let note: String
    let forget: () -> Void
    @State private var over = false

    var body: some View {
        HStack(spacing: 8) {
            Text(note)
                .font(.system(size: 13.5))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: forget) { Symbol("minus.circle.fill", size: 14) }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(ButtonCSS.danger)
                .opacity(over ? 1 : 0)
                .keyTip("Forget")
                .accessibilityLabel("Forget")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: ChatProjectCard.row)
        .contentShape(Rectangle())
        .onHover { over = $0 }
    }
}
