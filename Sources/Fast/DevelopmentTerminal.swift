import SwiftUI
import SwiftTerm

/// The window owns sessions. Attaching a different view never stops the PTY.
@MainActor
final class DevelopmentTerminals {
    private var sessions: [DevelopmentProject: DevelopmentShell] = [:]

    func session(for project: DevelopmentProject, folder: String) -> DevelopmentShell? {
        if let existing = sessions[project] { return existing }
        guard let session = DevelopmentShell(folder: folder) else { return nil }
        sessions[project] = session
        return session
    }

    func restart(_ project: DevelopmentProject, folder: String) -> DevelopmentShell? {
        guard sessions[project]?.status != nil else { return sessions[project] }
        sessions.removeValue(forKey: project)
        return session(for: project, folder: folder)
    }
}

@MainActor @Observable
final class DevelopmentShell: LocalProcessTerminalViewDelegate {
    let terminal: LocalProcessTerminalView
    private(set) var status: String?

    init?(folder: String) {
        var directory: ObjCBool = false
        guard folder.hasPrefix("/"), FileManager.default.fileExists(atPath: folder, isDirectory: &directory),
              directory.boolValue, FileManager.default.isExecutableFile(atPath: folder) else { return nil }

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
