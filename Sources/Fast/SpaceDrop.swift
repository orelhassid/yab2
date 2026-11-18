import AppKit
import SwiftUI

// A tab dragged in the column or the strip, held over the space's capsule,
// opens the tray as a spring-loaded folder does in the Finder: its list is
// where the tab can go. Over a space, the row says what letting go does;
// let go, the tab goes there (Browser.moveTabs) and the window stays. Over
// New Space, a new space is made around it. Taken away past the tray's
// edge, the tray goes and the drag goes on as it was. Held over a space in
// the foot's row, as over Arc's space icons, that space is lit, and let go
// there the tab goes to it at once.
//
// A folder of yours dragged whole comes the same ways, and goes whole
// (Browser.moveFolder) to the space it is let go over, or into a new one.
//
// The drag stays the column's or the strip's own gesture: it asks here as
// the hand moves, and here when it lets go, and does nothing of its own
// while this answers yes.

@MainActor
final class SpaceDrop: ObservableObject {
    static let shared = SpaceDrop()

    /// The capsule under a tab in the hand, before the tray opens.
    @Published private(set) var hot = false

    /// How long the hand rests on the capsule before the tray opens: a tab
    /// dragged past it on the way somewhere else doesn't open it.
    static let wait: TimeInterval = 0.25
    static let springWait: TimeInterval = 0.35
    /// How far past the tray's edge the hand may go and keep it.
    static let reach: CGFloat = 40

    /// The foot's space under the hand, retained after spring-loading so
    /// letting go on that same door still means top of today.
    @Published private(set) var slot: UUID?

    @Published private(set) var trailOwner: ObjectIdentifier?
    @Published private(set) var overTrail = false

    private var carrying: [Tab] = []
    /// The folder they are, when a folder of yours is in the hand.
    private var folder: Nest?
    private var waiting: DispatchWorkItem?
    private var springing: DispatchWorkItem?
    private weak var owner: Browser?

    /// The hand moved, carrying these tabs, or `folder` whole. Yes while it
    /// is over the capsule, the tray or a space in the foot: the row it came
    /// from leaves it alone. `at`: a point in the window, for the bench;
    /// otherwise the drag's own event's, or the pointer's.
    func track(_ tabs: [Tab], browser: Browser, folder: Nest? = nil, at given: NSPoint? = nil) -> Bool {
        guard browser.spacesShown, !tabs.isEmpty || folder != nil,
              let window = BrowserWindows.shared.window(for: browser) ?? Links.window else { return false }
        if let owner, owner !== browser { cancel() }
        owner = browser
        let point = given ?? {
            if let event = NSApp.currentEvent, event.window === window, event.type == .leftMouseDragged { return event.locationInWindow }
            return window.convertPoint(fromScreen: NSEvent.mouseLocation)
        }()
        carrying = tabs
        self.folder = folder
        let eligible = folder == nil && (browser.spaceRailWidth > 0 || browser.sidebarAppsShown) && !tabs.isEmpty
            && tabs.allSatisfy { TrailApps.shared.address(for: $0) != nil }
        let hoveringTrail = eligible && SpaceAnchors.overTrail(point, in: window, pinsOnly: false)
        let trail = hoveringTrail ? ObjectIdentifier(browser) : nil
        if trailOwner != trail { trailOwner = trail }
        let inside = hoveringTrail && SpaceAnchors.overTrail(point, in: window)
        if overTrail != inside { overTrail = inside }
        if inside {
            settle()
            SpaceTray.shown?.leave()
            return true
        }
        // A foot door accepts a drop immediately and opens after a rest.
        if SpaceTray.shown == nil, let id = SpaceAnchors.slot(at: point, in: window), (id != browser.spaceID || slot == id),
           browser.spaces.contains(where: { $0.id == id }) {
            if slot != id {
                settle()
                slot = id
                // SwiftUI's row and the top strip keep their current dot
                // drop. Only the AppKit hand survives a page changing.
                if ColumnSpaceCarry.of(browser) != nil {
                    let work = DispatchWorkItem { [weak self, weak browser] in
                        guard let self, let browser, self.owner === browser, self.slot == id,
                              ColumnSpaceCarry.of(browser) != nil else { return }
                        browser.switchSpace(to: id)
                    }
                    springing = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.springWait, execute: work)
                }
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            return true
        }
        if slot != nil {
            slot = nil
            springing?.cancel()
            springing = nil
        }
        guard !tabs.isEmpty else { return false }
        if let tray = SpaceTray.shown, !tray.draft.carrying.isEmpty {
            if let over = tray.dropTarget(at: point) {
                if tray.draft.over != over { tray.draft.over = over }
                return true
            }
            if overCapsule(point, window: window) {
                if tray.draft.over != nil { tray.draft.over = nil }
                return true
            }
            tray.leave()
            return false
        }
        guard SpaceTray.shown == nil, overCapsule(point, window: window) else {
            settle()
            return hoveringTrail
        }
        if !hot {
            hot = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            let work = DispatchWorkItem { [weak self] in
                guard let self, hot, !carrying.isEmpty else { return }
                hot = false
                SpaceTray.openCarrying(browser, tabs: carrying)
            }
            waiting = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.wait, execute: work)
        }
        return true
    }

    func finishTrail(_ browser: Browser, at point: NSPoint?) -> Bool {
        guard owner === browser, trailOwner == ObjectIdentifier(browser),
              let window = BrowserWindows.shared.window(for: browser) ?? Links.window,
              let point, SpaceAnchors.overTrail(point, in: window) else {
            if overTrail { overTrail = false }
            return false
        }
        carrying.forEach { TrailApps.shared.pin($0) }
        cancel()
        return true
    }

    /// Let go. Yes when it was over a space and the tabs went there, or
    /// over New Space; the row they came from forgets the drag.
    func finish(_ browser: Browser) -> Bool {
        let folder = self.folder
        defer {
            carrying = []
            self.folder = nil
        }
        if overTrail, owner === browser {
            carrying.forEach { TrailApps.shared.pin($0) }
            cancel()
            return true
        }
        if trailOwner != nil { trailOwner = nil }
        let tabs = carrying
        let lit = slot
        settle()
        if let lit {
            if let hand = ColumnSpaceCarry.of(browser), hand.finish(dot: lit) { return true }
            if let folder { browser.moveFolder(folder, to: lit) } else { browser.moveTabs(tabs, to: lit, top: true) }
            return true
        }
        guard let tray = SpaceTray.shown, !tray.draft.carrying.isEmpty else { return false }
        guard let over = tray.draft.over, !tabs.isEmpty else {
            tray.leave()
            return false
        }
        if over < 0 {
            if let folder { SpaceTray.open(browser, folder: folder) } else { SpaceTray.open(browser, taking: tabs) }
            return true
        }
        guard browser.spaces.indices.contains(over), browser.spaces[over].id != browser.spaceID else {
            tray.leave()
            return false
        }
        let target = browser.spaces[over].id
        tray.draft.over = nil
        tray.draft.landed[target, default: 0] += 1
        if let folder { browser.moveFolder(folder, to: target, say: false) } else { browser.moveTabs(tabs, to: target, say: false) }
        // The emoji gives, then the tray goes back into the capsule.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { tray.leave() }
        return true
    }

    /// A drag given up (Escape): nothing goes anywhere, the tray goes.
    func cancel() {
        if trailOwner != nil { trailOwner = nil }
        if overTrail { overTrail = false }
        carrying = []
        folder = nil
        settle()
        SpaceTray.shown?.leave()
    }

    /// The hand gone elsewhere, or the drag over.
    private func settle() {
        waiting?.cancel()
        waiting = nil
        springing?.cancel()
        springing = nil
        if hot { hot = false }
        if slot != nil { slot = nil }
    }

    private func overCapsule(_ point: NSPoint, window: NSWindow) -> Bool {
        guard let dot = SpaceAnchors.dot, dot.window === window else { return false }
        return dot.convert(dot.bounds, to: nil).insetBy(dx: -4, dy: -4).contains(point)
    }
}
