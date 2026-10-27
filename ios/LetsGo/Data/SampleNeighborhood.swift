import Foundation
import SwiftData
import CoreLocation
import MapKit
import OSLog

/// Example gatherings and kitchens around you, so the map has a real-feeling
/// neighborhood before neighbors post. Gatherings sit at actual parks, courts,
/// cafés and bars near you (from Apple Maps); kitchens sit on nearby blocks.
/// Times are relative to now, and every item is marked as a sample on its page.
enum SampleNeighborhood {
    private static let centerKey = "sample.center"
    private static let seededAtKey = "sample.seededAt"
    private static let versionKey = "sample.version"
    /// Bump when the seed content changes so phones reseed.
    private static let version = 4
    static let enabledKey = "sample.enabled"
    private static let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "seed")
    private static var seeding = false

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Reseeds when there are no samples, the batch is old or from an older version,
    /// or you've moved to a different neighborhood.
    /// In San Francisco, real listings stand in for the made-up gatherings, so only kitchens are seeded.
    static func refreshIfNeeded(around center: CLLocationCoordinate2D, context: ModelContext, now: Date = .now) async {
        let includeGatherings = !CityListings.covers(center)
        guard isEnabled, !seeding else { return }
        let defaults = UserDefaults.standard
        let sameCenter = defaults.string(forKey: centerKey) == center.roundedKey
        let fresh = (defaults.object(forKey: seededAtKey) as? Date).map { now.timeIntervalSince($0) < 6 * 3600 } ?? false
        let current = defaults.integer(forKey: versionKey) == version
        let count = (try? context.fetchCount(FetchDescriptor<Kitchen>(predicate: #Predicate { $0.isSample }))) ?? 0
        guard !(sameCenter && fresh && current && count > 0) else { return }
        await seed(around: center, context: context, now: now, includeGatherings: includeGatherings)
        defaults.set(center.roundedKey, forKey: centerKey)
        defaults.set(now, forKey: seededAtKey)
        defaults.set(version, forKey: versionKey)
    }

    static func clear(context: ModelContext) {
        do {
            try context.delete(model: Gathering.self, where: #Predicate { $0.isSample })
            try context.delete(model: Person.self, where: #Predicate { $0.isSample })
            try context.delete(model: Crew.self, where: #Predicate { $0.isSample })
            // Cascade rules only run for object deletes, so delete sample kitchens one by one.
            try context.fetch(FetchDescriptor<Kitchen>(predicate: #Predicate { $0.isSample })).forEach { context.delete($0) }
        } catch {
            log.error("Clearing samples failed: \(error.localizedDescription, privacy: .public)")
        }
        UserDefaults.standard.removeObject(forKey: seededAtKey)
        Ledger.save(context, "clear samples")
    }

    static func seed(around c: CLLocationCoordinate2D, context: ModelContext, now: Date = .now, includeGatherings: Bool? = nil) async {
        guard !seeding else { return }
        seeding = true
        defer { seeding = false }
        let withGatherings = includeGatherings ?? !CityListings.covers(c)
        let places = withGatherings ? await PlaceFinder.find(around: c) : []
        clear(context: context)
        let t = Times(now: now)
        var spots = Spots(places: places, center: c)

        let gatherings: [Gathering] = [
            g("Pickup soccer", .play, spots.take(.park, fallback: "The big field", east: -340, north: 160),
              "Small-sided, mixed levels. Teams picked on the spot, subs every ten minutes.",
              t.min(38), t.min(140), cap: 14, going: 12, host: "Sam Okafor",
              bring: "A light and a dark shirt", recurring: "Every \(t.weekday)"),
            g("3v3, winners stay on", .play, spots.take(.court, fallback: "Corner court", east: 560, north: -120),
              "Half court. Call your own fouls.", t.min(-35), t.min(70), cap: 12, going: 8, host: "Andre Williams"),
            g("Easy 5k, talking pace", .move, spots.take(.cafe, fallback: "The loop trailhead", east: -600, north: -260, suffix: ", out front"),
              "One loop, about 11 min a mile, nobody gets dropped. Coffee after.", t.min(65), t.min(115),
              going: 9, host: "Jess Nakamura", recurring: "Every \(t.weekday)"),
            g("Backyard set", .music, spots.home("Mira's backyard", east: -520, north: 470),
              "House DJ until late. String lights, bring a chair if you want to sit.", t.min(-20), t.min(220),
              cap: 40, going: 14, host: "Mira Kowalski", bring: "Something to drink"),
            g("Trivia, team needs two", .party, spots.take(.bar, fallback: "The corner bar", east: 380, north: 300),
              "We're 4 and the max is 6. Pop culture and geography people especially welcome.",
              t.today(19, 30), t.today(21, 30), cap: 6, going: 4, host: "Ben Carter", recurring: "Every Tuesday"),
            g("Sunset frisbee", .play, spots.take(.park, fallback: "The upper lawn", east: 240, north: 520),
              "Ultimate if we get 10, catch if we don't.", t.today(18, 15), t.today(19, 45),
              cap: 16, going: 7, host: "Tomás Ruiz"),
            g("Open mic", .music, spots.take(.venue, fallback: "The back room", east: -150, north: -480),
              "Sign-up sheet at 7:30. Two songs or ten minutes, whichever comes first.",
              t.today(20, 0), t.today(22, 30), going: 18, host: "Dev Patel"),
            g("Spanish–English swap", .party, spots.take(.cafe, fallback: "The café on the corner", east: 120, north: -360),
              "Half the hour in each. All levels, no textbooks.", t.today(19, 0), t.today(20, 30),
              cap: 10, going: 6, host: "Lucía Ferrer"),
            g("Chess in the park", .party, spots.take(.park, fallback: "The chess tables", east: -60, north: 260),
              "Bring a board if you have one. Blitz after 4.", t.min(90), t.min(240), cap: 8, going: 3,
              host: "Viktor Ilić"),
            g("Board game night", .party, spots.home("Theo's front room", east: 120, north: 380),
              "Catan, Codenames, whatever shows up. Snacks on the table.", t.today(19, 30), t.today(23, 0),
              cap: 10, going: 6, host: "Theo Brandt", bring: "A game, if you have one"),
            g("Doubles, need a fourth", .play, spots.take(.tennis, fallback: "The tennis courts", east: 700, north: 200),
              "Solid 3.5 level. We have balls.", t.tomorrow(8, 0), t.tomorrow(9, 30), cap: 4, going: 3,
              host: "Priya Raman"),
            g("Sketch & coffee", .party, spots.take(.cafe, fallback: "The café by the park", east: -280, north: 80),
              "Bring whatever you draw with. Nobody looks unless you want them to.",
              t.tomorrow(10, 0), t.tomorrow(12, 0), cap: 8, going: 4, host: "Hana Kim"),
            g("Yoga on the grass", .move, spots.take(.park, fallback: "The east lawn", east: 430, north: -300),
              "Gentle flow, an hour. Mats if you have them, towels if you don't.",
              t.weekend(.sunday, 9, 0), t.weekend(.sunday, 10, 0), cap: 20, going: 11, host: "Ana Lindqvist",
              bring: "A mat or towel", recurring: "Every Sunday"),
            g("Picnic and card games", .party, spots.take(.park, fallback: "The picnic tables", east: -420, north: -80),
              "Potluck-ish. Bring one thing to share.", t.weekend(.saturday, 13, 0), t.weekend(.saturday, 16, 0),
              going: 9, host: "Theo Brandt"),
            g("Ride to the bridge and back", .move, spots.take(.cafe, fallback: "The bike shop", east: 300, north: 640, suffix: ", out front"),
              "About 12 miles, no-drop, flat-ish. Helmets on.", t.weekend(.sunday, 10, 0), t.weekend(.sunday, 12, 30),
              going: 6, host: "Omar Haddad"),
            g("Karaoke crew", .music, spots.take(.bar, fallback: "The karaoke place", east: 640, north: -420),
              "Private room's booked for 8. Split the bill, no judgment.", t.weekend(.saturday, 21, 0),
              t.weekend(.saturday, 23, 30), cap: 8, going: 5, host: "Kai Morales"),
            g("Book swap", .party, spots.take(.library, fallback: "The library steps", east: -680, north: 340),
              "Bring two, leave with two. Coffee from the cart.", t.weekend(.sunday, 11, 0), t.weekend(.sunday, 13, 0),
              going: 7, host: "Nora Ali"),
            g("Stairs at sunrise", .move, spots.home("The hill stairs", east: 300, north: 640),
              "Ten laps, then coffee at whoever's closest.", t.tomorrow(7, 0), t.tomorrow(8, 0), going: 5,
              host: "June Lee"),
        ]
        if withGatherings { gatherings.forEach(context.insert) }

        for k in kitchens(around: c, t: t) {
            context.insert(k.kitchen)
            for (i, item) in k.menu.enumerated() {
                let m = MenuItem(name: item.0, note: item.1, priceCents: item.2, sortIndex: i)
                context.insert(m)
                m.kitchen = k.kitchen
            }
            context.insert(k.drop)
            k.drop.kitchen = k.kitchen
        }
        seedPeople(around: c, context: context, now: now)
        Ledger.save(context, "seed samples")
        log.info("Seeded \(withGatherings ? gatherings.count : 0) gatherings, \(places.count) real places nearby")
    }

    // MARK: People

    /// Sample friends until you have real ones. The "team" pair and the "solo" one are put on
    /// the best things nearby when the screens draw (`Crowd.resolve`); porch lights sit on
    /// nearby blocks. Every one shows as Sample wherever they appear.
    private static func seedPeople(around c: CLLocationCoordinate2D, context: ModelContext, now: Date) {
        func person(_ name: String, _ role: String, free: Int?) -> Person {
            let p = Person(name: name, isSample: true, sampleRole: role)
            p.freeAfterHour = free
            context.insert(p)
            return p
        }
        let maya = person("Maya", "team", free: 14)
        let theo = person("Theo", "team", free: 16)
        _ = person("Jun", "solo", free: 12)
        let priya = person("Priya", "porch", free: 13)
        priya.porchUntil = now.addingTimeInterval(2 * 3600)
        priya.porchNote = "Up for something"
        let home = c.offset(east: 180, north: -60)
        priya.latitude = home.latitude
        priya.longitude = home.longitude
        let omar = person("Omar", "porch", free: 21)
        omar.porchUntil = now.addingTimeInterval(3 * 3600)
        omar.porchNote = "Free after 9 \u{00B7} up for a late ride"
        let flat = c.offset(east: -420, north: 260)
        omar.latitude = flat.latitude
        omar.longitude = flat.longitude
        let ben = person("Ben", "home", free: 18)
        for name in ["Luc\u{00ED}a", "Ana", "Leo"] { _ = person(name, "home", free: nil) }
        context.insert(Crew(name: "Tuesday trivia", memberIDs: [maya.id, theo.id, ben.id], isSample: true))
    }

    // MARK: Building blocks

    private static func g(
        _ title: String, _ genre: Genre, _ place: (name: String, coordinate: CLLocationCoordinate2D), _ details: String,
        _ start: Date, _ end: Date, cap: Int = 0, going: Int, host: String, bring: String = "", recurring: String = ""
    ) -> Gathering {
        Gathering(
            title: title, category: genre, details: details, placeName: place.name, coordinate: place.coordinate,
            start: start, end: end, capacity: cap, othersGoing: going, hostName: host, bring: bring,
            recurring: recurring, isSample: true
        )
    }

    private struct SampleKitchen {
        var kitchen: Kitchen
        var menu: [(String, String, Int)]
        var drop: Drop
    }

    private static func kitchens(around c: CLLocationCoordinate2D, t: Times) -> [SampleKitchen] {
        func k(_ name: String, _ cook: String, _ cuisine: String, _ story: String, east: Double, north: Double,
               note: String, porch: Int = 0, rating: Double, reviews: Int, regulars: Int,
               menu: [(String, String, Int)], drop: Drop, says: [(Int, String, String)]) -> SampleKitchen {
            let kitchen = Kitchen(
                name: name, cookName: cook, cuisine: cuisine, story: story, coordinate: c.offset(east: east, north: north),
                pickupNote: note, porchTables: porch, rating: rating, reviewCount: reviews, regulars: regulars, isSample: true
            )
            kitchen.sampleReviews = says.enumerated().map { i, r in SampleReview(stars: r.0, text: r.1, author: r.2, daysAgo: (i + 1) * 4) }
            return SampleKitchen(kitchen: kitchen, menu: menu, drop: drop)
        }
        return [
            k("Dana's Porch Pizza", "Dana", "Pizza", "Wood-fired in the backyard oven, ninety seconds a pie. Naturally leavened dough, three days cold.",
              east: 210, north: 260, note: "Side gate on the left. Ring the bell on the post.", porch: 2,
              rating: 4.9, reviews: 212, regulars: 38,
              menu: [("Margherita", "San Marzano, fior di latte, basil", 1400), ("Hot honey soppressata", "Her most reordered", 1600),
                     ("Mushroom & taleggio", "", 1600), ("Garlic knots, six", "", 600)],
              drop: Drop(start: t.min(18), end: t.min(108), total: 24, sold: 15),
              says: [(5, "Better than anything within a mile. Ate it on her porch steps.", "Jordan T."),
                     (5, "Hot honey one is unreal. Get there at the start of the drop.", "Lena S."),
                     (4, "Crust was perfect, wish there were more knots.", "Marcus D.")]),
            k("Arepa Corner", "Valentina", "Arepas", "Venezuelan arepas off a flat-top in the garage. Cash or card.",
              east: -260, north: -150, note: "Garage door's up. Order at the folding table.", porch: 1,
              rating: 4.8, reviews: 97, regulars: 21,
              menu: [("Reina pepiada", "Chicken, avocado, mayo", 1100), ("Dominó", "Black beans, white cheese", 1000),
                     ("Tequeños, five", "Cheese sticks", 800)],
              drop: Drop(start: t.min(-10), end: t.min(80), total: 30, sold: 19),
              says: [(5, "Reina pepiada tastes like Caracas.", "Andrés P."), (5, "Fast, friendly, ridiculous tequeños.", "Kim W.")]),
            k("Back Gate Ice Cream", "June", "Ice cream", "Small batches churned that morning. Three flavors, gone when they're gone.",
              east: 470, north: 90, note: "Blue back gate off the alley. Cooler is by the steps.", porch: 1,
              rating: 4.8, reviews: 31, regulars: 14,
              menu: [("Mango chili", "Sold out in 40 minutes last time", 600), ("Brown butter pecan", "", 600),
                     ("Strawberry buttermilk", "", 600), ("Pint to go", "Any flavor", 1400)],
              drop: Drop(start: t.min(108), end: t.min(198), total: 30, sold: 6),
              says: [(5, "Mango chili should be illegal.", "Ari P."), (5, "Ended up talking to her neighbors for an hour.", "Sam O.")]),
            k("Little Beirut Manakish", "Rami", "Manakish", "Flatbreads from his grandmother's saj, za'atar he mixes himself.",
              east: -90, north: 520, note: "Second-floor flat. Buzz 2B, he'll come down.",
              rating: 4.9, reviews: 58, regulars: 19,
              menu: [("Za'atar & olive oil", "", 900), ("Cheese & sujuk", "", 1200), ("Labneh plate", "With cucumber and mint", 1000)],
              drop: Drop(start: t.min(150), end: t.min(240), total: 24, sold: 5),
              says: [(5, "The za'atar is the real thing.", "Layla H.")]),
            k("Kenji's Curry Night", "Kenji", "Japanese curry", "Katsu curry from a pot that's been going since noon.",
              east: 640, north: 420, note: "Garage door will be up. Grab a bowl and a seat if there's one.", porch: 3,
              rating: 4.7, reviews: 48, regulars: 17,
              menu: [("Katsu curry", "Pork cutlet, rice, pickles", 1500), ("Veggie curry", "Squash, potato, soft egg", 1200)],
              drop: Drop(start: t.today(18, 0), end: t.today(20, 0), total: 20, sold: 4),
              says: [(5, "Rich, deep, perfect cutlet.", "Ryo T."), (4, "Get there early, the katsu goes first.", "Becca L.")]),
            k("Midnight Cookie Window", "Tess", "Cookies", "A kitchen window that opens at nine. Warm cookies, cold milk.",
              east: -470, north: 330, note: "The lit window on the side of the yellow house.",
              rating: 5.0, reviews: 133, regulars: 44,
              menu: [("Brown butter chocolate chip", "", 400), ("Miso oat", "", 400), ("Box of six", "Mix and match", 2000)],
              drop: Drop(start: t.today(21, 0), end: t.today(23, 30), total: 120, sold: 31, perSlot: 10),
              says: [(5, "Dangerous to live this close.", "Will A."), (5, "Miso oat is the sleeper hit.", "Grace N.")]),
            k("Sourdough by Ines", "Ines", "Bread", "Long-ferment loaves out of a home deck oven, ready at eight.",
              east: 160, north: -540, note: "Bench on the front porch. Your name's on the bag.",
              rating: 4.9, reviews: 76, regulars: 29,
              menu: [("Country loaf", "", 1200), ("Seeded rye", "", 1300), ("Morning buns, three", "Orange zest, cardamom", 900)],
              drop: Drop(start: t.tomorrow(8, 0), end: t.tomorrow(10, 0), total: 30, sold: 12, perSlot: 6),
              says: [(5, "Best crumb in the city, no exaggeration.", "Paul M.")]),
            k("Rosa's Tamales", "Rosa", "Tamales", "Her mother's recipe. Pork in red chile, chicken verde, and rajas con queso.",
              east: -180, north: -420, note: "Front porch. Knock twice, she's usually in the kitchen.",
              rating: 5.0, reviews: 64, regulars: 22,
              menu: [("Pork in red chile, dozen", "", 3000), ("Chicken verde, dozen", "", 3000), ("Rajas con queso, half dozen", "Vegetarian", 1600)],
              drop: Drop(start: t.tomorrow(10, 0), end: t.tomorrow(13, 0), total: 40, sold: 11, perSlot: 6),
              says: [(5, "Bought two dozen, froze one. Gone in a week anyway.", "Nina V.")]),
            k("Bao Saturday", "Mei", "Bao", "Steamed buns folded that morning. Lines move fast.",
              east: 520, north: -260, note: "Courtyard behind the green door. Follow the steam.", porch: 2,
              rating: 4.8, reviews: 89, regulars: 31,
              menu: [("Pork belly bao, two", "Peanut, cilantro, pickles", 1200), ("Mushroom bao, two", "", 1100), ("Chili crisp jar", "To take home", 900)],
              drop: Drop(start: t.weekend(.saturday, 11, 30), end: t.weekend(.saturday, 13, 30), total: 50, sold: 22, perSlot: 8),
              says: [(5, "Pork belly bao is worth the walk from anywhere.", "Derek F.")]),
            k("Nana Ama's Jollof", "Ama", "Jollof", "Ghanaian jollof, smoky from the bottom of the pot, with chicken or without.",
              east: -620, north: -40, note: "Ground-floor unit with the plants outside. She'll wave you in.",
              rating: 4.9, reviews: 41, regulars: 16,
              menu: [("Jollof & grilled chicken", "", 1700), ("Jollof, veggie", "", 1300), ("Kelewele", "Spiced fried plantain", 700)],
              drop: Drop(start: t.weekend(.saturday, 13, 0), end: t.weekend(.saturday, 15, 0), total: 30, sold: 8),
              says: [(5, "Settles the jollof debate.", "Kofi A.")]),
            k("Smoke & Oak", "Marcus", "BBQ", "Brisket on the offset smoker since 4 AM.",
              east: 380, north: 610, note: "Follow the smoke to the backyard. Gate's open.", porch: 4,
              rating: 4.8, reviews: 112, regulars: 40,
              menu: [("Brisket plate", "Half pound, slaw, pickles", 2200), ("Pulled pork sandwich", "", 1500), ("Mac & cheese", "", 700)],
              drop: Drop(start: t.weekend(.sunday, 12, 0), end: t.weekend(.sunday, 15, 0), total: 40, sold: 17, perSlot: 6),
              says: [(5, "Bark for days.", "Tyler B."), (5, "The mac is not an afterthought.", "Sofia R.")]),
            k("Pho Sunday", "Linh", "Pho", "Broth simmered overnight, herbs from the back garden.",
              east: -360, north: 600, note: "Side door, down the steps. Bowls come with a lid to go.",
              rating: 4.9, reviews: 67, regulars: 25,
              menu: [("Beef pho", "Brisket, rare eye of round", 1600), ("Chicken pho", "", 1500), ("Spring rolls, two", "Shrimp or tofu", 800)],
              drop: Drop(start: t.weekend(.sunday, 11, 0), end: t.weekend(.sunday, 14, 0), total: 36, sold: 9, perSlot: 6),
              says: [(5, "Tastes like my mom's. High praise.", "Minh L.")]),
        ]
    }

    /// Times relative to now, so "on now" always means now.
    private struct Times {
        let now: Date
        let cal = Calendar.current

        var weekday: String { now.formatted(.dateTime.weekday(.wide)) }

        func min(_ m: Double) -> Date { now.addingTimeInterval(m * 60) }

        func today(_ h: Int, _ m: Int) -> Date {
            cal.date(bySettingHour: h, minute: m, second: 0, of: now) ?? now
        }

        func tomorrow(_ h: Int, _ m: Int) -> Date {
            let day = cal.date(byAdding: .day, value: 1, to: now) ?? now
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
        }

        enum Day { case saturday, sunday }

        /// The coming (or current) weekend's day at a time.
        func weekend(_ d: Day, _ h: Int, _ m: Int) -> Date {
            guard let range = TimeWindow.weekendRange(from: now, calendar: cal) else { return tomorrow(h, m) }
            let day = d == .saturday ? range.lowerBound : cal.date(byAdding: .day, value: 1, to: range.lowerBound) ?? range.lowerBound
            let at = cal.date(bySettingHour: h, minute: m, second: 0, of: day) ?? day
            // Already past (it's Sunday and this was Saturday's): move it a week on.
            return at < now ? at.addingTimeInterval(7 * 86_400) : at
        }
    }

    /// Hands out real nearby places by kind, nearest first, never the same one twice.
    private struct Spots {
        var places: [PlaceFinder.Place]
        let center: CLLocationCoordinate2D
        var used: Set<String> = []

        mutating func take(_ kind: PlaceFinder.Kind, fallback: String, east: Double, north: Double, suffix: String = "") -> (name: String, coordinate: CLLocationCoordinate2D) {
            let candidates = places.filter { $0.kind == kind && !used.contains($0.name) }
                .sorted { $0.coordinate.distance(to: center) < $1.coordinate.distance(to: center) }
            if let p = candidates.first {
                used.insert(p.name)
                return (p.name + suffix, p.coordinate)
            }
            return home(fallback, east: east, north: north)
        }

        func home(_ name: String, east: Double, north: Double) -> (name: String, coordinate: CLLocationCoordinate2D) {
            (name, center.offset(east: east, north: north))
        }
    }
}

/// Real places nearby from Apple Maps, sorted into the kinds the samples need.
enum PlaceFinder {
    enum Kind { case park, court, tennis, cafe, bar, venue, library }

    struct Place {
        var name: String
        var coordinate: CLLocationCoordinate2D
        var kind: Kind
    }

    private static let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "places")

    static func find(around c: CLLocationCoordinate2D, radius: CLLocationDistance = 1200) async -> [Place] {
        let request = MKLocalPointsOfInterestRequest(center: c, radius: radius)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .park, .basketball, .tennis, .soccer, .cafe, .brewery, .nightlife, .winery, .musicVenue, .library,
        ])
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                guard let name = item.name, let category = item.pointOfInterestCategory, let kind = kind(for: category) else { return nil }
                return Place(name: name, coordinate: item.location.coordinate, kind: kind)
            }
        } catch {
            log.error("Places search failed, using made-up spots: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private static func kind(for c: MKPointOfInterestCategory) -> Kind? {
        switch c {
        case .park: .park
        case .basketball, .soccer: .court
        case .tennis: .tennis
        case .cafe: .cafe
        case .brewery, .nightlife, .winery: .bar
        case .musicVenue: .venue
        case .library: .library
        default: nil
        }
    }
}
