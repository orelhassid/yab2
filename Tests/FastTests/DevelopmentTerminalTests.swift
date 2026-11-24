import Foundation
import Testing
@testable import Fast

@MainActor
struct DevelopmentTerminalTests {
    @Test func anUnlinkedProjectDiffersFromAnUnavailableCheckout() throws {
        var project = DevelopmentDetails(name: "Example", icon: "", folder: "")
        #expect(project.availableSourceFolder == nil)
        #expect(!project.sourceFolderUnavailable)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        project.folder = root.path
        #expect(project.availableSourceFolder == nil)
        #expect(project.sourceFolderUnavailable)

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(project.availableSourceFolder == root.path)
        #expect(!project.sourceFolderUnavailable)

        let file = root.appendingPathComponent("file.txt")
        try Data().write(to: file)
        project.folder = file.path
        #expect(project.availableSourceFolder == nil)
        #expect(project.sourceFolderUnavailable)
    }

    @Test(arguments: ["codex", "claude"])
    func developmentRunRejectsAnUnavailableCheckoutBeforeRegisteringAConversation(provider: String) {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        let project = DevelopmentDetails(name: "Example", icon: "", folder: missing, provider: provider)
        let run = Agents.shared.run(prompt: "Check the current project", cli: provider, resume: nil, development: project)
        #expect(run.state == .failed)
        #expect(run.result == DevelopmentDetails.unavailableSourceMessage)
        #expect(Agents.shared.session(run.id) == nil)
    }

    @Test func shellAndOutputSurviveProjectSwitching() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let a = root.appendingPathComponent("One's folder")
        let b = root.appendingPathComponent("Second project")
        for url in [a, b] { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: root) }
        let terminals = DevelopmentTerminals()
        #expect(terminals.session(for: .yab, folder: "") == nil)
        let first = try #require(terminals.session(for: .yab, folder: a.path))
        let second = try #require(terminals.session(for: .sunday, folder: b.path))
        defer { first.terminal.terminate(); second.terminal.terminate() }
        first.terminal.send(txt: "export YAB_TEST_VALUE=one; mkdir sub; cd sub; sleep 0.3; echo finished > output\r")
        second.terminal.send(txt: "echo \"${YAB_TEST_VALUE:-independent}\" > output\r")
        let returned = try #require(terminals.session(for: .yab, folder: a.path))
        #expect(returned === first)
        returned.terminal.send(txt: "printf '%s' \"$YAB_TEST_VALUE\" > variable; printf 'scrollback-%d\\n' 42\r")
        let clock = ContinuousClock()
        let end = clock.now.advanced(by: .seconds(12))
        while clock.now < end {
            if String(decoding: returned.terminal.getBufferAsData(), as: UTF8.self).contains("scrollback-42"),
               FileManager.default.fileExists(atPath: b.appendingPathComponent("output").path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try String(contentsOf: a.appendingPathComponent("sub/output"), encoding: .utf8) == "finished\n")
        #expect(try String(contentsOf: a.appendingPathComponent("sub/variable"), encoding: .utf8) == "one")
        #expect(try String(contentsOf: b.appendingPathComponent("output"), encoding: .utf8) == "independent\n")
        #expect(String(decoding: returned.terminal.getBufferAsData(), as: UTF8.self).contains("scrollback-42"))
        returned.terminal.send(txt: "exit 7\r")
        let deadline = clock.now.advanced(by: .seconds(5))
        while returned.status == nil && clock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        #expect(returned.status == "Shell exited with status 7.")
        let replacement = try #require(terminals.restart(.yab, folder: a.path))
        #expect(replacement !== first)
        replacement.terminal.terminate()
    }

    @Test func changingTheLinkedCheckoutChangesTheShellWithoutClosingTheOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let original = root.appendingPathComponent("original")
        let relinked = root.appendingPathComponent("relinked")
        for url in [original, relinked] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        let terminals = DevelopmentTerminals()
        let first = try #require(terminals.session(for: .yab, folder: original.path))
        defer { first.terminal.terminate() }
        let linked = try #require(terminals.session(for: .yab, folder: relinked.path))
        guard linked !== first else {
            Issue.record("The terminal still points at the original checkout.")
            return
        }
        defer { linked.terminal.terminate() }
        #expect(terminals.session(for: .yab, folder: original.path) === first)
        #expect(first.status == nil)
        #expect(terminals.restart(.yab, folder: relinked.path) === linked)

        let marker = relinked.appendingPathComponent("relinked-shell.txt")
        linked.terminal.send(txt: "printf relinked > relinked-shell.txt\r")
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: marker.path) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try String(contentsOf: marker, encoding: .utf8) == "relinked")
        #expect(!FileManager.default.fileExists(atPath: original.appendingPathComponent(marker.lastPathComponent).path))
    }

    @Test func aReplacementDirectoryAtTheSamePathGetsItsOwnShell() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let checkout = root.appendingPathComponent("checkout")
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let terminals = DevelopmentTerminals()
        let original = try #require(terminals.session(for: .yab, folder: checkout.path))
        defer { original.terminal.terminate() }

        try FileManager.default.moveItem(at: checkout, to: root.appendingPathComponent("old"))
        #expect(terminals.session(for: .yab, folder: checkout.path) == nil)
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: false)
        let replacement = try #require(terminals.restart(.yab, folder: checkout.path))
        defer { if replacement !== original { replacement.terminal.terminate() } }
        #expect(replacement !== original)
        #expect(replacement.status == nil)
        #expect(terminals.session(for: .yab, folder: checkout.path) === replacement)
    }
}
