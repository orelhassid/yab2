import Foundation
import Testing
@testable import Fast

struct SidebarWidthDetentTests {
    @Test(arguments: [CGFloat(200), CGFloat(280)])
    func returningToDefaultTicksOnceDespitePointerJitter(start: CGFloat) {
        var detent = SidebarWidthDetent(width: start)
        let arrival = detent.update(wanted: Metrics.side + (start < Metrics.side ? -3 : 3), maximum: Metrics.sideMax)
        #expect(arrival.width == Metrics.side)
        #expect(arrival.aligned)
        for offset: CGFloat in [-2, 3, -5, 7, 0] {
            let result = detent.update(wanted: Metrics.side + offset, maximum: Metrics.sideMax)
            #expect(result.width == Metrics.side)
            #expect(!result.aligned)
        }
        let departure = detent.update(wanted: Metrics.side + 10, maximum: Metrics.sideMax)
        #expect(departure.width == Metrics.side + 10)
        #expect(!departure.aligned)
        #expect(detent.update(wanted: Metrics.side, maximum: Metrics.sideMax).aligned)
    }

    @Test func startingAtDefaultOnlyTicksAfterLeavingAndReturning() {
        var detent = SidebarWidthDetent(width: Metrics.side)
        #expect(!detent.update(wanted: Metrics.side + 2, maximum: Metrics.sideMax).aligned)
        #expect(!detent.update(wanted: Metrics.side - 20, maximum: Metrics.sideMax).aligned)
        #expect(detent.update(wanted: Metrics.side, maximum: Metrics.sideMax).aligned)
    }

    @Test func fastCrossingsTickInBothDirectionsWithoutReversingTheDrag() {
        var detent = SidebarWidthDetent(width: 200)
        let outward = detent.update(wanted: Metrics.side + 20, maximum: Metrics.sideMax)
        #expect(outward.width == Metrics.side + 20 && outward.aligned)
        #expect(!detent.update(wanted: Metrics.side + 30, maximum: Metrics.sideMax).aligned)
        let inward = detent.update(wanted: Metrics.side - 20, maximum: Metrics.sideMax)
        #expect(inward.width == Metrics.side - 20 && inward.aligned)
    }

    @Test func unavailableDefaultDoesNotTickOrExceedSplitViewRoom() {
        var detent = SidebarWidthDetent(width: 200)
        let result = detent.update(wanted: 250, maximum: Metrics.sideMin + 4)
        #expect(result.width == Metrics.sideMin + 4)
        #expect(!result.aligned)
        #expect(detent.update(wanted: 100, maximum: Metrics.sideMin + 4).width == Metrics.sideMin)
        #expect(detent.update(wanted: 600, maximum: Metrics.sideMax).width == Metrics.sideMax)
    }
}
