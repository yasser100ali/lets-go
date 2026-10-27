import SwiftUI
import MapKit
import Observation

/// What the tabs, the map, its Wren card and the list sheet share: the filters, the
/// search, the map's look, whether the list is open and how tall, what's open in it,
/// and where the map should look.
@Observable
final class HomeModel {
    static let half = PresentationDetent.fraction(0.5)

    var tab: AppTab = .map
    /// Afterglow, or Signal when you just want to be told where to go.
    var mode: MapMode = .afterglow
    var window: TimeWindow = .now
    /// Hours past now the map is showing, from Signal's ruler. Only used with `.now`.
    var ahead: Double = 0
    var genre: Genre?
    var freeOnly = false
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
    /// The Dostoevsky splash: on first launch, and again from Passport.
    var showQuote = false

    struct Focus: Equatable {
        var id = UUID()
        var latitude: Double
        var longitude: Double
        var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    }

    /// What the map pins and the list show, best first.
    func visible(_ all: [Candidate], now: Date, taste: Taste) -> [Candidate] {
        let inWindow = all.filter { c in
            window.contains(start: c.start, end: c.end, now: now)
                && (genre.map { c.category == $0 } ?? true)
                && (!freeOnly || c.isFree)
        }
        if window == .now { return Picks.picks(inWindow, now: now, taste: taste, limit: 80) }
        return inWindow.sorted { $0.start < $1.start }
    }

    /// Open the list from the map: "All 11", or the Wren card's handle.
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
        tab = .map
        path = NavigationPath()
        path.append(value)
        selectedID = id
        focus = Focus(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if !listOpen { detent = Self.half }
        listOpen = true
    }

    func toggleSignal() {
        withAnimation(.smooth(duration: 0.45)) {
            mode = mode == .signal ? .afterglow : .signal
            if mode == .signal {
                window = .now
                walking = false
            } else {
                ahead = 0
            }
        }
    }
}

enum AppTab: Hashable {
    case map, plans, passport, wren
}

enum MapMode: Hashable {
    /// The night map: glowing pins, Wren's line on glass.
    case afterglow
    /// Black and lime: the top three, numbered, with when to leave.
    case signal
}
