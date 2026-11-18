import Foundation
import Observation
import SwiftUI
#if canImport(SyncKit)
import SyncKit
#endif

/// A project of chats, as the Mac keeps it (Sources/Fast/Services/Chat/Projects.swift,
/// docs/chat-projects.md): a circle with an emoji, a name, its color, the
/// instructions its chats are told. The iPhone reads projects from sync and
/// writes none in v1: instructions and memory are edited on the Mac.
struct ChatProject: Identifiable, Hashable, Sendable {
    typealias ID = String

    var id: ID
    var name: String
    var emoji: String
    /// blue, green, orange, purple, pink, yellow, teal or gray.
    var tint: String
    var instructions: String
    var memoryOn: Bool
    var pinned: Bool
    var archived: Bool

    init(id: ID, name: String, emoji: String, tint: String = "blue", instructions: String = "",
         memoryOn: Bool = true, pinned: Bool = false, archived: Bool = false) {
        self.id = id; self.name = name; self.emoji = emoji; self.tint = tint
        self.instructions = instructions; self.memoryOn = memoryOn; self.pinned = pinned; self.archived = archived
    }

    init(_ synced: SyncProject) {
        self.init(id: synced.id, name: synced.name, emoji: synced.emoji, tint: synced.tint, instructions: synced.instructions,
                  memoryOn: synced.memoryOn, pinned: synced.pinned, archived: synced.archived)
    }
}

/// The projects this iPhone knows, in the Mac's order (SyncProject.all:
/// the pinned in their order first, then the newest), and the one open.
@MainActor
@Observable
final class ProjectStore {
    private(set) var all: [ChatProject] = []
    /// The project open in its cover over the Chats page (ProjectPage).
    var page: ProjectPresentation?
    /// Its card, over the project (ProjectCard).
    var info = false
    /// What is typed in the open project's field, before it is a chat.
    var draft = ""

    func project(_ id: ChatProject.ID?) -> ChatProject? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Not archived: what the Chats page shows.
    var listed: [ChatProject] { all.filter { !$0.archived } }
    var pinned: [ChatProject] { listed.filter(\.pinned) }

    func adopt(_ projects: [ChatProject]) {
        guard projects != all else { return }
        all = projects
        // A project gone from sync closes, as a chat that left would.
        if let open = page, project(open.project) == nil { page = nil; info = false }
    }
}

/// The open project and the navigation that opened it.
struct ProjectPresentation: Identifiable, Equatable {
    let id: UUID
    let project: ChatProject.ID

    @MainActor
    static func binding(app: AppModel) -> Binding<Self?> {
        let captured = app.projects.page
        return Binding(get: { captured.flatMap { app.projects.page == $0 && app.projects.project($0.project) != nil ? $0 : nil } },
                       set: { newValue in
            // UIKit's own pull down or edge swipe closed it: only this one.
            if newValue == nil, let captured, app.projects.page == captured { app.closeProject() }
        })
    }
}

// MARK: - what the Chats page and a project do

extension AppModel {
    /// The project a chat is in, when this iPhone knows it and it isn't archived.
    func project(of chat: Chat) -> ChatProject? {
        projects.project(chat.project).flatMap { $0.archived ? nil : $0 }
    }

    /// A project's chats as the Chats page lists them: pinned first, newest next.
    func chats(in project: ChatProject.ID) -> [Chat] {
        ChatSectioning.listed(chats.visibleChats, sheet: chatSheet).filter { $0.project == project }
    }

    /// Move to Project is offered: there are projects, and the chat's Mac
    /// takes the move from here (ChatProjects in its commandcap).
    func canMoveToProject(_ id: Chat.ID) -> Bool {
        guard !projects.listed.isEmpty, let chat = chats.chat(id), !chat.ephemeral else { return false }
        return isFixture || sync.canMoveToProject(id)
    }

    /// A new chat can start in a project: the Mac new work goes to takes it.
    var canStartInProject: Bool { isFixture || sync.canStartInProject() }

    /// Into `project`, or out of its project with nil; sync writes the
    /// chat's head (SyncBridge.flushChats). The card leaves its list for the
    /// other one, which says it moved.
    func moveChat(_ id: Chat.ID, to project: ChatProject.ID?) {
        guard canMoveToProject(id), chats.chat(id)?.project != project else { return }
        Haptics.play(.light, reason: Haptics.Reason.chatAction)
        Motion.columnRows.run { chats.update(id) { $0.project = project } }
    }

    /// The open project goes back into its circle or its card.
    func closeProject() {
        projects.info = false
        withAnimation(.default) { projects.page = nil }
    }
}
