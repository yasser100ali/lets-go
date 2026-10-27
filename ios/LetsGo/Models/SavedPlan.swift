import Foundation
import SwiftData

/// A plan Wren made that you asked people to: the stops, the walks, who's in it.
@Model
final class SavedPlan {
    var id: UUID
    var createdAt: Date
    var day: Date
    var title: String
    var dayLine: String
    /// `Person.id`s.
    var friendIDs: [UUID]
    var stops: [Plan.Stop]
    var legs: [Plan.Leg]
    var note: String
    /// What you said to Wren, so "Change" can start from it.
    var request: String
    var askedAt: Date?
    var confirmed: Bool

    init(_ plan: Plan, request: String) {
        self.id = UUID()
        self.createdAt = .now
        self.day = plan.day
        self.title = plan.title
        self.dayLine = plan.dayLine
        self.friendIDs = plan.friendIDs
        self.stops = plan.stops
        self.legs = plan.legs
        self.note = plan.note
        self.request = request
        self.askedAt = nil
        self.confirmed = false
    }

    var start: Date? { stops.first?.start }
    var meters: Double { legs.reduce(0) { $0 + $1.meters } }
    var event: Plan.Stop? { stops.last { $0.kind == .event } }
}
