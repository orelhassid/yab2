import AppKit

/// Only the keyboard is borrowed by the column. Widths, sidebar settings
/// and the window frame stay live while it is open.
@MainActor
final class ChatRestoration {
    private weak var window: NSWindow?
    private weak var responder: NSView?
    private let page: Tab.ID?
    private let field: Bool
    private let selection: NSRange?
    private let words: String?

    init(in window: NSWindow?, page: Tab.ID?, field: Bool) {
        self.window = window
        self.page = page
        self.field = field
        let view = window?.firstResponder as? NSView
        if let editor = view as? NSTextView, editor.isFieldEditor {
            responder = editor.delegate as? NSView
            selection = editor.selectedRange()
            words = editor.string
        } else {
            responder = view
            selection = nil
            words = nil
        }
    }

    /// A shared field editor may now belong to chat. Restore its control,
    /// and its selection only if the original words are still there.
    func restore(in window: NSWindow?, page: Tab.ID?, field: Bool) -> Bool {
        guard self.page == page, self.field == field, let window, self.window === window, let responder,
              responder.window === window, !responder.isHiddenOrHasHiddenAncestor,
              window.makeFirstResponder(responder) else { return false }
        if let selection, let editor = (responder as? NSTextField)?.currentEditor() as? NSTextView,
           editor.string == words, NSMaxRange(selection) <= editor.string.utf16.count {
            editor.setSelectedRange(selection)
        }
        return true
    }
}
