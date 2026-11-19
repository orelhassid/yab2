import AppKit
import UniformTypeIdentifiers
import WebKit

// chrome.downloads as a download manager extension sees it.
//
// Every download gets Chrome's kind of id the moment WebKit hands it over,
// and keeps it through a pause, a resume or a try again, though each of those
// is a new WKDownload underneath. A finished file listed in Downloads gets one
// the first time an extension asks, by its path.
//
// Chrome tells an extension of every change through downloads.onCreated,
// onChanged and onErased. WebKit has no way for the browser to call into an
// extension, so the shim asks (`downloads.events`) and the answer waits here
// until something happens, at most 25 s, and only in a context that listens.
// What happens while an extension's worker sleeps is kept for it and the
// worker is woken, as Chromium wakes it for the event. Nothing of this runs for
// an extension without the downloads permission, and nothing at all on pages.

@MainActor
enum ExtensionDownloads {
    /// One download, in Chrome's words.
    struct Item {
        let id: Int
        var url: String
        var finalUrl: String
        var referrer = ""
        var filename = ""
        var mime = ""
        let startTime: Date
        var endTime: Date?
        /// "in_progress", "interrupted" or "complete".
        var state = "in_progress"
        var paused = false
        var canResume = false
        var error: String?
        var received: Int64 = 0
        var total: Int64 = 0
        var exists = true
        var byExtension: String?
        /// The WKDownload carrying it now; nil once it ended or while paused.
        weak var download: WKDownload?
        /// The one that carried it last, kept once it ended: a page saved in
        /// an instant ends before download() has answered with its id.
        weak var ended: WKDownload?

        var json: [String: Any] {
            var row: [String: Any] = [
                "id": id, "url": url, "finalUrl": finalUrl, "referrer": referrer,
                "filename": filename, "incognito": false, "danger": "safe", "mime": mime,
                "startTime": Self.stamp(startTime), "state": state, "paused": paused,
                "canResume": canResume, "bytesReceived": received, "totalBytes": total,
                "fileSize": state == "complete" ? received : total, "exists": exists,
            ]
            if let endTime { row["endTime"] = Self.stamp(endTime) }
            if let error { row["error"] = error }
            if let byExtension { row["byExtensionId"] = byExtension }
            return row
        }

        static func stamp(_ date: Date) -> String {
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return format.string(from: date)
        }
    }

    private static var items: [Int: Item] = [:]
    private static var ids: [ObjectIdentifier: Int] = [:]
    private static var kept: [String: Int] = [:]
    private static var next = 1
    /// Downloads being paused: the end WebKit reports for them is the pause.
    private static var pausing: Set<Int> = []
    /// Asked for by an extension, so the item says which.
    private static var asked: [URL: String] = [:]
    private static var askedByID: [ObjectIdentifier: String] = [:]

    // MARK: - what happened, for the shim

    private struct Event { let seq: Int; let name: String; let value: Any; let target: ObjectIdentifier? }
    private static var log: [Event] = []
    private static var seq = 0
    private struct Waiter { let extensionID: String; let worker: Bool; let after: Int; let target: ObjectIdentifier?; let resume: ([String: Any]) -> Void }
    private static var waiting: [UUID: Waiter] = [:]
    /// The last event each extension's worker heard; what came after waits
    /// for it to wake.
    private static var heard: [String: Int] = [:]
    private struct ListenerKey: Hashable { let owner: ObjectIdentifier; let id: String }
    private static var contextHeard: [ListenerKey: Int] = [:]
    /// Workers that listen, kept between launches, so one asleep is woken.
    private static var listeners: Set<String> = Set(Store.settings.stringArray(forKey: "extensions.downloadListeners") ?? [])
    /// Set by the first call from an extension; before it, only a worker
    /// known to listen makes the extensions start for this.
    weak static var owner: Extensions?
    private static var reach: Extensions? { owner ?? (listeners.isEmpty ? nil : Extensions.shared) }
    private static var filenameListeners = Set(Store.settings.stringArray(forKey: "extensions.downloadFilenameListeners") ?? [])
    private static var filenameRequests: [ObjectIdentifier: String] = [:]

    static func listensForFilename(_ yes: Bool, extension id: String, owner: Extensions) {
        if yes { filenameListeners.insert(id) } else {
            filenameListeners.remove(id)
            ExtensionDownloadNaming.unloaded(filenameParticipant(id, in: owner))
        }
        Store.settings.set(Array(filenameListeners).sorted(), forKey: "extensions.downloadFilenameListeners")
    }

    private static func filenameParticipant(_ id: String, in owner: Extensions) -> String {
        "\(ObjectIdentifier(owner))/\(id)"
    }

    static func determineFilename(_ download: WKDownload, proposed: String, reply: @escaping (String) -> Void) {
        let controller = download.webView?.configuration.webExtensionController
        guard let owner = Extensions.all.first(where: { $0.controller === controller })
                ?? owner ?? (filenameListeners.isEmpty ? nil : Extensions.shared),
              let id = ids[ObjectIdentifier(download)], var item = items[id] else { reply(proposed); return }
        let participants = owner.installed.filter {
            $0.enabled && ($0.permissions.contains("downloads") || $0.permissions.contains("yab:downloads"))
                && filenameListeners.contains($0.id)
        }.sorted { ($0.installedAt ?? .distantPast) < ($1.installedAt ?? .distantPast) }.map(\.id)
        let key = ObjectIdentifier(download)
        guard let request = ExtensionDownloadNaming.begin(extensions: participants.map { filenameParticipant($0, in: owner) }, reply: { name in
            filenameRequests[key] = nil
            reply(name ?? proposed)
        }) else { return }
        filenameRequests[key] = request
        item.filename = proposed
        for id in participants { owner.wake(id) }
        emit("onDeterminingFilename", ["request": request, "item": item.json], target: owner)
    }

    static func filenameSuggestion(_ request: String, by id: String, owner: Extensions, filename: String?) {
        ExtensionDownloadNaming.suggest(request, by: filenameParticipant(id, in: owner), filename: filename)
    }

    static func unloaded(_ id: String, owner: Extensions) {
        ExtensionDownloadNaming.unloaded(filenameParticipant(id, in: owner))
    }

    // MARK: - from the browser

    /// WebKit handed over a download (Browser.keep).
    static func created(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        // The same download again; a new one where an old one, gone, was
        // (an address WebKit's next download reuses) gets an id of its own.
        if let id = ids[key], items[id]?.download === download { return }
        // Or one already over: the same, not a new one that never ends.
        if endedID(download) != nil { return }
        let url = download.originalRequest?.url
        let id = next
        next += 1
        ids[key] = id
        var item = Item(id: id, url: url?.absoluteString ?? "", finalUrl: url?.absoluteString ?? "", startTime: Date())
        item.download = download
        item.referrer = download.originalRequest?.value(forHTTPHeaderField: "Referer") ?? ""
        item.byExtension = askedByID.removeValue(forKey: key) ?? url.flatMap { asked.removeValue(forKey: $0) }
        items[id] = item
        emit("onCreated", item.json)
    }

    /// A download going on as a new one (a resume, a try again): it keeps
    /// the old one's id.
    static func carried(_ download: WKDownload, from old: ObjectIdentifier) {
        guard let id = ids.removeValue(forKey: old) else { return }
        ids[ObjectIdentifier(download)] = id
        items[id]?.download = download
        change(id) { item in
            item.paused = false
            item.canResume = false
            item.state = "in_progress"
            item.error = nil
            item.endTime = nil
        }
    }

    /// Where it will be written, and what it is.
    static func named(_ download: WKDownload, file: URL, response: URLResponse) {
        guard let id = ids[ObjectIdentifier(download)] else { return }
        change(id) { item in
            item.filename = file.path
            item.mime = response.mimeType ?? ""
            item.finalUrl = response.url?.absoluteString ?? item.finalUrl
            if response.expectedContentLength > 0 { item.total = response.expectedContentLength }
        }
    }

    static func finished(_ download: WKDownload, file: URL?) {
        guard let id = ids.removeValue(forKey: ObjectIdentifier(download)) else { return }
        if let file { kept[file.path] = id }
        change(id) { item in
            if let file { item.filename = file.path }
            item.received = max(download.progress.completedUnitCount, item.received)
            if item.total <= 0 { item.total = item.received }
            item.state = "complete"
            item.paused = false
            item.canResume = false
            item.endTime = Date()
            item.download = nil
            item.ended = download
        }
    }

    /// A completed file renamed by the browser keeps its download id,
    /// and extensions hear the new path through the ordinary change event.
    static func moved(from old: String, to new: String) {
        guard old != new, let id = kept.removeValue(forKey: old) else { return }
        kept[new] = id
        change(id) { $0.filename = new }
    }

    /// Ended without its file: refused a place, stopped, or broken.
    static func failed(_ download: WKDownload, resumable: Bool, canceled: Bool) {
        if let request = filenameRequests.removeValue(forKey: ObjectIdentifier(download)) { ExtensionDownloadNaming.cancel(request) }
        guard let id = ids[ObjectIdentifier(download)], !pausing.contains(id), items[id]?.paused != true else { return }
        change(id) { item in
            item.received = max(download.progress.completedUnitCount, item.received)
            item.state = "interrupted"
            item.paused = false
            item.canResume = resumable && !canceled
            item.error = canceled ? "USER_CANCELED" : "NETWORK_FAILED"
            item.endTime = Date()
            item.download = nil
        }
    }

    // MARK: - the API

    static func search(_ query: [String: Any], loot: Loot) -> [[String: Any]] {
        for keep in loot.kept where kept[keep.path] == nil {
            let id = next
            next += 1
            kept[keep.path] = id
            let source = keep.source?.absoluteString ?? keep.page?.absoluteString ?? keep.url.absoluteString
            var item = Item(id: id, url: source, finalUrl: source, startTime: keep.date)
            item.filename = keep.path
            item.state = "complete"
            item.endTime = keep.date
            item.received = (try? FileManager.default.attributesOfItem(atPath: keep.path)[.size] as? Int64) ?? 0
            item.total = item.received
            items[id] = item
        }
        var rows = items.values.filter { item in
            // A finished file taken off the list in Downloads is gone from here too.
            item.state != "complete" || loot.kept.contains { $0.path == item.filename } || ids.values.contains(item.id)
        }.map(live)
        for (key, wanted) in query {
            switch key {
            case "id", "url", "finalUrl", "filename", "state", "paused", "canResume", "exists", "mime", "error", "danger":
                rows = rows.filter { ($0[key] as? NSObject)?.isEqual(wanted) ?? false }
            case "urlRegex", "filenameRegex":
                let field = key == "urlRegex" ? "url" : "filename"
                guard let pattern = wanted as? String, let regex = try? NSRegularExpression(pattern: pattern) else { continue }
                rows = rows.filter {
                    let text = $0[field] as? String ?? ""
                    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
                }
            case "query":
                let words = (wanted as? [String] ?? []).map { $0.lowercased() }
                rows = rows.filter { row in
                    let text = ((row["url"] as? String ?? "") + " " + (row["filename"] as? String ?? "")).lowercased()
                    return words.allSatisfy { $0.hasPrefix("-") ? !text.contains($0.dropFirst()) : text.contains($0) }
                }
            case "startedAfter", "startedBefore":
                guard let text = wanted as? String else { continue }
                rows = rows.filter {
                    let start = $0["startTime"] as? String ?? ""
                    return key == "startedAfter" ? start > text : start < text
                }
            default: continue
            }
        }
        let order = (query["orderBy"] as? [String]) ?? ["-startTime"]
        rows.sort { a, b in
            for field in order {
                let descending = field.hasPrefix("-")
                let name = descending ? String(field.dropFirst()) : field
                let x = "\(a[name] ?? "")", y = "\(b[name] ?? "")"
                if x == y { continue }
                if let p = a[name] as? NSNumber, let q = b[name] as? NSNumber, !(a[name] is Bool) {
                    return descending ? p.compare(q) == .orderedDescending : p.compare(q) == .orderedAscending
                }
                return descending ? x > y : x < y
            }
            return false
        }
        let limit = query["limit"] as? Int ?? 1000
        return Array(rows.prefix(limit > 0 ? limit : rows.count))
    }

    /// The numbers as they are now: WebKit's own count, read when asked.
    private static func live(_ item: Item) -> [String: Any] {
        var item = item
        if let download = item.download {
            item.received = download.progress.completedUnitCount
            if download.progress.totalUnitCount > 0 { item.total = download.progress.totalUnitCount }
        }
        if item.state == "complete" { item.exists = FileManager.default.fileExists(atPath: item.filename) }
        return item.json
    }

    static func item(_ id: Int) -> Item? { items[id] }

    /// Asked for by an extension: a download manager takes over what the
    /// browser starts and downloads the same address again at once.
    static func byExtension(_ download: WKDownload) -> Bool {
        ids[ObjectIdentifier(download)].flatMap { items[$0]?.byExtension } != nil
    }

    /// downloads.download: the id of the download the browser now has.
    static func started(_ download: WKDownload, by extensionID: String) -> Int? {
        let key = ObjectIdentifier(download)
        created(download)
        // SingleFile's page, written in 17 ms, was over before its
        // download() answered; it was given a second id that never ended,
        // and its button stayed at "Save progress: 100%".
        guard let id = ids[key] ?? endedID(download) else { return nil }
        if items[id]?.byExtension == nil { items[id]?.byExtension = extensionID }
        return id
    }

    static func asking(_ url: URL, by extensionID: String) { asked[url] = extensionID }
    static func asking(_ download: WKDownload, by extensionID: String) { askedByID[ObjectIdentifier(download)] = extensionID }

    /// The id of a download already over, by the WKDownload that carried it.
    private static func endedID(_ download: WKDownload) -> Int? {
        items.values.first { $0.ended === download }?.id
    }

    static func pauseFromUI(_ download: any PageDownload, hoard: Hoard) async {
        if let id = ids[ObjectIdentifier(download)] {
            try? await pause(id, hoard: hoard)
        } else {
            _ = await hoard.pause(download)
        }
    }

    static func pause(_ id: Int, hoard: Hoard) async throws {
        guard let item = items[id] else { throw ExtensionShims.Unsupported(what: "Invalid download id \(id)") }
        guard item.state == "in_progress" else { throw ExtensionShims.Unsupported(what: "Download must be in progress") }
        guard !item.paused, let download = item.download else { return }
        guard pausing.insert(id).inserted else { return }
        defer { pausing.remove(id) }
        let resumable = await hoard.pause(download)
        change(id) { item in
            item.received = max(download.progress.completedUnitCount, item.received)
            item.paused = true
            item.canResume = resumable
        }
    }

    static func resume(_ id: Int, hoard: Hoard) throws {
        guard let item = items[id] else { throw ExtensionShims.Unsupported(what: "Invalid download id \(id)") }
        guard item.paused || (item.state == "interrupted" && item.canResume) else {
            if item.state == "in_progress" { return }
            throw ExtensionShims.Unsupported(what: "Download must be in progress")
        }
        guard let old = ids.first(where: { $0.value == id })?.key, hoard.resume(old) else {
            throw ExtensionShims.Unsupported(what: "Download can't be resumed")
        }
    }

    static func cancel(_ id: Int, hoard: Hoard, browser: Browser) {
        guard let item = items[id], item.state != "complete" else { return }
        if item.state == "interrupted" && !item.canResume { return }
        if let old = ids.first(where: { $0.value == id })?.key { hoard.stop(old) }
        change(id) { item in
            item.state = "interrupted"
            item.paused = false
            item.canResume = false
            item.error = "USER_CANCELED"
            item.endTime = Date()
            item.download = nil
        }
    }

    static func removeFile(_ id: Int) throws {
        guard let item = items[id], item.state == "complete" else {
            throw ExtensionShims.Unsupported(what: "Download must be complete")
        }
        try? FileManager.default.removeItem(atPath: item.filename)
        change(id) { $0.exists = false }
    }

    static func erase(_ query: [String: Any], loot: Loot) -> [Int] {
        let gone = search(query, loot: loot).compactMap { $0["id"] as? Int }
            .filter { items[$0]?.state != "in_progress" }
        for id in gone {
            if let path = items[id]?.filename, let keep = loot.kept.first(where: { $0.path == path }) { loot.forget(keep) }
            items[id] = nil
            kept = kept.filter { $0.value != id }
            emit("onErased", id)
        }
        return gone
    }

    /// The Finder's icon for the file, or for its kind while it comes.
    static func icon(_ id: Int, size: Int) throws -> String {
        guard let item = items[id] else { throw ExtensionShims.Unsupported(what: "Invalid download id \(id)") }
        let image: NSImage
        if FileManager.default.fileExists(atPath: item.filename) {
            image = NSWorkspace.shared.icon(forFile: item.filename)
        } else {
            let type = UTType(filenameExtension: (item.filename as NSString).pathExtension) ?? .data
            image = NSWorkspace.shared.icon(for: type)
        }
        let side = size == 16 || size == 32 ? size : 32
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return "" }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = rep.representation(using: .png, properties: [:]) else { return "" }
        return "data:image/png;base64," + png.base64EncodedString()
    }

    // MARK: - telling extensions

    private static func change(_ id: Int, _ edit: (inout Item) -> Void) {
        guard let before = items[id] else { return }
        var after = before
        edit(&after)
        items[id] = after
        let old = before.json, new = after.json
        var delta: [String: Any] = ["id": id]
        // Chrome says nothing of bytesReceived; it is read with search.
        for key in ["url", "finalUrl", "filename", "danger", "mime", "startTime", "endTime", "state",
                    "canResume", "paused", "error", "totalBytes", "fileSize", "exists"] {
            let a = old[key] as? NSObject, b = new[key] as? NSObject
            guard a != b else { continue }
            var pair: [String: Any] = [:]
            if let a { pair["previous"] = a }
            if let b { pair["current"] = b }
            delta[key] = pair
        }
        // A total said while it was already known is no change worth a word.
        if delta.count > 1 { emit("onChanged", delta) }
    }

    private static func emit(_ name: String, _ value: Any, target: Extensions? = nil) {
        guard let owner = target ?? reach, !owner.contexts.isEmpty || !listeners.isEmpty else { return }
        seq += 1
        log.append(Event(seq: seq, name: name, value: value, target: target.map(ObjectIdentifier.init)))
        if log.count > 400 { log.removeFirst(log.count - 400) }
        let current = seq
        DispatchQueue.main.async { flush(upTo: current) }
    }

    /// Answers every waiting question with what came since. A worker's
    /// answer counts as heard only once the worker asks again from it: a
    /// question can outlive the worker that asked, unloaded asleep, and its
    /// answer then goes nowhere. So a moment on, a listening worker that
    /// hasn't said it heard is woken, and asks for what it missed.
    private static func flush(upTo current: Int) {
        for (key, waiter) in waiting {
            waiting[key] = nil
            waiter.resume(answer(after: waiter.after, target: waiter.target))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard let owner = reach else { return }
            for id in listeners where (heard[id] ?? 0) < current {
                // Never asked since launch: all of it happened asleep.
                if heard[id] == nil { heard[id] = 0 }
                guard let context = owner.contexts[id] else {
                    owner.wake(id)
                    continue
                }
                owner.trace(id, "downloads woke the worker")
                context.loadBackgroundContent { _ in }
            }
        }
    }

    private static func answer(after: Int, target: ObjectIdentifier? = nil) -> [String: Any] {
        let events = log.filter { $0.seq > after && ($0.target == nil || $0.target == target) }.map { ["name": $0.name, "value": $0.value] as [String: Any] }
        return ["seq": seq, "events": events]
    }

    /// downloads.events: what happened after `after`, waiting up to 25 s
    /// for something to. Without `after`, a worker hears what it missed
    /// while asleep, and a page only learns where things stand.
    static func events(after: Int?, worker: Bool, extension id: String, owner: Extensions? = nil) async -> [String: Any] {
        if worker, !listeners.contains(id) {
            listeners.insert(id)
            Store.settings.set(Array(listeners).sorted(), forKey: "extensions.downloadListeners")
        }
        if after == nil && !worker { return ["seq": seq, "events": []] }
        let target = owner.map(ObjectIdentifier.init)
        let listenerKey = target.map { ListenerKey(owner: $0, id: id) }
        let previous = listenerKey.flatMap { contextHeard[$0] } ?? (listenerKey == nil ? heard[id] : nil)
        let since = after ?? previous ?? (filenameListeners.contains(id) ? 0 : seq)
        if worker, let listenerKey { contextHeard[listenerKey] = max(contextHeard[listenerKey] ?? 0, since) }
        if worker { heard[id] = max(heard[id] ?? 0, since) }
        if log.contains(where: { $0.seq > since }) { return answer(after: since, target: target) }
        let key = UUID()
        return await withCheckedContinuation { continuation in
            waiting[key] = Waiter(extensionID: id, worker: worker, after: since, target: target) { continuation.resume(returning: $0) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                guard let waiter = waiting.removeValue(forKey: key) else { return }
                waiter.resume(["seq": seq, "events": []])
            }
        }
    }

    /// Where things stand, for a context about to start a download and
    /// listen for it.
    static var now: [String: Any] { ["seq": seq, "events": []] }

    /// The worker stopped listening: nothing is kept for it any more.
    static func unheard(_ id: String) {
        guard listeners.remove(id) != nil else { return }
        heard[id] = nil
        Store.settings.set(Array(listeners).sorted(), forKey: "extensions.downloadListeners")
    }
}
