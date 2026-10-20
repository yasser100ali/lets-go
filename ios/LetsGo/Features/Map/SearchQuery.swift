import Foundation

/// What you typed in search, read for kinds of things, days, prices and moods.
struct SearchQuery: Equatable, Sendable {
    enum Day: Equatable, Sendable { case any, today, tomorrow, weekend, on(Date) }

    var categories: Set<Genre> = []
    var maxPriceCents: Int?
    var wantsFree = false
    var wantsQuiet = false
    var day: Day = .any
    var date: Date?
    var wantsToCreate = false
    var text: String = ""

    static let createWords = ["make", "host", "create", "start", "organize", "organise", "set up", "plan", "post"]
    static let quietWords = ["chill", "quiet", "small", "low key", "low-key", "calm", "mellow", "easy"]

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> SearchQuery {
        let text = raw.lowercased()
        let words = Set(text.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        var q = SearchQuery(text: raw)
        q.wantsToCreate = createWords.contains { text.hasPrefix($0) || text.contains(" \($0) ") || text.contains("\($0) a") }
        q.wantsQuiet = quietWords.contains { text.contains($0) }
        q.wantsFree = text.contains("free")
        for c in Genre.allCases where c.keywords.contains(where: { text.contains($0) }) {
            q.categories.insert(c)
        }
        // "game night" also contains "game"; a hang beats a sport there.
        if text.contains("game night") || text.contains("board game") { q.categories.remove(.play) }
        if let price = firstPrice(in: text) { q.maxPriceCents = price }

        // Plain day words win: Apple's date detector reads them against the real clock,
        // not `now`, and "tonight" is never a different day.
        if words.contains("weekend") {
            q.day = .weekend
        } else if !words.isDisjoint(with: ["tonight", "now", "today", "rn"]) {
            q.day = .today
            q.date = detectDate(in: raw, now: now).flatMap { calendar.isDate($0, inSameDayAs: now) ? $0 : nil }
        } else if let d = detectDate(in: raw, now: now) {
            q.date = d
            if calendar.isDate(d, inSameDayAs: now) {
                q.day = .today
            } else if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) {
                q.day = .tomorrow
            } else {
                q.day = .on(d)
            }
        } else if words.contains("tomorrow") {
            q.day = .tomorrow
        }
        return q
    }

    /// "under $15", "$15", "15 bucks"
    private static func firstPrice(in text: String) -> Int? {
        let pattern = #"\$\s?(\d{1,3})|(\d{1,3})\s?(bucks|dollars)"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for i in 1...2 {
            if let r = Range(m.range(at: i), in: text), let n = Int(text[r]) { return n * 100 }
        }
        return nil
    }

    static func detectDate(in text: String, now: Date) -> Date? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        guard let date = match?.date else { return nil }
        // "sat 8am" on a Saturday evening means next Saturday, not this morning.
        return date < now.addingTimeInterval(-3600) ? date.addingTimeInterval(7 * 86_400) : date
    }

    func matches(_ c: Candidate, now: Date, calendar: Calendar = .current) -> Bool {
        if !categories.isEmpty && !categories.contains(c.category) { return false }
        if wantsFree && !c.isFree { return false }
        if let max = maxPriceCents, let price = c.priceFromCents, price > max { return false }
        if wantsQuiet && c.category == .party && c.capacity > 12 { return false }
        if wantsQuiet && c.capacity > 20 { return false }
        switch day {
        case .any: return c.end > now
        case .today: return c.end > now && calendar.isDate(c.start, inSameDayAs: now)
        case .tomorrow:
            guard let t = calendar.date(byAdding: .day, value: 1, to: now) else { return false }
            return calendar.isDate(c.start, inSameDayAs: t)
        case .weekend: return TimeWindow.weekend.contains(start: c.start, end: c.end, now: now, calendar: calendar)
        case .on(let d): return calendar.isDate(c.start, inSameDayAs: d)
        }
    }
}

/// A gathering drafted from what you searched for, so "slow jog sat 8am" can become one.
struct GatheringDraft: Equatable, Sendable, Identifiable {
    var id = UUID()
    var title: String
    var category: Genre
    var start: Date
    var end: Date
    var placeName: String
    var capacity: Int = 0
    /// Set when hosting at a known place, so the pin starts there.
    var latitude: Double? = nil
    var longitude: Double? = nil

    static func from(_ q: SearchQuery, now: Date = .now, calendar: Calendar = .current) -> GatheringDraft {
        let text = q.text.lowercased()
        let category = q.categories.first ?? .party
        let start = q.date ?? roundUp(now.addingTimeInterval(3600), calendar: calendar)
        let keyword = category.keywords.first { text.contains($0) } ?? category.label.lowercased()
        let pace = ["slow", "easy", "chill", "fast", "casual"].first { text.contains($0) }
        let dayName = calendar.isDate(start, inSameDayAs: now) ? "" : start.formatted(.dateTime.weekday(.wide))
        let words = [pace?.capitalized, dayName.isEmpty ? nil : dayName, keyword]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        var title = words.joined(separator: " ")
        title = title.prefix(1).uppercased() + title.dropFirst()
        return GatheringDraft(
            title: title,
            category: category,
            start: start,
            end: start.addingTimeInterval(category == .move ? 3600 : 2 * 3600),
            placeName: place(in: q.text) ?? ""
        )
    }

    /// "around the lake" → "The lake". Stops at a time or day word.
    static func place(in text: String) -> String? {
        let lower = text.lowercased()
        for marker in [" around ", " at the ", " in the ", " by the ", " near "] {
            guard let r = lower.range(of: marker) else { continue }
            var tail = String(text[r.upperBound...])
            if marker.hasSuffix("the ") { tail = "the " + tail }
            let stops = [" at ", " on ", " sat", " sun", " mon", " tue", " wed", " thu", " fri", " tomorrow", " tonight", ",", "."]
            for stop in stops {
                if let s = tail.lowercased().range(of: stop) {
                    tail = String(tail[..<s.lowerBound])
                }
            }
            let trimmed = tail.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .decimalDigits) == nil else { continue }
            return trimmed.prefix(1).uppercased() + trimmed.dropFirst()
        }
        return nil
    }

    private static func roundUp(_ d: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: d)
        let m = comps.minute ?? 0
        comps.minute = m < 30 ? 30 : 0
        let base = calendar.date(from: comps) ?? d
        return m < 30 ? base : base.addingTimeInterval(3600)
    }
}

/// The three windows the map shows: the next few hours, tonight, the weekend.
enum TimeWindow: String, CaseIterable, Identifiable, Sendable {
    case now, tonight, weekend

    var id: String { rawValue }
    var label: String {
        switch self {
        case .now: "Now"
        case .tonight: "Tonight"
        case .weekend: "Weekend"
        }
    }

    func contains(start: Date, end: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard end > now else { return false }
        switch self {
        case .now:
            return start.timeIntervalSince(now) <= Picks.horizon
        case .tonight:
            // From 5 PM (or now, if later) until 2 AM.
            let today = calendar.startOfDay(for: now)
            guard let five = calendar.date(byAdding: .hour, value: 17, to: today),
                  let late = calendar.date(byAdding: .hour, value: 26, to: today) else { return false }
            return start < late && end > max(now, five)
        case .weekend:
            guard let range = Self.weekendRange(from: now, calendar: calendar) else { return false }
            return start < range.upperBound && end > max(now, range.lowerBound)
        }
    }

    /// This Saturday 00:00 to Monday 00:00; if it's already the weekend, this one.
    static func weekendRange(from now: Date, calendar: Calendar = .current) -> Range<Date>? {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = Sunday, 7 = Saturday
        let toSaturday = weekday == 1 ? -1 : (7 - weekday)
        guard let saturday = calendar.date(byAdding: .day, value: toSaturday, to: today),
              let monday = calendar.date(byAdding: .day, value: 2, to: saturday) else { return nil }
        return saturday..<monday
    }
}

/// Free-text search over what's nearby: "pizza", "basketball tonight", "free run this weekend".
enum Search {
    /// Words that carry no meaning for matching, or are already read by `SearchQuery`.
    static let ignored: Set<String> = [
        "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "with", "near", "me", "nearby",
        "some", "something", "anything", "any", "i", "want", "who", "whos", "who's", "is", "are", "selling",
        "tonight", "today", "tomorrow", "now", "rn", "weekend", "this", "morning", "afternoon", "evening",
        "under", "free", "cheap", "chill", "quiet", "small", "easy", "low", "key", "mellow", "calm",
        "am", "pm", "mon", "tue", "wed", "thu", "fri", "sat", "sun", "monday", "tuesday", "wednesday",
        "thursday", "friday", "saturday", "sunday", "bucks", "dollars", "where", "what", "go", "lets",
    ]
    /// Broad words that match a whole kind of thing, not a word in its title.
    static let broad: [String: Genre] = [
        "food": .food, "eat": .food, "hungry": .food, "dinner": .food, "lunch": .food, "dessert": .food,
        "sport": .play, "sports": .play, "game": .play, "games": .play, "play": .play, "pickup": .play,
        "music": .music, "live": .music, "run": .move, "running": .move, "runs": .move, "workout": .move,
        "move": .move, "hang": .party, "party": .party, "social": .party,
    ]

    static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
            .map(String.init)
            .filter { $0.count >= 2 && !ignored.contains($0) && Int($0) == nil && !$0.hasPrefix("$") }
    }

    static func results(_ text: String, in candidates: [Candidate], now: Date = .now) -> [Candidate] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var query = SearchQuery.parse(trimmed, now: now)
        let words = tokens(trimmed)
        // Specific words ("pizza") are matched as text, so don't also narrow by their kind.
        if !words.isEmpty { query.categories = Set(words.compactMap { broad[$0] }) }
        return candidates
            .filter { c in
                query.matches(c, now: now) && words.allSatisfy { w in
                    c.searchText.contains(w) || broad[w] == c.category || (w.hasSuffix("s") && c.searchText.contains(String(w.dropLast())))
                }
            }
            .sorted { $0.start < $1.start }
    }
}
