import Darwin
import SwiftUI
import SwiftTerm

/// The window keeps a shell for each checkout opened in a project.
@MainActor
final class DevelopmentTerminals {
    private struct Checkout: Hashable {
        let project: DevelopmentProject
        let path: String
        let device: dev_t
        let inode: ino_t

        init?(project: DevelopmentProject, folder: String) {
            guard folder.hasPrefix("/") else { return nil }
            let path = URL(fileURLWithPath: folder, isDirectory: true).resolvingSymlinksInPath().path
            var entry = stat()
            guard stat(path, &entry) == 0, entry.st_mode & S_IFMT == S_IFDIR,
                  FileManager.default.isExecutableFile(atPath: path) else { return nil }
            self.project = project
            self.path = path
            device = entry.st_dev
            inode = entry.st_ino
        }
    }

    private var sessions: [Checkout: DevelopmentShell] = [:]

    func session(for project: DevelopmentProject, folder: String) -> DevelopmentShell? {
        guard let checkout = Checkout(project: project, folder: folder) else { return nil }
        return sessions[checkout] ?? start(checkout)
    }

    func restart(_ project: DevelopmentProject, folder: String) -> DevelopmentShell? {
        guard let checkout = Checkout(project: project, folder: folder) else { return nil }
        if let existing = sessions[checkout], existing.status == nil { return existing }
        return start(checkout)
    }

    private func start(_ checkout: Checkout) -> DevelopmentShell {
        let session = DevelopmentShell(folder: checkout.path)
        sessions[checkout] = session
        return session
    }
}

@MainActor @Observable
final class DevelopmentShell: LocalProcessTerminalViewDelegate {
    let terminal: LocalProcessTerminalView
    private(set) var status: String?

    fileprivate init(folder: String) {
        terminal = ProjectTerminalView(frame: CGRect(x: 0, y: 0, width: 640, height: 400))
        terminal.processDelegate = self
        let configuredShell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        let shell = Shell.loginShell(configuredShell)
        // env reports a directory that disappears at launch and never starts a shell elsewhere.
        terminal.startProcess(executable: "/usr/bin/env", args: ["-C", folder, shell, "-il"],
                              environment: SwiftTerm.Terminal.getEnvironmentVariables() + ["SHELL=" + shell])
    }

    func processTerminated(source: SwiftTerm.TerminalView, exitCode: Int32?) {
        status = exitCode.map { "Shell exited with status \($0)." } ?? "Shell ended."
    }

    func processFailedToStart(source: SwiftTerm.TerminalView, error: LocalProcessError) {
        status = "Could not start the shell."
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
}

struct DevelopmentTerminalPane: View {
    let terminals: DevelopmentTerminals
    let project: DevelopmentProject
    let folder: String
    let openSettings: () -> Void
    @State private var session: DevelopmentShell?

    var body: some View {
        VStack(spacing: 0) {
            if let session {
                DevelopmentTerminalScreen(session: session).id(ObjectIdentifier(session))
                if let status = session.status {
                    HStack {
                        Text(status)
                        Button("Start new shell") { self.session = terminals.restart(project, folder: folder) }
                            .buttonStyle(.yab(.quiet, .small))
                    }.padding(8)
                }
            } else {
                Spacer()
                Text(folder.isEmpty ? "Choose a source folder to start the terminal." : "The source folder is unavailable.")
                Button("Project settings", action: openSettings).buttonStyle(.yab(.quiet, .small))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: folder) { session = terminals.session(for: project, folder: folder) }
    }
}

private struct DevelopmentTerminalScreen: NSViewRepresentable {
    let session: DevelopmentShell

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        session.terminal
    }

    func updateNSView(_ view: LocalProcessTerminalView, context: Context) {
        guard let tone = context.environment.tone else { return }
        let ink = Palette.shades(tone).strongNS
        let appearance = NSAppearance(named: tone.scheme == .dark ? .darkAqua : .aqua)
        if view.appearance != appearance { view.appearance = appearance }
        if view.nativeBackgroundColor != tone.page { view.nativeBackgroundColor = tone.page }
        if view.nativeForegroundColor != ink { view.nativeForegroundColor = ink }
        if view.caretColor != ink { view.caretColor = ink }
    }
}

private final class ProjectTerminalView: LocalProcessTerminalView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let target = window else { return }
        DispatchQueue.main.async { [weak self, weak target] in
            guard let self, let target, self.window === target else { return }
            target.makeFirstResponder(self)
        }
    }
}
