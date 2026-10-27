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

/// A walk with its turns, for the eyes-up walk.
struct Directions {
    var coordinates: [CLLocationCoordinate2D]
    var minutes: Int
    var meters: Double
    var turns: [Turn]
}

/// One turn on a walk: where it is, which way, and what Apple Maps calls it.
struct Turn: Equatable, Sendable {
    enum Way: String, Sendable { case left, right, straight, arrive }

    var way: Way
    var instruction: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// "Turn right onto Valencia St" → right. "Arrive at the destination" → arrive.
    static func way(from instruction: String) -> Way {
        let s = instruction.lowercased()
        if s.contains("arrive") || s.contains("destination") { return .arrive }
        if s.contains("left") { return .left }
        if s.contains("right") { return .right }
        return .straight
    }

    /// "Turn right onto Valencia St" → "Right on Valencia".
    static func short(_ instruction: String) -> String {
        let way = way(from: instruction)
        guard way == .left || way == .right else { return instruction }
        var street = ""
        for marker in [" onto ", " on ", " toward "] {
            if let r = instruction.range(of: marker) { street = String(instruction[r.upperBound...]); break }
        }
        for suffix in [" Street", " St", " Avenue", " Ave"] where street.hasSuffix(suffix) {
            street = String(street.dropLast(suffix.count))
        }
        let head = way == .left ? "Left" : "Right"
        return street.isEmpty ? head : "\(head) on \(street)"
    }
}

extension RouteBook {
    /// Walking directions with the turns in them.
    func directions(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async -> Directions? {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
        request.transportType = .walking
        do {
            let response = try await MKDirections(request: request).calculate()
            guard let route = response.routes.first else { return nil }
            var turns: [Turn] = []
            for step in route.steps where !step.instructions.isEmpty {
                // The turn happens where the step starts.
                guard let at = step.polyline.coordinateList.first else { continue }
                let way = Turn.way(from: step.instructions)
                if way == .straight { continue }
                turns.append(Turn(way: way, instruction: step.instructions, latitude: at.latitude, longitude: at.longitude))
            }
            if turns.last?.way != .arrive {
                turns.append(Turn(way: .arrive, instruction: "You're here", latitude: b.latitude, longitude: b.longitude))
            }
            return Directions(
                coordinates: route.polyline.coordinateList,
                minutes: max(1, Int((route.expectedTravelTime / 60).rounded())),
                meters: route.distance,
                turns: turns
            )
        } catch {
            return nil
        }
    }
}

/// When to buzz: as you come within reach of the next turn. Plain, so it's tested.
enum Guidance {
    /// Close enough to a turn to buzz for it.
    static let reach: CLLocationDistance = 22
    /// Arriving counts from a little further out: the door is somewhere around the pin.
    static let arriveReach: CLLocationDistance = 35

    /// The turn to buzz for now, if any, and the index of the next one to watch.
    /// Skips turns you've already walked past (you're nearer a later one).
    static func step(at here: CLLocationCoordinate2D, turns: [Turn], next: Int) -> (fire: Turn?, next: Int) {
        guard next < turns.count else { return (nil, next) }
        var i = next
        // Walked past one without passing close? Move on to the nearest ahead.
        if let nearest = (i..<turns.count).min(by: { here.distance(to: turns[$0].coordinate) < here.distance(to: turns[$1].coordinate) }), nearest > i {
            i = nearest
        }
        let turn = turns[i]
        let reachHere = turn.way == .arrive ? arriveReach : reach
        if here.distance(to: turn.coordinate) <= reachHere { return (turn, i + 1) }
        return (nil, i)
    }
}
