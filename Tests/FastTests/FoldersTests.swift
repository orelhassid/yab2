import Foundation
import Testing
@testable import Fast

// An agent's task folder: open, it shows four of its tabs and says how many
// more wait under them; the tab you are on and any asking are shown
// whatever; "N more" lets the rest out.
@MainActor
struct FoldersTests {
    static let ids = (0..<7).map { _ in UUID() }

    static func folder(_ n: Int, asking: Set<UUID> = []) -> Folders.Folder {
        Folders.Folder(id: "task", members: Array(ids.prefix(n)), asking: asking)
    }

    static func lay(_ folder: Folders.Folder, open: Bool, whole: Set<String> = [], active: UUID? = nil) -> [UUID: Folders.Place] {
        Folders.lay([folder], isOpen: { _ in open }, whole: whole, folding: [], active: active).places
    }

    @Test func openManyShowsFourAndMore() {
        let placed = Self.lay(Self.folder(7), open: true)
        let shown = Self.ids.filter { placed[$0]?.shown == true }
        #expect(shown == Array(Self.ids.prefix(4)))
        #expect(placed[Self.ids[3]]?.more == 3)
        #expect(placed.values.filter { $0.more > 0 }.count == 1)
    }

    @Test func fourOrFewerShowAll() {
        let placed = Self.lay(Self.folder(4), open: true)
        #expect(placed.values.allSatisfy { $0.shown && $0.more == 0 })
    }

    @Test func letOutShowsEverything() {
        let placed = Self.lay(Self.folder(7), open: true, whole: ["task"])
        #expect(placed.values.allSatisfy { $0.shown && $0.more == 0 })
    }

    @Test func closedShowsOnlyTheActiveAndAsking() {
        let placed = Self.lay(Self.folder(7, asking: [Self.ids[5]]), open: false, active: Self.ids[2])
        let shown = Self.ids.filter { placed[$0]?.shown == true }
        #expect(shown == [Self.ids[2], Self.ids[5]])
        #expect(placed.values.allSatisfy { $0.more == 0 })
    }

    @Test func activeBeyondFourIsShownAndCountedOut() {
        let placed = Self.lay(Self.folder(7), open: true, active: Self.ids[6])
        let shown = Self.ids.filter { placed[$0]?.shown == true }
        #expect(shown == Array(Self.ids.prefix(4)) + [Self.ids[6]])
        #expect(placed[Self.ids[6]]?.more == 2)
    }

    @Test func tuckedCountsTheHeldBack() {
        let laid = Folders.lay([Self.folder(7)], isOpen: { _ in true }, whole: [], folding: [], active: nil)
        #expect(laid.tucked == 3)
        #expect(laid.places.values.filter { !$0.shown }.allSatisfy { !$0.listed })
    }

    // MARK: - sealed: Yab's own work out of sight (Get to Know, the morning look)

    static func sealed(_ n: Int, asking: Set<UUID> = []) -> Folders.Folder {
        let tabs = ids.prefix(n).map { (root: "know", id: $0, asking: asking.contains($0)) }
        return Folders.form(tabs, task: { _ in false }, sealed: { $0 == "know" })[0]
    }

    @Test func sealedFormsFromItsFirstTab() {
        let one = Folders.form([(root: "know", id: Self.ids[0], asking: false)], task: { _ in false }, sealed: { $0 == "know" })
        #expect(one.map(\.id) == ["know"])
        #expect(one.first?.sealed == true)
        #expect(one.first?.members == [Self.ids[0]])
        // Any other task's one tab is still a plain row, until its second.
        let plain = Folders.form([(root: "task", id: Self.ids[1], asking: false)], task: { _ in false }, sealed: { _ in false })
        #expect(plain.isEmpty)
    }

    @Test func sealedNeverAsks() {
        #expect(Self.sealed(3, asking: [Self.ids[1]]).asking.isEmpty)
    }

    @Test func sealedNeverShowsItsTabs() {
        // Asked open, all let out, folding, one of its tabs in front and one
        // asking: none of them is shown, or listed.
        let folder = Folders.Folder(id: "know", members: Array(Self.ids.prefix(5)), asking: [Self.ids[3]], sealed: true)
        let laid = Folders.lay([folder], isOpen: { _ in true }, whole: ["know"], folding: ["know"], active: Self.ids[2])
        #expect(laid.places.count == 5)
        #expect(laid.places.values.allSatisfy { !$0.shown && !$0.listed && $0.more == 0 })
        #expect(laid.places[Self.ids[0]]?.head == true)
        #expect(laid.tucked == 5)
    }

    @Test func sealedStaysShutWhateverAsks() {
        let folder = Self.sealed(3)
        // Its id among the open, as a toggle that got through would leave it.
        #expect(!Folders.isOpen(folder, among: ["know"]))
        let placed = Folders.lay([folder], isOpen: { Folders.isOpen($0, among: ["know"]) }, whole: [], folding: [], active: nil).places
        #expect(placed.values.allSatisfy { !$0.shown })
        // Another task's opens as ever.
        #expect(Folders.isOpen(Self.folder(3), among: ["task"]))
    }

    @Test func sealedTitlesSayWhatItIsFor() {
        let knowing = Agents.Session(id: "k", cli: "claude", name: "Claude Code", prompt: "Research every detail about me", state: .running)
        knowing.sealed = true
        knowing.knowing = true
        // A name it gives itself doesn't change it.
        knowing.title = "Profile research"
        #expect(Folders.title(of: knowing) == "Getting to know you")
        #expect(Folders.stopping(knowing) == "Stop Getting to Know You")

        let look = Agents.Session(id: "l", cli: "claude", name: "Looking", prompt: "Look for what needs me", state: .running)
        look.quiet = true
        look.sealed = true
        #expect(Folders.title(of: look) == "Catching up")
        #expect(Folders.stopping(look) == "Stop Catching Up")

        // Any other task: the name it gave, else its prompt's first line.
        let task = Agents.Session(id: "t", cli: "claude", name: "Claude Code", prompt: "Flights to Lisbon\nin May", state: .running)
        #expect(Folders.title(of: task) == "Flights to Lisbon")
        task.title = "Lisbon trip"
        #expect(Folders.title(of: task) == "Lisbon trip")
        #expect(Folders.stopping(task) == "Stop Task")
    }

    @Test func stepsPassASealedFolder() {
        // Yours, yours, then a sealed folder of three, even asked open: a
        // step never lands in it.
        let mine = [UUID(), UUID()]
        let folder = Self.sealed(3)
        let placed = Folders.lay([folder], isOpen: { _ in true }, whole: [], folding: [], active: nil).places
        let row = mine + folder.members
        let passed = Browser.passed(row.map { placed[$0] }, sealed: row.map { folder.members.contains($0) }, open: { _ in true })
        #expect(passed == [false, false, true, true, true])
        #expect(Browser.stepped(from: 1, by: 1, skipping: passed) == 0)
        #expect(Browser.stepped(from: 0, by: -1, skipping: passed) == 1)
        // Its first tab before the folder is made: passed all the same.
        let early = Browser.passed(row.map { _ in nil }, sealed: row.map { folder.members.contains($0) }, open: { _ in true })
        #expect(early == passed)
    }

    @Test func numbersCountOnlyTabsYouCanBeOn() {
        // Four of yours, then a sealed folder of three.
        let open = [0, 1, 2, 3]
        #expect(Browser.tabIndex(for: 1, among: open) == 0)
        #expect(Browser.tabIndex(for: 4, among: open) == 3)
        // ⌘5: there is no fifth.
        #expect(Browser.tabIndex(for: 5, among: open) == nil)
        // ⌘9: the last of yours, not the folder's.
        #expect(Browser.tabIndex(for: 9, among: open) == 3)
        // No sealed folder: as ever.
        #expect(Browser.tabIndex(for: 3, among: [0, 1, 2]) == 2)
    }

    // Row 384: a task's folder left open in one space is still open when
    // you come back from another, as a folder of yours is; one whose task
    // is over, its tabs gone from every space, is shut for good.
    @Test func taskFolderStaysOpenAcrossSpaces() {
        let a = Folders.Folder(id: "a", members: [Self.ids[0], Self.ids[1]], asking: [])
        let b = Folders.Folder(id: "b", members: [Self.ids[2], Self.ids[3]], asking: [])
        // On screen: nothing else is read.
        #expect(Folders.stillOpen(["a"], here: [a], elsewhere: { Issue.record("read parked"); return [] }) == ["a"])
        // Away in another space: kept.
        #expect(Folders.stillOpen(["a", "b"], here: [b], elsewhere: { [a] }) == ["a", "b"])
        // Gone everywhere: dropped.
        #expect(Folders.stillOpen(["a", "b"], here: [b], elsewhere: { [] }) == ["b"])
        #expect(Folders.stillOpen([], here: [], elsewhere: { [a] }).isEmpty)
    }
}
