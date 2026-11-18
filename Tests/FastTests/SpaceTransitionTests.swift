import Foundation
import Testing
@testable import Fast

struct SpaceTransitionTests {
    @Test func missingAndUnknownValuesPreserveTheExistingSlideDefault() throws {
        let name = "SpaceTransitionTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(SpaceTransition.read(from: defaults) == .slide)
        defaults.set("unknown", forKey: SpaceTransition.key)
        #expect(SpaceTransition.read(from: defaults) == .slide)
    }

    @Test(arguments: SpaceTransition.allCases)
    func eachChoicePersistsAndRespectsReduceMotion(_ transition: SpaceTransition) throws {
        let name = "SpaceTransitionTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(transition.rawValue, forKey: SpaceTransition.key)
        #expect(SpaceTransition.read(from: defaults) == transition)
        #expect(transition.resolved(reduceMotion: false) == transition)
        #expect(transition.resolved(reduceMotion: true) == .none)
    }

    @MainActor @Test func transitionIsSearchableAndClassifiedForNativeControl() throws {
        let item = try #require(SettingsItem.all.first { $0.id == "space-transition" })
        #expect(item.page == .appearance)
        #expect(NativeActions.classification(item) == "read_write")
        #expect(SettingsResult.search("Space transition").best?.page == .appearance)
        let descriptor = try #require(NativeActions.descriptors.first { $0["id"] as? String == "settings.set.space-transition" })
        for transition in SpaceTransition.allCases {
            try NativeActions.validate(["value": .string(transition.rawValue)], descriptor: descriptor)
        }
        #expect(throws: NativeFailure.self) { try NativeActions.validate(["value": .string("zoom")], descriptor: descriptor) }
    }
}
