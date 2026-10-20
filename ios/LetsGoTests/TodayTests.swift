import Testing
import Foundation
import CoreLocation
@testable import LetsGo

@Suite("Today")
struct TodayTests {
    var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    func candidate(_ title: String, startsAt start: Date, minutes: Double = 90, meters: Double = 400) -> Candidate {
        Candidate(
            id: UUID(), kind: .gathering, title: title, category: .play,
            start: start, end: start.addingTimeInterval(minutes * 60), meters: meters
        )
    }

    @Test func headlineFollowsTheTimeOfDay() {
        #expect(Today.headline(now: date(20, 9), calendar: cal) == "What's on this morning")
        #expect(Today.headline(now: date(20, 14), calendar: cal) == "What's on this afternoon")
        #expect(Today.headline(now: date(20, 19), calendar: cal) == "What's alive tonight")
        #expect(Today.headline(now: date(20, 1), calendar: cal) == "What's alive tonight")
    }

    @Test func weekRunsMondayToSunday() {
        // Tuesday, October 20, 2026.
        let week = Today.week(of: date(20, 17), calendar: cal)
        #expect(week.count == 7)
        #expect(cal.component(.day, from: week[0]) == 19)
        #expect(cal.component(.weekday, from: week[0]) == 2)
        #expect(cal.component(.day, from: week[6]) == 25)
        // Sunday still belongs to the week that started Monday.
        #expect(cal.component(.day, from: Today.week(of: date(25, 20), calendar: cal)[0]) == 19)
    }

    @Test func walkableIsCloseAndNotTooFarOff() {
        let now = date(20, 17)
        let near = candidate("Near", startsAt: date(20, 18), meters: 600)
        let far = candidate("Far", startsAt: date(20, 18), meters: 3000)
        let tomorrow = candidate("Tomorrow", startsAt: date(21, 18), meters: 300)
        let ended = candidate("Ended", startsAt: date(20, 14), minutes: 60, meters: 300)
        let picked = Today.walkable([far, tomorrow, ended, near], now: now)
        #expect(picked.map(\.title) == ["Near"])
        #expect(Today.walkable([near], now: now, excluding: [near.id]).isEmpty)
    }

    @Test func happeningIsOneDaySoonestFirst() {
        let now = date(20, 9)
        let late = candidate("Late", startsAt: date(24, 20))
        let early = candidate("Early", startsAt: date(24, 11))
        let other = candidate("Other day", startsAt: date(25, 11))
        #expect(Today.happening([late, other, early], on: date(24, 0), now: now, calendar: cal).map(\.title) == ["Early", "Late"])
    }

    @Test func sunsetInSanFranciscoInLateOctober() throws {
        let sf = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let set = try #require(Sun.sunset(on: date(20, 12), at: sf, calendar: cal))
        let rise = try #require(Sun.sunrise(on: date(20, 12), at: sf, calendar: cal))
        // Published times for Oct 20, 2026: about 7:21 AM and 6:26 PM.
        #expect(abs(set.timeIntervalSince(date(20, 18, 26))) < 5 * 60)
        #expect(abs(rise.timeIntervalSince(date(20, 7, 21))) < 5 * 60)
    }

    @Test func noSunsetInPolarNight() {
        let north = CLLocationCoordinate2D(latitude: 78.2, longitude: 15.6)
        let december = cal.date(from: DateComponents(year: 2026, month: 12, day: 21, hour: 12))!
        #expect(Sun.sunset(on: december, at: north, calendar: cal) == nil)
    }
}

@Suite("City list")
struct SpotsTests {
    @Test func bundledListDecodesCompletely() throws {
        let url = try #require(Bundle.main.url(forResource: "sf_places", withExtension: "json"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Any]
        let spots = Spots.bundled()
        #expect(spots.count == raw?.count)
        #expect(spots.count == 50)
        #expect(Set(spots.map(\.id)).count == spots.count)
        #expect(spots.allSatisfy { CityListings.covers($0.coordinate) })
    }

    @Test func badEntriesAreSkipped() throws {
        let json = """
        [{"id":"a","title":"A","kind":"hike","area":"X","lat":37.77,"lon":-122.45,"blurb":"","miles":1.2},
         {"id":"b","title":"B","kind":"spaceship","area":"X","lat":37.77,"lon":-122.45,"blurb":""}]
        """
        let spots = try Spots.decode(Data(json.utf8))
        #expect(spots.map(\.id) == ["a"])
        #expect(spots[0].miles == 1.2)
        #expect(spots[0].stops == nil)
    }

    @Test func progressCountsEachBucket() throws {
        let json = """
        [{"id":"a","title":"A","kind":"hike","area":"X","lat":37.77,"lon":-122.45,"blurb":""},
         {"id":"b","title":"B","kind":"view","area":"X","lat":37.77,"lon":-122.45,"blurb":""},
         {"id":"c","title":"C","kind":"food","area":"X","lat":37.77,"lon":-122.45,"blurb":""}]
        """
        let spots = try Spots.decode(Data(json.utf8))
        let p = Spots.progress(spots, done: ["a"])
        #expect(p.map(\.bucket) == [.outdoors, .food, .culture, .night])
        #expect(p[0].done == 1 && p[0].total == 2)
        #expect(p[1].done == 0 && p[1].total == 1)
        #expect(p[2].total == 0)
    }

    @Test func closestFirst() throws {
        let json = """
        [{"id":"far","title":"Far","kind":"hike","area":"X","lat":37.80,"lon":-122.45,"blurb":""},
         {"id":"near","title":"Near","kind":"hike","area":"X","lat":37.7601,"lon":-122.4270,"blurb":""}]
        """
        let spots = try Spots.decode(Data(json.utf8))
        let here = CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)
        #expect(Spots.closest(spots, to: here).map(\.id) == ["near", "far"])
    }
}

@Suite("Listings merge")
struct ListingsMergeTests {
    func listing(_ title: String, _ venue: String, price: String = "") throws -> CityListings.Listing {
        let json = """
        [{"title":"\(title)","genre":"music","venue":"\(venue)","lat":37.77,"lon":-122.42,
          "schedule":{"date":"2026-10-24","start":"20:00"},"price":"\(price)"}]
        """
        let all = try CityListings.decode(Data(json.utf8))
        return try #require(all.first)
    }

    @Test func serverWinsAndNewBundledOnesAreAdded() throws {
        let server = [try listing("Show", "Club", price: "$20")]
        let bundled = [try listing("show ", "club", price: "$15"), try listing("New thing", "Park")]
        let merged = CityListings.merge(server: server, bundled: bundled)
        #expect(merged.map(\.title) == ["Show", "New thing"])
        #expect(merged[0].price == "$20")
    }
}
