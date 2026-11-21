import AppKit
import QuartzCore
import Testing
@testable import Fast

/// Controlled incoming model data reaches the real native card renderer.
@MainActor
@Suite(.serialized)
struct PlayerClockViewTests {
    @Test func anUnrepresentableDurationRendersAndTheSameCardRecovers() async throws {
        let env = ProcessInfo.processInfo.environment
        try #require(env["YAB_FARM_WORKER"] == "1" && env["YAB_HISTORY"] == "own")
        try #require(Store.testing && Store.unitTests && Store.world?.hasPrefix("appkit-gate-") == true)
        try #require(NSApp?.isRunning == true && BandView.last == nil,
                     "Use a fresh isolated AppKit child with no foreign player view")
        let browser = Browser(windowID: UUID())
        let source = Fast.Tab(shy: true, configuration: Web.configuration(shy: true, extensions: false))
        let notes = Fast.Tab(shy: true, configuration: Web.configuration(shy: true, extensions: false))
        let view = BandView(frame: NSRect(x: 0, y: 0, width: 360, height: Band.reach))
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 480))
        let window = NSWindow(contentRect: root.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = root
        browser.dozing?.invalidate()
        browser.stuck.timer?.invalidate()
        browser.stuck.agentTimer?.invalidate()
        browser.stuck.frontTimer?.invalidate()
        browser.pressure?.cancel()
        defer {
            view.bench("close")
            view.removeFromSuperview()
            window.contentView = nil
            window.orderOut(nil)
            window.close()
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.stuck.agentTimer?.invalidate()
            browser.stuck.frontTimer?.invalidate()
            browser.pressure?.cancel()
            browser.tabs.forEach { $0.close() }
        }
        for tab in [source, notes] {
            tab.restore(url: URL(string: "about:blank")!, title: "Owned clock fixture")
            browser.prepare(tab)
        }
        browser.lay([source, notes])
        browser.activeID = notes.id
        view.attach(browser.player)
        root.addSubview(view)
        window.orderFront(nil)
        source.tune = Tune(title: "Clock range fixture", duration: 120, elapsed: 30,
                           stamp: CACurrentMediaTime(), playing: true)
        browser.player.heard(source)
        browser.player.restage(immediate: true)
        try #require(browser.player.face?.tab == source.id,
                     "A playing offscreen source must first raise its real face")
        source.tune?.playing = false
        browser.player.heard(source)
        browser.player.restage(immediate: true)
        let bound = try await Loaded.until(3) {
            BandView.last === view && view.report["title"] as? String == "Clock range fixture"
        }
        try #require(bound && view.window === window)
        view.bench("open")
        let initial = view.report["times"] as? [String] ?? []
        try #require(initial.count == 2 && initial[0] == "0:30" && initial[1].hasSuffix("1:30"),
                     "Positive control must paint the actual finite clock")

        source.tune?.duration = 1e100
        browser.player.heard(source)
        browser.player.restage(immediate: true)
        let extreme = view.report
        let times = extreme["times"] as? [String] ?? []
        #expect(extreme["duration"] as? Double == 1e100)
        #expect(times.count == 2 && times[0] == "0:30" && times[1].hasSuffix("0:00"))
        print("PLAYER_CLOCK_RENDER_EXTREME \(times)")

        source.tune?.duration = 300
        browser.player.heard(source)
        browser.player.restage(immediate: true)
        let restored = view.report["times"] as? [String] ?? []
        #expect(restored.count == 2 && restored[0] == "0:30" && restored[1].hasSuffix("4:30"))
        print("PLAYER_CLOCK_RENDER_RESTORED \(restored)")
    }
}
