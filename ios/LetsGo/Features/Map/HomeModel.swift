import SwiftUI
import MapKit
import Observation

/// What the tabs, the now bar, the map and the list sheet share: the filters, the
/// search, whether the list is open and how tall, what's open in it, and where the
/// map should look.
@Observable
final class HomeModel {
    static let half = PresentationDetent.fraction(0.5)

    var tab: AppTab = .map
    var window: TimeWindow = .now
    var genre: Genre?
    var query = ""
    var listOpen = false
    var detent: PresentationDetent = HomeModel.half
    /// Set when the list should open with the search field focused.
    var wantsSearch = false
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

    /// What the map pins and the list show, best first.
    func visible(_ all: [Candidate], now: Date, taste: Taste) -> [Candidate] {
        let inWindow = all.filter { c in
            window.contains(start: c.start, end: c.end, now: now) && (genre.map { c.category == $0 } ?? true)
        }
        if window == .now { return Picks.picks(inWindow, now: now, taste: taste, limit: 80) }
        return inWindow.sorted { $0.start < $1.start }
    }

    /// The now bar: open the list from wherever you are.
    func showList() {
        tab = .map
        path = NavigationPath()
        detent = Self.half
        listOpen = true
    }

    func startSearch() {
        tab = .map
        wantsSearch = true
        detent = .large
        listOpen = true
    }

    /// Opens something's page in the list sheet and points the map at it.
    func open(_ value: some Hashable, id: UUID, at coordinate: CLLocationCoordinate2D) {
        path = NavigationPath()
        path.append(value)
        selectedID = id
        focus = Focus(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if !listOpen { detent = Self.half }
        listOpen = true
    }
}

enum AppTab: Hashable {
    case map, kitchens, you
}
