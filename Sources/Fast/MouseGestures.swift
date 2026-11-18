import AppKit

struct MouseStroke {
    private var anchor: CGPoint
    private(set) var directions = ""
    let minimum: CGFloat

    init(start: CGPoint, minimum: CGFloat) {
        anchor = start
        self.minimum = minimum
    }

    /// Both the editor and the window supply coordinates increasing downward.
    mutating func move(to point: CGPoint) {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        guard max(abs(dx), abs(dy)) >= minimum else { return }
        let direction: Character = abs(dx) >= abs(dy) ? (dx > 0 ? "R" : "L") : (dy > 0 ? "D" : "U")
        if directions.last != direction { directions.append(direction) }
        anchor = point
    }

    static func arrows(_ directions: String) -> String {
        directions.compactMap { ["U":"↑", "D":"↓", "L":"←", "R":"→"][String($0)] }.joined(separator: " ")
    }
}

struct MouseMapping: Identifiable, Codable, Equatable {
    var id = UUID()
    var command: String
    var directions: String
    var title: String { Command(rawValue: command)?.title ?? command }
}

@MainActor
final class MouseMappings: ObservableObject {
    static let shared = MouseMappings()
    static let enabledKey = "mouse.gestures.enabled"
    static let optionKey = "mouse.gestures.option"
    static let minimumKey = "mouse.gestures.minimum"
    static let mappingKey = "mouse.gestures.mapping"
    static let minimumRange = 8...64
    static var minimum: Int {
        min(64, max(8, Store.settings.object(forKey: minimumKey) as? Int ?? 20))
    }
    static var defaults: [MouseMapping] {
        [MouseMapping(command: Command.back.rawValue, directions: "L"),
         MouseMapping(command: Command.forward.rawValue, directions: "R"),
         MouseMapping(command: Command.newTab.rawValue, directions: "D"),
         MouseMapping(command: Command.reload.rawValue, directions: "UD")]
    }

    @Published private(set) var mappings: [MouseMapping]
    init() {
        mappings = Store.settings.data(forKey: Self.mappingKey).flatMap {
            try? JSONDecoder().decode([MouseMapping].self, from: $0)
        } ?? Self.defaults
    }
    func match(_ directions: String) -> MouseMapping? { mappings.first { $0.directions == directions } }

    func previewLabel(_ directions: String, browser: Browser? = nil) -> String? {
        guard !directions.isEmpty else { return nil }
        guard let mapping = match(directions), let command = Command(rawValue: mapping.command) else { return "No match" }
        if let browser, !command.available(in: browser) { return "\(command.title) (unavailable)" }
        return command.title
    }
    func conflict(_ mapping: MouseMapping) -> MouseMapping? {
        mappings.first { $0.id != mapping.id && $0.directions == mapping.directions }
    }
    @discardableResult func save(_ mapping: MouseMapping) -> Bool {
        guard !mapping.directions.isEmpty, conflict(mapping) == nil else { return false }
        var next = mappings
        if let i = next.firstIndex(where: { $0.id == mapping.id }) { next[i] = mapping }
        else { next.append(mapping) }
        replace(next)
        return true
    }
    func replace(_ next: [MouseMapping]) {
        guard let data = try? JSONEncoder().encode(next) else { return }
        Store.settings.set(data, forKey: Self.mappingKey)
        mappings = next
    }
}

/// A local monitor defers a page's right press until release distinguishes a click
/// from a stroke. Replaying an ordinary click lets the original page build its menu.
@MainActor
final class MouseGestureInput {
    static let shared = MouseGestureInput()
    private var monitor: Any?
    private weak var window: NSWindow?
    private weak var target: NSView?
    private var down: NSEvent?
    private var stroke: MouseStroke?
    private var hold: Task<Void, Never>?
    private var wheel: RadialMenuHost?
    private let pages = NSHashTable<NSView>.weakObjects()
    private var dropdown: RadialDropdownHost?
    private var submenu: RadialDropdownHost?
    private var dropdownMoved = false
    func registerPage(_ page: NSView) { pages.add(page) }

    private var wheelMoved = false
    private var replaying = false
    private var trail: MouseTrailHost?
    private var points: [CGPoint] = []
    private var resignObserver: NSObjectProtocol?

    func install() {
        guard monitor == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let w = note.object as? NSWindow, w === self?.window { self?.clear() }
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .rightMouseDragged, .mouseMoved, .flagsChanged, .leftMouseDown, .keyDown]) { event in
            MainActor.assumeIsolated { self.handle(event) }
        }
    }

    private func clear() {
        hold?.cancel()
        hold = nil
        dropdown?.removeFromSuperview()
        submenu?.removeFromSuperview()
        dropdown = nil
        submenu = nil
        dropdownMoved = false
        wheel?.removeFromSuperview()
        wheel = nil
        wheelMoved = false
        trail?.removeFromSuperview()
        trail = nil
        points.removeAll(keepingCapacity: true)
        window = nil
        target = nil
        down = nil
        stroke = nil
    }
    private func updateTrail(_ location: CGPoint, browser: Browser) {
        guard let target, let root = window?.contentView, let stroke else { return }
        let frame = root.convert(target.visibleRect, from: target)
        let local = root.convert(location, from: nil)
        let point = CGPoint(x: local.x - frame.minX, y: root.isFlipped ? local.y - frame.minY : frame.maxY - local.y)
        guard points.last != point else { return }
        points.append(point)
        guard points.count > 1 else { return }
        let preview = GestureTrailPreview(points: points, label: MouseMappings.shared.previewLabel(stroke.directions, browser: browser))
        if let trail { trail.frame = frame; trail.rootView = preview }
        else {
            let host = MouseTrailHost(rootView: preview)
            host.sizingOptions = []
            host.frame = frame
            root.addSubview(host, positioned: .above, relativeTo: nil)
            trail = host
        }
    }

    private func scheduleWheel(for browser: Browser) {
        hold = Task { @MainActor [weak self, weak browser] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let browser,
                  let window, window.isKeyWindow, window.attachedSheet == nil,
                  target?.window === window, let root = window.contentView, let down else { return }
            let spaces = browser.spacesShown ? browser.spaces : []
            let slots = RadialPreferences.saved
            if Store.settings.string(forKey: RadialPreferences.layoutKey) == "dropdown" {
                dropdown = RadialDropdownHost.place(rows: RadialDropdownRow.commands(slots, browser: browser),
                    paint: SpacePaint(browser.prefs), in: root, near: root.convert(down.locationInWindow, from: nil)) { [weak self] i in
                        guard let self else { return }
                        if let command = slots[i] {
                            self.clear()
                            RadialPreferences.run(command, in: browser)
                        } else { self.openSpaces(in: browser, index: i) }
                    }
                return
            }
            let menu = RadialMenu(paint: SpacePaint(browser.prefs), spaces: spaces, available: slots.map {
                $0?.available(in: browser) ?? !spaces.isEmpty
            }, selection: RadialSelection(slots: slots))
            let host = RadialMenuHost(rootView: menu)
            host.sizingOptions = []
            let side = min(RadialMenu.side, root.bounds.width, root.bounds.height)
            guard side > 0 else { return }
            let origin = root.convert(down.locationInWindow, from: nil)
            let x = min(max(root.bounds.minX, origin.x - side / 2), root.bounds.maxX - side)
            let y = min(max(root.bounds.minY, origin.y - side / 2), root.bounds.maxY - side)
            host.frame = CGRect(x: x, y: y, width: side, height: side)
            host.bounds.size = CGSize(width: RadialMenu.side, height: RadialMenu.side)
            root.addSubview(host, positioned: .above, relativeTo: nil)
            wheel = host
        }
    }

    private func openSpaces(in browser: Browser, index: Int) {
        guard let dropdown, let root = dropdown.superview, submenu == nil else { return }
        let spaces = browser.spaces
        let rows = spaces.map { RadialDropdownRow(title: $0.name, icon: $0.icon, spaceIcon: true, checked: $0.id == browser.spaceID) }
        let rowOffset = RadialDropdown.inset + CGFloat(index) * RadialDropdown.rowHeight
        let y = root.isFlipped ? dropdown.frame.minY + rowOffset : dropdown.frame.maxY - rowOffset
        submenu = RadialDropdownHost.place(rows: rows, paint: SpacePaint(browser.prefs), in: root,
            near: CGPoint(x: 0, y: y), parent: dropdown) { [weak self] i in
                self?.clear()
                if browser.spaces.contains(where: { $0.id == spaces[i].id }) { browser.switchSpace(to: spaces[i].id) }
            }
    }

    private func trackDropdown(_ point: CGPoint, browser: Browser) -> (RadialDropdownHost, Int)? {
        guard let dropdown else { return nil }
        if let submenu, submenu.bounds.contains(submenu.convert(point, from: nil)) {
            let i = submenu.row(at: point)
            submenu.highlight(i)
            return i.map { (submenu, $0) }
        }
        submenu?.highlight(nil)
        guard let i = dropdown.row(at: point) else {
            if submenu == nil { dropdown.highlight(nil) }
            return nil
        }
        guard dropdown.rootView.rows[i].enabled else {
            dropdown.highlight(nil)
            submenu?.removeFromSuperview()
            submenu = nil
            return nil
        }
        if dropdown.rootView.selected != i {
            submenu?.removeFromSuperview()
            submenu = nil
        }
        dropdown.highlight(i)
        if dropdown.rootView.rows[i].children { openSpaces(in: browser, index: i) }
        return (dropdown, i)
    }

    private func finishWheel(in browser: Browser, at location: CGPoint) {
        guard let wheel else { return }
        if wheelMoved { wheel.track(location) }
        let menu = wheel.rootView
        let valid = target?.window === window
        clear()
        guard valid, let index = menu.selection.wedge, menu.available[index] else { return }
        if let child = menu.selection.space {
            let id = menu.spaces[child].id
            if browser.spacesShown, browser.spaces.contains(where: { $0.id == id }) {
                browser.switchSpace(to: id)
            }
        } else if let command = menu.selection.slots[index] {
            RadialPreferences.run(command, in: browser)
        }
    }

    private func page(in window: NSWindow, at location: CGPoint) -> NSView? {
        guard let root = window.contentView?.superview else { return nil }
        var view = root.hitTest(root.convert(location, from: nil))
        while let current = view {
            if current is any PageHandle { return current }
            view = current.superview
        }
        return pages.allObjects.first { view in
            view.window === window && !view.isHiddenOrHasHiddenAncestor && view.visibleRect.contains(view.convert(location, from: nil))
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !replaying,
              let w = event.window, w.isKeyWindow, w.attachedSheet == nil,
              let browser = BrowserWindows.shared.browser(for: w) else { clear(); return event }
        if w !== window { clear() }
        if let dropdown {
            switch event.type {
            case .rightMouseDragged, .mouseMoved:
                dropdownMoved = true
                _ = trackDropdown(event.locationInWindow, browser: browser)
                return nil
            case .rightMouseUp:
                down = nil
                if dropdownMoved {
                    if let (host, i) = trackDropdown(event.locationInWindow, browser: browser) { host.rootView.choose(i) }
                    else { clear() }
                }
                return nil
            case .leftMouseDown:
                if [dropdown, submenu].compactMap({ $0 }).contains(where: { $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }) { return event }
                clear()
                return event
            case .keyDown where event.keyCode == 53:
                clear()
                return nil
            default: break
            }
        }
        let point = CGPoint(x: event.locationInWindow.x, y: -event.locationInWindow.y)
        let option = event.modifierFlags.intersection([.option, .command, .control, .shift]) == .option
        let gesturesEnabled = Store.settings.bool(forKey: MouseMappings.enabledKey)
        let optionEnabled = gesturesEnabled && Store.settings.bool(forKey: MouseMappings.optionKey)
        switch event.type {
        case .rightMouseDown:
            clear()
            guard let page = page(in: w, at: event.locationInWindow) else { return event }
            target = page
            window = w
            down = event
            scheduleWheel(for: browser)
            if gesturesEnabled { stroke = MouseStroke(start: point, minimum: CGFloat(MouseMappings.minimum)) }
            updateTrail(event.locationInWindow, browser: browser)
            return nil
        case .rightMouseDragged where down != nil:
            if let wheel {
                wheelMoved = true
                wheel.track(event.locationInWindow)
                return nil
            }
            if let origin = down?.locationInWindow,
               hypot(event.locationInWindow.x - origin.x, event.locationInWindow.y - origin.y) >= 6 {
                hold?.cancel()
            }
            stroke?.move(to: point)
            updateTrail(event.locationInWindow, browser: browser)
            return nil
        case .rightMouseUp where down != nil:
            if wheel != nil {
                finishWheel(in: browser, at: event.locationInWindow)
                return nil
            }
            stroke?.move(to: point)
            let press = down, path = stroke?.directions ?? "", original = target
            clear()
            if original?.window === w {
                if path.isEmpty, let press {
                    replaying = true
                    NSApp.postEvent(event, atStart: true)
                    w.sendEvent(press)
                    replaying = false
                } else { run(path, in: browser) }
            }
            return nil
        case .flagsChanged, .mouseMoved:
            guard down == nil else { return event }
            if option && optionEnabled {
                guard let page = page(in: w, at: event.locationInWindow) else { clear(); return event }
                if target !== page {
                    clear()
                    window = w
                    target = page
                    stroke = MouseStroke(start: point, minimum: CGFloat(MouseMappings.minimum))
                } else { stroke?.move(to: point) }
                updateTrail(event.locationInWindow, browser: browser)
            } else if let current = stroke {
                let finish = event.type == .flagsChanged && optionEnabled && !event.modifierFlags.contains(.option) && target?.window === w
                clear()
                if finish { run(current.directions, in: browser) }
            }
        case .keyDown where wheel != nil && event.keyCode == 53:
            clear()
            return nil
        case .keyDown, .leftMouseDown: clear()
        default: break
        }
        return event
    }

    private func run(_ path: String, in browser: Browser) {
        guard let mapping = MouseMappings.shared.match(path),
              let command = Command(rawValue: mapping.command) else { return }
        command.run(in: browser)
    }
}
