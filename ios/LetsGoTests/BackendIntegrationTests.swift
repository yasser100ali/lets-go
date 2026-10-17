import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import LetsGo

/// Runs against a real backend. Start it with `docker compose up`, then:
///
///     TEST_RUNNER_LETSGO_API=http://localhost:8100 xcodebuild test …
///
/// Skipped when LETSGO_API isn't set.
@Suite("Backend round trip", .enabled(if: ProcessInfo.processInfo.environment["LETSGO_API"] != nil), .serialized)
struct BackendIntegrationTests {
    let here = CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)

    func container() throws -> ModelContainer {
        try ModelContainer(
            for: Gathering.self, Kitchen.self, MenuItem.self, Drop.self, Order.self, Review.self, Stamp.self, TasteNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @Test func hostedGatheringComesBackFromNearby() async throws {
        let context = ModelContext(try container())
        let g = Gathering(
            title: "Integration soccer \(UUID().uuidString.prefix(4))", category: .play, placeName: "The big field",
            coordinate: here.offset(east: -200, north: 100),
            start: .now.addingTimeInterval(1800), end: .now.addingTimeInterval(7200), capacity: 10, hostName: "You", isMine: true
        )
        try await Sync.host(g, context: context)
        #expect(g.remoteID != nil)

        // A fresh phone sees it through /v1/nearby.
        let other = ModelContext(try container())
        try await Sync.refresh(around: here, context: other)
        let found = try other.fetch(FetchDescriptor<Gathering>()).first { $0.remoteID == g.remoteID }
        #expect(found?.title == g.title)
        #expect(found?.isMine == true)
        #expect(found?.going == 1)
        // Python's microsecond timestamps decode to within a second of what we sent.
        #expect(abs((found?.start.timeIntervalSince(g.start)) ?? 99) < 1)
    }

    @Test func kitchenMenuAndDropRoundTrip() async throws {
        let context = ModelContext(try container())
        let mine = try? await APIClient.shared.send(Endpoint<KitchenDTO>.get("/v1/kitchens/me"))
        let k: Kitchen
        if let mine {
            // One kitchen per account; reuse it on later runs.
            k = Kitchen(name: mine.name, cookName: "You", cuisine: mine.cuisine, story: "", coordinate: here, pickupNote: "", isMine: true)
            k.remoteID = mine.id
            context.insert(k)
            try await Sync.refresh(k, context: context)
        } else {
            k = Kitchen(name: "Test Porch Pizza", cookName: "You", cuisine: "Pizza", story: "", coordinate: here.offset(east: 100, north: 50),
                        pickupNote: "Side gate", isMine: true)
            k.permitConfirmed = true
            k.handlerCardConfirmed = true
            try await Sync.open(k, context: context)
        }
        #expect(k.remoteID != nil)

        let item = MenuItem(name: "Margherita \(UUID().uuidString.prefix(4))", priceCents: 1400, sortIndex: k.menu.count)
        try await Sync.add(item, to: k, context: context)
        #expect(item.remoteID != nil)

        let start = Date.now.addingTimeInterval(3600)
        let drop = Drop(start: start, end: start.addingTimeInterval(5400), total: 12)
        try await Sync.post(drop, to: k, context: context)
        #expect(drop.remoteID != nil)

        // Ordering from your own kitchen is refused, with the server's reason.
        let order = Order(pickupAt: start, lines: [OrderLine(name: item.name, priceCents: 1400, quantity: 1)], eatOnPorch: false)
        await #expect(throws: APIError.rejected(status: 409, reason: "You can't order from your own kitchen")) {
            try await Sync.reserve(order, picked: [(item: item, quantity: 1)], at: k, drop: drop, context: context)
        }
    }
}

@Suite("Server dates")
struct DateParsingTests {
    @Test func microsecondsParse() {
        let d = JSONCoding.parseDate("2026-10-17T05:06:26.123456+00:00")
        #expect(d != nil)
        #expect(JSONCoding.parseDate("2026-10-17T05:06:26+00:00") != nil)
        #expect(JSONCoding.parseDate("2026-10-17T05:06:26.5Z") != nil)
        #expect(JSONCoding.parseDate("yesterday") == nil)
    }
}
