import AppKit
import SwiftUI

/// The profile menu's body and pointer share one outline. Placement uses the
/// trigger's screen coordinates so the pointer follows it when the body shifts.
struct ProfilePopoverPlacement: Equatable {
    static let depth = Radius.control
    static let gap = Radius.small
    static let rim: CGFloat = 1

    let frame: CGRect
    let edge: Edge
    let pointer: CGFloat
    let bodySize: CGSize

    static func place(anchor: CGRect, in screen: CGRect, preferred: Edge, size: CGSize) -> Self {
        let safe = screen.insetBy(dx: SideBar.gap, dy: SideBar.gap)
        let edges: [Edge]
        switch preferred {
        case .leading: edges = [.leading, .trailing, .bottom, .top]
        case .trailing: edges = [.trailing, .leading, .bottom, .top]
        case .bottom: edges = [.bottom, .top, .leading, .trailing]
        case .top: edges = [.top, .bottom, .leading, .trailing]
        }
        let reach = depth + gap + 2 * rim
        var candidates: [Self] = []
        for edge in edges {
            let side = edge == .leading || edge == .trailing
            let across: CGFloat
            switch edge {
            case .leading: across = safe.maxX - anchor.maxX - reach
            case .trailing: across = anchor.minX - safe.minX - reach
            case .bottom: across = safe.maxY - anchor.maxY - reach
            case .top: across = anchor.minY - safe.minY - reach
            }
            let width = min(size.width, side ? across : safe.width - 2 * rim)
            let height = min(size.height, side ? safe.height - 2 * rim : across)
            guard width > 0, height > 0 else { continue }

            let frameWidth = width + 2 * rim + (side ? depth : 0)
            let frameHeight = height + 2 * rim + (side ? 0 : depth)
            let x: CGFloat
            let y: CGFloat
            switch edge {
            case .leading:
                x = anchor.maxX + gap
                y = clamp(anchor.midY - frameHeight / 2, safe.minY, safe.maxY - frameHeight)
            case .trailing:
                x = anchor.minX - gap - frameWidth
                y = clamp(anchor.midY - frameHeight / 2, safe.minY, safe.maxY - frameHeight)
            case .bottom:
                x = clamp(anchor.midX - frameWidth / 2, safe.minX, safe.maxX - frameWidth)
                y = anchor.maxY + gap
            case .top:
                x = clamp(anchor.midX - frameWidth / 2, safe.minX, safe.maxX - frameWidth)
                y = anchor.minY - gap - frameHeight
            }
            let frame = CGRect(x: x, y: y, width: frameWidth, height: frameHeight)
            let pointer = side ? frame.maxY - anchor.midY - rim : anchor.midX - frame.minX - rim
            let candidate = Self(frame: frame, edge: edge, pointer: pointer, bodySize: CGSize(width: width, height: height))
            if candidate.bodySize == size { return candidate }
            candidates.append(candidate)
        }
        return candidates.max { $0.bodySize.width * $0.bodySize.height < $1.bodySize.width * $1.bodySize.height }
            ?? Self(frame: .zero, edge: preferred, pointer: 0, bodySize: .zero)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }

    var insets: EdgeInsets {
        let rim = Self.rim
        let extra = rim + Self.depth
        return EdgeInsets(top: edge == .top ? extra : rim, leading: edge == .leading ? extra : rim,
                          bottom: edge == .bottom ? extra : rim, trailing: edge == .trailing ? extra : rim)
    }
}

struct ProfilePopoverOutline: Shape {
    let placement: ProfilePopoverPlacement

    func path(in rect: CGRect) -> Path {
        let inset = placement.insets
        let x = rect.minX + inset.leading, y = rect.minY + inset.top
        let w = max(0, rect.width - inset.leading - inset.trailing)
        let h = max(0, rect.height - inset.top - inset.bottom)
        let corners = [CGPoint(x: x, y: y), CGPoint(x: x + w, y: y),
                       CGPoint(x: x + w, y: y + h), CGPoint(x: x, y: y + h)]
        let edges: [Edge] = [.top, .trailing, .bottom, .leading]
        let units = [CGVector(dx: 1, dy: 0), CGVector(dx: 0, dy: 1),
                     CGVector(dx: -1, dy: 0), CGVector(dx: 0, dy: -1)]
        let lengths = [w, h, w, h]
        guard let index = edges.firstIndex(of: placement.edge) else { return Path() }
        let length = lengths[index]
        let center = min(max(0, placement.pointer), length)
        let along = index < 2 ? center : length - center
        let half = min(CardFrame.inset, along, length - along)
        let radius = min(Radius.window, w / 2, h / 2)
        var radii = Array(repeating: radius, count: edges.count)
        // Shorten the corner next to a pointer near the screen edge to leave
        // its shoulders tangent to a straight edge and its center on the trigger.
        radii[index] = min(radius, along - half)
        radii[(index + 1) % edges.count] = min(radius, length - along - half)

        var outline = Path()
        outline.move(to: CGPoint(x: x + radii[0], y: y))
        for i in edges.indices {
            let next = (i + 1) % edges.count
            let start = corners[i], unit = units[i]
            func point(_ distance: CGFloat, out: CGFloat = 0) -> CGPoint {
                CGPoint(x: start.x + distance * unit.dx + out * unit.dy,
                        y: start.y + distance * unit.dy - out * unit.dx)
            }
            if i == index, half > 0 {
                let depth = ProfilePopoverPlacement.depth
                outline.addLine(to: point(along - half))
                // Both halves meet with matching tangents at the tip.
                outline.addCurve(to: point(along, out: depth),
                                 control1: point(along - half / 2), control2: point(along - half / 3, out: depth))
                outline.addCurve(to: point(along + half),
                                 control1: point(along + half / 3, out: depth), control2: point(along + half / 2))
            }
            let corner = corners[next], tangent = units[next], r = radii[next]
            outline.addLine(to: point(lengths[i] - r))
            outline.addQuadCurve(to: CGPoint(x: corner.x + tangent.dx * r, y: corner.y + tangent.dy * r), control: corner)
        }
        outline.closeSubpath()
        return outline
    }
}

@MainActor
final class ProfilePopover: ObservableObject {
    enum Item: Hashable {
        case header, profile(UUID), tabs, settings
    }

    @Published private(set) var shown = false
    @Published private(set) var focused: Item?
    @Published private(set) var placement: ProfilePopoverPlacement?
    weak var anchor: NSView?
    private weak var browser: Browser?
    private var panel: DropPanel?
    private var watchers: [NSObjectProtocol] = []
    private var mouseMonitor: Any?
    private var dismissedOnResign: TimeInterval?
    private var preferred: Edge = .bottom

    var choices: [Space] {
        guard let browser, browser.windowPurpose == .normal, !browser.blank, browser.prefs.usesSpaces else { return [] }
        var seen = Set<UUID>()
        let spaces = ([browser.currentProfileSpace] + browser.turnOrder.filter { $0.id != Space.mailID })
            .filter { seen.insert($0.profileID).inserted }
        return spaces.count > 1 ? spaces : []
    }

    func toggle(in browser: Browser, preferred: Edge) {
        if shown { close(); return }
        // The parent can become key before it delivers the click that
        // dismissed its child panel. Consume that press on the trigger.
        if let at = dismissedOnResign {
            dismissedOnResign = nil
            if ProcessInfo.processInfo.systemUptime - at < 0.2 { return }
        }
        guard let anchor, let window = anchor.window else { return }
        self.browser = browser
        self.preferred = preferred
        reposition()
        guard let placement, placement.bodySize.height >= minimumHeight else { return }

        let panel = DropPanel(contentRect: placement.frame, styleMask: [.borderless, .nonactivatingPanel],
                              backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.appearance = window.effectiveAppearance
        panel.level = window.level
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        let host = NSHostingView(rootView: WorkspaceThemeReader(browser: browser) { theme in
            let tone = theme.tone ?? SpaceSurface.tone(in: browser)
            ProfileSwitcher(browser: browser, popover: self).toned(tone)
        })
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.closes = { [weak self] in
            self?.dismissedOnResign = ProcessInfo.processInfo.systemUptime
            self?.close(restoreFocus: false)
        }
        panel.actionKey = { [weak self] event in self?.handle(event) ?? false }
        panel.actionKeyEquivalent = panel.actionKey
        self.panel = panel
        let opening = NSApp.currentEvent?.type
        focused = opening == .keyDown || opening == .keyUp ? .header : nil
        shown = true
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self, weak anchor] event in
            guard let self, let anchor, event.window === anchor.window,
                  anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) else { return event }
            self.close()
            return nil
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
            watchers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reposition() }
            })
        }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animate ? 0 : 1
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        if animate {
            NSAnimationContext.runAnimationGroup { animation in
                animation.duration = 0.12
                panel.animator().alphaValue = 1
            }
        }
    }

    private var minimumHeight: CGFloat {
        ProfileSwitcher.fixedHeight(hasChoices: !choices.isEmpty) + (choices.isEmpty ? 0 : SideBar.row)
    }

    func reposition() {
        guard let anchor, let window = anchor.window, let screen = window.screen, !anchor.bounds.isEmpty else { return }
        let face = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let size = CGSize(width: ProfileSwitcher.width, height: ProfileSwitcher.height(for: choices.count))
        let visible = window.frame.intersection(screen.visibleFrame)
        let inside = ProfilePopoverPlacement.place(anchor: face, in: visible, preferred: preferred, size: size)
        // Prefer the visible browser viewport. Small or partially obscured
        // windows can borrow space from their screen for the complete menu.
        let next = inside.bodySize.height >= minimumHeight && inside.bodySize.width == size.width ? inside
            : ProfilePopoverPlacement.place(anchor: face, in: screen.visibleFrame, preferred: preferred, size: size)
        if panel != nil, next.bodySize.height < minimumHeight { close(); return }
        guard placement != next else { return }
        placement = next
        panel?.setFrame(next.frame, display: true)
        panel?.invalidateShadow()
    }

    func close(restoreFocus: Bool = true, action: (() -> Void)? = nil) {
        guard let panel else { return }
        self.panel = nil
        shown = false
        focused = nil
        watchers.forEach(NotificationCenter.default.removeObserver)
        watchers.removeAll()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        let parent = panel.parent
        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.closes = {}
        panel.actionKey = nil
        panel.actionKeyEquivalent = nil
        panel.ignoresMouseEvents = true
        if restoreFocus { parent?.makeKey() }
        if action != nil || still {
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ animation in
                animation.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            })
        }
        action?()
    }

    func choose(_ item: Item) {
        guard let browser else { return }
        close {
            switch item {
            case .header, .settings: SettingsWindow.shared.show(.profile, for: browser)
            case .tabs: browser.showLibrary(.tabs)
            case .profile(let id):
                if let space = browser.spaces.first(where: { $0.id == id }),
                   space.profileID != browser.currentProfileSpace.profileID { browser.switchSpace(to: id) }
            }
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        switch event.keyCode {
        case 53: close(); return true
        case 36, 76, 49: choose(focused ?? .header); return true
        case 48, 125, 126:
            let items = [Item.header] + choices.map { .profile($0.id) } + [.tabs, .settings]
            let step = event.keyCode == 126 || (event.keyCode == 48 && event.modifierFlags.contains(.shift)) ? -1 : 1
            let current = focused.flatMap { items.firstIndex(of: $0) } ?? (step == 1 ? -1 : 0)
            focused = items[(current + step + items.count) % items.count]
            return true
        default: return false
        }
    }
}

struct ProfilePopoverAnchor: NSViewRepresentable {
    let popover: ProfilePopover

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        popover.anchor = view
        if popover.shown { DispatchQueue.main.async { popover.reposition() } }
    }
}
