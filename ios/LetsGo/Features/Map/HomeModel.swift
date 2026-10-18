import SwiftUI
import MapKit
import Observation

/// What the map and its sheet share: the filters, the search, where the sheet is,
/// what's open in it, and where the map should look.
@Observable
final class HomeModel {
    static let peek = PresentationDetent.height(148)
    static let mid = PresentationDetent.fraction(0.46)

    var section: HomeSection = .nearby
    var window: TimeWindow = .now
    var genre: Genre?
    var query = ""
    var detent: PresentationDetent = HomeModel.mid
    var path = NavigationPath()
    var selectedID: UUID?
    var walking = false
    /// Bumped to ask the map to fly somewhere.
    var focus: Focus?

    struct Focus: Equatable {
        var id = UUID()
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// What the map pins and the Nearby list show, best first.
    func visible(_ all: [Candidate], now: Date, taste: Taste) -> [Candidate] {
        let inWindow = all.filter { c in
            window.contains(start: c.start, end: c.end, now: now) && (genre.map { c.category == $0 } ?? true)
        }
        if window == .now { return Picks.picks(inWindow, now: now, taste: taste, limit: 80) }
        return inWindow.sorted { $0.start < $1.start }
    }

    /// Opens something's page in the sheet and points the map at it.
    func open(_ value: some Hashable, id: UUID, at coordinate: CLLocationCoordinate2D) {
        path = NavigationPath()
        path.append(value)
        selectedID = id
        focus = Focus(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if detent == Self.peek { detent = Self.mid }
    }

    func closeDetail() {
        selectedID = nil
    }
}

enum HomeSection: String, CaseIterable, Identifiable {
    case nearby, kitchens, you

    var id: String { rawValue }

    var label: String {
        switch self {
        case .nearby: "Nearby"
        case .kitchens: "Kitchens"
        case .you: "You"
        }
    }
}
