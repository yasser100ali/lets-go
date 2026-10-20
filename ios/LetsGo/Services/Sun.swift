import Foundation
import CoreLocation

/// Sunrise and sunset for a place and day, from the standard sunrise equation.
/// Good to a minute or two, which is all "sunset 6:28" needs.
enum Sun {
    static func sunset(on day: Date, at c: CLLocationCoordinate2D, calendar: Calendar = .current) -> Date? {
        times(on: day, at: c, calendar: calendar)?.set
    }

    static func sunrise(on day: Date, at c: CLLocationCoordinate2D, calendar: Calendar = .current) -> Date? {
        times(on: day, at: c, calendar: calendar)?.rise
    }

    /// The day is the calendar day `day` falls on in `calendar`'s time zone.
    /// Nil when the sun doesn't rise or set that day (near the poles).
    static func times(on day: Date, at c: CLLocationCoordinate2D, calendar: Calendar = .current) -> (rise: Date, set: Date)? {
        let ymd = calendar.dateComponents([.year, .month, .day], from: day)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        guard let noon = utc.date(from: DateComponents(year: ymd.year, month: ymd.month, day: ymd.day, hour: 12)) else { return nil }
        let rad = Double.pi / 180
        // Whole days since noon UTC on Jan 1, 2000, then the mean solar noon at this longitude.
        let n = (noon.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_545.0).rounded()
        let meanNoon = n - c.longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let m = anomaly * rad
        let center = 1.9148 * sin(m) + 0.0200 * sin(2 * m) + 0.0003 * sin(3 * m)
        let ecliptic = (anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360) * rad
        let transit = 2_451_545.0 + meanNoon + 0.0053 * sin(m) - 0.0069 * sin(2 * ecliptic)
        let declination = asin(sin(ecliptic) * sin(23.4397 * rad))
        let lat = c.latitude * rad
        let cosHour = (sin(-0.833 * rad) - sin(lat) * sin(declination)) / (cos(lat) * cos(declination))
        guard (-1...1).contains(cosHour) else { return nil }
        let half = acos(cosHour) / rad / 360
        func date(_ julian: Double) -> Date { Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86_400) }
        return (date(transit - half), date(transit + half))
    }
}
