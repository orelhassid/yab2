import Foundation
import SyncKit

// Projects for chats, the way Messages has contacts (docs/chat-projects.md):
// a circle with an emoji, its conversations, what its agent is told
// (instructions), what it remembers, its routines and its files.
//
// A chat is in at most one project (Chat.project). A project's
// instructions and then its memory go into the brief of every chat in it
// (Agents.brief), in this order: instructions, memory, the
// conversation. Its memory is a page of its own, memory/projects/<id>.md,
// written after a turn the way the shared memory is (Agents.remember).
// Its files are a folder every chat in it is told of, agent/project/<id>/files.

struct Project: Codable, Identifiable, Equatable {
    let id: String
    var name: String
    /// One emoji, the circle's face.
    var emoji: String
    /// The circle's color, one of `tints`.
    var tint: String
    /// What every chat in it is told before anything else.
    var instructions: String = ""
    /// Whether its chats keep what they learn in its memory page.
    var memoryOn: Bool = true
    /// A big circle over the list, in `order`.
    var pinned: Bool = false
    /// Put away: out of the list, its chats with it. Optional, as Chat's.
    var archived: Bool?
    var created: Date
    var updated: Date
    /// Where it stands among the pinned ones (SyncKit.Order).
    var order: String

    /// The colors a circle can be, as the iPhone and the Mac both draw them.
    static let tints = ["blue", "green", "orange", "purple", "pink", "yellow", "teal", "gray"]

    /// A new id: `prj-` and eight letters, never a memory page's name.
    static func newID() -> String {
        "prj-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    static let idPrefix = "prj-"

    /// Its files, shared by all of its chats.
    var files: URL { Self.files(id) }

    static func files(_ id: String) -> URL { Store.file("agent/project/\(id)/files") }

    /// Its memory page, by the name Memory.write takes.
    var memoryPage: String { "projects/\(id)" }
}

/// Every project, kept as a file each in `projects/`, written a moment
/// after a change in one batch, as Chats keeps chats.
@MainActor
final class Projects: ObservableObject {
    static let shared = Projects()

    @Published private(set) var all: [Project] = []
    private var waiting: [String: Project] = [:]
    private var writing = false
    private static let disk = DispatchQueue(label: "yab.projects", qos: .utility)
    private let storage: URL

    nonisolated static var folder: URL { Store.file("projects") }
    static let changed = Notification.Name("yab.projects.changed")

    /// Read at once: a project is a few hundred bytes, and a chat's brief
    /// or its column may ask for one the moment Yab starts.
    init(folder: URL = Projects.folder) {
        storage = folder
        all = Projects.read(folder)
    }

    func project(_ id: String?) -> Project? {
        guard let id else { return nil }
        return all.first { $0.id == id }
    }

    /// Those in the list: not put away, the newest first.
    var listed: [Project] { all.filter { $0.archived != true }.sorted { $0.updated > $1.updated } }

    /// The big circles, in their order.
    var pinned: [Project] {
        all.filter { $0.pinned && $0.archived != true }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }

    var archived: [Project] { all.filter { $0.archived == true }.sorted { $0.updated > $1.updated } }

    /// A new project, its chats moved into it. An empty name or emoji
    /// takes a plain one.
    @discardableResult
    func add(name: String, emoji: String = "", tint: String? = nil, instructions: String = "", pinned: Bool = false,
             chats ids: [String] = [], in chats: Chats = .shared, now: Date = Date()) -> Project {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(id: Project.newID(), name: clean.isEmpty ? "New Project" : String(clean.prefix(80)),
                              emoji: Self.face(emoji), tint: tint.flatMap { Project.tints.contains($0) ? $0 : nil } ?? Self.nextTint(all),
                              instructions: instructions, pinned: pinned, created: now, updated: now,
                              order: SyncKit.Order.between(self.pinned.last?.order, nil))
        all.append(project)
        save(project)
        if !ids.isEmpty { chats.move(ids, to: project.id) }
        return project
    }

    /// One emoji, or the folder one when none was given.
    static func face(_ emoji: String) -> String {
        let clean = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.first.map { String($0) } ?? "📁"
    }

    /// The color after the last one used, so new circles differ.
    static func nextTint(_ all: [Project]) -> String {
        guard let last = all.max(by: { $0.created < $1.created }), let at = Project.tints.firstIndex(of: last.tint) else { return Project.tints[0] }
        return Project.tints[(at + 1) % Project.tints.count]
    }

    /// Its name, face, color, instructions or memory switch, as edited.
    func update(_ project: Project, now: Date = Date()) {
        guard let index = all.firstIndex(where: { $0.id == project.id }) else { return }
        var changed = project
        changed.emoji = Self.face(project.emoji)
        if !Project.tints.contains(changed.tint) { changed.tint = all[index].tint }
        guard changed != all[index] else { return }
        changed.updated = now
        all[index] = changed
        save(changed)
    }

    /// Touched: a chat in it moved, so it comes up the list.
    func touch(_ id: String?, at now: Date = Date()) {
        guard let id, let index = all.firstIndex(where: { $0.id == id }), all[index].updated < now else { return }
        all[index].updated = now
        save(all[index])
    }

    /// A big circle, the last of them; or a row again.
    func pin(_ id: String, _ on: Bool) {
        guard let index = all.firstIndex(where: { $0.id == id }), all[index].pinned != on else { return }
        if on { all[index].order = SyncKit.Order.between(pinned.last?.order, nil) }
        all[index].pinned = on
        save(all[index])
    }

    /// A pinned circle put before another, or last.
    func move(_ id: String, before other: String?) {
        let others = pinned.filter { $0.id != id }
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        let at = other.flatMap { o in others.firstIndex { $0.id == o } } ?? others.count
        let low = at > 0 ? others[at - 1].order : nil
        let high = at < others.count ? others[at].order : nil
        all[index].order = SyncKit.Order.between(low, high)
        all[index].pinned = true
        save(all[index])
    }

    /// Put away, its chats with it, or back in the list.
    func archive(_ id: String, _ on: Bool) {
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].archived = on ? true : nil
        save(all[index])
    }

    /// Gone, and with it its instructions, memory and files; its chats
    /// stay, back in Chats, and its routines run on without it.
    func delete(_ id: String, chats: Chats = .shared, routines: Routines? = nil) {
        guard all.contains(where: { $0.id == id }) else { return }
        all.removeAll { $0.id == id }
        waiting[id] = nil
        chats.move(chats.all.filter { $0.project == id }.map(\.id), to: nil)
        (routines ?? (storage == Projects.folder ? Routines.shared : nil))?.leave(project: id)
        let file = storage.appendingPathComponent(id + ".json")
        let ownsFiles = storage == Projects.folder
        Projects.disk.async {
            try? FileManager.default.removeItem(at: file)
            guard ownsFiles else { return }
            Memory.eraseProject(id)
            try? FileManager.default.removeItem(at: Project.files(id).deletingLastPathComponent())
        }
        NotificationCenter.default.post(name: Projects.changed, object: nil)
    }

    /// The projects as sync says they are now (SyncProject): what each is
    /// comes from there; one removed there (`removed`) is gone here, its
    /// chats back in Chats. One made here and not yet told stays.
    func adopt(_ synced: [SyncProject], removed: Set<String>, chats: Chats = .shared) {
        let mine = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var next: [Project] = []
        for one in synced where one.id.hasPrefix(Project.idPrefix) {
            let here = mine[one.id]
            let project = Project(id: one.id, name: one.name, emoji: Self.face(one.emoji),
                                  tint: Project.tints.contains(one.tint) ? one.tint : here?.tint ?? Project.tints[0],
                                  instructions: one.instructions, memoryOn: one.memoryOn, pinned: one.pinned,
                                  archived: one.archived ? true : nil,
                                  created: Date(timeIntervalSince1970: one.created), updated: Date(timeIntervalSince1970: one.updated),
                                  order: one.order)
            next.append(project)
        }
        let gone = Set(mine.keys).intersection(removed).subtracting(next.map(\.id))
        // An edit here newer than what came is told next, not taken back.
        let changed = next.filter { one in mine[one.id] != one && (mine[one.id]?.updated ?? .distantPast) <= one.updated }
        guard !gone.isEmpty || !changed.isEmpty else { return }
        for id in gone { delete(id, chats: chats) }
        for project in changed {
            if let index = all.firstIndex(where: { $0.id == project.id }) { all[index] = project } else { all.append(project) }
            save(project)
        }
    }

    // MARK: - disk

    nonisolated static func read(_ folder: URL) -> [Project] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? decoder.decode(Project.self, from: $0) }
        }.sorted { $0.created < $1.created }
    }

    private func save(_ project: Project) {
        waiting[project.id] = project
        NotificationCenter.default.post(name: Projects.changed, object: nil)
        guard !writing else { return }
        writing = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self else { return }
            let batch = Array(self.waiting.values)
            self.waiting = [:]
            self.writing = false
            let folder = self.storage
            Projects.disk.async { Projects.write(batch, to: folder) }
        }
    }

    /// Wait for changes already kept in memory to reach the folder.
    func flush() async {
        let batch = Array(waiting.values)
        waiting = [:]
        let folder = storage
        await withCheckedContinuation { continuation in
            Projects.disk.async {
                Projects.write(batch, to: folder)
                continuation.resume()
            }
        }
    }

    nonisolated static func write(_ projects: [Project], to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        for project in projects {
            guard let data = try? encoder.encode(project) else { continue }
            try? data.write(to: folder.appendingPathComponent(project.id + ".json"), options: .atomic)
        }
    }
}

// MARK: - What a project's chat is told

extension Project {
    /// The project's part of a chat's brief: its instructions, then what
    /// it remembers, then where its files are. Empty parts are left out.
    func brief(memory notes: [String], full: Bool) -> String {
        var out = "\n\nThis chat is in the user's project \u{201C}\(name)\u{201D}."
        let said = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { out += " The user's instructions for every chat in it:\n\n" + String(said.prefix(8000)) }
        if memoryOn, !notes.isEmpty {
            out += "\n\nWhat this project remembers (memory page \(memoryPage)):\n\n" + notes.map { "- " + $0 }.joined(separator: "\n")
        }
        if full { out += "\n\nThis project's files, shared by its chats, are in \(files.path): keep files for it there." }
        return out
    }
}
