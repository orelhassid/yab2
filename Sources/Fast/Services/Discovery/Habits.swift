import Foundation

// What you open by hand on a schedule, when it is that time now
// (PLAN-hints.md §5): the Stripe payouts most Mondays around ten, the team's
// board most weekday mornings around nine. Arithmetic over the visits
// AgentHistory reads (yab's diary and the Chromium browsers brought in from,
// thirty-five days), no model: so habits work from the first day for
// someone who came from Chrome.
//
// A place is a host and the first part of its path, as AgentHistory groups
// them: google.com/maps is not google.com/search. Of each place only the
// first visit of a day counts: a habit is coming, not staying. A place is
// a habit when, of the last five weekdays, on four the first visit fell in
// one window ninety minutes wide; or of the last four of today's weekday,
// three. It is offered from ten minutes before that window to its end, if
// it hasn't been opened today. A place opened most hours of the day (mail,
// chat) is no habit: it is open anyway.
//
// All in local time of each visit's own day, so a trip across time zones
// or a change to summer time moves the clock, not the habit.

struct Habit: Equatable {
    /// Host and first part of the path.
    let place: String
    let host: String
    /// The page opened most there, and what it is called.
    let url: URL
    let title: String?
    /// The middle of the window, minutes after midnight: the window runs
    /// 45 minutes either side.
    let center: Int
    /// The day of the week it is kept on (1 is Sunday), or nil for weekdays.
    let weekday: Int?
    /// Days it held, of the last five weekdays or four same days.
    let days: Int

    /// Why it is here, in words: "You open it most Mondays around 10 AM".
    var detail: String {
        let rounded = (center + 15) / 30 * 30 % 1440
        let hour = rounded / 60 % 12 == 0 ? 12 : rounded / 60 % 12
        // Morning or evening said, so half past midnight never reads as noon.
        let half = rounded < 720 ? "AM" : "PM"
        let time = rounded == 0 ? "midnight" : rounded == 720 ? "noon"
            : rounded % 60 == 0 ? "\(hour) \(half)" : "\(hour):30 \(half)"
        guard let weekday else { return "You open it most weekdays around \(time)" }
        let names = ["Sundays", "Mondays", "Tuesdays", "Wednesdays", "Thursdays", "Fridays", "Saturdays"]
        return "You open it most \(names[(weekday - 1) % 7]) around \(time)"
    }

    /// Whether now is its time: in the window, or ten minutes before it.
    func current(at now: Date, calendar: Calendar) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let offset = Habits.signed(minute - center)
        return offset >= -Habits.half - Habits.lead && offset <= Habits.half
    }
}

enum Habits {
    struct Visit: Equatable, Codable {
        let url: URL
        let at: Date
        var title: String?
    }

    /// How far back, the window's half width and how early it is offered.
    static let history = 35
    static let half = 45
    static let lead = 10
    /// More active hours a day than this, on average, and it is always open.
    static let hourly = 6.0

    /// Where a visit was, as habits count it, or nil for what is never one:
    /// a sign-in, a shortener, a search, yab's own pages, this Mac.
    static func place(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let raw = url.host()?.lowercased() else { return nil }
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        guard !AgentHistory.noise(host) else { return nil }
        let first = url.path.split(separator: "/").first.map { $0.lowercased() } ?? ""
        let searches = ["duckduckgo.com", "bing.com", "search.brave.com", "kagi.com", "ecosia.org", "search.yahoo.com", "startpage.com"]
        if searches.contains(host) || first == "search" || first == "webhp" { return nil }
        return first.isEmpty ? host : host + "/" + first
    }

    /// Minutes apart on a clock face, -720 to 720: 23:50 is ten before 00:00.
    static func signed(_ minutes: Int) -> Int {
        var value = ((minutes % 1440) + 1440) % 1440
        if value > 720 { value -= 1440 }
        return value
    }

    /// Of first visits, minutes after midnight: the middle of the most
    /// of them that fit in ninety minutes, if at least `need` do.
    static func window(_ minutes: [Int], need: Int) -> (center: Int, count: Int)? {
        guard minutes.count >= need else { return nil }
        var best: [Int] = []
        for start in minutes {
            // Each as an offset after this one, round midnight.
            let inside = minutes.map { ((($0 - start) % 1440) + 1440) % 1440 }.filter { $0 <= 2 * half }.sorted()
            if inside.count > best.count { best = inside.map { $0 + start } }
        }
        guard best.count >= need else { return nil }
        return (((best[best.count / 2] % 1440) + 1440) % 1440, best.count)
    }

    /// Every habit for today, whatever the time: what was opened today is
    /// left out, and what is opened most hours of the day.
    static func find(visits: [Visit], now: Date, calendar: Calendar) -> [Habit] {
        let today = calendar.startOfDay(for: now)
        guard let since = calendar.date(byAdding: .day, value: -history, to: today) else { return [] }
        struct Day { var first: Int; var at: Date; var hours: Set<Int> }
        var days: [String: [Date: Day]] = [:]
        var pages: [String: [String: (count: Int, url: URL, title: String?)]] = [:]
        for visit in visits where visit.at >= since && visit.at <= now {
            guard let place = place(visit.url) else { continue }
            let day = calendar.startOfDay(for: visit.at)
            let parts = calendar.dateComponents([.hour, .minute], from: visit.at)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            var kept = days[place, default: [:]][day] ?? Day(first: minute, at: visit.at, hours: [])
            if visit.at < kept.at { kept.first = minute; kept.at = visit.at }
            kept.hours.insert(parts.hour ?? 0)
            days[place, default: [:]][day] = kept
            var page = URLComponents(url: visit.url, resolvingAgainstBaseURL: false)
            page?.fragment = nil
            let key = page?.string ?? visit.url.absoluteString
            var seen = pages[place, default: [:]][key] ?? (0, visit.url, nil)
            seen.count += 1
            if let title = visit.title, !title.isEmpty { seen.title = title }
            pages[place, default: [:]][key] = seen
        }
        // The days asked about: the last five weekdays and the last four of
        // today's weekday, today not among them.
        var weekdays: [Date] = []
        var day = today
        for _ in 0..<14 where weekdays.count < 5 {
            guard let before = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = before
            if !calendar.isDateInWeekend(day) { weekdays.append(day) }
        }
        let same = (1...4).compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: today) }
        let weekday = calendar.component(.weekday, from: now)
        let working = !calendar.isDateInWeekend(now)

        var out: [Habit] = []
        for (place, byDay) in days where byDay[today] == nil {
            let hours = byDay.values.reduce(0) { $0 + $1.hours.count }
            guard Double(hours) / Double(byDay.count) <= hourly else { continue }
            var found: (center: Int, count: Int, weekday: Int?)?
            if working, let hit = window(weekdays.compactMap { byDay[$0]?.first }, need: 4) {
                found = (hit.center, hit.count, nil)
            } else if let hit = window(same.compactMap { byDay[$0]?.first }, need: 3) {
                found = (hit.center, hit.count, weekday)
            }
            guard let found, let page = pages[place]?.values.max(by: { $0.count < $1.count }) else { continue }
            out.append(Habit(place: place, host: String(place.split(separator: "/").first ?? ""), url: page.url, title: page.title,
                             center: found.center, weekday: found.weekday, days: found.count))
        }
        // One a site: the part of it kept on more days, the first by name on a tie.
        out.sort { $0.place < $1.place }
        var bySite: [String: Habit] = [:]
        for habit in out where (bySite[habit.host]?.days ?? 0) < habit.days { bySite[habit.host] = habit }
        return bySite.values.sorted { $0.center != $1.center ? $0.center < $1.center : $0.place < $1.place }
    }

    /// The habits whose time is now.
    static func now(visits: [Visit], now: Date, calendar: Calendar) -> [Habit] {
        find(visits: visits, now: now, calendar: calendar).filter { $0.current(at: now, calendar: calendar) }
    }
}
