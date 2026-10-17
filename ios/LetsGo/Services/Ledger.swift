import Foundation
import SwiftData
import OSLog

/// The things you do that change what the app knows about you:
/// joining, checking in, ordering, reviewing, hosting. Each one saves,
/// awards any stamp it earned, and teaches Wren a little.
enum Ledger {
    private static let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "ledger")

    static func save(_ context: ModelContext, _ what: String) {
        do {
            try context.save()
        } catch {
            log.error("Save failed (\(what, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Gatherings

    static func join(_ g: Gathering, context: ModelContext) {
        g.isJoined = true
        learn("into:\(g.category.rawValue)", "Into \(g.category.noun)", g.category, context: context)
        save(context, "join")
    }

    static func leave(_ g: Gathering, context: ModelContext) {
        g.isJoined = false
        save(context, "leave")
    }

    /// Returns the stamp earned, if this check-in earned a new one.
    @discardableResult
    static func checkIn(_ g: Gathering, context: ModelContext, now: Date = .now) -> Stamp? {
        g.isJoined = true
        g.checkedInAt = now
        let earned = award(
            key: "place:\(g.placeName.lowercased())",
            title: g.placeName,
            symbol: g.category.symbol,
            category: g.category,
            context: context
        )
        let checkIns = count(context, FetchDescriptor<Gathering>(predicate: #Predicate { $0.checkedInAt != nil }))
        if checkIns == 1 {
            award(key: "first-checkin", title: "First show-up", symbol: "figure.wave", category: g.category, context: context)
        }
        if checkIns >= 5 {
            award(key: "checkins-5", title: "Five show-ups", symbol: "star.circle", category: g.category, context: context)
        }
        learn("into:\(g.category.rawValue)", "Into \(g.category.noun)", g.category, context: context)
        save(context, "check-in")
        return earned
    }

    static func host(_ g: Gathering, context: ModelContext) {
        context.insert(g)
        award(key: "first-host", title: "Hosted one", symbol: "flag.fill", category: g.category, context: context)
        save(context, "host")
    }

    // MARK: Kitchens

    static func reserve(_ order: Order, at kitchen: Kitchen, drop: Drop?, context: ModelContext) {
        context.insert(order)
        order.kitchen = kitchen
        if let drop { drop.sold += order.itemCount }
        learn("eats:\(kitchen.cuisine.lowercased())", "Likes \(kitchen.cuisine.lowercased())", .food, context: context)
        save(context, "reserve")
    }

    @discardableResult
    static func review(_ review: Review, for order: Order, context: ModelContext) -> Stamp? {
        guard let kitchen = order.kitchen else { return nil }
        context.insert(review)
        review.kitchen = kitchen
        order.status = .reviewed
        award(key: "first-review", title: "First review", symbol: "text.bubble.fill", category: .food, context: context)
        var earned: Stamp?
        let visits = kitchen.orders.filter { $0.status != .reserved }.count
        if visits >= 3 {
            earned = award(key: "regular:\(kitchen.id.uuidString)", title: "Regular at \(kitchen.cookName)'s", symbol: "fork.knife", category: .food, context: context)
        }
        save(context, "review")
        return earned
    }

    static func openKitchen(_ kitchen: Kitchen, context: ModelContext) {
        context.insert(kitchen)
        award(key: "opened-kitchen", title: "Opened a kitchen", symbol: "house.fill", category: .food, context: context)
        save(context, "open kitchen")
    }

    // MARK: Stamps and taste

    @discardableResult
    static func award(key: String, title: String, symbol: String, category: Genre, context: ModelContext) -> Stamp? {
        let existing = count(context, FetchDescriptor<Stamp>(predicate: #Predicate { $0.key == key }))
        guard existing == 0 else { return nil }
        let stamp = Stamp(key: key, title: title, symbol: symbol, category: category)
        context.insert(stamp)
        return stamp
    }

    /// Adds a note Wren believes about you, unless you deleted it before.
    static func learn(_ key: String, _ text: String, _ category: Genre?, context: ModelContext) {
        let existing = count(context, FetchDescriptor<TasteNote>(predicate: #Predicate { $0.key == key }))
        guard existing == 0 else { return }
        context.insert(TasteNote(key: key, text: text, category: category))
    }

    private static func count<T: PersistentModel>(_ context: ModelContext, _ descriptor: FetchDescriptor<T>) -> Int {
        do {
            return try context.fetchCount(descriptor)
        } catch {
            log.error("Count failed: \(error.localizedDescription, privacy: .public)")
            return 0
        }
    }
}
