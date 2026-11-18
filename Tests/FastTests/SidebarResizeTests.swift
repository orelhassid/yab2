import AppKit
import SwiftUI
import Testing
@testable import Fast

@MainActor
@Suite(.serialized)
struct SidebarResizeTests {
    private func world(floating: Bool = false, _ body: @MainActor (Browser, ColumnPage, EdgeHandle.Handle) async throws -> Void) async throws {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        let prefs = browser.prefs
        let old = (prefs.sidebar, prefs.sideShut, prefs.sideWidth)
        prefs.sidebar = true; prefs.sideShut = floating; prefs.sideWidth = 240
        let tabs = (0..<12).map { n in
            let tab = Tab()
            tab.restore(url: URL(string: "https://resize.invalid/\(n)")!, title: "Tab \(n)")
            if n < 8 { tab.pin = String(n) }
            browser.prepare(tab)
            return tab
        }
        browser.lay(tabs)
        let window = NSWindow(contentRect: CGRect(x: -30000, y: 0, width: 800, height: 600),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        window.contentView = root
        let page = ColumnPage(browser: browser, space: browser.spaceID)
        root.addSubview(page)
        let host = NSHostingView(rootView: SideEdge(browser: browser, prefs: prefs, floating: floating))
        host.frame = CGRect(x: 230, y: 0, width: 20, height: 600)
        root.addSubview(host)
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> EdgeHandle.Handle? {
            if let handle = view as? EdgeHandle.Handle { return handle }
            return view.subviews.lazy.compactMap(find).first
        }
        defer {
            window.close()
            browser.dozing?.invalidate(); browser.stuck.timer?.invalidate(); browser.pressure?.cancel()
            tabs.forEach { $0.close() }
            prefs.sidebar = old.0; prefs.sideShut = old.1; prefs.sideWidth = old.2
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
                Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
            }
        }
        try await body(browser, page, #require(find(host)))
    }

    private func event(_ type: NSEvent.EventType, x: CGFloat, in handle: EdgeHandle.Handle) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 200), modifierFlags: [],
                                        timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: handle.window?.windowNumber ?? 0, context: nil,
                                        eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
    }

    private func lay(_ page: ColumnPage, _ browser: Browser) {
        page.frame = CGRect(x: 0, y: 0, width: browser.prefs.sideWidth, height: 600)
        page.live(ColumnLayout.live(browser), head: ColumnLayout.head(browser),
                  frame: ColumnPages.Frame(lead: ColumnLayout.lead(browser, pins: browser.pinCellCount), footRoom: 0, top: 36, foot: false),
                  look: ColumnPages.Look(tone: nil, scheme: .light, titleSize: 13, grain: 0))
    }

    private func slides(in view: NSView) -> [String] {
        (view.layer?.animationKeys() ?? []).filter { $0.hasPrefix("column.slide.") }
            + view.subviews.flatMap { slides(in: $0) }
    }

    @Test(arguments: [false, true])
    func resizeTracksTheHandWithoutAnimatingPinReflow(floating: Bool) async throws {
        try await world(floating: floating) { browser, page, handle in
            lay(page, browser)
            handle.mouseDown(with: try event(.leftMouseDown, x: 240, in: handle))
            handle.mouseDragged(with: try event(.leftMouseDragged, x: 420, in: handle))
            #expect(browser.trackingSize == !floating)
            lay(page, browser)
            handle.mouseDragged(with: try event(.leftMouseDragged, x: 200, in: handle))
            lay(page, browser)
            #expect(slides(in: page).isEmpty, "a resize must not spring pins through their old positions")
            #expect(browser.prefs.sideWidth == Metrics.sideMin)
            handle.mouseUp(with: try event(.leftMouseUp, x: 200, in: handle))
            try await Task.sleep(for: .milliseconds(20))
            #expect(!browser.trackingSize)
        }
    }

    @Test func aPreviousReleaseCannotEndTheNextResize() async throws {
        try await world { browser, _, handle in
            handle.mouseDown(with: try event(.leftMouseDown, x: 240, in: handle))
            handle.mouseDragged(with: try event(.leftMouseDragged, x: 280, in: handle))
            handle.mouseUp(with: try event(.leftMouseUp, x: 280, in: handle))
            handle.mouseDown(with: try event(.leftMouseDown, x: 280, in: handle))
            handle.mouseDragged(with: try event(.leftMouseDragged, x: 300, in: handle))
            try await Task.sleep(for: .milliseconds(20))
            #expect(browser.trackingSize)
            handle.mouseUp(with: try event(.leftMouseUp, x: 300, in: handle))
            try await Task.sleep(for: .milliseconds(20))
            #expect(!browser.trackingSize)
        }
    }
}
