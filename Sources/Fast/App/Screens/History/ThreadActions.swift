import AppKit

// What can be done to a day's thread (docs/day-threads.md), from History's
// By Thread, from Memory › Days and from an answer's rows: its pages again
// as a folder in this space, Forget This Thread with the corner's Undo and
// ⌘Z, Rename…, and an answer's source opened.

extension Browser {
    /// An answer's row under ⌘T's Ask: its page, or its thread as a folder.
    func openSource(_ index: Int) {
        let commands = selectionCommands
        guard commands.sources.indices.contains(index) else { return }
        let source = commands.sources[index]
        commands.sourceSpot = index
        switch source.kind {
        case .page:
            guard let url = source.urls.first else { return }
            let asking = self.asking
            close()
            place(url, asking, from: active)
        case .folder:
            close()
            reopenAsFolder(source.urls, named: source.name)
        }
    }

    /// Reopen as Folder: the pages, in the order you were on them, as one of
    /// today's folders in this space under the thread's name, the first in
    /// front. One page is just that page.
    func reopenAsFolder(_ urls: [URL], named name: String) {
        let urls = Array(urls.prefix(12))
        guard let first = urls.first else { return }
        guard urls.count > 1 else {
            select(open(first, foreground: true, from: nil))
            return
        }
        let tabs = urls.map { open($0, foreground: false, from: nil, rowNow: true) }
        newFolder(with: tabs, today: true)
        if let nest = tabs.first?.nest {
            nest.name = name
            if folderBook.naming == nest.id { folderBook.naming = nil }
            writeSession()
        }
        select(tabs[0])
    }

    /// Forget This Thread: its visits and every page seen only in it, from
    /// History too, at once; the corner says so with Undo, and ⌘Z.
    /// `inSettings`: forgotten from Memory › Days, where Settings' corner
    /// offers the Undo and its ⌘Z takes it back.
    func forgetThread(_ id: Int64, inSettings: Bool = false, then done: (() -> Void)? = nil) {
        Task { @MainActor in
            let thread = await Diary.shared.thread(id)
            let (taken, urls) = await Diary.shared.take(thread: id)
            let pretty = urls.compactMap(URL.init(string:)).map(History.key(for:))
            let gone = history.take(pretty)
            let words = thread.map { "Forgot \(DayThreads.pages($0.pages.count)) from \($0.when)" } ?? "Forgot the thread"
            NotificationCenter.default.post(name: Diary.threadsChanged, object: nil)
            done?()
            let back = { [weak self] in
                self?.history.putBack(gone)
                Diary.shared.giveBack(taken) {
                    NotificationCenter.default.post(name: Diary.threadsChanged, object: nil)
                }
            }
            if inSettings {
                SettingsWindow.shared.did(words, mark: "trash", back)
            } else {
                let step = did(back)
                toaster.pop(words, mark: "trash", undo: { [weak self] in self?.undo(step: step) })
            }
        }
    }

    /// Rename…: asked in the app's own card, a name typed over the old one.
    func renameThread(_ id: Int64, was name: String, place: Question.Place = .page) {
        let field = Question.Field(name, prompt: "Name")
        let question = Question(title: "Rename this thread", glyph: "pencil", yes: "Rename", place: place, field: field)
        Task { @MainActor in
            guard await Questions.shared.ask(question), !field.trimmed.isEmpty, field.trimmed != name else { return }
            Diary.shared.rename(thread: id, to: field.trimmed)
        }
    }

    /// Open in History: History's By Thread, on this thread.
    func showThreadInHistory(_ id: Int64) {
        openPlace(.history)
        query.placeFilter = FieldPlace.byThread
        query.stock.threadChosen = id
        askHistory()
    }
}
