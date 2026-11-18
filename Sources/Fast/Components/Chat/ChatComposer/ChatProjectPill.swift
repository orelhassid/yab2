import AppKit
import SwiftUI

// MARK: - the project a new chat begins in

/// "🧳 Lisbon Trip ⇅" in a new chat's field: the project it begins in,
/// which a click changes, or takes it out of any.
struct ChatProjectPill: View {
    let browser: Browser
    let project: Project
    @State private var anchor = ChatViewAnchor()

    var body: some View {
        Button {
            guard let view = anchor.view else { return }
            ActionMenu.show(Self.menu(browser: browser, current: project.id), under: view)
        } label: {
            HStack(spacing: 4) {
                ProjectCircle(project: project, size: 20)
                Text(project.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Symbol("chevron.up.chevron.down", size: 9)
                    .foregroundStyle(Palette.muted)
            }
            .padding(.leading, 4) // design: the circle concentric with the pill's end
            .padding(.trailing, 6) // design: the chevron in from the pill's other end
            .frame(height: 26)
            .background(Palette.wash, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .background(ChatProjectAnchorView(box: anchor))
        .keyTip("Change the project")
        .accessibilityLabel("Project " + project.name)
    }

    static func menu(browser: Browser, current: String) -> NSMenu {
        let menu = NSMenu(title: "Project")
        for project in Projects.shared.listed {
            let item = ClosureItem(ChatMoves.title(project)) { browser.chatNewProject = project.id }
            item.state = project.id == current ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(ClosureItem("No Project") { browser.chatNewProject = nil })
        return menu
    }
}
