import Foundation
import SwiftData

/// Proof you showed up. Earned by being there, never by tapping a button from home.
@Model
final class Stamp {
    var id: UUID
    /// Stable key so the same stamp is never awarded twice ("place:Dolores Park").
    var key: String
    var title: String
    var symbol: String
    var categoryRaw: String
    var earnedAt: Date

    init(key: String, title: String, symbol: String, category: Genre, earnedAt: Date = .now) {
        self.id = UUID()
        self.key = key
        self.title = title
        self.symbol = symbol
        self.categoryRaw = category.rawValue
        self.earnedAt = earnedAt
    }

    var category: Genre { Genre(rawValue: categoryRaw) ?? .party }
}

/// Something Wren believes about you. You can see every one and delete any of them.
@Model
final class TasteNote {
    var id: UUID
    var key: String
    var text: String
    var categoryRaw: String?
    var createdAt: Date
    /// Deleted by you. Kept (hidden) so Wren doesn't learn it straight back.
    var isHidden: Bool

    init(key: String, text: String, category: Genre?) {
        self.id = UUID()
        self.key = key
        self.text = text
        self.categoryRaw = category?.rawValue
        self.createdAt = .now
        self.isHidden = false
    }

    var category: Genre? { categoryRaw.flatMap(Genre.init(rawValue:)) }
}
