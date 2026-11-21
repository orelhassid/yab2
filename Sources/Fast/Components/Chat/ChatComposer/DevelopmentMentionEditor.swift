import AppKit
import SwiftUI

/// An inline mention occupies one editable character. Its display name and
/// the context it refers to travel together through editing and undo.
private final class MentionAttachment: NSTextAttachment {
    let mention: DevelopmentMention

    init(_ mention: DevelopmentMention) {
        self.mention = mention
        super.init(data: nil, ofType: nil)
        attachmentCell = MentionCell(mention)
    }

    required init?(coder: NSCoder) { nil }
}

private final class MentionCell: NSTextAttachmentCell {
    private let mention: DevelopmentMention
    private let labelFont = NSFont.systemFont(ofSize: 13.5, weight: .medium)

    init(_ mention: DevelopmentMention) {
        self.mention = mention
        super.init(textCell: "")
        setAccessibilityLabel(mention.name)
    }

    required init(coder: NSCoder) { fatalError("Mentions are made by the composer") }

    override func cellSize() -> NSSize {
        let width = (mention.name as NSString).size(withAttributes: [.font: labelFont]).width
        return NSSize(width: min(190, ceil(width) + 28), height: 20)
    }

    override func cellBaselineOffset() -> NSPoint { NSPoint(x: 0, y: -4) }

    override func draw(withFrame frame: NSRect, in controlView: NSView?) {
        let dark = controlView?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let tint = mention.badge.tint.mentionInk(dark: dark)
        let wash = mention.badge.tint.wash(dark: dark)
        NSColor(wash).setFill()
        NSBezierPath(roundedRect: frame.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
        let icon = Glyphs.art(mention.symbol) ?? NSImage(systemSymbolName: mention.symbol, accessibilityDescription: nil)
        if let icon {
            let rect = NSRect(x: frame.minX + 5, y: frame.midY - 7, width: 14, height: 14)
            if let context = NSGraphicsContext.current?.cgContext {
                context.beginTransparencyLayer(auxiliaryInfo: nil)
                icon.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                tint.setFill()
                rect.fill(using: .sourceIn)
                context.endTransparencyLayer()
            }
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (mention.name as NSString).draw(in: NSRect(x: frame.minX + 22, y: frame.midY - 8, width: frame.width - 26, height: 17),
                                       withAttributes: [.font: labelFont, .foregroundColor: tint, .paragraphStyle: paragraph])
    }
}

extension FolderTint {
    func mentionInk(dark: Bool) -> NSColor {
        let color = NSColor(ink(dark: dark))
        return dark ? color.blended(withFraction: 0.33, of: .white) ?? color : color
    }
}

struct DevelopmentMentionToken: Equatable {
    let query: String
    let range: NSRange

    private static let prefix = try! NSRegularExpression(pattern: #"(?<![^\s\uFFFC])@([^\s@\uFFFC]*)\z"#)

    static func at(_ selection: NSRange, in text: String) -> Self? {
        let words = text as NSString
        guard selection.length == 0, selection.location <= words.length,
              let match = prefix.firstMatch(in: words.substring(to: selection.location), range: NSRange(location: 0, length: selection.location)) else {
            return nil
        }
        return Self(query: words.substring(with: match.range(at: 1)), range: match.range)
    }
}

@MainActor
enum DevelopmentDraft {
    static func chip(_ mention: DevelopmentMention) -> NSAttributedString {
        NSAttributedString(attachment: MentionAttachment(mention))
    }

    static func mentioned(in draft: NSAttributedString) -> [DevelopmentMention] {
        var mentions: [DevelopmentMention] = []
        draft.enumerateAttribute(.attachment, in: NSRange(location: 0, length: draft.length)) { value, _, _ in
            if let tag = value as? MentionAttachment { mentions.append(tag.mention) }
        }
        return mentions
    }

    static func plain(_ draft: NSAttributedString) -> String {
        message(draft).text
    }

    static func message(_ draft: NSAttributedString) -> (text: String, spans: [ChatMentionSpan]) {
        let text = NSMutableString(string: draft.string)
        var spans: [ChatMentionSpan] = []
        var delta = 0
        draft.enumerateAttribute(.attachment, in: NSRange(location: 0, length: draft.length)) { value, range, _ in
            guard let tag = value as? MentionAttachment else { return }
            let name = "@" + tag.mention.name
            let count = (name as NSString).length
            let location = range.location + delta
            text.replaceCharacters(in: NSRange(location: location, length: range.length), with: name)
            spans.append(ChatMentionSpan(location: location, length: count, tint: tag.mention.badge.tint.rawValue))
            delta += count - range.length
        }
        return (text as String, spans)
    }
}

@MainActor
struct DevelopmentMentionEditor: NSViewRepresentable {
    let draft: NSAttributedString
    let tone: Tone?
    let placeholder: String
    let changed: (NSAttributedString) -> Void
    let moved: (DevelopmentMentionToken?) -> Void
    let focused: (Bool) -> Void
    let keyDown: (NSEvent) -> Bool
    let handle: Handle

    @MainActor final class Handle {
        fileprivate weak var editor: Editor?

        func focus() {
            if let editor { editor.window?.makeFirstResponder(editor) }
        }

        func insert(_ mention: DevelopmentMention, replacing range: NSRange?) {
            guard let editor else { return }
            var target = range ?? editor.selectedRange()
            let text = editor.string as NSString
            guard NSMaxRange(target) <= text.length else { return }
            if NSMaxRange(target) < text.length, text.character(at: NSMaxRange(target)) == 32 { target.length += 1 }
            focus()
            let insertion = NSMutableAttributedString(attributedString: DevelopmentDraft.chip(mention))
            insertion.append(NSAttributedString(string: " ", attributes: editor.typingAttributes))
            editor.insertText(insertion, replacementRange: target)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let editor = Editor(usingTextLayoutManager: false)
        editor.isRichText = true
        editor.allowsUndo = true
        editor.drawsBackground = false
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.widthTracksTextView = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.delegate = context.coordinator
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = editor
        handle.editor = editor
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let editor = scroll.documentView as? Editor else { return }
        let coordinator = context.coordinator
        coordinator.changed = changed
        coordinator.moved = moved
        coordinator.focused = focused
        editor.onKeyDown = keyDown
        editor.setAccessibilityLabel(placeholder)
        if coordinator.kept != draft || coordinator.tone != tone {
            let isNewDraft = coordinator.kept != draft
            editor.appearance = tone?.appearance
            let color = tone.map { Palette.shades($0).strongNS } ?? NSColor.labelColor
            let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: color]
            let content = NSMutableAttributedString(attributedString: draft)
            content.addAttributes(style, range: NSRange(location: 0, length: content.length))
            let caret = isNewDraft ? NSRange(location: content.length, length: 0) : editor.selectedRange()
            coordinator.updating = true
            editor.textStorage?.setAttributedString(content)
            editor.typingAttributes = style
            editor.insertionPointColor = color
            editor.setSelectedRange(caret)
            coordinator.updating = false
            if isNewDraft { editor.edits.removeAllActions() }
            coordinator.kept = draft
            coordinator.tone = tone
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, let editor = nsView.documentView as? Editor,
              let layout = editor.layoutManager, let container = editor.textContainer else { return nil }
        let size = NSSize(width: width, height: .greatestFiniteMagnitude)
        if container.containerSize != size { container.containerSize = size }
        layout.ensureLayout(for: container)
        let height = max(layout.usedRect(for: container).maxY, layout.extraLineFragmentRect.maxY)
        return CGSize(width: width, height: min(160, max(30, ceil(height))))
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var kept: NSAttributedString?
        var tone: Tone?
        var changed: ((NSAttributedString) -> Void)?
        var moved: ((DevelopmentMentionToken?) -> Void)?
        var focused: ((Bool) -> Void)?
        var updating = false

        func textDidBeginEditing(_ note: Notification) {
            focused?(true)
        }

        func textDidEndEditing(_ note: Notification) {
            focused?(false)
            moved?(nil)
        }

        func textDidChange(_ note: Notification) {
            guard let editor = note.object as? Editor else { return }
            let draft = NSAttributedString(attributedString: editor.attributedString())
            kept = draft
            changed?(draft)
            selection(editor)
        }

        func textViewDidChangeSelection(_ note: Notification) {
            guard let editor = note.object as? Editor else { return }
            selection(editor)
        }

        private func selection(_ editor: Editor) {
            guard !updating, editor.window?.firstResponder === editor else { return }
            moved?(DevelopmentMentionToken.at(editor.selectedRange(), in: editor.string))
        }

        func undoManager(for view: NSTextView) -> UndoManager? { (view as? Editor)?.edits }
    }

    final class Editor: NSTextView {
        let edits = UndoManager()
        var onKeyDown: ((NSEvent) -> Bool)?

        override func keyDown(with event: NSEvent) {
            if !hasMarkedText(), onKeyDown?(event) == true { return }
            super.keyDown(with: event)
        }

        override func paste(_ sender: Any?) { pasteAsPlainText(sender) }

        override func copy(_ sender: Any?) {
            let draft = attributedString().attributedSubstring(from: selectedRange())
            guard !DevelopmentDraft.mentioned(in: draft).isEmpty else { super.copy(sender); return }
            let board = NSPasteboard.general
            board.clearContents()
            board.setString(DevelopmentDraft.plain(draft), forType: .string)
        }
    }
}
