import Foundation

/// What you asked Wren for, read out of plain text.
struct WrenQuery: Equatable, Sendable {
    enum Day: Equatable, Sendable { case any, today, tomorrow, on(Date) }

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

    static func parse(_ raw: String, now: Date = .now, calendar: Calendar = .current) -> WrenQuery {
        let text = raw.lowercased()
        var q = WrenQuery(text: raw)
        q.wantsToCreate = createWords.contains { text.hasPrefix($0) || text.contains(" \($0) ") || text.contains("\($0) a") }
        q.wantsQuiet = quietWords.contains { text.contains($0) }
        q.wantsFree = text.contains("free")
        for c in Genre.allCases where c.keywords.contains(where: { text.contains($0) }) {
            q.categories.insert(c)
        }
        // "game night" also contains "game"; a hang beats a sport there.
        if text.contains("game night") || text.contains("board game") { q.categories.remove(.play) }
        if let price = firstPrice(in: text) { q.maxPriceCents = price }

        if let d = detectDate(in: raw, now: now) {
            q.date = d
            if calendar.isDate(d, inSameDayAs: now) {
                q.day = .today
            } else if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(d, inSameDayAs: t) {
                q.day = .tomorrow
            } else {
                q.day = .on(d)
            }
        } else if text.contains("tonight") || text.contains("now") || text.contains("today") {
            q.day = .today
        } else if text.contains("tomorrow") {
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
        case .on(let d): return calendar.isDate(c.start, inSameDayAs: d)
        }
    }
}

/// A gathering Wren wrote from one sentence, waiting for you to post it.
struct GatheringDraft: Equatable, Sendable, Identifiable {
    var id = UUID()
    var title: String
    var category: Genre
    var start: Date
    var end: Date
    var placeName: String
    var capacity: Int = 0

    static func from(_ q: WrenQuery, now: Date = .now, calendar: Calendar = .current) -> GatheringDraft {
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
