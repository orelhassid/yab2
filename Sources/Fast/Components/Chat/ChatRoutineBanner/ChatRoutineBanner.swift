import AppKit
import SwiftUI

// MARK: - a routine's news

/// What a routine found, as an iPhone notice comes in at the column's top
/// (concept state "Routine News"): its project's circle, the routine's
/// name and project, and the finding itself; a click opens its chat.
@MainActor
final class ChatBanners: ObservableObject {
    static let shared = ChatBanners()

    struct Banner: Equatable, Identifiable {
        let id = UUID()
        let chat: String
        let project: String?
        let title: String
        let body: String
    }

    @Published private(set) var shown: Banner?
    private var hush: DispatchWorkItem?

    /// How long it stays unless the pointer is on it.
    static let stay: TimeInterval = 8

    func show(_ banner: Banner) {
        withAnimation(Motion.chatIn) { shown = banner }
        hold(false)
    }

    /// The pointer on it keeps it; off, it goes after a while.
    func hold(_ on: Bool) {
        hush?.cancel()
        guard !on else { return }
        let id = shown?.id
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.shown?.id == id else { return }
            self.dismiss()
        }
        hush = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stay, execute: work)
    }

    func dismiss() {
        hush?.cancel()
        withAnimation(Motion.leave) { shown = nil }
    }
}

struct ChatRoutineBanner: View {
    let browser: Browser
    let banner: ChatBanners.Banner

    var body: some View {
        let project = Projects.shared.project(banner.project)
        Button {
            ChatBanners.shared.dismiss()
            browser.showChat(banner.chat)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let project {
                    ProjectCircle(project: project, size: 38)
                } else {
                    Symbol("clock.arrow.circlepath", size: 17)
                        .foregroundStyle(Palette.muted)
                        .frame(width: 38, height: 38)
                        .background(Palette.wash, in: Circle())
                }
                VStack(alignment: .leading, spacing: 1) {
                    (Text(banner.title).fontWeight(.semibold) + Text(project.map { " \u{00B7} " + $0.name } ?? ""))
                        .lineLimit(1)
                    Text(banner.body)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("now")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.faint)
            }
            // Solid, not glass: it lies over the project's head, whose
            // circle and buttons read through clear glass (the concept's
            // notice is frosted thick).
            .cardFrame()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { ChatBanners.shared.hold($0) }
        .accessibilityLabel(banner.title + ". " + banner.body)
    }
}
