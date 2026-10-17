import Testing
import Foundation
@testable import LetsGo

@Suite("City listings")
struct CityListingsTests {
    let cal = Calendar.current

    func date(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = d; c.hour = h; c.minute = m
        return cal.date(from: c)!
    }

    let json = """
    [
      {"title":"Saturday market","genre":"food","venue":"Ferry Building","address":"1 Ferry Building","lat":37.7955,"lon":-122.3937,
       "schedule":{"weekday":"Saturday","start":"08:00","end":"14:00"},"price":"Free","organizer":"CUESA","url":"https://example.com","description":"Market.","confidence":"high"},
      {"title":"Two-day thing","genre":"move","venue":"Park","address":"","lat":37.77,"lon":-122.45,
       "schedule":[{"weekday":"Wednesday","start":"06:30","end":"07:30"},{"weekday":"Friday","start":"06:30","end":"07:30"}],"price":"Free","organizer":"NP","url":"","description":"Workout.","confidence":"high"},
      {"title":"Late show","genre":"music","venue":"Club","address":"","lat":37.76,"lon":-122.42,
       "schedule":{"date":"2026-10-24","start":"21:00","end":"01:00"},"price":"$15","organizer":"Club","url":"","description":"Show.","confidence":"medium"},
      {"title":"Broken","genre":"music","venue":"Nowhere","lat":"not a number","lon":0,"schedule":{"weekday":"Monday","start":"x","end":"y"}}
    ]
    """

    @Test func decodesAndSkipsBadEntries() throws {
        let listings = try CityListings.decode(Data(json.utf8))
        #expect(listings.map(\.title) == ["Saturday market", "Two-day thing", "Late show"])
        #expect(listings[1].schedule.count == 2)
    }

    @Test func weeklyExpandsAcrossTwoWeeks() throws {
        let market = try CityListings.decode(Data(json.utf8))[0]
        // Saturday Oct 17 at 11:26: today's market is on, then the next two Saturdays.
        let o = CityListings.occurrences(of: market, from: date(17, 11, 26))
        #expect(o.count == 2)
        #expect(o.first?.start == date(17, 8))
        #expect(o.first?.recurring == "Every Saturday")
    }

    @Test func endedTodayIsSkipped() throws {
        let market = try CityListings.decode(Data(json.utf8))[0]
        let o = CityListings.occurrences(of: market, from: date(17, 15))
        #expect(o.first?.start == date(24, 8))
    }

    @Test func pastMidnightEndsNextDay() throws {
        let show = try CityListings.decode(Data(json.utf8))[2]
        let o = CityListings.occurrences(of: show, from: date(17, 12))
        #expect(o.count == 1)
        #expect(o.first?.end == date(25, 1))
        #expect(o.first?.recurring == "")
    }

    @Test func missingEndGetsATypicalLength() throws {
        let run = """
        [{"title":"Run","genre":"move","venue":"Park","address":"","lat":37.76,"lon":-122.43,
          "schedule":{"weekday":"Wednesday","start":"06:29","end":null},"price":"Free","organizer":"NP","url":"","description":"","confidence":"medium"}]
        """
        let l = try CityListings.decode(Data(run.utf8))
        #expect(l.count == 1)
        let o = CityListings.occurrences(of: l[0], from: date(17, 12))
        #expect(o.first?.start == date(21, 6, 29))
        #expect(o.first?.end == date(21, 7, 44))
    }

    @Test func bundledFileDecodesCompletely() throws {
        let url = try #require(Bundle.main.url(forResource: "sf_happenings", withExtension: "json"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [Any]
        let listings = CityListings.bundled()
        #expect(listings.count == raw?.count)
        #expect(listings.allSatisfy { CityListings.covers(.init(latitude: $0.lat, longitude: $0.lon)) })
    }

    @Test func coversTheCity() {
        #expect(CityListings.covers(.init(latitude: 37.7955, longitude: -122.3937)))
        #expect(!CityListings.covers(.init(latitude: 37.8044, longitude: -122.2712)))  // Oakland
    }
}
