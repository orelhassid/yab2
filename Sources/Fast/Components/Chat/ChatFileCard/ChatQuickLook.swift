import AppKit
import SwiftUI
import Quartz

// MARK: - Quick Look

/// Quick Look on a card's file (Space over it). The panel takes as its
/// controller the first in the keyboard's line that will have it: the
/// card's still view steps into that place while it is up, and the chat's
/// field takes the keyboard back after.
@MainActor
final class ChatQuickLook: NSObject, QLPreviewPanelDataSource {
    static let shared = ChatQuickLook()
    /// What the panel shows, ← and → walking it, and where it is.
    private(set) var items: [URL] = []
    private var at = 0
    var item: URL? { items.indices.contains(at) ? items[at] : nil }
    weak var anchor: ChatQuickLookAnchor?

    func toggle(_ url: URL) { show([url], at: 0) }

    /// Pictures of a turn, Quick Look's own panel over Yab, from `index`.
    func show(_ urls: [URL], at index: Int) {
        let panel = QLPreviewPanel.shared()!
        let url = urls.indices.contains(index) ? urls[index] : nil
        if panel.isVisible, item == url, items == urls {
            panel.close()
            return
        }
        items = urls
        at = max(0, min(index, urls.count - 1))
        if panel.isVisible, panel.dataSource === self {
            panel.reloadData()
            panel.currentPreviewItemIndex = at
            return
        }
        if let anchor, let window = anchor.window { window.makeFirstResponder(anchor) }
        // No anchor in the window's line (a picture in a chat): the panel
        // takes this as its source itself.
        if panel.dataSource == nil || !(panel.dataSource is ChatQuickLook) { panel.dataSource = self }
        panel.makeKeyAndOrderFront(nil)
        panel.reloadData()
        panel.currentPreviewItemIndex = at
    }

    func ended() {
        items = []
        BrowserWindows.shared.activeBrowser?.chatFocus += 1
        // Control went elsewhere with the panel up: it stayed, empty
        // ("No items selected"), off where it was.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard QLPreviewPanel.sharedPreviewPanelExists(), let panel = QLPreviewPanel.shared(),
                      panel.isVisible, panel.dataSource == nil else { return }
                panel.orderOut(nil)
            }
        }
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { items.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { items.indices.contains(index) ? items[index] as NSURL : nil }
    }
}

final class ChatQuickLookAnchor: NSView {
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated { if window != nil { ChatQuickLook.shared.anchor = self } }
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = ChatQuickLook.shared
            panel.reloadData()
        }
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel.dataSource = nil
            ChatQuickLook.shared.ended()
        }
    }
}

struct ChatQuickLookAnchorView: NSViewRepresentable {
    func makeNSView(context: Context) -> ChatQuickLookAnchor { ChatQuickLookAnchor() }
    func updateNSView(_ view: ChatQuickLookAnchor, context: Context) {}
}
