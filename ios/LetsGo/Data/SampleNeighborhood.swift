import Foundation
import SwiftData
import CoreLocation

/// Example gatherings and kitchens placed around you, so the map has something
/// on it before real neighbors post. Every sample is tagged in the UI.
/// Times are relative to now, so "on now" always means now.
enum SampleNeighborhood {
    private static let centerKey = "sample.center"
    private static let seededAtKey = "sample.seededAt"
    static let enabledKey = "sample.enabled"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Reseeds when there are no samples, the last batch is from another day,
    /// or you've moved to a different neighborhood.
    static func refreshIfNeeded(around center: CLLocationCoordinate2D, context: ModelContext, now: Date = .now) {
        guard isEnabled else { return }
        let defaults = UserDefaults.standard
        let sameCenter = defaults.string(forKey: centerKey) == center.roundedKey
        let seededAt = defaults.object(forKey: seededAtKey) as? Date
        let fresh = seededAt.map { now.timeIntervalSince($0) < 6 * 3600 } ?? false
        let count = (try? context.fetchCount(FetchDescriptor<Gathering>(predicate: #Predicate { $0.isSample }))) ?? 0
        guard !(sameCenter && fresh && count > 0) else { return }
        seed(around: center, context: context, now: now)
        defaults.set(center.roundedKey, forKey: centerKey)
        defaults.set(now, forKey: seededAtKey)
    }

    static func clear(context: ModelContext) {
        do {
            try context.delete(model: Gathering.self, where: #Predicate { $0.isSample })
            // Cascade rules only run for object deletes, so delete sample kitchens one by one.
            let kitchens = try context.fetch(FetchDescriptor<Kitchen>(predicate: #Predicate { $0.isSample }))
            kitchens.forEach { context.delete($0) }
        } catch {
            Ledger.save(context, "clear samples (after error: \(error.localizedDescription))")
            return
        }
        UserDefaults.standard.removeObject(forKey: seededAtKey)
        Ledger.save(context, "clear samples")
    }

    static func seed(around c: CLLocationCoordinate2D, context: ModelContext, now: Date = .now) {
        clear(context: context)
        let min: (Double) -> Date = { now.addingTimeInterval($0 * 60) }
        let weekday = now.formatted(.dateTime.weekday(.wide))

        let gatherings = [
            Gathering(
                title: "Pickup soccer", category: .play,
                details: "Small-sided, mixed levels. Teams picked on the spot.",
                placeName: "The big field", coordinate: c.offset(east: -340, north: 160),
                start: min(38), end: min(140), capacity: 14, othersGoing: 12,
                hostName: "Sam O.", bring: "A light and a dark shirt. Shin guards optional.",
                recurring: "Every \(weekday)", isSample: true
            ),
            Gathering(
                title: "Backyard set", category: .music,
                details: "House DJ, string lights, bring a chair if you want to sit.",
                placeName: "Mira's backyard", coordinate: c.offset(east: -520, north: 470),
                start: min(-20), end: min(200), capacity: 40, othersGoing: 14,
                hostName: "Mira K.", bring: "Something to drink", isSample: true
            ),
            Gathering(
                title: "Easy 5k, talking pace", category: .move,
                details: "One loop, nobody gets dropped. About 11 min/mi.",
                placeName: "The loop trailhead", coordinate: c.offset(east: -600, north: -260),
                start: min(65), end: min(110), othersGoing: 9,
                hostName: "Priya R.", recurring: "Every \(weekday)", isSample: true
            ),
            Gathering(
                title: "Board game night", category: .party,
                details: "Catan, Codenames, whatever shows up. Snacks on the table.",
                placeName: "Theo's front room", coordinate: c.offset(east: 120, north: 380),
                start: min(120), end: min(300), capacity: 10, othersGoing: 6,
                hostName: "Theo B.", bring: "A game, if you have one", isSample: true
            ),
            Gathering(
                title: "Corner court 3v3", category: .play,
                details: "Winners stay on.",
                placeName: "Corner court", coordinate: c.offset(east: 560, north: -120),
                start: min(-35), end: min(70), capacity: 12, othersGoing: 8,
                hostName: "Andre W.", isSample: true
            ),
            Gathering(
                title: "Sunrise walk and coffee", category: .move,
                details: "Thirty minutes, then coffee at whoever's closest.",
                placeName: "The hill stairs", coordinate: c.offset(east: 300, north: 640),
                start: tomorrow(at: 8, from: now), end: tomorrow(at: 9, from: now), othersGoing: 5,
                hostName: "June L.", isSample: true
            ),
        ]
        gatherings.forEach(context.insert)

        let dana = Kitchen(
            name: "Dana's Porch Pizza", cookName: "Dana", cuisine: "Pizza",
            story: "Wood-fired in the backyard oven. Twelve-inch pies, ninety seconds each.",
            coordinate: c.offset(east: 210, north: 260),
            pickupNote: "Side gate on the left. Ring the bell on the post.",
            porchTables: 2, rating: 4.9, reviewCount: 212, regulars: 38, isSample: true
        )
        add(dana, menu: [
            ("Margherita", "12\", 90-second wood oven", 1400),
            ("Hot honey soppressata", "Her most reordered", 1600),
            ("Garlic knots, six", "", 600),
        ], drop: Drop(start: min(18), end: min(108), total: 24, sold: 15), context: context)
        add(dana, reviews: [
            (5, "Better than the place on the main drag. Ate it on her porch steps.", "Jordan T."),
            (5, "Hot honey one is unreal. Get there at the start of the drop.", "Lena S."),
            (4, "Crust was perfect, wish there were more knots.", "Marcus D."),
        ], now: now)

        let june = Kitchen(
            name: "Back Gate Ice Cream", cookName: "June", cuisine: "Ice cream",
            story: "Small batches churned that morning. Three flavors, gone when they're gone.",
            coordinate: c.offset(east: 470, north: 90),
            pickupNote: "Blue back gate off the alley. Cooler is by the steps.",
            porchTables: 1, rating: 4.8, reviewCount: 31, regulars: 14, isSample: true
        )
        add(june, menu: [
            ("Mango chili", "Sold out in 40 min last time", 600),
            ("Brown butter pecan", "", 600),
            ("Strawberry buttermilk", "", 600),
        ], drop: Drop(start: min(108), end: min(198), total: 30, sold: 6), context: context)
        add(june, reviews: [
            (5, "Mango chili should be illegal.", "Ari P."),
            (5, "Ended up talking to her neighbors for an hour.", "Sam O."),
        ], now: now)

        let rosa = Kitchen(
            name: "Rosa's Tamales", cookName: "Rosa", cuisine: "Tamales",
            story: "Her mother's recipe. Pork in red chile, chicken verde, and rajas con queso.",
            coordinate: c.offset(east: -180, north: -420),
            pickupNote: "Front porch. Knock twice, she's usually in the kitchen.",
            rating: 5.0, reviewCount: 64, regulars: 22, isSample: true
        )
        add(rosa, menu: [
            ("Pork in red chile, dozen", "", 3000),
            ("Chicken verde, dozen", "", 3000),
            ("Rajas con queso, half dozen", "Vegetarian", 1600),
        ], drop: Drop(start: tomorrow(at: 10, from: now), end: tomorrow(at: 13, from: now), total: 40, sold: 11, perSlot: 6), context: context)
        add(rosa, reviews: [
            (5, "Bought two dozen, froze one. Gone in a week anyway.", "Nina V."),
        ], now: now)

        let kenji = Kitchen(
            name: "Kenji's Curry Night", cookName: "Kenji", cuisine: "Japanese curry",
            story: "Katsu curry from a pot that's been going since noon.",
            coordinate: c.offset(east: 640, north: 420),
            pickupNote: "Garage door will be up. Grab a bowl and a seat if there's one.",
            porchTables: 3, rating: 4.7, reviewCount: 48, regulars: 17, isSample: true
        )
        add(kenji, menu: [
            ("Katsu curry", "Pork cutlet, rice, pickles", 1500),
            ("Veggie curry", "Squash, potato, egg", 1200),
        ], drop: Drop(start: min(150), end: min(240), total: 20, sold: 4), context: context)

        Ledger.save(context, "seed samples")
    }

    private static func add(_ k: Kitchen, menu: [(String, String, Int)], drop: Drop, context: ModelContext) {
        context.insert(k)
        for (i, item) in menu.enumerated() {
            let m = MenuItem(name: item.0, note: item.1, priceCents: item.2, sortIndex: i)
            context.insert(m)
            m.kitchen = k
        }
        context.insert(drop)
        drop.kitchen = k
    }

    private static func add(_ k: Kitchen, reviews: [(Int, String, String)], now: Date) {
        // Sample reviews are already counted in the base rating; these are just
        // the ones shown on the page, so they live as plain text on the kitchen.
        k.sampleReviews = reviews.enumerated().map { i, r in
            SampleReview(stars: r.0, text: r.1, author: r.2, daysAgo: (i + 1) * 3)
        }
    }

    private static func tomorrow(at hour: Int, from now: Date) -> Date {
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
    }
}
