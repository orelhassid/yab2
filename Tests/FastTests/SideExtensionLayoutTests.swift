import Foundation
import Testing
@testable import Fast

@MainActor
struct SideExtensionLayoutTests {
    private func layout(width: CGFloat, count: Int, door: CGFloat, controls: Int = 3) -> SideExtensionLayout {
        SideExtensionLayout(width: width, count: count, door: door, controls: controls, margin: SideBar.margin,
                            columns: SideBar.pinColumns(count, width: width), gap: SideBar.pinGap)
    }

    @Test func emptyAndSinglePinKeepAddressHeight() {
        for count in [0, 1] {
            let layout = layout(width: 240, count: count, door: 28)
            #expect(!layout.separate)
            #expect(layout.height == 0)
        }
    }

    @Test func wideningTheSidebarBringsTheSamePinsBackInline() {
        let narrow = layout(width: 240, count: 4, door: 28)
        let wide = layout(width: 360, count: 4, door: 28)
        #expect(narrow.separate)
        #expect(narrow.columns == 4)
        #expect(narrow.cell >= 28)
        #expect(!wide.separate)
        #expect(wide.height == 0)
    }

    @Test func bookmarkControlReservesRoomForTheAddress() {
        #expect(!layout(width: 240, count: 2, door: 28, controls: 2).separate)
        #expect(layout(width: 240, count: 2, door: 28, controls: 3).separate)
    }

    @Test func spacePlateReservesTheWrappedPinRowWhenResizedBesideTheTrail() throws {
        let prefsKeys = ["sidebar", "sidebar.flank", "sidebar.shut", "sidebar.width", "spaces", Preferences.trailPositionKey]
        let saved = prefsKeys.map { ($0, Store.settings.object(forKey: $0)) }
        let browser = Browser(windowID: UUID())
        let space = UUID()
        let file = Extensions.list(of: space)
        let tab = Tab(bench: true, engine: .webKit)
        defer {
            tab.close()
            browser.letGo()
            try? FileManager.default.removeItem(at: file)
            for (key, value) in saved { Store.settings.set(value, forKey: key) }
        }
        let pin = Installed(id: "resize-fixture", name: "Pinned extension", version: "1",
                            enabled: true, fromStore: false, permissions: [], pinned: true)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode([pin]).write(to: file)
        tab.restore(url: URL(string: "https://example.test/")!, title: "Example")
        browser.prefs.sidebar = true
        browser.prefs.sideFlank = .left
        browser.prefs.sideShut = false
        browser.prefs.usesSpaces = true
        browser.prefs.trailPosition = .left

        browser.prefs.sideWidth = 324
        #expect(SidePlate.pinsHeight(in: browser, space: space, tab: tab) == 0)
        browser.prefs.sideWidth = Metrics.sideMin
        #expect(browser.railInsideColumn > 0)
        #expect(SidePlate.pinsHeight(in: browser, space: space, tab: tab) == SidePlate.door + SideBar.pinGap)

        browser.prefs.trailPosition = .right
        #expect(SidePlate.pinsHeight(in: browser, space: space, tab: tab) == 0)
    }

    @Test func everyPinHasRoomAtEveryDensity() {
        for door: CGFloat in [26, 28] {
            for width: CGFloat in [200, 240, 300, 360] {
                for count in [4, 8, 12, 30] {
                    let layout = self.layout(width: width, count: count, door: door)
                    if layout.separate {
                        #expect(layout.cell >= door)
                        #expect(CGFloat(layout.columns) * layout.cell + CGFloat(layout.columns - 1) * layout.gap <= width - 16 + 0.01)
                        let rows = Int(layout.height / (door + layout.gap))
                        #expect(rows * layout.columns >= count)
                    }
                }
            }
        }
    }
    @Test func extensionTilesUseTheFavoritesGrid() {
        for width: CGFloat in [200, 220, 240, 300, 360] {
            for count in [4, 5, 6, 12] {
                let extensions = layout(width: width, count: count, door: 28)
                let favorites = ColumnLayout.grid(count: count, width: width)
                #expect(extensions.columns == favorites.cols)
                #expect(abs(extensions.cell - favorites.width) < 0.01)
                #expect(extensions.gap == SideBar.pinGap)
            }
        }
    }

}
