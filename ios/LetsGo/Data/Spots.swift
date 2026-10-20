import Foundation
import SwiftUI
import CoreLocation
import OSLog

/// A place in the city worth going to at least once: a trail, a viewpoint, a landmark,
/// the burrito. Together they make the city list. From `sf_places.json` in the app bundle.
/// Being there (within 200 m) and checking in stamps it.
struct Spot: Decodable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var kind: Kind
    var area: String
    var lat: Double
    var lon: Double
    var blurb: String
    /// For trails: the usual loop or round trip.
    var miles: Double?
    var minutes: Int?
    var gainFeet: Int?
    var best: String?
    var stops: [String]?
    var tip: String?

    enum Kind: String, Decodable, CaseIterable, Sendable {
        case hike, view, water, park, landmark, culture, food, night
    }

    /// The four bars on the list's progress card.
    enum Bucket: String, CaseIterable, Identifiable, Sendable {
        case outdoors, food, culture, night
        var id: String { rawValue }
        var label: String {
            switch self {
            case .outdoors: "Outdoors"
            case .food: "Food"
            case .culture: "Culture"
            case .night: "Night"
            }
        }
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lon) }
    /// The stamp you get for being there.
    var stampKey: String { "spot:\(id)" }
}

extension Spot.Kind {
    var label: String {
        switch self {
        case .hike: "Hike"
        case .view: "Viewpoint"
        case .water: "Water"
        case .park: "Park"
        case .landmark: "Landmark"
        case .culture: "Culture"
        case .food: "Food"
        case .night: "Night out"
        }
    }

    /// How the app talks about it: "you're into viewpoints".
    var noun: String {
        switch self {
        case .hike: "hikes"
        case .view: "viewpoints"
        case .water: "the water"
        case .park: "parks"
        case .landmark: "landmarks"
        case .culture: "museums and art"
        case .food: "local food"
        case .night: "nights out"
        }
    }

    var symbol: String {
        switch self {
        case .hike: "figure.hiking"
        case .view: "binoculars.fill"
        case .water: "water.waves"
        case .park: "tree.fill"
        case .landmark: "building.columns.fill"
        case .culture: "paintpalette.fill"
        case .food: "fork.knife"
        case .night: "moon.stars.fill"
        }
    }

    var color: Color {
        switch self {
        case .hike: Color(hex: 0x4CB8A6)
        case .view: Color(hex: 0xE8A33D)
        case .water: Color(hex: 0x3A9BD9)
        case .park: Color(hex: 0x3FA772)
        case .landmark: Color(hex: 0x9C7BE0)
        case .culture: Color(hex: 0xD46A9A)
        case .food: Color(hex: 0xE07B4C)
        case .night: Color(hex: 0x7B83E0)
        }
    }

    var bucket: Spot.Bucket {
        switch self {
        case .hike, .view, .water, .park: .outdoors
        case .food: .food
        case .landmark, .culture: .culture
        case .night: .night
        }
    }

    /// The closest kind of gathering, for stamps, taste and hosting something there.
    var genre: Genre {
        switch self {
        case .hike, .view, .water, .park: .move
        case .food: .food
        case .landmark, .culture: .party
        case .night: .music
        }
    }
}

enum Spots {
    private static let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "spots")

    /// The city list.
    static let all: [Spot] = bundled()

    static var listTitle: String { "Know your city: SF \(all.count)" }

    static func bundled() -> [Spot] {
        guard let url = Bundle.main.url(forResource: "sf_places", withExtension: "json") else {
            log.error("sf_places.json missing from the bundle")
            return []
        }
        do {
            return try decode(Data(contentsOf: url))
        } catch {
            log.error("sf_places.json didn't decode: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    static func decode(_ data: Data) throws -> [Spot] {
        // Skip any single bad entry instead of losing the whole list.
        struct Lenient: Decodable {
            var spot: Spot?
            init(from decoder: Decoder) throws { spot = try? Spot(from: decoder) }
        }
        return try JSONDecoder().decode([Lenient].self, from: data).compactMap(\.spot)
    }

    /// The ids of the spots you've stamped, with when.
    static func stamped(_ stamps: [Stamp]) -> [String: Date] {
        var out: [String: Date] = [:]
        for s in stamps where s.key.hasPrefix("spot:") {
            out[String(s.key.dropFirst(5))] = s.earnedAt
        }
        return out
    }

    static func closest(_ spots: [Spot], to here: CLLocationCoordinate2D) -> [Spot] {
        spots
            .map { ($0, here.distance(to: $0.coordinate)) }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    struct Progress: Identifiable, Equatable, Sendable {
        var bucket: Spot.Bucket
        var done: Int
        var total: Int
        var id: Spot.Bucket { bucket }
    }

    /// Done and total in each bucket, in bucket order.
    static func progress(_ spots: [Spot], done: Set<String>) -> [Progress] {
        Spot.Bucket.allCases.map { b in
            let inBucket = spots.filter { $0.kind.bucket == b }
            return Progress(bucket: b, done: inBucket.filter { done.contains($0.id) }.count, total: inBucket.count)
        }
    }
}
