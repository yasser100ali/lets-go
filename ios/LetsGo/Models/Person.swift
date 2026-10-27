import Foundation
import SwiftData
import SwiftUI
import CoreLocation

/// Someone you go out with. Real friends come from the server (you became friends by
/// trading a code); sample ones stand in until you have some, and say so.
@Model
final class Person {
    /// A real friend's id is their id on the server.
    var id: UUID
    var name: String
    var isSample: Bool
    /// For sample people: what they're doing in the sample neighborhood ("team", "solo", "porch", "home").
    var sampleRole: String = ""
    /// Porch light: up for something until then.
    var porchUntil: Date?
    var porchNote: String = ""
    /// Where their porch light is, if they shared it. Sample people have one so the map has them.
    var latitude: Double?
    var longitude: Double?
    /// What they joined tonight, from the server: "there" (checked in) or "heading".
    var outStateRaw: String = ""
    var outTitle: String = ""
    var outPlace: String = ""
    var outStart: Date?
    var outGatheringID: UUID?
    var outLatitude: Double?
    var outLongitude: Double?
    /// They waved at you.
    var wavedAt: Date?
    /// You waved at them.
    var youWavedAt: Date?
    /// For sample people: the hour they're free from on a weekend, for Wren's planning.
    var freeAfterHour: Int?

    init(id: UUID = UUID(), name: String, isSample: Bool, sampleRole: String = "") {
        self.id = id
        self.name = name
        self.isSample = isSample
        self.sampleRole = sampleRole
    }
}

/// A named group of friends: "Tuesday trivia", "the run lot".
@Model
final class Crew {
    var id: UUID
    var name: String
    /// `Person.id`s, you not included.
    var memberIDs: [UUID]
    var isMine: Bool
    var isSample: Bool

    init(id: UUID = UUID(), name: String, memberIDs: [UUID], isMine: Bool = true, isSample: Bool = false) {
        self.id = id
        self.name = name
        self.memberIDs = memberIDs
        self.isMine = isMine
        self.isSample = isSample
    }
}

/// A person as the screens and Wren reason about them: a plain value, so it can be tested.
struct Friend: Identifiable, Hashable, Sendable {
    enum OutState: String, Sendable { case there, heading }

    struct Out: Hashable, Sendable {
        var state: OutState
        var title: String
        var place: String
        var start: Date?
        /// The local gathering they're at or heading to, when this phone has it.
        var gatheringID: UUID?
        var latitude: Double?
        var longitude: Double?
    }

    var id: UUID
    var name: String
    var isSample: Bool
    var sampleRole: String = ""
    var porchUntil: Date?
    var porchNote: String = ""
    var latitude: Double?
    var longitude: Double?
    var out: Out?
    var wavedAt: Date?
    var youWavedAt: Date?
    var freeAfterHour: Int?

    var firstName: String { name.split(separator: " ").first.map(String.init) ?? name }
    var initial: String { String(name.first ?? "?").uppercased() }

    func porchOn(at now: Date) -> Bool { (porchUntil ?? .distantPast) > now }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }

    /// Ink, pastel and amber: one per person, the same every time.
    var color: Color { Color(hex: Self.hue(for: name)) }
    var ink: Color { Color(hex: Self.ink(for: name)) }

    static let swatches: [(fill: UInt32, ink: UInt32)] = [
        (0xF2B04B, 0x2A1A00), (0x7DB5FF, 0x04182F), (0x6ED7A0, 0x052414), (0xF58FB7, 0x2E0716),
        (0xB9A2FF, 0x170A33), (0xFF9F7A, 0x2E0E02), (0xE9E4D8, 0x1B1A17), (0x9FD9E8, 0x062A33),
    ]

    /// The mocks' own colors for the sample people, then a stable pick for anyone else.
    static func swatch(for name: String) -> (fill: UInt32, ink: UInt32) {
        let named: [String: Int] = ["Maya": 0, "Theo": 1, "Jun": 2, "Priya": 3, "Ben": 4, "Lucía": 5, "Ana": 5, "Omar": 6, "Leo": 7]
        if let i = named[name] { return swatches[i] }
        return swatches[Int(Art.unit(name, 7) * Double(swatches.count)) % swatches.count]
    }

    static func hue(for name: String) -> UInt32 { swatch(for: name).fill }
    static func ink(for name: String) -> UInt32 { swatch(for: name).ink }
}

extension Person {
    var snapshot: Friend {
        var out: Friend.Out?
        if let state = Friend.OutState(rawValue: outStateRaw) {
            out = Friend.Out(
                state: state, title: outTitle, place: outPlace, start: outStart,
                gatheringID: outGatheringID, latitude: outLatitude, longitude: outLongitude
            )
        }
        return Friend(
            id: id, name: name, isSample: isSample, sampleRole: sampleRole,
            porchUntil: porchUntil, porchNote: porchNote, latitude: latitude, longitude: longitude,
            out: out, wavedAt: wavedAt, youWavedAt: youWavedAt, freeAfterHour: freeAfterHour
        )
    }
}
