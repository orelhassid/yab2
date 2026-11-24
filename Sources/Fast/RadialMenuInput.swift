import AppKit

/// Defers a page's right press until the pointer moves far enough to open the command menu.
@MainActor
final class RadialMenuInput {
    static let shared = RadialMenuInput()
    private var monitor: Any?
    private var resignObserver: NSObjectProtocol?
    private weak var window: NSWindow?
    private weak var target: NSView?
    private var down: NSEvent?
    private var wheel: RadialMenuHost?
    private var dropdown: RadialDropdownHost?
    private var submenu: RadialDropdownHost?
    private var flickDistance: CGFloat?
    private var replaying = false
    private let pages = NSHashTable<NSView>.weakObjects()

    private let tabBodies = NSHashTable<NSView>.weakObjects()

    func registerTabBody(_ body: NSView) { tabBodies.add(body) }

    func registerPage(_ page: NSView) { pages.add(page) }

    func install() {
        guard monitor == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                if let window = note.object as? NSWindow, window === self?.window { self?.clear() }
            }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .rightMouseUp, .rightMouseDragged, .mouseMoved, .leftMouseDown, .keyDown]) { event in
            MainActor.assumeIsolated { self.handle(event) }
        }
    }

    private func clear() {
        dropdown?.removeFromSuperview()
        dropdown = nil
        submenu?.removeFromSuperview()
        submenu = nil
        wheel?.removeFromSuperview()
        wheel = nil
        flickDistance = nil
        window = nil
        target = nil
        down = nil
    }

    private func showMenu(for browser: Browser) {
        guard let window, window.isKeyWindow, window.attachedSheet == nil,
              target?.window === window, let root = window.contentView, let down else { return }
        let slots = RadialPreferences.saved
        guard !slots.isEmpty else { return }
        let origin = root.convert(down.locationInWindow, from: nil)
        let paint = browser.developmentLook ?? SpacePaint(browser.prefs)
        if Store.settings.string(forKey: RadialPreferences.layoutKey) == "dropdown" {
            dropdown = RadialDropdownHost.place(rows: RadialDropdownRow.commands(slots, browser: browser),
                paint: paint, in: root, near: origin) { [weak self, weak browser] index in
                    guard let self, let browser, slots[index].available(in: browser) else { return }
                    switch slots[index] {
                    case .command(let command):
                        clear()
                        RadialPreferences.run(command, in: browser)
                    case .spaces, .submenu:
                        openSubmenu(for: slots[index], at: index, in: browser)
                    }
                }
            return
        }

        let menu = RadialMenu(paint: paint, rows: [], available: slots.map { $0.available(in: browser) },
                              selection: RadialSelection(slots: slots))
        let host = RadialMenuHost(rootView: menu)
        host.sizingOptions = []
        let side = min(RadialMenu.side, root.bounds.width, root.bounds.height)
        guard side > 0 else { return }
        let x = min(max(root.bounds.minX, origin.x - side / 2), root.bounds.maxX - side)
        let y = min(max(root.bounds.minY, origin.y - side / 2), root.bounds.maxY - side)
        host.frame = CGRect(x: x, y: y, width: side, height: side)
        host.bounds.size = CGSize(width: RadialMenu.side, height: RadialMenu.side)
        root.addSubview(host, positioned: .above, relativeTo: nil)
        wheel = host
    }

    private struct Child {
        let row: RadialDropdownRow
        let run: (Browser) -> Void
    }

    private func children(of item: RadialItem, in browser: Browser) -> [Child] {
        switch item {
        case .command: return []
        case .spaces:
            guard browser.spacesShown else { return [] }
            return browser.spaces.map { space in
                Child(row: RadialDropdownRow(title: space.name, icon: space.icon, spaceIcon: true,
                                             checked: space.id == browser.spaceID)) { browser in
                    if browser.spacesShown, browser.spaces.contains(where: { $0.id == space.id }) {
                        browser.switchSpace(to: space.id)
                    }
                }
            }
        case .submenu(let menu):
            return menu.commands.map { command in
                Child(row: RadialDropdownRow(title: command.title, icon: command.symbol, enabled: command.available(in: browser))) {
                    RadialPreferences.run(command, in: $0)
                }
            }
        }
    }

    private func openSubmenu(for item: RadialItem, at index: Int, in browser: Browser) {
        guard let dropdown, let root = dropdown.superview else { return }
        if submenu != nil, dropdown.rootView.selected == index { return }
        submenu?.removeFromSuperview()
        submenu = nil
        dropdown.highlight(index)
        let children = children(of: item, in: browser)
        guard !children.isEmpty else { return }
        let offset = dropdown.topOffset(of: index)
        let y = root.isFlipped ? dropdown.frame.minY + offset : dropdown.frame.maxY - offset
        submenu = RadialDropdownHost.place(rows: children.map(\.row), paint: browser.developmentLook ?? SpacePaint(browser.prefs), in: root,
            near: CGPoint(x: 0, y: y), parent: dropdown) { [weak self, weak browser] index in
                guard let self, let browser, children[index].row.enabled else { return }
                clear()
                children[index].run(browser)
            }
    }

    private func trackDropdown(_ point: CGPoint) -> (RadialDropdownHost, Int)? {
        guard let dropdown else { return nil }
        if let submenu, submenu.bounds.contains(submenu.convert(point, from: nil)) {
            let index = submenu.row(at: point).flatMap { submenu.rootView.rows[$0].enabled ? $0 : nil }
            submenu.highlight(index)
            return index.map { (submenu, $0) }
        }
        submenu?.highlight(nil)
        guard let index = dropdown.row(at: point) else {
            if submenu == nil { dropdown.highlight(nil) }
            return nil
        }
        let row = dropdown.rootView.rows[index]
        if !row.enabled || dropdown.rootView.selected != index {
            submenu?.removeFromSuperview()
            submenu = nil
        }
        dropdown.highlight(row.enabled ? index : nil)
        guard row.enabled else { return nil }
        if row.children { dropdown.rootView.choose(index) }
        return (dropdown, index)
    }

    private func trackWheel(_ wheel: RadialMenuHost, at location: CGPoint, in browser: Browser) {
        var menu = wheel.rootView
        if let down {
            let delta = wheel.delta(at: location, from: down.locationInWindow)
            menu.selection.move(delta, childCount: menu.rows.count, activationDistance: flickDistance)
            menu.rows = menu.selection.wedge.map { children(of: menu.selection.slots[$0], in: browser).map(\.row) } ?? []
        } else {
            menu.selection.moveInChildRing(wheel.delta(at: location), count: menu.rows.count)
        }
        wheel.rootView = menu
    }

    private func finishWheel(_ wheel: RadialMenuHost, at location: CGPoint, in browser: Browser) {
        trackWheel(wheel, at: location, in: browser)
        guard target?.window === window,
              let index = wheel.rootView.selection.wedge, wheel.rootView.available[index] else {
            clear()
            return
        }

        let item = wheel.rootView.selection.slots[index]
        if let child = wheel.rootView.selection.child {
            let children = children(of: item, in: browser)
            clear()
            if children.indices.contains(child), children[child].row.enabled { children[child].run(browser) }
        } else if case .command(let command) = item {
            clear()
            RadialPreferences.run(command, in: browser)
        } else if down != nil, item != .spaces, !wheel.rootView.rows.isEmpty {
            down = nil
        } else {
            clear()
        }
    }

    private func page(in window: NSWindow, at location: CGPoint, browser: Browser) -> NSView? {
        if browser.inDevelopment {
            return tabBodies.allObjects.first { body in
                body.window === window && !body.isHiddenOrHasHiddenAncestor && body.visibleRect.contains(body.convert(location, from: nil))
            }
        }
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

    private func startFlick(at location: CGPoint, press: NSEvent, in browser: Browser) {
        guard wheel == nil, dropdown == nil else { return }
        let origin = press.locationInWindow
        let distance = RadialPreferences.sensitivity
        guard hypot(location.x - origin.x, location.y - origin.y) >= distance else { return }
        // Use window points, even when the displayed wheel is shifted away from a window edge.
        flickDistance = distance
        showMenu(for: browser)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !replaying else { return event }
        if BrowserUIInspector.shared.ownsPointer(in: event.window) { clear(); return event }
        guard let window = event.window, window.isKeyWindow, window.attachedSheet == nil,
              let browser = BrowserWindows.shared.browser(for: window) else { clear(); return event }
        if window !== self.window { clear() }
        let location = event.locationInWindow
        switch event.type {
        case .rightMouseDown:
            clear()
            guard let page = page(in: window, at: location, browser: browser) else { return event }
            target = page
            self.window = window
            down = event
            return nil
        case .rightMouseDragged, .rightMouseUp:
            guard let press = down else { return event }
            startFlick(at: location, press: press, in: browser)
            let isDrag = event.type == .rightMouseDragged
            if let wheel {
                if isDrag { trackWheel(wheel, at: location, in: browser) }
                else { finishWheel(wheel, at: location, in: browser) }
            } else if dropdown != nil {
                let selection = trackDropdown(location)
                if !isDrag {
                    down = nil
                    if let (host, index) = selection { host.rootView.choose(index) }
                    else { clear() }
                }
            } else if !isDrag {
                let valid = target?.window === window
                clear()
                if valid {
                    replaying = true
                    NSApp.postEvent(event, atStart: true)
                    window.sendEvent(press)
                    replaying = false
                }
            }
            return nil
        case .mouseMoved:
            if dropdown != nil { _ = trackDropdown(location); return nil }
            if let wheel, down == nil { trackWheel(wheel, at: location, in: browser); return nil }
        case .leftMouseDown:
            if let wheel, down == nil {
                let point = wheel.delta(at: location)
                if hypot(point.x, point.y) <= RadialSelection.outer {
                    finishWheel(wheel, at: location, in: browser)
                    return nil
                }
            }
            if [submenu, dropdown].compactMap({ $0 }).contains(where: { $0.bounds.contains($0.convert(location, from: nil)) }) {
                return event
            }
            clear()
        case .keyDown:
            let dismiss = event.keyCode == 53 && (wheel != nil || dropdown != nil)
            clear()
            if dismiss { return nil }
        default: break
        }
        return event
    }
}
