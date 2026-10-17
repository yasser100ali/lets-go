import SwiftUI
import SwiftData
import MapKit

/// Home: a flat map of what's on within walking distance, a search bar, and a
/// sheet listing it. Walk view tilts the map into the street around you.
struct MapHomeView: View {
    @Environment(LocationService.self) private var location
    @Environment(SyncStatus.self) private var sync
    @Query(sort: \Gathering.start) private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    @State private var path = NavigationPath()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var window: TimeWindow = .now
    @State private var genre: Genre?
    @State private var query = ""
    @FocusState private var searching: Bool
    @State private var selected: UUID?
    @State private var detent: SheetDetent = .peek
    @State private var walking = false
    @State private var hosting: GatheringDraft?
    @State private var hostingBlank = false

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let now = timeline.date
                let all = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: location.center, now: now)
                let shown = visible(all, now: now)
                let results = Search.results(query, in: all, now: now)
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        map(shown: query.isEmpty ? shown : results, now: now)
                        if walking { SkyBand(now: now).allowsHitTesting(false) }
                        controls
                    }
                    .overlay(alignment: .bottom) {
                        MapSheet(detent: $detent, available: geo.size.height - 150) {
                            sheetHeader(shown: shown, results: results)
                        } content: {
                            sheetContent(shown: shown, results: results, now: now)
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .navigationDestination(for: Kitchen.self) { KitchenView(kitchen: $0) }
            .sheet(item: $hosting) { NewGatheringView(draft: $0) }
            .sheet(isPresented: $hostingBlank) { NewGatheringView(draft: nil) }
            .onChange(of: searching) { _, on in if on { detent = .full; selected = nil } }
            .onChange(of: location.center.roundedKey) { if walking { followInWorld() } }
            .onAppear {
                // In the city, the listings are spread out: start wide enough to see a few neighborhoods.
                if CityListings.covers(location.center) {
                    position = .camera(MapCamera(centerCoordinate: location.center, distance: 9000))
                }
            }
        }
    }

    // MARK: What's shown

    private func visible(_ all: [Candidate], now: Date) -> [Candidate] {
        let inWindow = all.filter { c in
            window.contains(start: c.start, end: c.end, now: now) && (genre.map { c.category == $0 } ?? true)
        }
        if window == .now {
            let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
            return Picks.picks(inWindow, now: now, taste: taste, limit: 60)
        }
        return inWindow.sorted { $0.start < $1.start }
    }

    // MARK: Map

    private func map(shown: [Candidate], now: Date) -> some View {
        let top = Set(shown.prefix(3).map(\.id))
        return Map(position: $position) {
            if walking {
                Annotation("You", coordinate: location.center, anchor: .bottom) { Avatar() }
                    .annotationTitles(.hidden)
            } else {
                UserAnnotation()
            }
            ForEach(shown) { c in
                Annotation(c.title, coordinate: coordinate(of: c), anchor: walking ? .bottom : .center) {
                    Button { select(c) } label: {
                        if top.contains(c.id) || selected == c.id {
                            VStack(spacing: 0) {
                                MapMarker(genre: c.category, caption: short(c), detail: markerDetail(c, now: now), selected: selected == c.id)
                                if walking { Beam(color: c.category.color) }
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
        .mapStyle(.standard(elevation: walking ? .realistic : .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onTapGesture { searching = false }
        .ignoresSafeArea()
    }

    private func coordinate(of c: Candidate) -> CLLocationCoordinate2D {
        switch c.kind {
        case .gathering: gatherings.first { $0.id == c.id }?.coordinate ?? location.center
        case .drop: kitchens.first { $0.id == c.id }?.coordinate ?? location.center
        }
    }

    /// "Pizza drop", "Pickup soccer": short enough to sit under a marker.
    private func short(_ c: Candidate) -> String {
        c.kind == .drop ? "\(c.place) drop" : c.title.split(separator: ",").first.map(String.init) ?? c.title
    }

    private func markerDetail(_ c: Candidate, now: Date) -> String? {
        if c.start <= now { return "now" }
        if c.kind == .gathering && c.capacity > 0 { return "\(c.going)/\(c.capacity)" }
        return c.start.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                    TextField("Search nearby", text: $query)
                        .focused($searching)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.muted)
                        }
                        .accessibilityLabel("Clear search")
                    }
                }
                .font(.system(size: 16))
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassEffect(.regular.interactive(), in: .capsule)

                if searching {
                    Button("Cancel") { query = ""; searching = false; detent = .peek }
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Palette.ink)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    Button { hostingBlank = true } label: {
                        Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(Palette.ink)
                            .frame(width: 46, height: 46)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Host something")
                }
            }
            if !searching {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(TimeWindow.allCases) { w in
                            FilterChip(title: w.label, on: window == w) { window = w; selected = nil }
                        }
                        Divider().frame(height: 20).padding(.horizontal, 2)
                        ForEach([Genre.play, .food, .music, .move, .party]) { g in
                            FilterChip(title: g.plural, on: genre == g) { genre = genre == g ? nil : g; selected = nil }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
                .padding(.horizontal, -16)

                HStack {
                    Spacer()
                    Button { toggleWalk() } label: {
                        Image(systemName: walking ? "map" : "figure.walk")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(walking ? Palette.accent : Palette.ink)
                            .frame(width: 44, height: 44)
                    }
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel(walking ? "Back to the map" : "Walk view")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.snappy, value: searching)
    }

    private func toggleWalk() {
        walking.toggle()
        selected = nil
        if walking {
            followInWorld()
        } else {
            withAnimation(.smooth(duration: 0.8)) { position = .userLocation(fallback: .automatic) }
        }
    }

    private func followInWorld() {
        withAnimation(.smooth(duration: 1.0)) {
            position = .camera(MapCamera(centerCoordinate: location.center, distance: 520, heading: 20, pitch: 68))
        }
    }

    private func select(_ c: Candidate) {
        searching = false
        selected = c.id
        detent = .peek
        if !walking {
            withAnimation(.smooth) {
                position = .camera(MapCamera(centerCoordinate: coordinate(of: c), distance: 1400))
            }
        }
    }

    // MARK: Sheet

    @ViewBuilder
    private func sheetHeader(shown: [Candidate], results: [Candidate]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if !query.isEmpty {
                Text(results.isEmpty ? "No results" : "\(results.count) result\(results.count == 1 ? "" : "s")")
                    .font(.system(size: 22, weight: .bold))
            } else if selected != nil {
                Text("Selected").font(.system(size: 22, weight: .bold))
            } else {
                Text(window == .now ? "Nearby" : window.label).display(22)
            }
            Spacer()
            if selected != nil {
                Button { selected = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Palette.muted)
                        .frame(width: 30, height: 30).background(Palette.raise, in: .circle)
                }
                .accessibilityLabel("Close")
            } else if query.isEmpty {
                Text(summary(shown)).font(.system(size: 13)).foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 6)
    }

    private func summary(_ shown: [Candidate]) -> String {
        let now = Date.now
        let on = shown.filter { $0.start <= now }.count
        if window == .now && on > 0 { return "\(on) on now · \(shown.count - on) soon" }
        return "\(shown.count) things"
    }

    @ViewBuilder
    private func sheetContent(shown: [Candidate], results: [Candidate], now: Date) -> some View {
        if let id = selected, let c = (shown + results).first(where: { $0.id == id }) {
            SelectedCard(candidate: c, now: now) { open(c) }
                .padding(.horizontal, 16)
                .padding(.top, 4)
        } else if searching && query.isEmpty {
            suggestions
        } else if !query.isEmpty {
            if results.isEmpty {
                emptySearch
            } else {
                rows(results, now: now)
            }
        } else if shown.isEmpty {
            Text(window == .now ? "Nothing in the next few hours. Try Tonight or Weekend, or host something." : "Nothing yet. Host something and it shows up here.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 18)
                .padding(.top, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            rows(shown, now: now)
        }
    }

    private func rows(_ items: [Candidate], now: Date) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, c in
                PickRow(pick: c, now: now) { open(c) }
                    .padding(.horizontal, 18)
                if i < items.count - 1 { Divider().overlay(Palette.line).padding(.leading, 66) }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Try").eyebrow().padding(.horizontal, 18).padding(.bottom, 4)
            ForEach(["Pizza", "Basketball", "Tonight", "Free this weekend", "Run", "Ice cream"], id: \.self) { s in
                Button { query = s } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted).frame(width: 36)
                        Text(s).font(.system(size: 16)).foregroundStyle(Palette.ink)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptySearch: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Nothing nearby matches \u{201C}\(query)\u{201D}.")
                .font(.system(size: 15))
                .foregroundStyle(Palette.muted)
            Button {
                hosting = GatheringDraft.from(SearchQuery.parse(query))
            } label: {
                Label("Host \u{201C}\(query)\u{201D}", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func open(_ c: Candidate) {
        searching = false
        switch c.kind {
        case .gathering: if let g = gatherings.first(where: { $0.id == c.id }) { path.append(g) }
        case .drop: if let k = kitchens.first(where: { $0.id == c.id }) { path.append(k) }
        }
    }
}

/// One row in the sheet: tinted icon, name, the facts, and when.
struct PickRow: View {
    var pick: Candidate
    var now: Date
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryDot(category: pick.category, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pick.title).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.ink).lineLimit(1)
                    Text(subtitle).font(.system(size: 13)).foregroundStyle(Palette.muted).lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(pick.start <= now ? "Now" : When.short(pick.start, now: now))
                    .font(.system(size: 13, weight: pick.start <= now ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(pick.start <= now ? Palette.live : Palette.muted)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        var parts: [String] = []
        if pick.kind == .gathering && !pick.place.isEmpty { parts.append(pick.place) }
        parts.append(Picks.reason(pick, now: now))
        return parts.joined(separator: " · ")
    }
}

/// The card the sheet shows after you tap something on the map.
struct SelectedCard: View {
    var candidate: Candidate
    var now: Date
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                CategoryDot(category: candidate.category, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.title).display(20).lineLimit(2)
                    Text(candidate.kind == .gathering ? candidate.place : candidate.place.capitalized)
                        .font(.system(size: 14)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            InfoStrip(items: facts)
            Button(candidate.kind == .drop ? "See the menu" : "See details", action: open)
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var facts: [InfoStrip.Item] {
        let when = InfoStrip.Item(
            label: candidate.start <= now ? "On" : "Starts",
            value: candidate.start <= now ? "Now" : candidate.start.formatted(.dateTime.hour().minute()),
            detail: candidate.start <= now ? "until \(candidate.end.formatted(date: .omitted, time: .shortened))" : When.relative(candidate.start, now: now)
        )
        let walk = InfoStrip.Item(label: "Walk", value: "\(candidate.walkMinutes)", detail: "minutes")
        let third: InfoStrip.Item
        if let left = candidate.dropLeft, let total = candidate.dropTotal {
            third = .init(label: "Left", value: "\(left)", detail: "of \(total)")
        } else if candidate.capacity > 0 {
            third = .init(label: "Going", value: "\(candidate.going)", detail: "of \(candidate.capacity)")
        } else {
            third = .init(label: "Going", value: "\(candidate.going)", detail: "so far")
        }
        return [when, walk, third]
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
