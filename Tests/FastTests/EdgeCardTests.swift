import AppKit
import Testing
@testable import Fast

/// Feedback #165: with the window edge to edge, the column brought out over
/// the page is a card in its space's look, as Arc's sidebar out over the
/// page wears its space's theme, and the same paint as on a color.
@Suite(.serialized)
struct EdgeCardTests {
    @Test func pageLayoutRestoresTheLegacyFrameAndHonorsAnExplicitChoice() {
        #expect(PageLayout.restored(nil, backdrop: .none) == .edgeToEdge)
        #expect(PageLayout.restored(nil, backdrop: .color) == .card)
        #expect(PageLayout.restored(nil, backdrop: .site) == .card)
        #expect(PageLayout.restored(PageLayout.edgeToEdge.rawValue, backdrop: .site) == .edgeToEdge)
        #expect(PageLayout.restored(PageLayout.card.rawValue, backdrop: .none) == .card)
    }

    @MainActor @Test func pageFrameDoesNotChangeTheWindowPaint() throws {
        try #require(Store.testing)
        let prefs = Preferences()
        let savedLayout = prefs.pageLayout
        let savedMode = prefs.backdrop
        defer {
            prefs.pageLayout = savedLayout
            prefs.backdrop = savedMode
        }
        prefs.backdrop = .color
        prefs.pageLayout = .card
        let paint = try #require(SpaceWash.worn(prefs))

        prefs.pageLayout = .edgeToEdge
        #expect(prefs.backdrop == .color)
        #expect(SpaceWash.worn(prefs) == paint)
        #expect(Preferences().pageLayout == .edgeToEdge)
    }

    @MainActor @Test func edgeToEdgeCardWearsTheSpacesLookAsOnAColor() throws {
        try #require(Store.testing)
        let prefs = Preferences()
        let saved = SpacePaint(prefs)
        let savedMode = prefs.backdrop
        let savedSidebar = prefs.sidebar, savedShut = prefs.sideShut
        defer {
            saved.wear(prefs)
            prefs.backdrop = savedMode
            prefs.sidebar = savedSidebar
            prefs.sideShut = savedShut
        }
        prefs.sidebar = true
        prefs.sideShut = true
        prefs.swatch = .custom
        prefs.backdropColor = NSColor(srgbRed: 0.12, green: 0.17, blue: 0.28, alpha: 1)
        prefs.grain = 0.4
        prefs.backdropTransparency = 0.3
        prefs.backdropColors = ["8FB8A0"]
        prefs.lookGlass = false
        prefs.backdrop = .color
        let framed = try #require(SpaceWash.worn(prefs))
        let tone = Tone(framed.color, lifted: true, glass: false)
        prefs.backdrop = .none
        // Put away, the window wears nothing of its own; the card the space's look:
        // its color, gradient, grain and frost, so the same inks.
        #expect(SpaceWash.worn(prefs) == nil)
        let card = Column.paint(tone, prefs: prefs)
        #expect(card == framed)
        #expect(card.colors.count == 1 && card.grain == 0.4)
        #expect(tone.card(card) == tone.card(framed))
    }

    /// #256: docked edge to edge, the column stands on the window's own
    /// backdrop, so a look and its glass read as they do on a color.
    @MainActor @Test func dockedEdgeToEdgeWearsTheWindowsBackdropAsOnAColor() throws {
        try #require(Store.testing)
        let prefs = Preferences()
        let saved = SpacePaint(prefs)
        let savedMode = prefs.backdrop
        let savedSidebar = prefs.sidebar, savedShut = prefs.sideShut
        defer {
            saved.wear(prefs)
            prefs.backdrop = savedMode
            prefs.sidebar = savedSidebar
            prefs.sideShut = savedShut
        }
        prefs.swatch = .custom
        prefs.backdropColor = NSColor(srgbRed: 0.25, green: 0.48, blue: 0.88, alpha: 1)
        prefs.grain = 0.2
        prefs.backdropTransparency = 0.4
        prefs.backdropColors = []
        prefs.sidebar = true
        prefs.sideShut = false
        for glass in [false, true] {
            prefs.lookGlass = glass
            prefs.backdrop = .color
            let framed = try #require(SpaceWash.worn(prefs))
            let framedGlass = prefs.wearsGlass
            prefs.backdrop = .none
            #expect(prefs.edgeBackdrop)
            #expect(SpaceWash.worn(prefs) == framed)
            #expect(prefs.wearsGlass == framedGlass)
            #expect(prefs.wornTransparency(dark: false) == SpacePaint(prefs).wornTransparency(dark: false))
        }
        // Put away, or with the tabs across the top, the window is the
        // page's alone again.
        prefs.sideShut = true
        #expect(!prefs.edgeBackdrop && SpaceWash.worn(prefs) == nil && !prefs.wearsGlass)
        prefs.sideShut = false
        prefs.sidebar = false
        #expect(!prefs.edgeBackdrop && SpaceWash.worn(prefs) == nil)
    }
}
