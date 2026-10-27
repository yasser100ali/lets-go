import Foundation

/// What the Today tab picks out of everything nearby. Plain functions so they can be tested.
enum Today {
    /// A short walk: the "Within a 15-minute walk" section.
    static let walkMinutes = 15
    /// How far ahead the short-walk section looks.
    static let walkHorizon: TimeInterval = 6 * 3600

    static func headline(now: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: now) {
        case 4..<12: "What's on this morning"
        case 12..<17: "What's on this afternoon"
        default: "What's alive tonight"
        }
    }

    /// Monday to Sunday of the week `now` is in. Weeks start on Monday.
    static func week(of now: Date, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.firstWeekday = 2
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    /// On now, or starting within the hour, best first.
    static func startingSoon(_ all: [Candidate], now: Date, taste: Taste, limit: Int = 8) -> [Candidate] {
        Picks.picks(all, now: now, taste: taste, limit: 40)
            .filter { $0.start.timeIntervalSince(now) <= 3600 }
            .prefix(limit)
            .map { $0 }
    }

    /// Within a 15-minute walk, on now or later today, soonest first.
    static func walkable(_ all: [Candidate], now: Date, excluding: Set<UUID> = [], limit: Int = 6) -> [Candidate] {
        all
            .filter { !excluding.contains($0.id) && $0.walkMinutes <= walkMinutes }
            .filter { $0.end > now && $0.start.timeIntervalSince(now) <= walkHorizon }
            .filter { $0.spotsLeft != 0 && $0.dropLeft != 0 }
            .sorted { $0.start < $1.start }
            .prefix(limit)
            .map { $0 }
    }

    /// Everything starting on `day` that hasn't ended, soonest first.
    static func happening(_ all: [Candidate], on day: Date, now: Date, calendar: Calendar = .current) -> [Candidate] {
        all
            .filter { calendar.isDate($0.start, inSameDayAs: day) && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    /// When nothing is close enough to be a pick: the next thing that hasn't ended.
    static func next(_ all: [Candidate], now: Date) -> Candidate? {
        all.filter { $0.end > now && $0.spotsLeft != 0 && $0.dropLeft != 0 }.min { $0.start < $1.start }
    }
}
