import Foundation
import Testing
@testable import Fast

// The column header's row (ColumnHead): the column's own door after the
// lights, and where the row folds, at the numbers the Oct 20 mockup has.
// No reading mode door in this row.
@MainActor
@Suite(.serialized)
struct ColumnHeadTests {
    static let comfortable = Door.Size(side: 30, glyph: 13, arrow: 14.5, mark: 16, gap: 4)
    static let compact = Door.Size(side: 28, glyph: 12, arrow: 13.5, mark: 15, gap: 4)

    @Test func doorStandsTwentySevenFromTheGreenLight() {
        #expect(ColumnHead.green == 66)
        #expect(ColumnHead.doorX(Self.comfortable) == 78)
        #expect(ColumnHead.doorX(Self.comfortable) + 15 - ColumnHead.green == 27)
    }

    @Test func thresholdsComfortable() {
        #expect(ColumnHead.full(right: false, size: Self.comfortable, margin: 8) == 218)
        let fit = { (w: CGFloat) in ColumnHead.fit(width: w, right: false, size: Self.comfortable, margin: 8) }
        #expect(fit(189) == .fold)
        #expect(fit(217) == .fold)
        #expect(fit(218) == .full)
        #expect(fit(475) == .full)
    }

    @Test func thresholdsCompact() {
        let fit = { (w: CGFloat) in ColumnHead.fit(width: w, right: false, size: Self.compact, margin: 8) }
        #expect(ColumnHead.doorX(Self.compact) == 79)
        #expect(fit(210) == .fold)
        #expect(fit(211) == .full)
    }

    /// On the right the lights are over the page: everything fits at the
    /// column's narrowest.
    @Test func rightAlwaysFits() {
        #expect(ColumnHead.full(right: true, size: Self.comfortable, margin: 8) == 148)
        #expect(ColumnHead.fit(width: Metrics.sideMin, right: true, size: Self.comfortable, margin: 8) == .full)
        #expect(ColumnHead.fit(width: Metrics.sideMin, right: true, size: Self.compact, margin: 8) == .full)
    }

    @Test func headerFitsAtMinimumSidebarWidth() {
        let size = ColumnHead.doors(width: Metrics.sideMin, right: false, margin: 8)
        #expect(ColumnHead.fit(width: Metrics.sideMin, right: false, size: Self.comfortable, margin: 8) == .full)
        #expect(8 + Metrics.sideLights + size.helm + 8 <= Metrics.sideMin)
        #expect(ColumnHead.doors(width: 189, right: false, margin: 8).side == Door.Size.header.side)
        #expect(ColumnHead.doors(width: Metrics.sideMin, right: true, margin: 8).side == Door.Size.header.side)
    }

    /// Arc's arrows and mark are larger than the rest of the row's glyphs.
    @Test func arrowsAndMarkAsArcDrawsThem() {
        let size = Self.comfortable
        #expect(size.glyph(for: "arrow.left") == 14.5)
        #expect(size.glyph(for: "arrow.right") == 14.5)
        #expect(size.glyph(for: "sidebar.left") == 16)
        #expect(size.glyph(for: "sidebar.right") == 16)
        #expect(size.glyph(for: "arrow.clockwise") == 13)
        #expect(Door.Size().glyph(for: "arrow.left") == 11)
    }

    /// One line weight and round marks in both rows. The header's reload
    /// uses the Oct 22 sizes; the band's smaller override stays separate.
    @Test(arguments: [Density.comfortable, .compact])
    func headerDrawsOneWeight(density: Density) {
        let before = Density.current
        Density.current = density
        defer { Density.current = before }

        let header = Door.Size.header, band = Door.Size.band
        for size in [header, band] {
            #expect(size.stroke == 1.5)
            #expect(size.drawing(for: "sidebar.left") == "sidebar.left.round")
            #expect(size.drawing(for: "sidebar.right") == "sidebar.right.round")
            #expect(size.drawing(for: "arrow.left") == "arrow.left")
        }
        // Check the optional override itself: removing it must fail even
        // when Symbol's default rounded square happens to be the same size.
        #expect(header.side(for: "arrow.clockwise") == (density == .compact ? 16 : 18))
        #expect(band.side(for: "arrow.clockwise") == 16.5)
        #expect((band.side(for: "arrow.clockwise") ?? 99) < (band.glyph(for: "arrow.clockwise") * Glyphs.scale).rounded())
        #expect(header.side(for: "arrow.left") == nil)
        #expect(Door.Size().side(for: "arrow.clockwise") == nil)
        #expect(Door.Size().drawing(for: "sidebar.left") == "sidebar.left")
        #expect(Glyphs.art("sidebar.left.round", stroke: 1.5, side: 22) != nil)
        #expect(Glyphs.art("sidebar.right.round", stroke: 1.5, side: 22) != nil)
    }

    /// Arc's sidebar mark, Central's own, its pane on the column's side.
    @Test func sidebarMarksAreDrawn() {
        #expect(ColumnDoor.mark(.left) == "sidebar.left")
        #expect(ColumnDoor.mark(.right) == "sidebar.right")
        #expect(Glyphs.art("sidebar.left") != nil)
        #expect(Glyphs.art("sidebar.right") != nil)
    }

    /// #550: hiding the sidebar door gives Reload the space it occupied.
    @Test func hiddenSidebarDoorKeepsReloadOutOfOverflow() {
        #expect(ColumnHead.full(right: false, size: Self.comfortable, margin: 8, showSidebarButton: false) == 180)
        #expect(ColumnHead.full(right: true, size: Self.comfortable, margin: 8, showSidebarButton: false) == 114)
        #expect(ColumnHead.fit(width: 189, right: false, size: Self.comfortable, margin: 8) == .fold)
        #expect(ColumnHead.fit(width: 189, right: false, size: Self.comfortable, margin: 8, showSidebarButton: false) == .full)
        #expect(ColumnHead.full(right: false, size: Self.compact, margin: 8, showSidebarButton: false) == 174)
        #expect(ColumnHead.fit(width: 173, right: false, size: Self.compact, margin: 8, showSidebarButton: false) == .fold)
        #expect(ColumnHead.fit(width: 174, right: false, size: Self.compact, margin: 8, showSidebarButton: false) == .full)
    }

    @Test func sidebarButtonStartsVisibleAndPersistsTheChoice() {
        let store = Store.settings, key = "sidebar.button"
        let before = store.object(forKey: key)
        defer { store.set(before, forKey: key) }
        store.removeObject(forKey: key)
        let prefs = Preferences()
        #expect(prefs.sidebarButton)
        prefs.sidebarButton = false
        #expect(store.object(forKey: key) as? Bool == false)
        #expect(!Preferences().sidebarButton)
        prefs.sidebarButton = true
        #expect(Preferences().sidebarButton)
    }

    @Test func hidingSidebarDoorKeepsItsMenuAndShortcut() {
        let browser = Browser(windowID: UUID())
        let before = browser.prefs.sidebarButton
        let key = Keymap.shared.keys(.column)
        defer {
            browser.prefs.sidebarButton = before
            browser.dozing?.invalidate()
            browser.stuck.timer?.invalidate()
            browser.pressure?.cancel()
            browser.tabs.forEach { $0.close() }
            if let id = browser.windowID {
                try? FileManager.default.removeItem(at: Store.file("session-window-\(id.uuidString).json"))
                Store.settings.removeObject(forKey: "window.\(id.uuidString).space")
            }
        }
        browser.prefs.sidebarButton = false
        let menu = HelmMore.make(browser, tab: nil, own: false)
        #expect(menu.items.contains { $0.title == browser.columnTitle })
        #expect(menu.items.contains { $0.title == "Reload" })
        #expect(Keymap.shared.keys(.column) == key)
    }
}
