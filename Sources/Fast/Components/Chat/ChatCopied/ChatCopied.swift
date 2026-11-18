import AppKit
import SwiftUI

// Under an answer that put something on the clipboard (copy, AgentClip):
// "Copied · 14 addresses" in words, and Copy Again (⌘C) to put it back
// once something else took the clipboard. Nothing changes size when it is
// pressed: the button keeps the width of its longer words.

extension ChatItem {
    /// The steps of the last turn: what came after the last thing asked.
    static func lastTurn(_ items: [ChatItem]) -> ArraySlice<ChatItem> {
        let start = items.lastIndex { $0.kind == .asked && !$0.isInternalContinuation }.map { $0 + 1 } ?? items.startIndex
        return items[start...]
    }

    /// The clip a chat's last turn copied, for ⌘C in its field.
    static func lastClip(_ items: [ChatItem]) -> String? {
        copied(in: Array(lastTurn(items)))?.clip
    }
}

extension AgentClips {
    /// Copy Again pressed, by the button or ⌘C: the clip back on the
    /// clipboard, and its button says Copied for a moment.
    func pressAgain(_ id: String) -> Bool {
        guard again(id) else { return false }
        NotificationCenter.default.post(name: Self.pressed, object: id)
        return true
    }

    static let pressed = Notification.Name("yab.agentClipPressed")
}

/// "Copied · 14 addresses", and Copy Again with its key.
struct ChatCopiedLine: View {
    let what: String
    let clip: String?
    /// The answer card has Copy Again among its own buttons.
    var button = true

    var body: some View {
        HStack(spacing: 8) {
            Text("Copied · " + what)
                .font(.system(size: 12))
                .foregroundStyle(Palette.muted)
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
            if button, let clip, AgentClips.shared.clip(clip) != nil {
                ChatCopyAgain(clip: clip)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Copy Again: the clip back on the clipboard; says Copied for a moment,
/// in the width it had.
struct ChatCopyAgain: View {
    let clip: String
    var kind: ButtonKind = .secondary
    @State private var done = false

    var body: some View {
        Button { _ = AgentClips.shared.pressAgain(clip) } label: {
            AgentAnswer.label(done ? "Copied" : "Copy Again", .answerCopy, holding: "Copy Again")
        }
        .buttonStyle(.yab(kind, .small))
        .focusable(false)
        .onReceive(NotificationCenter.default.publisher(for: AgentClips.pressed)) { note in
            guard note.object as? String == clip else { return }
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { done = false }
        }
    }
}
