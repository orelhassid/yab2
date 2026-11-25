import AppKit
import Testing
import WebKit
@testable import Fast

@MainActor @Suite(.serialized)
struct ExtensionPopupLayoutTests {
    private final class Watcher: NSObject, WKScriptMessageHandler {
        var messages: [[String: Any]] = []
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let body = message.body as? [String: Any] { messages.append(body) }
        }
    }

    private func fixture(size: NSSize = NSSize(width: 360, height: 240),
                         html: String = "<style>html{width:80px;height:120px}body{margin:0}</style><body><button>Click</button></body>") async throws -> (WKWebView, Watcher) {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(), watcher = Watcher()
        config.websiteDataStore = .nonPersistent()
        config.preferences.inactiveSchedulingPolicy = .none
        config.userContentController.add(watcher, contentWorld: ExtensionPopup.layoutWorld, name: ExtensionPopup.layoutHandler)
        // In no window, as a popup whose window is hidden or occluded: the
        // page gets no animation frames and must still publish its size.
        let web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        // The initial empty document is already "complete": wait for the
        // fixture's own, or the observer lands in about:blank and is retired
        // by its pagehide, as a real popup's would be on navigation.
        let marker = UUID().uuidString
        web.loadHTMLString("<!doctype html><meta name=fixture content=\(marker)>" + html, baseURL: nil)
        let loaded = "document.readyState === 'complete' && document.querySelector('meta[name=fixture]')?.content === '\(marker)'"
        for _ in 0..<200 {
            if (try? await web.evaluateJavaScript(loaded)) as? Bool == true { return (web, watcher) }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Popup fixture did not load")
        return (web, watcher)
    }

    private func install(_ web: WKWebView, token: String) async throws {
        _ = try await web.evaluateJavaScript(ExtensionPopup.layoutBridge(token: token), in: nil, in: ExtensionPopup.layoutWorld)
    }

    @Test func narrowLayoutsAreSizesAndInvalidSizesAreRejected() {
        #expect(ExtensionPopup.layoutSize(["width": 80.0, "height": 120.0]) == NSSize(width: 80, height: 120))
        for width in [0.0, 24, 801, .infinity, .nan] {
            #expect(ExtensionPopup.layoutSize(["width": width, "height": 120.0]) == nil)
        }
        #expect(ExtensionPopup.layoutSize(["width": 80.0]) == nil)
    }

    @Test func documentPublishesNarrowSizeAndLateResizeWithoutAPollingWindow() async throws {
        let (web, watcher) = try await fixture()
        defer { web.stopLoading() }
        try await install(web, token: "first-document")
        for _ in 0..<100 where watcher.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let first = try #require(watcher.messages.first)
        #expect(first["token"] as? String == "first-document")
        #expect(ExtensionPopup.layoutSize(first) == NSSize(width: 80, height: 120))
        // The old six-second polling window has ended. A real layout change
        // must still reach the popup, including shrinkage after growth.
        try await Task.sleep(for: .seconds(6.5))
        for (width, height) in [(520, 200), (80, 90)] {
            _ = try await web.evaluateJavaScript("document.documentElement.style.cssText='width:\(width)px;height:\(height)px';true")
            for _ in 0..<100 {
                if watcher.messages.last.flatMap(ExtensionPopup.layoutSize) == NSSize(width: CGFloat(width), height: CGFloat(height)) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(watcher.messages.last.flatMap(ExtensionPopup.layoutSize) == NSSize(width: CGFloat(width), height: CGFloat(height)))
        }
    }

    @Test func replacingTheDocumentObserverRetiresItsGeneration() async throws {
        let (web, watcher) = try await fixture()
        defer { web.stopLoading() }
        try await install(web, token: "old-document")
        try await install(web, token: "new-document")
        try await Task.sleep(for: .milliseconds(150))
        watcher.messages.removeAll()
        _ = try await web.evaluateJavaScript("document.documentElement.style.width='420px';true")
        for _ in 0..<100 where watcher.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(!watcher.messages.isEmpty)
        #expect(watcher.messages.allSatisfy { $0["token"] as? String == "new-document" })
    }

    @Test func declaredDimensionsSurviveAMatchingCachedViewport() async throws {
        let (web, watcher) = try await fixture(size: NSSize(width: 80, height: 120))
        defer { web.stopLoading() }
        try await install(web, token: "reopened")
        for _ in 0..<100 where watcher.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(watcher.messages.first.flatMap(ExtensionPopup.layoutSize) == NSSize(width: 80, height: 120))
        let style = try await web.evaluateJavaScript("String(document.documentElement.getAttribute('style'))") as? String
        #expect(style == "null", "root style left: \(style ?? "?"); messages: \(watcher.messages)")
    }

    @Test func autoSizedRootFollowsItsContentsInsteadOfRememberingTheViewport() async throws {
        let (web, watcher) = try await fixture(html: "<style>body{margin:0;width:80px;height:120px}</style><body>Popup</body>")
        defer { web.stopLoading() }
        try await install(web, token: "content-sized")
        for (width, height) in [(80, 120), (520, 200), (80, 90)] {
            _ = try await web.evaluateJavaScript("document.body.style.cssText='width:\(width)px;height:\(height)px';true")
            for _ in 0..<100 {
                if watcher.messages.last.flatMap(ExtensionPopup.layoutSize) == NSSize(width: CGFloat(width), height: CGFloat(height)) { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(watcher.messages.last.flatMap(ExtensionPopup.layoutSize) == NSSize(width: CGFloat(width), height: CGFloat(height)))
            web.setFrameSize(NSSize(width: CGFloat(width), height: CGFloat(height)))
        }
    }

    @Test func inheritedBodyPositionStaysInFlowDuringMeasurement() async throws {
        let html = """
        <style>body{margin:0;width:300px;height:584px;overflow:hidden;position:inherit!important}</style>
        <body><button>Decline</button></body>
        """
        let (web, watcher) = try await fixture(size: NSSize(width: 25, height: 25), html: html)
        defer { web.stopLoading() }
        try await install(web, token: "inherited-position")
        for _ in 0..<100 where watcher.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(watcher.messages.first.flatMap(ExtensionPopup.layoutSize) == NSSize(width: 300, height: 584))
        let position = try await web.evaluateJavaScript("getComputedStyle(document.body).position") as? String
        #expect(position == "static")
    }

    @Test func rootPaddingAndMinimumHeightKeepTheirBoxModel() async throws {
        for (model, width, height) in [("content-box", 104, 264), ("border-box", 80, 240)] {
            let (web, watcher) = try await fixture(html: "<style>html{box-sizing:\(model);width:80px;min-height:240px;padding:10px;border:2px solid}body{margin:0}</style><body>Popup</body>")
            defer { web.stopLoading() }
            try await install(web, token: model)
            for _ in 0..<100 where watcher.messages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
            #expect(watcher.messages.first.flatMap(ExtensionPopup.layoutSize) == NSSize(width: CGFloat(width), height: CGFloat(height)))
            let style = try await web.evaluateJavaScript("String(document.documentElement.getAttribute('style'))") as? String
        #expect(style == "null", "root style left: \(style ?? "?"); messages: \(watcher.messages)")
        }
    }
}
