import AppKit
import SwiftUI
import Testing
@testable import Fast

/// The island stands over the column's foot, which keeps the column's
/// bottom as in Arc (row 1090): the island takes its room from the rows,
/// never pushing the downloads, the plus and the spaces up, and its row
/// never reaches down over them.
@MainActor
@Suite(.serialized)
struct PlayerPlacementTests {
    @Test func theIslandRowStandsOverTheFoot() {
        let base = Band.base(edge: Band.edge, foot: true)
        #expect(base == SideBar.footHeight + Band.edge)
        // The row's bottom is clear of the foot's top.
        #expect(base >= SideBar.footHeight)
        // With no foot it keeps the column's corner.
        #expect(Band.base(edge: Band.edge, foot: false) == Band.edge)
        // Full screen's inset moves it the same way over the foot.
        #expect(Band.base(edge: 12, foot: true) == SideBar.footHeight + 12)
    }

    @Test(arguments: [true, false], [true, false])
    func theSlotFitsBesideTheTrailAndAboveTheFoot(trailing: Bool, foot: Bool) throws {
        _ = NSApplication.shared
        let browser = Browser(windowID: UUID())
        defer {
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.stuck.agentTimer?.invalidate()
            browser.stuck.frontTimer?.invalidate()
            browser.pressure?.cancel()
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
            }
        }
        let column = Metrics.sideMin
        let margin = SideBar.margin
        for rail in [0, SideBar.row + 2 * margin] {
            let host = NSHostingView(rootView: BandSlot(player: browser.player, prefs: browser.prefs,
                                                        room: browser.player.room, column: column,
                                                        rail: rail, trailing: trailing, foot: foot))
            // As tall as it asks: SwiftUI centers a smaller view in a
            // taller host, and the column pins it to its bottom.
            let size = host.fittingSize
            #expect(abs(size.width - column) < 0.5)
            #expect(abs(size.height - Band.reach - Band.base(edge: Band.edge, foot: foot)) < 0.5)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let band = try #require(Self.band(in: host))
            let frame = band.convert(band.bounds, to: host)
            #expect(abs(frame.minX - (margin + (trailing ? 0 : rail))) < 0.5)
            #expect(abs(frame.maxX - (column - margin - (trailing ? rail : 0))) < 0.5)
            // AppKit's y runs up from the host's bottom, where the slot's
            // bottom stands.
            let bottom = host.isFlipped ? host.bounds.height - frame.maxY : frame.minY
            #expect(abs(bottom - Band.base(edge: Band.edge, foot: foot)) < 0.5, "foot \(foot): bottom \(bottom)")
        }
    }

    private static func band(in view: NSView) -> BandView? {
        (view as? BandView) ?? view.subviews.lazy.compactMap(band(in:)).first
    }
}
