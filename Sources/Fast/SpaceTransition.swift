import Foundation
import AppKit

enum SpaceTransition: String, CaseIterable, Identifiable {
    case slide, fade, none

    static let key = "spaces.transition"
    nonisolated(unsafe) static var current = read(from: Store.settings)
    var id: String { rawValue }
    var title: String {
        switch self {
        case .slide: "Slide"
        case .fade: "Fade"
        case .none: "None"
        }
    }

    static func read(from defaults: UserDefaults) -> Self {
        defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? .slide
    }

    func resolved(reduceMotion: Bool) -> Self { reduceMotion ? .none : self }
}

extension Browser {
    var animatesSpaceChanges: Bool {
        !SpaceTurn.still && prefs.spaceTransition.resolved(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) != .none
    }
}
