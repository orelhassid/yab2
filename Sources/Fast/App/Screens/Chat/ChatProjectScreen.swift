import AppKit
import SwiftUI

// A project of chats open in the column, as a group chat in Messages
// (docs/chat-projects.md): its circle and name over its chats in rows, and
// at the foot a field for a new chat in it. Its name opens its own card.

struct ChatProjectScreen: View {
    let browser: Browser
    let project: Project
    @ObservedObject private var chats = Chats.shared
    @State private var words = ""
    @FocusState private var focused: Bool
    /// Its own card is out in its place (ChatProjectCard).
    @State private var info = false

    var body: some View {
        ZStack(alignment: .top) {
            if info {
                ChatProjectCard(browser: browser, project: project)
                    .transition(ChatColumn.haze(depth: 1.03))
            } else {
                list.transition(ChatColumn.haze(depth: 0.97))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onExitCommand { browser.openProject(nil) }
        .onAppear {
            info = browser.chatProjectInfo
            ChatSwipe.shared.watch()
        }
        .onDisappear { ChatSwipe.shared.unwatch() }
        // The column's keys go to its field, as they go to a chat's.
        .onReceive(browser.changes(\.chatFocus).dropFirst()) { _ in
            DispatchQueue.main.async { if !info { focused = true } }
        }
        .onReceive(browser.changes(\.chatProjectInfo)) { _ in
            DispatchQueue.main.async { info = browser.chatProjectInfo }
        }
    }

    private var list: some View {
        let mine = chats.of(project: project.id).sorted { a, b in a.pinned != b.pinned ? a.pinned : a.updated > b.updated }
        return VStack(spacing: 0) {
            if mine.isEmpty { empty } else { head }
            if !mine.isEmpty { ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(mine, id: \.listed) { chat in
                        ChatHistoryRow(browser: browser, chat: chat, below: [], done: {})
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(ChatCards.space)) } action: { frame in
                // A row scrolled out of it has nowhere to zoom from (ChatCards.card).
                ChatCards.shown = frame.minY...max(frame.minY, frame.maxY)
                ChatCards.width = frame.width
            } }
            field
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// A project with no chat in it: its circle stays as big as the form
    /// had it, its name and instructions under, what it can hold in three
    /// tiles, and the field waiting for the first chat. The circle goes up
    /// into the head with the first chat sent.
    private var empty: some View {
        VStack(spacing: 0) {
            HStack {
                Button { browser.openProject(nil) } label: { Symbol("chevron.left", size: 15) }
                    .buttonStyle(.yab(.glass, ChatHead.button, icon: .round))
                    .focusable(false)
                    .keyTip("Chats", keys: "esc")
                    .accessibilityLabel("Back to Chats")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            ProjectCircle(project: project, size: Self.bigCircle)
                .morphs(ProjectMorph.id(project))
                .padding(.top, 8)
            Button { browser.chatProjectInfo = true } label: {
                Text(project.name)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .padding(.top, 12)
            .padding(.horizontal, 24)
            .accessibilityLabel(project.name + ", about the project")
            Text(project.instructions.isEmpty ? "Chats you start here share its instructions and memory." : project.instructions)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.top, 4)
                .padding(.horizontal, 32)
            HStack(spacing: 8) {
                tile("Files", mark: "paperclip")
                tile("Routine", mark: "clock")
                tile("Instructions", mark: "doc.text")
            }
            .padding(.top, 16)
            .padding(.horizontal, 12)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .onAppear { DispatchQueue.main.async { focused = true } }
    }

    /// One thing the project holds, opening its card.
    private func tile(_ title: String, mark: String) -> some View {
        Button { browser.chatProjectInfo = true } label: {
            VStack(spacing: 4) {
                Symbol(mark, size: 15)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Back, its circle and name, and New Chat in it.
    private var head: some View {
        ZStack(alignment: .top) {
            HStack {
                Button { browser.openProject(nil) } label: { Symbol("chevron.left", size: 15) }
                    .buttonStyle(.yab(.glass, ChatHead.button, icon: .round))
                    .focusable(false)
                    .keyTip("Chats", keys: "esc")
                    .accessibilityLabel("Back to Chats")
                Spacer(minLength: 0)
                Button { browser.newChat(in: project.id) } label: { Symbol("square.and.pencil", size: 15) }
                    .buttonStyle(.yab(.glass, ChatHead.button, icon: .round))
                    .focusable(false)
                    .keyTip("New Chat in " + project.name)
            }
            VStack(spacing: 6) {
                ProjectCircle(project: project, size: Self.circle)
                    .morphs(ProjectMorph.id(project))
                Button { browser.chatProjectInfo = true } label: {
                    HStack(spacing: 4) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Symbol("chevron.right", size: 9, weight: .semibold)
                            .foregroundStyle(Palette.faint)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel(project.name + ", about the project")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline).frame(height: 0.5) // design: the group's head rule, as Messages'
        }
    }

    /// "New chat in Lisbon Trip": what is typed and sent is a new chat in it.
    private var field: some View {
        let ready = !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            TextField("New chat in " + project.name, text: $words)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .focused($focused)
                .onSubmit(send)
                .onExitCommand { if words.isEmpty { browser.openProject(nil) } else { words = "" } }
            Button(action: send) { Symbol("arrow.up", size: 13) }
                .buttonStyle(.yab(.primary, .small, tint: .accentColor, icon: .round))
                .focusable(false)
                .disabled(!ready)
                .opacity(ready ? 1 : 0.35)
                .keyTip("New Chat", keys: "\u{21A9}")
        }
        .padding(.leading, 12) // design: the words in from the pill's curve
        .padding(.trailing, 6) // design: the round button concentric with the pill's end
        .frame(height: 36)
        .background { FieldGlass(shape: Capsule()) }
        .contentShape(Capsule())
        .onTapGesture { focused = true }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private func send() {
        let text = words.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard ChatComposer.begin(text, with: [], in: browser, project: project.id) != nil else { return }
        words = ""
    }

    static let circle: CGFloat = 56
    static let bigCircle: CGFloat = 96
}
