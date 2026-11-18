import AppKit

/// The project card and command field share these operations. Named targets
/// are rebuilt at execution so deleted or archived projects cannot be used.
@MainActor
enum ChatProjectCommands {
    static let commands: Set<Command> = [
        .newChatProject, .openChatProject, .askInChatProject, .moveChatToProject, .removeChatFromProject,
        .inspectChatProject, .pinChatProject, .unpinChatProject, .archiveChatProject, .unarchiveChatProject,
        .renameChatProject, .deleteChatProject, .showProjectFiles, .addProjectFiles, .newProjectRoutine,
        .enableProjectMemory, .disableProjectMemory,
    ]

    static func current(in browser: Browser) -> Project? {
        browser.chatProjects.project(browser.chatHistory ? browser.chatProject
            : Chats.shared.chat(browser.chatID)?.project ?? browser.chatNewProject)
    }

    static func targets(_ operation: Command?, in browser: Browser) -> [MenuCommandTarget] {
        guard !browser.privateBrowsing else { return [] }
        return browser.chatProjects.listed.flatMap { project -> [MenuCommandTarget] in
            let open = MenuCommandTarget(id: "openChatProject:" + project.id, operation: .openChatProject,
                title: project.name, aliases: ["open project " + project.name], symbol: "folder", opens: true) {
                    $0.openProject(project.id)
                }
            let ask = MenuCommandTarget(id: "askInChatProject:" + project.id, operation: .askInChatProject,
                title: "Ask in " + project.name, aliases: ["new chat in " + project.name], symbol: "square.and.pencil", opens: true) {
                    $0.newChat(in: project.id)
                }
            return [open, ask].filter { operation == nil || $0.operation == operation }
        }
    }

    static func rename(_ project: Project) {
        let field = Question.Field(project.name, prompt: "Name")
        let question = Question(title: "Rename this project", glyph: "pencil", yes: "Rename", field: field)
        Task { @MainActor in
            guard await Questions.shared.ask(question), !field.trimmed.isEmpty,
                  var changed = Projects.shared.project(project.id) else { return }
            changed.name = String(field.trimmed.prefix(80))
            Projects.shared.update(changed)
        }
    }

    static func delete(_ project: Project, in browser: Browser) {
        let question = Question(title: "Delete “\(project.name)”?",
            detail: "Its chats go back to Chats. Its instructions, memory and files are deleted.",
            glyph: "trash", yes: "Delete Project", danger: true)
        Task { @MainActor in
            guard await Questions.shared.ask(question) else { return }
            browser.openProject(nil)
            Projects.shared.delete(project.id)
        }
    }

    static func addFiles(_ project: Project, done: @escaping () -> Void = {}) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.begin { answer in
            guard answer == .OK, Projects.shared.project(project.id) != nil else { return }
            do {
                try FileManager.default.createDirectory(at: project.files, withIntermediateDirectories: true)
                for url in panel.urls {
                    try FileManager.default.copyItem(at: url, to: project.files.appendingPathComponent(url.lastPathComponent))
                }
            } catch {
                let question = Question(title: "Couldn’t add files", detail: error.localizedDescription, glyph: "paperclip", yes: "OK")
                Task { @MainActor in _ = await Questions.shared.ask(question) }
            }
            done()
        }
    }
}
