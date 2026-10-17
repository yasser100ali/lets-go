import Testing
import Foundation
@testable import LetsGo

@Suite("Picks")
struct PickTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func candidate(_ title: String, _ category: Genre = .play, startsIn minutes: Double, meters: Double = 400,
                   capacity: Int = 0, going: Int = 0) -> Candidate {
        Candidate(
            id: UUID(), kind: .gathering, title: title, category: category,
            start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + 90) * 60),
            meters: meters, capacity: capacity, going: going
        )
    }

    @Test func endedAndFullThingsAreNeverPicked() {
        let ended = candidate("Ended", startsIn: -200)
        let full = candidate("Full", startsIn: 20, capacity: 10, going: 10)
        let open = candidate("Open", startsIn: 20)
        let picks = Picks.picks([ended, full, open], now: now, taste: Taste())
        #expect(picks.map(\.title) == ["Open"])
    }

    @Test func soonAndCloseBeatsLaterAndFar() {
        let near = candidate("Near", startsIn: 15, meters: 300)
        let far = candidate("Far", startsIn: 150, meters: 1500)
        #expect(Picks.picks([far, near], now: now, taste: Taste()).first?.title == "Near")
    }

    @Test func nothingBeyondTheHorizon() {
        let tomorrow = candidate("Tomorrow", startsIn: 60 * 20)
        #expect(Picks.picks([tomorrow], now: now, taste: Taste()).isEmpty)
    }

    @Test func tasteBreaksATie() {
        let soccer = candidate("Soccer", .play, startsIn: 30)
        let music = candidate("Music", .music, startsIn: 30)
        let taste = Taste(weights: [.music: 1])
        #expect(Picks.picks([soccer, music], now: now, taste: taste).first?.title == "Music")
    }
}

@Suite("Reading a search")
struct SearchQueryTests {
    // A Friday evening, so "sat 8am" means tomorrow morning.
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 16; c.hour = 18; c.minute = 12
        return Calendar.current.date(from: c)!
    }()

    @Test func moodWithPrice() {
        let q = SearchQuery.parse("something chill tonight, outside, under $15", now: now)
        #expect(q.wantsQuiet)
        #expect(q.maxPriceCents == 1500)
        #expect(q.day == .today)
        #expect(!q.wantsToCreate)
    }

    @Test func planBecomesADraft() {
        let q = SearchQuery.parse("make a slow jog sat 8am around the lake", now: now)
        #expect(q.wantsToCreate)
        #expect(q.categories.contains(.move))
        let draft = GatheringDraft.from(q, now: now)
        #expect(draft.category == .move)
        #expect(draft.placeName == "The lake")
        #expect(draft.title.hasPrefix("Slow"))
        #expect(Calendar.current.component(.hour, from: draft.start) == 8)
        #expect(Calendar.current.component(.weekday, from: draft.start) == 7)
    }

    @Test func gameNightIsAHangNotASport() {
        let q = SearchQuery.parse("any board game night?", now: now)
        #expect(q.categories.contains(.party))
        #expect(!q.categories.contains(.play))
    }

    @Test func knowIsNotNow() {
        #expect(SearchQuery.parse("do you know any runs", now: now).day == .any)
        #expect(SearchQuery.parse("anything now?", now: now).day == .today)
    }

    @Test func foodWords() {
        #expect(SearchQuery.parse("who's selling pizza", now: now).categories == [.food])
    }
}

@Suite("Money and walking")
struct SmallMathTests {
    @Test func serviceFeeHasAFloor() {
        #expect(Pricing.serviceFee(for: 0) == 0)
        #expect(Pricing.serviceFee(for: 600) == 50)
        #expect(Pricing.serviceFee(for: 3000) == 150)
    }

    @Test func walkMinutes() {
        #expect(Walk.minutes(10) == 1)
        #expect(Walk.minutes(800) == 10)
    }

    @Test func lowercasingKeepsNames() {
        #expect("Pickup soccer".lowercasedFirst == "pickup soccer")
        #expect("Dana's Porch Pizza".lowercasedFirst == "Dana's Porch Pizza")
    }
}

@Suite("Search")
struct SearchTests {
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 17; c.hour = 11; c.minute = 26
        return Calendar.current.date(from: c)!
    }()

    func item(_ title: String, _ genre: Genre, _ text: String, in minutes: Double, price: Int? = nil, kind: Candidate.Kind = .gathering) -> Candidate {
        Candidate(
            id: UUID(), kind: kind, title: title, category: genre,
            start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + 90) * 60),
            meters: 400, priceFromCents: price, searchText: (title + " " + text).lowercased()
        )
    }

    var all: [Candidate] {
        [
            item("Dana's Porch Pizza", .food, "pizza margherita garlic knots", in: 18, price: 600, kind: .drop),
            item("Back Gate Ice Cream", .food, "ice cream mango chili", in: 108, price: 600, kind: .drop),
            item("3v3, winners stay on", .play, "corner court half court basketball", in: -20),
            item("Pickup soccer", .play, "lafayette park", in: 38),
            item("Easy 5k, talking pace", .move, "run coffee", in: 65),
        ]
    }

    @Test func wordsMatchTitlesAndMenus() {
        #expect(Search.results("pizza", in: all, now: now).map(\.title) == ["Dana's Porch Pizza"])
        #expect(Search.results("mango", in: all, now: now).map(\.title) == ["Back Gate Ice Cream"])
        #expect(Search.results("basketball", in: all, now: now).map(\.title) == ["3v3, winners stay on"])
    }

    @Test func broadWordsMatchAKind() {
        let food = Search.results("food", in: all, now: now).map(\.title)
        #expect(food.count == 2)
        #expect(Search.results("sports", in: all, now: now).count == 2)
    }

    @Test func emptyAndNonsenseFindNothing() {
        #expect(Search.results("", in: all, now: now).isEmpty)
        #expect(Search.results("zzqx", in: all, now: now).isEmpty)
    }

    @Test func pluralsStillMatch() {
        #expect(Search.results("knots", in: all, now: now).count == 1)
        #expect(Search.results("runs", in: all, now: now).count == 1)
    }
}

@Suite("Time windows")
struct TimeWindowTests {
    let cal = Calendar(identifier: .gregorian)

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = d; c.hour = h; c.minute = m
        return cal.date(from: c)!
    }

    @Test func nowIsTheNextThreeHours() {
        let now = date(17, 11)
        #expect(TimeWindow.now.contains(start: date(17, 13), end: date(17, 14), now: now, calendar: cal))
        #expect(!TimeWindow.now.contains(start: date(17, 15), end: date(17, 16), now: now, calendar: cal))
        #expect(!TimeWindow.now.contains(start: date(17, 9), end: date(17, 10), now: now, calendar: cal))
    }

    @Test func tonightRunsFromFiveToTwo() {
        let now = date(17, 11)
        #expect(TimeWindow.tonight.contains(start: date(17, 20), end: date(17, 22), now: now, calendar: cal))
        #expect(TimeWindow.tonight.contains(start: date(18, 1), end: date(18, 2), now: now, calendar: cal))
        #expect(!TimeWindow.tonight.contains(start: date(17, 13), end: date(17, 14), now: now, calendar: cal))
    }

    @Test func weekendFromAThursday() {
        // Oct 15 2026 is a Thursday; that weekend is Sat 17 – Mon 19.
        let range = TimeWindow.weekendRange(from: date(15, 10), calendar: cal)
        #expect(range?.lowerBound == date(17, 0))
        #expect(range?.upperBound == date(19, 0))
    }

    @Test func onASundayItsStillThisWeekend() {
        let range = TimeWindow.weekendRange(from: date(18, 15), calendar: cal)
        #expect(range?.lowerBound == date(17, 0))
    }
}
