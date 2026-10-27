import Testing
import Foundation
import CoreLocation
@testable import LetsGo

@Suite("A night out")
struct NightMathTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    @Test func oneAMIsStillLastNight() {
        #expect(NightMath.evening(of: date(31, 23), calendar: cal) == cal.startOfDay(for: date(31, 12)))
        #expect(NightMath.evening(of: date(32, 1), calendar: cal) == cal.startOfDay(for: date(31, 12)))
        #expect(NightMath.evening(of: date(32, 6), calendar: cal) == cal.startOfDay(for: date(32, 12)))
    }

    @Test func goingDarkRunsToAWholeHour() {
        let until = NightMath.darkUntil(from: date(31, 21, 20), calendar: cal)
        #expect(until == date(31, 23))
        #expect(cal.component(.minute, from: until) == 0)
    }

    @Test func theMorningAfterComesOnceTheNextMorning() {
        let evening = cal.startOfDay(for: date(31, 12))
        #expect(NightMath.wantsRecap(evening: evening, stops: 3, seen: false, now: date(32, 10), calendar: cal))
        #expect(!NightMath.wantsRecap(evening: evening, stops: 3, seen: true, now: date(32, 10), calendar: cal))
        #expect(!NightMath.wantsRecap(evening: evening, stops: 0, seen: false, now: date(32, 10), calendar: cal))
        #expect(!NightMath.wantsRecap(evening: evening, stops: 3, seen: false, now: date(32, 17), calendar: cal))
        #expect(!NightMath.wantsRecap(evening: evening, stops: 3, seen: false, now: date(31, 23), calendar: cal))
    }

    @Test func theRibbonHasAStretchPerPlaceAndTheWalksBetween() throws {
        let stops = [
            NightStop(title: "Tamales", genreRaw: "food", arrivedAt: date(31, 16, 30)),
            NightStop(title: "Dolores Park", genreRaw: "play", arrivedAt: date(31, 17)),
            NightStop(title: "Make-Out Room", genreRaw: "music", arrivedAt: date(31, 19)),
        ]
        let ribbon = NightMath.ribbon(stops: stops, start: date(31, 16, 30), end: date(31, 23, 50))
        let places = ribbon.map(\.title).filter { !$0.isEmpty }
        #expect(places == ["Tamales", "Dolores Park", "Make-Out Room"])
        let first = try #require(ribbon.first)
        #expect(first.from == 0)
        #expect(ribbon.last?.to == 1)
        for (a, b) in zip(ribbon, ribbon.dropFirst()) {
            #expect(a.to <= b.from + 0.0001)
        }
        // A walk (gray, no title) sits between each place.
        let hasWalk = ribbon.contains { $0.title.isEmpty && $0.genre == nil }
        #expect(hasWalk)
    }

    @Test func clocksAndDurations() {
        #expect(NightMath.clock(9372) == "2:36:12")
        #expect(NightMath.duration(26_400) == "7h 20m")
        #expect(NightMath.duration(2700) == "45m")
        #expect(NightMath.duration(7200) == "2h")
    }
}

@Suite("Eyes-up walk")
struct GuidanceTests {
    let here = CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)

    func turn(_ way: Turn.Way, east: Double, north: Double) -> Turn {
        let at = here.offset(east: east, north: north)
        return Turn(way: way, instruction: way.rawValue, latitude: at.latitude, longitude: at.longitude)
    }

    @Test func instructionsBecomeBuzzes() {
        #expect(Turn.way(from: "Turn right onto Valencia St") == .right)
        #expect(Turn.way(from: "Turn left onto 22nd St") == .left)
        #expect(Turn.way(from: "Arrive at the destination") == .arrive)
        #expect(Turn.way(from: "Continue on Dolores St") == .straight)
        #expect(Turn.short("Turn right onto Valencia St") == "Right on Valencia")
        #expect(WalkHaptics.count(for: .left) == 1)
        #expect(WalkHaptics.count(for: .right) == 2)
        #expect(WalkHaptics.count(for: .arrive) == 3)
    }

    @Test func itBuzzesAsYouReachEachTurn() {
        let turns = [turn(.right, east: 0, north: 200), turn(.left, east: 150, north: 200), turn(.arrive, east: 150, north: 400)]
        // Far from the first turn: nothing yet.
        let start = Guidance.step(at: here, turns: turns, next: 0)
        #expect(start.fire == nil)
        #expect(start.next == 0)
        // At the first turn: buzz right, watch the second.
        let first = Guidance.step(at: here.offset(east: 0, north: 190), turns: turns, next: 0)
        #expect(first.fire?.way == .right)
        #expect(first.next == 1)
        // Arriving counts from a little further out.
        let end = Guidance.step(at: here.offset(east: 150, north: 370), turns: turns, next: 2)
        #expect(end.fire?.way == .arrive)
    }

    @Test func aMissedTurnIsSkipped() {
        let turns = [turn(.right, east: 0, north: 200), turn(.left, east: 150, north: 200), turn(.arrive, east: 150, north: 400)]
        // Cut the corner: you're at the second turn without passing the first.
        let step = Guidance.step(at: here.offset(east: 145, north: 205), turns: turns, next: 0)
        #expect(step.fire?.way == .left)
        #expect(step.next == 2)
    }
}
