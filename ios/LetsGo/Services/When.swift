import Foundation

/// How times read in the app: "now", "in 18 min", "6:30 PM", "Sat 8:00 AM".
enum When {
    static func short(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "Tomorrow \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    /// Relative while it's close, clock time once it's far.
    static func relative(_ start: Date, end: Date? = nil, now: Date = .now) -> String {
        if let end, start <= now, now < end { return "on now" }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 0 { return "started" }
        if minutes < 1 { return "starting" }
        if minutes < 60 { return "in \(minutes) min" }
        return short(start, now: now)
    }

    static func range(_ start: Date, _ end: Date) -> String {
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return "\(s)–\(e)"
    }
}
