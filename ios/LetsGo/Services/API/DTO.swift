import Foundation

// Shapes of the backend's JSON (backend/app/schemas.py), snake_case converted.

nonisolated struct GatheringDTO: Codable, Sendable, Identifiable {
    var id: UUID
    var title: String
    var genre: String
    var details: String
    var placeName: String
    var lat: Double
    var lon: Double
    var startsAt: Date
    var endsAt: Date
    var capacity: Int
    var bring: String
    var recurring: String
    var hostName: String
    var going: Int
    var isMine: Bool
    var isJoined: Bool
    var checkedInAt: Date?
    var distanceM: Double?
}

nonisolated struct NewGatheringDTO: Encodable, Sendable {
    var title: String
    var genre: String
    var details: String
    var placeName: String
    var lat: Double
    var lon: Double
    var startsAt: Date
    var endsAt: Date
    var capacity: Int
    var bring: String
    var recurring: String = ""
}

nonisolated struct CheckInDTO: Encodable, Sendable {
    var lat: Double
    var lon: Double
}

nonisolated struct DropDTO: Codable, Sendable {
    var id: UUID
    var startsAt: Date
    var endsAt: Date
    var total: Int
    var sold: Int
    var perSlot: Int
    var left: Int
}

nonisolated struct MenuItemDTO: Codable, Sendable {
    var id: UUID
    var name: String
    var note: String
    var priceCents: Int
}

nonisolated struct ReviewDTO: Codable, Sendable {
    var stars: Int
    var tags: [String]
    var text: String
    var authorName: String
    var createdAt: Date
}

nonisolated struct KitchenDTO: Codable, Sendable, Identifiable {
    var id: UUID
    var name: String
    var cookName: String
    var cuisine: String
    var story: String
    var lat: Double
    var lon: Double
    var porchTables: Int
    var permitted: Bool
    var rating: Double?
    var reviewCount: Int
    var nextDrop: DropDTO?
    var isMine: Bool
    var distanceM: Double?
    // Only on the detail endpoint.
    var menu: [MenuItemDTO]?
    var reviews: [ReviewDTO]?
    var pickupNote: String?
}

nonisolated struct NearbyDTO: Codable, Sendable {
    var gatherings: [GatheringDTO]
    var kitchens: [KitchenDTO]
}

nonisolated struct NewKitchenDTO: Encodable, Sendable {
    var name: String
    var cuisine: String
    var story: String
    var lat: Double
    var lon: Double
    var pickupNote: String
    var porchTables: Int
    var permitConfirmed: Bool
    var handlerCardConfirmed: Bool
}

nonisolated struct KitchenPermitsDTO: Encodable, Sendable {
    var permitConfirmed: Bool
    var handlerCardConfirmed: Bool
}

nonisolated struct NewMenuItemDTO: Encodable, Sendable {
    var name: String
    var note: String
    var priceCents: Int
}

nonisolated struct NewDropDTO: Encodable, Sendable {
    var startsAt: Date
    var endsAt: Date
    var total: Int
    var perSlot: Int
}

nonisolated struct OrderLineDTO: Codable, Sendable {
    var name: String
    var priceCents: Int
    var quantity: Int
}

nonisolated struct OrderDTO: Codable, Sendable {
    var id: UUID
    var clientId: UUID
    var kitchenId: UUID
    var kitchenName: String
    var dropId: UUID
    var pickupAt: Date
    var eatOnPorch: Bool
    var status: String
    var lines: [OrderLineDTO]
    var subtotalCents: Int
    var serviceCents: Int
    var totalCents: Int
    var pickupNote: String
}

nonisolated struct NewOrderDTO: Encodable, Sendable {
    struct Line: Encodable, Sendable {
        var menuItemId: UUID
        var quantity: Int
    }

    var clientId: UUID
    var dropId: UUID
    var pickupAt: Date
    var lines: [Line]
    var eatOnPorch: Bool
}

nonisolated struct NewReviewDTO: Encodable, Sendable {
    var stars: Int
    var tags: [String]
    var text: String
}

nonisolated struct ProfileDTO: Codable, Sendable {
    var displayName: String
}

/// GET /v1/listings: the same shape as sf_happenings.json, so the phone keeps the server's copy as-is.
nonisolated struct ListingsDTO: Codable, Sendable {
    var listings: [ListingDTO]
}

nonisolated struct ListingDTO: Codable, Sendable {
    var title: String
    var genre: String
    var venue: String
    var address: String
    var lat: Double
    var lon: Double
    var schedule: [SlotDTO]
    var price: String
    var organizer: String
    var url: String
    var description: String
    var confidence: String
}

nonisolated struct SlotDTO: Codable, Sendable {
    var weekday: String?
    var date: String?
    var start: String
    var end: String?
}
