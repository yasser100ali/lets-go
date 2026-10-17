import Foundation
import CoreLocation

/// One thing Wren could suggest: a gathering, or a kitchen's drop.
/// A plain value so the scoring can be tested without a database.
struct Candidate: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable { case gathering, drop }

    var id: UUID
    var kind: Kind
    var title: String
    var category: Genre
    var start: Date
    var end: Date
    var meters: Double
    var capacity: Int = 0
    var going: Int = 0
    var dropLeft: Int?
    var dropTotal: Int?
    var priceFromCents: Int?
    var isJoined: Bool = false
    var isSample: Bool = false

    var spotsLeft: Int? { capacity > 0 ? max(0, capacity - going) : nil }
    var walkMinutes: Int { Walk.minutes(meters) }
    var isFree: Bool { kind == .gathering }
}

extension Candidate {
    init(_ g: Gathering, from here: CLLocationCoordinate2D) {
        self.init(
            id: g.id, kind: .gathering, title: g.title, category: g.category,
            start: g.start, end: g.end, meters: here.distance(to: g.coordinate),
            capacity: g.capacity, going: g.going, isJoined: g.isJoined, isSample: g.isSample
        )
    }

    init?(_ k: Kitchen, from here: CLLocationCoordinate2D, now: Date) {
        guard let drop = k.nextDrop(after: now) else { return nil }
        self.init(
            id: k.id, kind: .drop, title: k.name, category: .food,
            start: drop.start, end: drop.end, meters: here.distance(to: k.coordinate),
            dropLeft: drop.left, dropTotal: drop.total,
            priceFromCents: k.menu.map(\.priceCents).min(), isSample: k.isSample
        )
    }
}

/// How much you seem to like each kind of thing, 0...1, learned from what you
/// joined, showed up to and ordered, minus anything you told Wren to forget.
struct Taste: Sendable {
    var weights: [Genre: Double] = [:]

    func weight(_ c: Genre) -> Double { weights[c] ?? 0 }

    static func from(notes: [TasteNote], joined: [Genre], ordered: Int) -> Taste {
        var raw: [Genre: Double] = [:]
        for c in joined { raw[c, default: 0] += 1 }
        raw[.food, default: 0] += Double(ordered)
        for n in notes where !n.isHidden {
            if let c = n.category { raw[c, default: 0] += 0.5 }
        }
        // A category you've hidden every note for drops to zero.
        let hidden = Set(notes.filter(\.isHidden).compactMap(\.category))
        let visible = Set(notes.filter { !$0.isHidden }.compactMap(\.category))
        for c in hidden.subtracting(visible) { raw[c] = 0 }
        let top = raw.values.max() ?? 0
        guard top > 0 else { return Taste() }
        return Taste(weights: raw.mapValues { $0 / top })
    }
}

enum Wren {
    /// How far ahead the map counts as "now".
    static let horizon: TimeInterval = 3 * 3600

    /// Higher is better. Zero means don't suggest it.
    static func score(_ c: Candidate, now: Date, taste: Taste) -> Double {
        if c.end <= now { return 0 }
        if c.spotsLeft == 0 || c.dropLeft == 0 { return 0 }
        let until = c.start.timeIntervalSince(now)
        if until > horizon { return 0 }

        // Soon beats later; something already on is as good as starting now.
        let timeScore = until <= 0 ? 0.9 : 1 - until / horizon
        // Twenty minutes' walk is the edge of interesting.
        let walkScore = max(0, 1 - Double(c.walkMinutes) / 20)
        var urgency = 0.0
        if let spots = c.spotsLeft, spots <= 2 { urgency += 0.35 }
        if let left = c.dropLeft, let total = c.dropTotal, total > 0, Double(left) / Double(total) < 0.5 { urgency += 0.25 }
        if c.isJoined { urgency += 0.4 }
        let tasteScore = taste.weight(c.category) * 0.5
        return timeScore * 0.9 + walkScore * 1.1 + urgency + tasteScore
    }

    static func picks(_ candidates: [Candidate], now: Date, taste: Taste, limit: Int = 3) -> [Candidate] {
        candidates
            .map { ($0, score($0, now: now, taste: taste)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// The short reason under a pick: "2 spots left · 6 min walk".
    static func reason(_ c: Candidate, now: Date) -> String {
        var parts: [String] = []
        if let spots = c.spotsLeft {
            parts.append(spots == 1 ? "needs 1 more" : spots <= 3 ? "needs \(spots)" : "\(c.going) going")
        } else if let left = c.dropLeft {
            parts.append("\(left) left")
        } else if c.going > 0 {
            parts.append("\(c.going) going")
        }
        if let price = c.priceFromCents { parts.append("from \(Pricing.format(price))") }
        parts.append(Walk.label(c.meters))
        return parts.joined(separator: " · ")
    }

    /// Wren's one line at the top of the map, written from the top picks.
    /// Markdown, with the figures in bold.
    static func line(_ picks: [Candidate], now: Date) -> String {
        guard let first = picks.first else {
            return "Quiet around you right now. Start something and people nearby will see it."
        }
        let a = clause(first, now: now, lead: true)
        guard picks.count > 1 else { return a + "." }
        let second = picks[1]
        let b = clause(second, now: now, lead: false)
        // Both fit if the second starts after the first one's first hour.
        let doable = abs(second.start.timeIntervalSince(first.start)) >= 45 * 60
            || second.kind != first.kind
        return "\(a), and \(b).\(doable ? " You could do both." : "")"
    }

    private static func clause(_ c: Candidate, now: Date, lead: Bool) -> String {
        let name = lead ? c.title : c.title.lowercasedFirst
        let when = c.start <= now ? "**on now**" : "**\(When.relative(c.start, now: now))**"
        switch c.kind {
        case .gathering:
            if let spots = c.spotsLeft, spots <= 3 {
                let short = spots == 1 ? "**one short**" : "**\(spots) short**"
                return "\(name) is \(short), \(c.walkMinutes) min away"
            }
            return c.start <= now ? "\(name) is \(when), \(c.walkMinutes) min away" : "\(name) starts \(when)"
        case .drop:
            if c.start <= now, let left = c.dropLeft {
                return "\(name) has **\(left) left**, \(c.walkMinutes) min away"
            }
            return "\(name) drops \(when), \(c.walkMinutes) min away"
        }
    }
}

extension String {
    /// "Pickup soccer" → "pickup soccer", but leaves names like "Dana's" alone.
    var lowercasedFirst: String {
        guard let first = first, first.isUppercase else { return self }
        let firstWord = prefix { $0 != " " }
        if firstWord.contains("'") { return self }
        return first.lowercased() + dropFirst()
    }
}
