import AppKit
import Testing
@testable import Fast
import Foundation

struct MouseGestureTests {
    @Test func pathUsesMinimumDistanceForEachTurn() {
        var stroke = MouseStroke(start: .zero, minimum: 20)
        stroke.move(to: CGPoint(x: 10, y: 3))
        #expect(stroke.directions.isEmpty)
        for x in [20, 40, 60] { stroke.move(to: CGPoint(x: x, y: 3)) }
        stroke.move(to: CGPoint(x: 62, y: 22))
        #expect(stroke.directions == "R")
        stroke.move(to: CGPoint(x: 62, y: 32))
        stroke.move(to: CGPoint(x: 61, y: 4))
        #expect(stroke.directions == "RDU")
    }

    @MainActor @Test func mappingSurvivesEditingAndRejectsDuplicateStrokes() {
        let key = MouseMappings.mappingKey
        let previous = Store.settings.object(forKey: key)
        defer { Store.settings.set(previous, forKey: key) }
        let model = MouseMappings()
        model.replace([])
        var mapping = MouseMapping(command: Command.newTab.rawValue, directions: "RD")
        #expect(model.save(mapping))
        #expect(!model.save(MouseMapping(command: Command.forward.rawValue, directions: "RD")))
        mapping.directions = "UR"
        #expect(model.save(mapping))
        #expect(MouseMappings().mappings == [mapping])
    }
}

@MainActor
struct MouseGestureInputTests {
    private final class KeyWindow: NSWindow { override var isKeyWindow: Bool { true } }
    @Test(arguments: [false, true])
    func mappedStrokeOpensOverviewInOriginatingWindow(usingOption: Bool) throws {
        let defaults = Store.settings
        let keys = [MouseMappings.enabledKey, MouseMappings.optionKey]
        let previous = keys.map { defaults.object(forKey: $0) }
        let mappings = MouseMappings.shared
        let original = mappings.mappings
        defer {
            for (key, value) in zip(keys, previous) { defaults.set(value, forKey: key) }
            mappings.replace(original)
        }
        for key in keys { defaults.set(true, forKey: key) }
        mappings.replace([MouseMapping(command: Command.tabOverview.rawValue, directions: "RU")])

        let browser = Browser(windowID: UUID())
        let tab = browser.open(URL(string: "about:blank#mouse-gesture-test")!, foreground: true)
        let window = KeyWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.page
        BrowserWindows.shared.register(window, for: browser)
        window.makeKeyAndOrderFront(nil)
        defer { window.close(); browser.tabs.forEach { $0.close() } }
        MouseGestureInput.shared.install()
        let flags: NSEvent.ModifierFlags = usingOption ? .option : []
        func move(_ type: NSEvent.EventType, _ x: Int, _ y: Int) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: flags,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: 0))
            NSApp.sendEvent(event)
        }
        try move(usingOption ? .mouseMoved : .rightMouseDown, 80, 80)
        try move(usingOption ? .mouseMoved : .rightMouseDragged, 160, 80)
        let overlay = try #require(window.contentView?.subviews.compactMap { $0 as? MouseTrailHost }.first)
        #expect(overlay.rootView.label == "No match")
        try move(usingOption ? .mouseMoved : .rightMouseDragged, 160, 160)
        #expect(overlay.rootView.label == Command.tabOverview.title)
        #expect(overlay.rootView.points.count == 3)
        #expect(browser.active === tab)
        if usingOption {
            let release = try #require(NSEvent.keyEvent(with: .flagsChanged, location: NSPoint(x: 160, y: 160),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58))
            NSApp.sendEvent(release)
        } else { try move(.rightMouseUp, 160, 160) }
        #expect(overlay.superview == nil)
        #expect(browser.active?.libraryPage == .tabs)
    }
}
