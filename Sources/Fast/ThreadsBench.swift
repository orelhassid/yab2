import AppKit

// `./bench threads …`, test runs only: a probe world's day threads, as
// evals/day-threads/run.py drives them. "icons" gives seeded sites a lettered
// icon on their color (the prototype's), "visits" plants visits at their
// times, "shots" pictures of pages, "acts" what was done on them; "rethread"
// groups the days planted; "names" names the thread holding a page as a
// model would; "note" adds what tasks noticed to a day's note. "ask" puts
// ⌘T's Ask in a state with its answer's rows from the world's own threads
// ("numbers": the ones the answer names), "spot" a row chosen. "stats" says
// what grouping has cost, on and off the main thread.

extension Bench {
    func threadsCommand(_ request: [String: Any], browser: Browser, _ answer: @escaping ([String: Any]) -> Void) {
        guard Store.testing else { return answer(["error": "threads only works on a --test run"]) }
        Task { @MainActor in
            for icon in request["icons"] as? [[String: Any]] ?? [] {
                guard let host = icon["host"] as? String, let letter = icon["letter"] as? String,
                      let color = (icon["color"] as? String).flatMap(NSColor.init(hex:)),
                      let data = ThreadsBench.icon(letter, color) else { continue }
                await Favicons.shared.adopt(data, for: host)
            }
            var days = Set<String>()
            var planted: [Diary.Planted] = []
            for visit in request["visits"] as? [[String: Any]] ?? [] {
                guard let link = visit["url"] as? String, let url = URL(string: link), let at = visit["at"] as? Double else { continue }
                let when = Date(timeIntervalSince1970: at)
                days.insert(Diary.dayName(when))
                planted.append(Diary.Planted(url: url, title: visit["title"] as? String ?? "", at: when, space: visit["space"] as? String ?? "",
                                             quiet: visit["quiet"] as? Bool ?? false, text: visit["text"] as? String ?? ""))
            }
            if !planted.isEmpty { await Diary.shared.plant(planted) }
            for shot in request["shots"] as? [[String: Any]] ?? [] {
                guard let url = (shot["url"] as? String).flatMap(URL.init(string:)),
                      let color = (shot["color"] as? String).flatMap(NSColor.init(hex:)) else { continue }
                Diary.shared.keep(ThreadsBench.page(color), for: url)
            }
            for act in request["acts"] as? [[String: Any]] ?? [] {
                guard let url = (act["url"] as? String).flatMap(URL.init(string:)),
                      let kind = (act["kind"] as? String).flatMap(DayThread.Act.Kind.init(rawValue:)), let at = act["at"] as? Double else { continue }
                Diary.shared.act(kind, on: url, words: act["words"] as? String ?? "", at: Date(timeIntervalSince1970: at))
            }
            if request["rethread"] as? Bool == true {
                for day in days.sorted() { if let date = Diary.day(named: day) { await Diary.shared.rethread(date) } }
            }
            for name in request["names"] as? [[String: Any]] ?? [] {
                guard let url = (name["url"] as? String).flatMap(URL.init(string:)), let at = name["at"] as? Double,
                      let id = await Diary.shared.threadID(holding: url, on: Date(timeIntervalSince1970: at)) else { continue }
                await Diary.shared.name(thread: id, DayThreads.Naming(topic: name["topic"] as? String ?? "", doing: name["doing"] as? String ?? "",
                                                                      done: name["done"] as? String ?? "", line: name["line"] as? String ?? ""))
            }
            if let note = request["note"] as? [String: Any], let day = note["day"] as? String, let text = note["text"] as? String {
                _ = Memory.write("episodic/" + day, text: text, replacing: nil)
                MemoryShelf.shared.reload()
            }
            if request["names"] != nil || request["rethread"] != nil {
                NotificationCenter.default.post(name: Diary.threadsChanged, object: nil)
            }
            if let ask = request["ask"] as? [String: Any] { await ThreadsBench.ask(ask, in: browser) }
            if let spot = request["spot"] as? Int {
                browser.selectionCommands.sourceSpot = spot < 0 ? nil : spot
            }
            var out: [String: Any] = [:]
            // History's filter set, its menu dropped with a row walked to, a row chosen.
            if let filter = request["filter"] as? Int, browser.query.place == .history {
                browser.query.placeFilter = filter
                browser.query.stock.threadPages = nil
                browser.askHistory()
                try? await Task.sleep(for: .milliseconds(400))
            }
            if let row = request["row"] as? Int { browser.query.spot = row }
            if let walk = request["filterMenu"] as? Int {
                browser.chooseFilter()
                browser.query.acting = walk
            }
            if request["closeSettings"] as? Bool == true { SettingsWindow.shared.hide() }
            // A day's page as text (Edit as Markdown), or its timeline again.
            if let day = request["editDay"] as? String { DaysModel.shared.editing = day.isEmpty ? nil : "episodic/\(day).md" }
            // Forget This Thread from Memory › Days, on the thread holding a page.
            if let forget = request["forget"] as? [String: Any], let url = (forget["url"] as? String).flatMap(URL.init(string:)),
               let at = forget["at"] as? Double, let id = await Diary.shared.threadID(holding: url, on: Date(timeIntervalSince1970: at)) {
                browser.forgetThread(id, inSettings: true)
                try? await Task.sleep(for: .milliseconds(600))
            }
            // Browsing as a tab lands pages: each visit handed to the diary
            // from here, the main thread, timed; the grouping after it is
            // the diary queue's, after the pause.
            if let pages = request["browse"] as? Int {
                let began = DispatchTime.now().uptimeNanoseconds
                for index in 0..<pages {
                    Diary.shared.visit(URL(string: "https://browse.invalid/page-\(index % 40)?n=\(index)")!, title: "Browsing page \(index % 40)",
                                       tab: UUID(), space: browser.spaceID)
                }
                out["mainMicroseconds"] = Double(DispatchTime.now().uptimeNanoseconds - began) / 1000
                out["browsed"] = pages
            }
            let all = await Diary.shared.threads(from: Date().addingTimeInterval(-40 * 86_400), to: Date().addingTimeInterval(60))
            out["threads"] = all.map { ["id": $0.id, "day": $0.day, "name": $0.name, "pages": $0.pages.count, "when": $0.when, "open": $0.open] }
            let cost = await Diary.shared.threadCost()
            out["stats"] = ["passes": cost.passes, "visits": cost.visits, "ms": cost.milliseconds, "longest": cost.longest, "onMain": cost.onMain,
                            "named": ThreadNamer.shared.answered, "asked": ThreadNamer.shared.asked]
            let commands = browser.selectionCommands
            out["sources"] = commands.sources.map(\.title)
            out["spot"] = commands.sourceSpot ?? -1
            out["primary"] = browser.answerActions.first?.title ?? ""
            answer(out)
        }
    }
}

@MainActor
enum ThreadsBench {
    /// ⌘T's Ask over the field, in a state: "typing" leaves the words in
    /// the field; "thinking" the live line; "answer" the words and the rows
    /// the world's own threads give for the numbers named.
    static func ask(_ ask: [String: Any], in browser: Browser) async {
        let question = ask["question"] as? String ?? ""
        let state = ask["state"] as? String ?? "answer"
        if !browser.fieldShowing { browser.edit() }
        if state == "typing" {
            browser.typed = question
            return
        }
        let tab = browser.holder()
        let snap = SelectionSnapshot(asking: nil)
        browser.fieldSelection = snap
        browser.enterPlace(.selection)
        browser.query.acting = nil
        browser.query.answering = true
        let commands = browser.selectionCommands
        let command = SelectionCommand(id: "ask", name: "Ask", prompt: question, executor: ask["executor"] as? String ?? "claude", custom: true)
        commands.show(command, on: tab, snapshot: snap, stage: state == "thinking" ? .running : .preview,
                      output: state == "thinking" ? "" : ask["answer"] as? String ?? "")
        commands.answering = true
        if state == "thinking" { commands.lookingThrough = DayThreads.span(question)?.words }
        if state != "thinking", let context = await AskFromDay.context(for: question) {
            // The pages the answer names, by their addresses.
            let named = (ask["cite"] as? [String] ?? []).compactMap { link in
                context.pages.first { $0.value.urls.first?.absoluteString == link }?.key
            }
            commands.cite(context, numbers: ask["numbers"] as? [Int] ?? named)
        }
        browser.replaceTyped("")
    }

    /// A site's icon as the prototype draws its stand-ins: a letter on its
    /// color, rounded.
    static func icon(_ letter: String, _ color: NSColor) -> Data? {
        let side: CGFloat = 64
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(roundedRect: rect, xRadius: side * 0.28, yRadius: side * 0.28).fill()
            let words = NSAttributedString(string: letter, attributes: [
                .font: NSFont.systemFont(ofSize: side * 0.58, weight: .bold), .foregroundColor: NSColor.white,
            ])
            let size = words.size()
            words.draw(at: NSPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
            return true
        }
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// A page's picture as the prototype draws one: the page's ground, a bar
    /// of its color, gray lines.
    static func page(_ color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 640, height: 420), flipped: true) { rect in
            NSColor.white.setFill()
            rect.fill()
            color.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: NSRect(x: 48, y: 44, width: 270, height: 30), xRadius: 15, yRadius: 15).fill()
            NSColor(white: 0, alpha: 0.12).setFill()
            for (index, width) in [1.0, 0.7, 1.0, 0.55, 0.85, 1.0, 0.6].enumerated() {
                NSBezierPath(roundedRect: NSRect(x: 48, y: 104 + CGFloat(index) * 40, width: (rect.width - 96) * width, height: 18),
                             xRadius: 9, yRadius: 9).fill()
            }
            return true
        }
    }
}
