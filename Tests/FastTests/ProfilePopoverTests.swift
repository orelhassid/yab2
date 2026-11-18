import SwiftUI
import Testing
@testable import Fast

struct ProfilePopoverTests {
    private let screen = CGRect(x: 0, y: 24, width: 900, height: 600)
    private let size = CGSize(width: 260, height: 308)

    @Test func sidePointerFollowsTriggerWhenBodyClampsToScreen() {
        let anchor = CGRect(x: 8, y: 32, width: 36, height: 36)
        let placement = ProfilePopoverPlacement.place(anchor: anchor, in: screen, preferred: .leading, size: size)
        #expect(placement.edge == .leading)
        #expect(screen.contains(placement.frame))
        #expect(placement.frame.maxY - ProfilePopoverPlacement.rim - placement.pointer == anchor.midY)
        #expect(placement.frame.minX == anchor.maxX + ProfilePopoverPlacement.gap)
        checkSymmetricPointer(placement)
    }

    @Test func pointerFlipsToOppositeEdgeWhenPreferredSideDoesNotFit() {
        let anchor = CGRect(x: 850, y: 40, width: 36, height: 36)
        let placement = ProfilePopoverPlacement.place(anchor: anchor, in: screen, preferred: .leading, size: size)
        #expect(placement.edge == .trailing)
        #expect(screen.contains(placement.frame))
        #expect(placement.frame.maxY - ProfilePopoverPlacement.rim - placement.pointer == anchor.midY)
        checkSymmetricPointer(placement)
    }

    @Test func footerPointerKeepsItsCenterWhenFlippedAtTopOfScreen() {
        let anchor = CGRect(x: 855, y: 565, width: 36, height: 36)
        let placement = ProfilePopoverPlacement.place(anchor: anchor, in: screen, preferred: .bottom, size: size)
        #expect(placement.edge == .top)
        #expect(screen.contains(placement.frame))
        #expect(placement.frame.minX + ProfilePopoverPlacement.rim + placement.pointer == anchor.midX)
        checkSymmetricPointer(placement)
    }

    @Test func footerPointerRemainsCenteredOnTheBottomEdge() {
        let anchor = CGRect(x: 240, y: 28, width: 36, height: 36)
        let placement = ProfilePopoverPlacement.place(anchor: anchor, in: screen, preferred: .bottom, size: size)
        #expect(placement.edge == .bottom)
        #expect(screen.contains(placement.frame))
        #expect(placement.frame.minX + ProfilePopoverPlacement.rim + placement.pointer == anchor.midX)
        checkSymmetricPointer(placement)
    }

    @Test func shortViewportCapsTheContentHeight() {
        let short = CGRect(x: 0, y: 24, width: 900, height: 260)
        let anchor = CGRect(x: 8, y: 32, width: 36, height: 36)
        let placement = ProfilePopoverPlacement.place(anchor: anchor, in: short, preferred: .leading, size: size)
        #expect(short.contains(placement.frame))
        #expect(placement.bodySize.height < size.height)
        #expect(placement.bodySize.width == size.width)
    }

    private func checkSymmetricPointer(_ placement: ProfilePopoverPlacement) {
        let rect = CGRect(origin: .zero, size: placement.frame.size)
        let path = ProfilePopoverOutline(placement: placement).path(in: rect)
        let rim = ProfilePopoverPlacement.rim
        let midpoint = placement.pointer + rim
        func point(_ along: CGFloat, depth: CGFloat) -> CGPoint {
            switch placement.edge {
            case .top: return CGPoint(x: along, y: rim + depth)
            case .leading: return CGPoint(x: rim + depth, y: along)
            case .trailing: return CGPoint(x: rect.maxX - rim - depth, y: along)
            case .bottom: return CGPoint(x: along, y: rect.maxY - rim - depth)
            }
        }
        #expect(path.contains(point(midpoint, depth: 1)))
        #expect(path.contains(point(midpoint - 2, depth: 2)))
        #expect(path.contains(point(midpoint + 2, depth: 2)))
        #expect(!path.contains(point(midpoint - 11, depth: 2)))
        #expect(!path.contains(point(midpoint + 11, depth: 2)))
    }
}
