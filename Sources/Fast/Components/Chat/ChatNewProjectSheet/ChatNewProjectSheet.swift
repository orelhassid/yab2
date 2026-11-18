import AppKit
import SwiftUI

// New Project, as Messages' New Group (docs/chat-projects.md, concept
// state "New Project"): × on glass and ✓ on the accent, its title between, over a big
// circle, a row of emoji for its face and the whole emoji picker behind the
// circle and the row's last face, its name, what its chats are told, and
// the chats to put in it ticked. Created, it opens.

struct ChatNewProjectSheet: View {
    let browser: Browser
    /// The chats ticked as it opens (Move to Project › New Project…).
    @MainActor static var preset: Set<String> = []
    /// The emoji picker out as it opens: the bench's photo of it.
    @MainActor static var presetChoosing = false
    @ObservedObject private var chats = Chats.shared
    @State private var name = ""
    @State private var emoji = Self.faces[0]
    @State private var tint = Projects.nextTint(Projects.shared.all)
    @State private var instructions = ""
    @State private var picked: Set<String> = []
    /// The emoji picker is out, as Change Icon's is for a folder.
    @State private var choosing = false
    @FocusState private var naming: Bool

    /// The faces offered first; any emoji typed in the name's place works too.
    static let faces = ["🧳", "🚀", "🏠", "📚", "💼", "🎨", "📑", "🧪", "🍳", "💪"]

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    Button { choosing = true } label: {
                        ProjectCircle(project: preview, size: Self.circle)
                    }
                    .buttonStyle(.plain)
                    .keyTip("Choose an emoji")
                    .morphs(ProjectMorph.form)
                    .padding(.top, 2)
                    faces
                    TextField("Project Name", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 15, weight: .semibold))
                        .focused($naming)
                        .onSubmit(create)
                        .padding(12)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                    caption("Instructions")
                    TextEditor(text: $instructions)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .scrollDisabled(true)
                        .frame(minHeight: 56)
                        .padding(8)
                        .overlay(alignment: .topLeading) {
                            if instructions.isEmpty {
                                Text("Optional. Who it\u{2019}s for, what to keep in mind, how to answer.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Palette.faint)
                                    .padding(12)
                                    .allowsHitTesting(false)
                            }
                        }
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
                        .padding(.horizontal, 12)
                        .accessibilityLabel("Instructions")
                    if !loose.isEmpty {
                        caption("Add chats")
                        // Lazy: a row is a button, and the name field takes
                        // the keyboard as the form comes, so SwiftUI walks
                        // every focusable row under it; with 2,000 chats
                        // that walk hung the app on each layout pass.
                        LazyVStack(spacing: 0) {
                            ForEach(Array(loose.enumerated()), id: \.element.id) { index, chat in
                                if index > 0 {
                                    Rectangle().fill(Palette.hairline).frame(height: 0.5) // design: the group's row rule, under the words only
                                        .padding(.leading, 54) // design: the rule starts under the words, past the 32 face and its gaps
                                }
                                pick(chat)
                            }
                        }
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: Radius.floating, style: .continuous))
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Palette.ground)
        .onAppear {
            picked = Self.preset
            Self.preset = []
            DispatchQueue.main.async { naming = true }
            if Self.presetChoosing {
                Self.presetChoosing = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { choosing = true }
            }
        }
        .onExitCommand { browser.chatProjectSheet = false }
    }

    /// The project as it will be, for its circle.
    private var preview: Project {
        Project(id: "new", name: name, emoji: emoji, tint: tint, created: Date(), updated: Date(), order: "")
    }

    /// The chats not in a project yet, newest first.
    private var loose: [Chat] {
        chats.all.filter { ($0.archived != true && Projects.shared.project($0.project) == nil) || picked.contains($0.id) }
            .sorted { $0.updated > $1.updated }
    }

    /// Cancel and Create as the chat head's buttons, round: × on Liquid
    /// Glass, ✓ white on the accent, the title in the middle of the bar.
    private var bar: some View {
        ZStack {
            Text("New Project")
                .font(.system(size: 13.5, weight: .semibold))
            HStack {
                Button { browser.chatProjectSheet = false } label: { Symbol("xmark", size: 14) }
                    .buttonStyle(.yab(.glass, .large, icon: .round))
                    .focusable(false)
                    .accessibilityLabel("Cancel")
                    .keyTip("Cancel", keys: "esc")
                Spacer(minLength: 8)
                Button(action: create) { Symbol("checkmark", size: 15, weight: .semibold) }
                    .buttonStyle(.yab(.primary, .large, tint: .accentColor, icon: .round))
                    .focusable(false)
                    .accessibilityLabel("Create")
                    .keyTip("Create", keys: "\u{21A9}")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
    }

    /// The emoji to pick from, the one picked ringed; a click on the
    /// picked one again changes its color. The last opens every emoji,
    /// and wears one picked there.
    private var faces: some View {
        let quick = Array(Self.faces.prefix(6))
        let own = quick.contains(emoji) ? nil : emoji
        return HStack(spacing: 6) {
            ForEach(quick, id: \.self) { face in
                Button {
                    if emoji == face { nextTint() } else { emoji = face }
                } label: {
                    faceTile(face, on: emoji == face)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(face)
            }
            Button {
                choosing = true
            } label: {
                if let own {
                    faceTile(own, on: true)
                } else {
                    Symbol("ellipsis", size: 13, weight: .semibold)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 34, height: 34)
                        .background(Palette.wash, in: Circle())
                        .contentShape(Circle())
                }
            }
            .buttonStyle(.plain)
            .keyTip("All Emoji")
            .accessibilityLabel("All Emoji")
            .popover(isPresented: $choosing, arrowEdge: .bottom) {
                // Change Icon's picker, as a folder's: every emoji
                // searched, these faces first.
                IconPicker(mark: emoji, space: Self.faces, pick: { mark in
                    guard let mark, Spaces.isEmoji(mark) else { return }
                    emoji = mark
                    choosing = false
                }, close: { choosing = false }, emojiOnly: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }

    private func faceTile(_ face: String, on: Bool) -> some View {
        Text(face)
            .font(.system(size: 17))
            .frame(width: 34, height: 34)
            .background(Palette.wash, in: Circle())
            .overlay {
                if on { Circle().strokeBorder(Color.accentColor, lineWidth: 2) }
            }
            .contentShape(Circle())
    }

    private func nextTint() {
        let at = Project.tints.firstIndex(of: tint) ?? 0
        tint = Project.tints[(at + 1) % Project.tints.count]
    }

    private func caption(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12))
            .foregroundStyle(Palette.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private func pick(_ chat: Chat) -> some View {
        let on = picked.contains(chat.id)
        return Button {
            if on { picked.remove(chat.id) } else { picked.insert(chat.id) }
        } label: {
            HStack(spacing: 10) {
                ChatAvatar(chat: chat, size: 32)
                Text(chat.title.isEmpty ? "Chat" : chat.title)
                    .font(.system(size: 13.5))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    if on {
                        Circle().fill(Color.accentColor)
                        Symbol("checkmark", size: 10, weight: .bold)
                            .foregroundStyle(.white)
                    } else {
                        Circle().strokeBorder(Palette.hairline, lineWidth: 1.5) // design: an unticked check ring, as the iPhone draws one, not a card
                    }
                }
                .frame(width: 22, height: 22)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chat.title)
        .accessibilityValue(on ? "selected" : "")
    }

    private func create() {
        guard browser.chatProjectSheet else { return }
        Self.make(name: name, emoji: emoji, tint: tint, instructions: instructions,
             chats: loose.map(\.id).filter(picked.contains), browser: browser)
    }

    /// Made as Create makes it, and opened.
    @discardableResult
    static func make(name: String, emoji: String, tint: String?, instructions: String, chats ids: [String], browser: Browser) -> Project {
        // A face typed as the name's first letter is taken as its emoji.
        var words = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var face = emoji
        if let first = words.first, first.unicodeScalars.first?.properties.isEmojiPresentation == true {
            face = String(first)
            words = String(words.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // The first few stand as big circles over the list, as pinned contacts.
        let project = Projects.shared.add(name: words, emoji: face, tint: tint, instructions: instructions,
                                          pinned: Projects.shared.pinned.count < 3)
        ChatMoves.move(ids, to: project.id)
        ProjectMorph.made(project)
        browser.chatProjectSheet = false
        browser.openProject(project.id)
        return project
    }

    static let circle: CGFloat = 84
}
