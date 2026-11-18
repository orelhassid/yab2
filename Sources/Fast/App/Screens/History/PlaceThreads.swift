import AppKit
import SwiftUI

// History's By Thread (docs/day-threads.md): History stays a list of pages,
// and its filter has one more row, By Thread,
// under All Time, Today and This Week. There the rows are the day's threads:
// three sites' icons, the name, "6 pages", the time under it; the preview
// pictures four of its pages and lists what you did. ↩ reopens its pages as
// a folder; ⌘K has the rest.

extension PlaceThing {
    var isThread: Bool {
        if case .thread = self { return true }
        return false
    }
}

extension Browser {
    /// How far back By Thread lists.
    static let threadDays = 90

    /// By Thread's rows for the words now, newest first, from the diary's
    /// queue; until they come the rows before them stay.
    func askThreads(_ asked: Int, words: String) {
        let now = Date()
        let from = now.addingTimeInterval(-Double(Browser.threadDays) * 86_400)
        let terms = words.lowercased().split(separator: " ").map(String.init)
        Diary.shared.threads(from: from, to: now.addingTimeInterval(60)) { [weak self] threads in
            guard let self, self.query.stock.asked == asked, self.query.place == .history,
                  self.query.placeFilter == FieldPlace.byThread else { return }
            let items = threads.reversed().compactMap { thread -> PlaceItem? in
                let said = ([thread.name, thread.topic, thread.summary] + thread.pages.map { $0.title + " " + $0.host })
                    .joined(separator: " ").lowercased()
                guard terms.allSatisfy({ said.contains($0) }) else { return nil }
                return Browser.threadItem(thread)
            }
            self.query.stock.visits = items
            self.query.stock.ended = true
            if let chosen = self.query.stock.threadChosen, let at = items.firstIndex(where: { $0.id == "thread.\(chosen)" }) {
                self.query.spot = at
                self.query.stock.threadChosen = nil
            } else if self.query.spot >= items.count {
                self.query.spot = max(0, items.count - 1)
            }
        }
    }

    static func threadItem(_ thread: DayThread) -> PlaceItem {
        var hosts: [String] = []
        for page in thread.pages where !hosts.contains(page.host) { hosts.append(page.host) }
        return PlaceItem(id: "thread.\(thread.id)", section: Browser.day(thread.start), title: thread.name, source: thread.when,
                         tile: .stack(Array(hosts.prefix(3))), tag: DayThreads.pages(thread.pages.count), what: .thread(thread))
    }

    /// Show Its Pages: the list, kept to the thread's pages, in the order
    /// you were on them, newest first as History lists.
    func listThread(_ thread: DayThread) {
        let rows: [[String: Any]] = thread.pages.reversed().map { page in
            ["key": page.key, "url": page.url, "title": page.title, "host": page.host,
             "at": page.at.timeIntervalSince1970 * 1000, "count": page.visits]
        }
        query.stock.visits = visitItems(rows, words: "")
        query.stock.ended = true
        if query.spot >= query.stock.visits.count { query.spot = 0 }
    }

    /// What a thread's row can have done to it, ↩ first.
    func threadActions(_ thread: DayThread) -> [FieldAction] {
        let urls = thread.pages.compactMap { URL(string: $0.url) }
        return [
            FieldAction(id: "open", title: "Reopen as Folder", symbol: "folder") {
                self.close()
                self.reopenAsFolder(urls, named: thread.name)
            },
            FieldAction(id: "askthread", title: "Ask About This Thread", symbol: "spark") {
                let day = AskFromDay.dayWord(thread.day)
                _ = self.leavePlace()
                self.askInField("What did I do in \u{201C}\(thread.name)\u{201D}, \(day == "Today" || day == "Yesterday" ? day.lowercased() : "on " + day)?")
            },
            FieldAction(id: "copy", title: "Copy URLs", keys: Keymap.shared.text(.fieldCopy), symbol: "link", group: 1) {
                self.copyPlain(urls.map(\.absoluteString).joined(separator: "\n"))
            },
            FieldAction(id: "rename", title: "Rename Thread…", symbol: "doc.text", group: 1) {
                self.close()
                self.renameThread(thread.id, was: thread.name)
            },
            FieldAction(id: "pages", title: "Show Its Pages", symbol: "yab.threads", group: 1) {
                self.query.placeFilter = 0
                self.query.stock.threadPages = thread
                self.query.spot = 0
                self.askHistory()
            },
            FieldAction(id: "forget", title: "Forget This Thread", keys: Keymap.shared.text(.fieldDelete), symbol: "trash", group: 3) {
                self.forgetThread(thread.id) { [weak self] in self?.askHistory() }
            },
        ]
    }

    /// By Thread with none to list.
    var threadEmpty: PlaceEmpty {
        let words = typed.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty {
            return PlaceEmpty(place: .history, searching: true, title: "No thread for \u{201C}\(words)\u{201D}",
                              detail: "Threads are found by their names and their pages.")
        }
        return PlaceEmpty(place: .history, searching: false, title: "No threads yet",
                          detail: "Pages you open together come here as threads, by what you were doing.",
                          actions: [FieldAction(id: "all", title: "Show All Time", symbol: "clock") {
                              self.query.placeFilter = 0
                              self.askHistory()
                          }])
    }
}

/// Three sites' icons, one over another, each ringed in the ground so the
/// one above stands off the one under it: a thread's mark.
struct ThreadStack: View {
    let hosts: [String]
    var side: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(hosts.prefix(3).enumerated()), id: \.offset) { index, host in
                let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
                Mark(icon: Favicons.shared.cached(host) ?? Favicons.shared.cached(bare),
                     letter: bare.first.map { String($0).uppercased() } ?? "", size: side)
                    .background {
                        RoundedRectangle(cornerRadius: side * 0.22 + 1.5, style: .continuous)
                            .fill(Palette.ground) // design: a ring of the ground around each icon so the one above stands off the one under it, not a card
                            .padding(-1.5)
                    }
                    .offset(ThreadStack.place(index))
            }
        }
        .frame(width: Omnibox.tile, height: Omnibox.tile, alignment: .topLeading)
    }

    /// Where each of the three sits in the tile.
    static func place(_ index: Int) -> CGSize {
        switch index {
        case 1: return CGSize(width: 8, height: 4)
        case 2: return CGSize(width: 3, height: 8)
        default: return .zero
        }
    }
}

/// The top of a thread's preview: four of its pages as you saw them, then
/// its mark, its name and how many pages when.
struct ThreadPreviewHead: View {
    let thread: DayThread
    let on: Bool
    @State private var pictures: [String: NSImage] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            let shown = Array(thread.pages.prefix(4))
            if on, !shown.isEmpty {
                Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                    GridRow {
                        tile(shown.indices.contains(0) ? shown[0] : nil)
                        tile(shown.indices.contains(1) ? shown[1] : nil)
                    }
                    GridRow {
                        tile(shown.indices.contains(2) ? shown[2] : nil)
                        tile(shown.indices.contains(3) ? shown[3] : nil)
                    }
                }
                .frame(height: 150)
                .background(Palette.hairline)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.control, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.5)) // design: a picture's edge, as the file previews have it, not a card
            }
            HStack(spacing: 12) {
                ThreadStack(hosts: hosts)
                    .scaleEffect(1.6)
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(thread.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(2)
                    Text(DayThreads.pages(thread.pages.count) + " · " + Browser.day(thread.start) + ", " + thread.when)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
            }
        }
        .task(id: thread.id) {
            let keys = thread.pages.prefix(4).map(\.key)
            let read = await Task.detached(priority: .userInitiated) {
                var out: [String: NSImage] = [:]
                for key in keys {
                    for file in [Diary.shot(key), Diary.og(key)] where FileManager.default.fileExists(atPath: file.path) {
                        if let image = NSImage(contentsOf: file) { out[key] = image }
                        break
                    }
                }
                return out
            }.value
            pictures = read
        }
    }

    private var hosts: [String] {
        var out: [String] = []
        for page in thread.pages where !out.contains(page.host) { out.append(page.host) }
        return Array(out.prefix(3))
    }

    @ViewBuilder private func tile(_ page: DayThread.Page?) -> some View {
        ZStack {
            Palette.ground
            if let page, let picture = pictures[page.key], picture.size.width > 0 {
                // Its top, as wide as the tile: what you saw first.
                GeometryReader { room in
                    Image(nsImage: picture)
                        .resizable()
                        .frame(width: room.size.width, height: room.size.width * picture.size.height / picture.size.width)
                }
            } else if let page {
                // Nothing pictured: its site's mark on the page's ground.
                PlaceTileView(tile: .site(page.host), meter: AnswerSourceRow.meter)
                    .opacity(0.8)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74.5) // design: half the four pictures' 150, less the hairline between them
        .clipped()
    }
}
