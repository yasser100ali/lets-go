import Foundation
import MapKit
import Observation
import OSLog

/// Walking routes from Apple Maps, kept for as long as you stay put. Falls back to a
/// straight line and the usual 80 m a minute when directions don't come back.
@Observable
final class RouteBook {
    struct Leg {
        var coordinates: [CLLocationCoordinate2D]
        var minutes: Int
        var meters: Double
    }

    private(set) var legs: [UUID: Leg] = [:]
    @ObservationIgnored private var origin = ""
    @ObservationIgnored private let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "routes")

    /// Fills in a leg for each pick that doesn't have one from here yet.
    func load(_ picks: [Candidate], from here: CLLocationCoordinate2D) async {
        if here.roundedKey != origin {
            legs = [:]
            origin = here.roundedKey
        }
        for c in picks where legs[c.id] == nil {
            let there = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
            legs[c.id] = await walk(from: here, to: there) ?? Leg(coordinates: [here, there], minutes: c.walkMinutes, meters: c.meters)
        }
    }

    func walk(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Leg? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            return Leg(
                coordinates: route.polyline.coordinateList,
                minutes: max(1, Int((route.expectedTravelTime / 60).rounded())),
                meters: route.distance
            )
        } catch {
            log.error("Walking directions failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension MKPolyline {
    /// The line's points as coordinates.
    var coordinateList: [CLLocationCoordinate2D] {
        var out = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: pointCount)
        getCoordinates(&out, range: NSRange(location: 0, length: pointCount))
        return out
    }
}
