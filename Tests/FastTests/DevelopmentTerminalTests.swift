import Foundation
import Testing
@testable import Fast

@MainActor
struct DevelopmentTerminalTests {
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
        let returned = try #require(terminals.session(for: .yab, folder: b.path))
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
        let replacement = try #require(terminals.restart(.yab, folder: b.path))
        #expect(replacement !== first)
        replacement.terminal.terminate()
    }
}
