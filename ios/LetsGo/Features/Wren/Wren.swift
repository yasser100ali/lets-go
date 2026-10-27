import Foundation

/// Wren's answers. The suggestions always come from what's really nearby, read with
/// the same parser search uses (`SearchQuery`), so they can be tested without a model.
enum Wren {
    struct Answer {
        var reply: String
        var picks: [Candidate] = []
        var draft: GatheringDraft?
    }

    static func answer(_ raw: String, candidates: [Candidate], taste: Taste, now: Date) -> Answer {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return Answer(reply: hello) }
        let query = SearchQuery.parse(text, now: now)
        if query.wantsToCreate {
            return Answer(
                reply: "Here's a draft. Check the place and time, then post it and people nearby will see it.",
                draft: GatheringDraft.from(query, now: now)
            )
        }
        let matches = Search.results(text, in: candidates, now: now)
        // Asked about now or tonight: rank by what's worth going to. Otherwise, soonest first.
        var picks: [Candidate] = []
        if query.day == .any || query.day == .today {
            picks = Picks.picks(matches, now: now, taste: taste, limit: 3)
        }
        if picks.isEmpty { picks = Array(matches.sorted { $0.start < $1.start }.prefix(3)) }
        return Answer(reply: reply(query, picks, now: now), picks: picks)
    }

    static let hello = "Tell me a mood, like \u{201C}something chill tonight under $15\u{201D}, or a plan, like \u{201C}host a slow jog Saturday 8am around the lake\u{201D}, and I'll find it or draft it."

    static func reply(_ q: SearchQuery, _ picks: [Candidate], now: Date) -> String {
        guard let first = picks.first else {
            if q.categories.isEmpty {
                return "Nothing like that near you yet. Want to start one? Say \u{201C}host\u{201D} and what you have in mind."
            }
            let kinds = q.categories.map(\.noun).sorted().joined(separator: " or ")
            return "No \(kinds) near you for that. Say \u{201C}host\u{201D} and what you have in mind, and I'll draft one."
        }
        if picks.count == 1 { return "One that fits: \(first.title), \(Picks.reason(first, now: now))." }
        let quiet = q.wantsQuiet ? " They're all small." : ""
        let lead = picks.count == 2 ? "Two that fit." : "A few that fit."
        let soonest = picks.min { $0.start < $1.start } ?? first
        return "\(lead)\(quiet) \(soonest.title) is the soonest, \(When.relative(soonest.start, end: soonest.end, now: now))."
    }
}
