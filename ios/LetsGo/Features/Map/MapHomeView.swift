import SwiftUI
import SwiftData
import MapKit

/// Home: the map, full screen, with the native sheet over it (Apple Maps' pattern).
/// The sheet holds search, the Nearby list, Kitchens and You, and opens places'
/// pages; the map follows what's open.
struct HomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(SyncStatus.self) private var sync
    @Query(sort: \Gathering.start) private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    @State private var model = HomeModel()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var hostingBlank = false

    var body: some View {
        @Bindable var model = model
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let all = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: location.center, now: now)
            let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
            let shown = model.query.isEmpty ? model.visible(all, now: now, taste: taste) : Search.results(model.query, in: all, now: now)
            ZStack(alignment: .topLeading) {
                map(shown: shown, now: now)
                if model.walking { SkyBand(now: now).allowsHitTesting(false) }
                floatingButtons
            }
        }
        .sheet(isPresented: .constant(true)) {
            HomeSheet()
                .environment(model)
                .environment(location)
                .environment(sync)
                .presentationDetents([HomeModel.peek, HomeModel.mid, .large], selection: $model.detent)
                .presentationBackgroundInteraction(.enabled(upThrough: HomeModel.mid))
                .presentationContentInteraction(.scrolls)
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
                .sheet(isPresented: $hostingBlank) { NewGatheringView(draft: nil) }
        }
        .onChange(of: model.focus) { _, focus in
            guard let focus, !model.walking else { return }
            withAnimation(.smooth(duration: 0.6)) {
                // Sit the place in the visible top half, above the sheet.
                position = .camera(MapCamera(centerCoordinate: focus.coordinate.offset(east: 0, north: -260), distance: 2200))
            }
        }
        .onChange(of: location.center.roundedKey) { if model.walking { followInWorld() } }
        .onAppear {
            // In the city, the listings are spread out: start wide enough to see a few neighborhoods.
            if CityListings.covers(location.center) {
                position = .camera(MapCamera(centerCoordinate: location.center.offset(east: 0, north: -900), distance: 9000))
            }
        }
    }

    // MARK: Map

    private func map(shown: [Candidate], now: Date) -> some View {
        let top = Set(shown.prefix(4).map(\.id))
        return Map(position: $position) {
            if model.walking {
                Annotation("You", coordinate: location.center, anchor: .bottom) { Avatar() }
                    .annotationTitles(.hidden)
            } else {
                UserAnnotation()
            }
            ForEach(shown) { c in
                Annotation(c.title, coordinate: .init(latitude: c.lat, longitude: c.lon), anchor: model.walking ? .bottom : .center) {
                    Button { open(c) } label: {
                        if top.contains(c.id) || model.selectedID == c.id {
                            VStack(spacing: 0) {
                                MapMarker(genre: c.category, caption: short(c), detail: markerDetail(c, now: now), selected: model.selectedID == c.id)
                                if model.walking { Beam(color: c.category.color) }
                            }
                        } else {
                            MapDot(genre: c.category, later: c.start.timeIntervalSince(now) > 90 * 60)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: model.walking ? .realistic : .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea()
    }

    private func open(_ c: Candidate) {
        switch c.kind {
        case .gathering:
            if let g = gatherings.first(where: { $0.id == c.id }) { model.open(g, id: g.id, at: g.coordinate) }
        case .drop:
            if let k = kitchens.first(where: { $0.id == c.id }) { model.open(k, id: k.id, at: k.coordinate) }
        }
    }

    /// "Pizza drop", "Pickup soccer": short enough to sit under a marker.
    private func short(_ c: Candidate) -> String {
        let name = c.kind == .drop ? "\(c.place) drop" : c.title.split(separator: ",").first.map(String.init) ?? c.title
        return name.count > 22 ? String(name.prefix(20)) + "…" : name
    }

    private func markerDetail(_ c: Candidate, now: Date) -> String? {
        if c.start <= now { return "now" }
        if c.kind == .gathering && c.capacity > 0 { return "\(c.going)/\(c.capacity)" }
        return c.start.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Buttons over the map

    private var floatingButtons: some View {
        VStack(spacing: 10) {
            circleButton(model.walking ? "map" : "figure.walk", label: model.walking ? "Back to the map" : "Walk view", on: model.walking) {
                toggleWalk()
            }
            circleButton("plus", label: "Host something", on: false) { hostingBlank = true }
        }
        .padding(.leading, 14)
        .padding(.top, 8)
    }

    private func circleButton(_ symbol: String, label: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(on ? Palette.accent : Palette.ink)
                .frame(width: 46, height: 46)
        }
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private func toggleWalk() {
        model.walking.toggle()
        if model.walking {
            model.detent = HomeModel.peek
            followInWorld()
        } else {
            model.detent = HomeModel.mid
            withAnimation(.smooth(duration: 0.8)) { position = .userLocation(fallback: .automatic) }
        }
    }

    private func followInWorld() {
        withAnimation(.smooth(duration: 1.0)) {
            position = .camera(MapCamera(centerCoordinate: location.center, distance: 520, heading: 20, pitch: 68))
        }
    }
}

/// You, in walk view: a small figure standing on the street.
struct Avatar: View {
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: 0xF2D3B6), Color(hex: 0xC99A78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 18, height: 18)
            UnevenRoundedRectangle(topLeadingRadius: 11, bottomLeadingRadius: 7, bottomTrailingRadius: 7, topTrailingRadius: 11)
                .fill(LinearGradient(colors: [Color(hex: 0x6E8BFF), Color(hex: 0x3E58D6)], startPoint: .top, endPoint: .bottom))
                .frame(width: 24, height: 26)
            Ellipse().fill(.black.opacity(0.4)).frame(width: 30, height: 8).offset(y: -4)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 3)
        .accessibilityLabel("You")
    }
}

/// The light column under a marker in walk view.
struct Beam: View {
    var color: Color

    var body: some View {
        Rectangle()
            .fill(LinearGradient(colors: [color, color.opacity(0)], startPoint: .top, endPoint: .bottom))
            .frame(width: 2, height: 46)
    }
}

/// A band of sky over walk view that follows the real time of day.
struct SkyBand: View {
    var now: Date

    var body: some View {
        let hour = Calendar.current.component(.hour, from: now)
        let top: Color = switch hour {
        case 5..<9: Color(hex: 0xF4B78F)
        case 9..<17: Color(hex: 0x8EC3F2)
        case 17..<20: Color(hex: 0xE58F73)
        default: Color(hex: 0x1B2346)
        }
        LinearGradient(colors: [top.opacity(0.75), top.opacity(0)], startPoint: .top, endPoint: .bottom)
            .frame(height: 220)
            .frame(maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
    }
}
