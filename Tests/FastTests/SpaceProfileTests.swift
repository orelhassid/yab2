import Foundation
import Testing
import SyncKit
@testable import Fast

@MainActor
struct SpaceProfileTests {
    @Test func detachedOwnerLeavesOtherMembersInTheirExistingStore() {
        let owner = Space(id: UUID(), name: "Work", icon: "💼", ownSignIns: true)
        let member = Space(id: UUID(), name: "Projects", icon: "📁", ownSignIns: true, signInWith: owner.id)
        let fresh = UUID()
        #expect(member.profileID == owner.profileID)
        #expect(Space.ownProfile(for: owner, among: [owner, member], fresh: fresh) == fresh)
        #expect(member.profileID == owner.id)
        // Selecting Its own again on an independent profile does not sign out.
        var detached = owner
        detached.signInWith = fresh
        #expect(Space.ownProfile(for: detached, among: [detached, member]) == fresh)
    }

    @Test func sharedDefaultCanDetachEvenTheFirstSpace() {
        let first = Space(id: Space.firstID, name: "Personal", icon: "🏠", ownSignIns: false)
        let member = Space(id: UUID(), name: "Work", icon: "💼", ownSignIns: false)
        let fresh = UUID()
        #expect(first.profileID == member.profileID)
        #expect(Space.ownProfile(for: first, among: [first, member], fresh: fresh) == fresh)
        #expect(member.profileID == Space.firstID)
    }

    @Test func deletingAProfileRequiresADestinationForEverySpace() throws {
        let first = Space(id: Space.firstID, name: "Personal", icon: "🏠", ownSignIns: false)
        let work = Space(id: UUID(), name: "Work", icon: "💼", ownSignIns: true, signedInAs: "Dia:Work")
        let projects = Space(id: UUID(), name: "Projects", icon: "📁", ownSignIns: true, signedInAs: "Dia:Work", signInWith: work.id)
        let client = Space(id: UUID(), name: "Client", icon: "💻", ownSignIns: true)
        let spaces = [first, work, projects, client]
        #expect(BrowserProfile.listed(in: spaces).map(\.id) == [first.id, work.id, client.id])
        #expect(BrowserProfile.reassigning(work.id, to: [work.id: first.id], in: spaces) == nil)
        #expect(BrowserProfile.reassigning(work.id, to: [work.id: first.id, projects.id: work.id], in: spaces) == nil)
        #expect(BrowserProfile.reassigning(first.id, to: [first.id: client.id], in: [first]) == nil)
        let moved = try #require(BrowserProfile.reassigning(work.id, to: [work.id: first.id, projects.id: client.id], in: spaces))
        #expect(moved.map(\.id) == spaces.map(\.id))
        #expect(moved.map(\.profileID) == [first.id, first.id, client.id, client.id])
        #expect(moved[1].signedInAs == nil)
        #expect(moved[2].signedInAs == nil)
    }

    @Test func googleIdentityPersistsAndKeepsACustomName() throws {
        let suite = "yab-profile-test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = UUID()
        let identities = BrowserProfileIdentities(settings: defaults)
        let identity = BrowserProfileIdentities.Google(email: "work@example.test", name: "Google Name",
                                                       photo: URL(string: "https://lh3.googleusercontent.com/avatar"))
        identities.link(identity, to: id)
        #expect(identities[id].title(fallback: "Work") == "Google Name")
        identities.rename(id, to: "  My Work  ")
        let reloaded = BrowserProfileIdentities(settings: defaults)
        #expect(reloaded[id].google == identity)
        #expect(reloaded[id].google?.picture == identity.photo)
        #expect(reloaded[id].title(fallback: "Work") == "My Work")
        #expect(reloaded[UUID()].google == nil)
        reloaded.link(nil, to: id)
        #expect(reloaded[id].title(fallback: "Work") == "My Work")
        reloaded.rename(id, to: "")
        #expect(reloaded[id].title(fallback: "Work") == "Work")
    }

    @Test func deletedOwnerDoesNotBreakMembersOrSync() throws {
        let gone = UUID()
        let member = Space(id: UUID(), name: "Same name", icon: "📁", ownSignIns: true, signInWith: gone)
        let fields = SyncShapes.spaces([member], orders: [:])
        let wire = try #require(fields[member.id.uuidString])
        #expect(wire["signInWith"] == .string(gone.uuidString))
        // Shared schema, used by both the Mac and the iPhone, retains it.
        let value = SyncSpace(id: member.id.uuidString, name: member.name, icon: member.icon, ownSignIns: true, signInWith: gone.uuidString)
        #expect(value.fields["signInWith"] == .string(gone.uuidString))
        var record = SyncKit.Record(collection: SyncCollection.space, id: member.id.uuidString)
        record.update(to: value.fields, clock: Clock(device: "second-mac", now: { 10 }))
        let back = try #require(SyncShapes.spaces(from: [record]).first)
        #expect(back.profileID == gone)
        #expect(SyncSpace(record)?.signInWith == gone.uuidString)
        #expect(member.profileID == gone)
        #expect(Spaces.routing([member]) == [member.id: gone])
    }

    @Test func concurrentMembershipChangesMergeAsOneChoice() throws {
        SyncCollection.register()
        let id = UUID().uuidString
        let profile = UUID().uuidString
        let older = Clock(device: "mac-a", now: { 10 })
        let newer = Clock(device: "mac-b", now: { 20 })
        var linked = SyncKit.Record(collection: SyncCollection.space, id: id)
        linked.update(to: SyncSpace(id: id, name: "Work", icon: "💼", ownSignIns: true, signInWith: profile).fields, clock: older)
        var detached = linked
        detached.update(to: SyncSpace(id: id, name: "Work", icon: "💼", ownSignIns: false).fields, clock: newer)
        let merged = try #require(SyncSpace(linked.merged(with: detached)))
        #expect(!merged.ownSignIns)
        #expect(merged.signInWith == nil)
        #expect(detached["signInWith"] == nil) // visible fields omit nulls
        #expect(detached.stamps["signInWith"] != nil) // explicit choice is still observable
        #expect(detached.merged(with: linked) == linked.merged(with: detached))
    }

    @Test func independentProfileWritesAnExplicitNullToClearRemoteLink() {
        let own = SyncSpace(id: UUID().uuidString, name: "Own", icon: "📁", ownSignIns: true)
        #expect(own.fields["signInWith"] == .null)
    }
}
