import AppKit
import Testing
@testable import Fast

@MainActor
struct RadialMenuTests {
    private final class KeyWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    @Test func nestedRingTracksEverySpaceAndCancelsInCenter() {
        for count in [1, 3, 12] {
            var selection = RadialSelection()
            selection.move(CGPoint(x: 48, y: -80), spaceCount: count)
            #expect(selection.showsSpaces)
            for index in 0..<count {
                let angle = -.pi / 3 + 2 * Double.pi * Double(index) / Double(count)
                selection.move(CGPoint(x: 160 * cos(angle), y: 160 * sin(angle)), spaceCount: count)
                #expect(selection.space == index)
            }
            selection.move(.zero, spaceCount: count)
            #expect(selection.space == nil && selection.wedge == nil)
        }
    }

    @Test func rightHoldOpensWheelAndReleaseOpensDownloads() async throws {
        let browser = Browser(windowID: UUID())
        let tab = browser.open(URL(string: "about:blank#radial-menu-test")!, foreground: true)
        let window = KeyWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 480),
                               styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.page
        BrowserWindows.shared.register(window, for: browser)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); browser.tabs.forEach { $0.close() } }
        MouseGestureInput.shared.install()

        func mouse(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: y),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
            NSApp.sendEvent(event)
        }
        try mouse(.rightMouseDown, x: 320, y: 240)
        try await Task.sleep(for: .milliseconds(450))
        let wheel = try #require(window.contentView?.subviews.compactMap { $0 as? RadialMenuHost }.first)
        try mouse(.rightMouseDragged, x: 367, y: 159)
        #expect(wheel.rootView.selection.wedge == 1)
        #expect(browser.active === tab)
        try mouse(.rightMouseUp, x: 367, y: 159)
        #expect(wheel.superview == nil)
        #expect(browser.active?.libraryPage == .downloads)
    }
}
