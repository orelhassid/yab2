import Foundation
import SwiftUI

// Whose history, besides Yab's own, Yab may read: the agent's `history`
// tool, habits ("your usual tab at this time"), Now and the field's
// suggestions all read the Chromium browsers on this Mac only through here.
//
// A browser's history is read only after it was brought in from that
// browser (the welcome's Bring step, Settings › General): bringing it was
// the yes, and its later visits keep coming, since that is what the import
// asked for. Settings › Bring In lists the browsers on this Mac, each with
// its switch, to stop it or to start it without an import.
//
// Kept as one dictionary, a browser's name to whether it is read: a name
// there was brought in from or switched; a name missing is never read.
// Before this was kept (0.32.1), everything was read; on the first look the
// browser first brought in from, `bring.from`, keeps being read, and
// nobody else's is.

enum OtherHistory {
    static let key = "history.others"
    /// `Bringing.fromKey`, the browser first brought in from; spelled out,
    /// since Bringing is the main thread's and this is read off it.
    static let broughtFromKey = "bring.from"

    /// The browsers whose history is read now, among those on this Mac.
    static func sources(among installed: @autoclosure () -> [Chromium.Source] = Chromium.installed()) -> [Chromium.Source] {
        sources(choices: choices, ownOnly: ownOnly, discover: installed)
    }

    static func sources(choices: [String: Bool], ownOnly: Bool, discover: () -> [Chromium.Source]) -> [Chromium.Source] {
        // An eager default argument used to discover every browser even
        // when none of their histories could be read.
        guard !ownOnly, choices.values.contains(true) else { return [] }
        return allowed(discover(), choices: choices, ownOnly: false)
    }

    /// Whether this browser's history is read.
    static func reads(_ name: String) -> Bool { choices[name] == true }

    /// Its history was just brought in: read from now on.
    static func brought(_ name: String) { set(name, reading: true) }

    /// The switch in Settings › Bring In.
    static func set(_ name: String, reading: Bool) {
        var now = choices
        guard now[name] != reading else { return }
        now[name] = reading
        Store.settings.set(now, forKey: key)
        changed()
    }

    /// Every name with a choice, read or not, for Settings.
    static var choices: [String: Bool] {
        lock.lock()
        defer { lock.unlock() }
        if let kept = Store.settings.dictionary(forKey: key) as? [String: Bool] { return kept }
        let first = migrated(broughtFrom: Store.settings.string(forKey: broughtFromKey))
        Store.settings.set(first, forKey: key)
        return first
    }

    // MARK: - the rule, without the settings, for tests

    /// Those of `installed` whose history is read under `choices`; none in
    /// a test world told `YAB_HISTORY=own`.
    static func allowed(_ installed: [Chromium.Source], choices: [String: Bool], ownOnly: Bool) -> [Chromium.Source] {
        ownOnly ? [] : installed.filter { choices[$0.name] == true }
    }

    /// The first choices of someone from before they were kept: the browser
    /// they brought in from, if any.
    static func migrated(broughtFrom: String?) -> [String: Bool] {
        guard let name = broughtFrom, !name.isEmpty else { return [:] }
        return [name: true]
    }

    // MARK: -

    /// A test world told `YAB_HISTORY=own` reads only its own history: an
    /// eval's agent sees the places it was given, not this Mac's browsers,
    /// whatever was brought in.
    static var ownOnly: Bool {
        Store.testing && ProcessInfo.processInfo.environment["YAB_HISTORY"] == "own"
    }

    private static let lock = NSLock()

    /// What was counted from the old choice goes: the hosts an agent may
    /// lead to, and today's habits.
    private static func changed() {
        AgentHistory.forget()
        Task { @MainActor in Noticing.shared.recountHabits() }
    }
}

/// Settings › Bring In: each Chromium browser on this Mac and whether its
/// history is read, on for those brought in from.
struct OtherHistoryRows: View {
    @State private var choices = OtherHistory.choices
    private let installed = Chromium.installed()

    var body: some View {
        if !installed.isEmpty {
            Section {
                ForEach(installed) { source in
                    SettingsSwitch("History from \(source.name)", isOn: Binding(
                        get: { choices[source.name] == true },
                        set: { on in
                            OtherHistory.set(source.name, reading: on)
                            choices = OtherHistory.choices
                        }
                    ))
                }
                SettingsNote("Enable a browser's history for suggestions and agents. Importing a browser enables its history here.")
                    .settingsAnchor("other-history")
            }
        }
    }
}
