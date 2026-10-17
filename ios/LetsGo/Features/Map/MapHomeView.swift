import SwiftUI
import SwiftData
import MapKit

/// Home. The night map of what's on within walking distance, with Wren's
/// one line and the top picks on the panel at the bottom.
struct MapHomeView: View {
    @Environment(LocationService.self) private var location
    @Query(sort: \Gathering.start) private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    @State private var path = NavigationPath()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var filter: MapFilter = .now
    @State private var hosting = false

    /// Ten minutes' walk.
    private let walkRadius: CLLocationDistance = 800

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                let now = timeline.date
                ZStack(alignment: .top) {
                    map(now: now)
                    topBar
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    panel(now: now)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .navigationDestination(for: Kitchen.self) { KitchenView(kitchen: $0) }
            .sheet(isPresented: $hosting) { NewGatheringView(draft: nil) }
        }
    }

    // MARK: Map

    private func map(now: Date) -> some View {
        Map(position: $position) {
            UserAnnotation()
            MapCircle(center: location.center, radius: walkRadius)
                .foregroundStyle(Lamp.me.opacity(0.06))
                .stroke(Lamp.me.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))

            ForEach(visibleGatherings(now: now)) { g in
                Annotation(g.title, coordinate: g.coordinate, anchor: .center) {
                    Button { path.append(g) } label: {
                        GlowPin(
                            category: g.category,
                            badge: g.capacity > 0 ? "\(g.going)/\(g.capacity)" : (g.going > 0 ? "\(g.going)" : nil),
                            live: g.isLive(at: now) || g.start.timeIntervalSince(now) < 45 * 60,
                            later: g.start.timeIntervalSince(now) > 90 * 60,
                            mine: g.isJoined
                        )
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }

            ForEach(visibleKitchens(now: now)) { k in
                let drop = k.nextDrop(after: now)
                Annotation(k.name, coordinate: k.coordinate, anchor: .center) {
                    Button { path.append(k) } label: {
                        GlowPin(
                            category: .food,
                            badge: drop.map { $0.isSoldOut ? "sold out" : "\($0.left) left" },
                            live: drop.map { $0.isLive(at: now) || $0.start.timeIntervalSince(now) < 30 * 60 } ?? false,
                            later: drop.map { $0.start.timeIntervalSince(now) > 90 * 60 } ?? true,
                            mine: k.isMine
                        )
                    }
                    .buttonStyle(.plain)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .ignoresSafeArea(edges: .top)
    }

    private func visibleGatherings(now: Date) -> [Gathering] {
        gatherings.filter { g in
            guard !g.hasEnded(at: now) else { return false }
            switch filter {
            case .now: return g.start.timeIntervalSince(now) <= Wren.horizon
            case .later: return true
            case .category(let c): return g.category == c
            }
        }
    }

    private func visibleKitchens(now: Date) -> [Kitchen] {
        kitchens.filter { k in
            switch filter {
            case .now:
                guard let d = k.nextDrop(after: now) else { return false }
                return d.start.timeIntervalSince(now) <= Wren.horizon
            case .later: return k.nextDrop(after: now) != nil || k.isMine
            case .category(let c): return c == .food
            }
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "location.fill").foregroundStyle(Lamp.accent)
                    Text(location.isUsingFallback ? "Sample neighborhood · SF" : "Within a 10-min walk")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .glassEffect(.regular, in: .rect(cornerRadius: 16))

                Button { hosting = true } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Lamp.accentInk)
                        .frame(width: 44, height: 44)
                        .background(Lamp.accent, in: .rect(cornerRadius: 14))
                }
                .accessibilityLabel("Host something")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    FilterChip(title: "Now", symbol: nil, on: filter == .now) { filter = .now }
                    ForEach([Genre.play, .move, .music, .party, .food]) { c in
                        FilterChip(title: c.label, symbol: c.symbol, on: filter == .category(c)) {
                            filter = filter == .category(c) ? .now : .category(c)
                        }
                    }
                    FilterChip(title: "Later", symbol: "calendar", on: filter == .later) { filter = .later }
                }
                .padding(.horizontal, 16)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    // MARK: Panel

    private func panel(now: Date) -> some View {
        let here = location.center
        let candidates = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: here, now: now)
        let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
        let picks = Wren.picks(candidates, now: now, taste: taste)

        return VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(Lamp.muted.opacity(0.4)).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkles").foregroundStyle(Lamp.accent).font(.system(size: 15, weight: .semibold)).padding(.top, 3)
                Text(markdown: Wren.line(picks, now: now))
                    .font(.system(size: 17, weight: .semibold).width(.standard))
                    .foregroundStyle(Lamp.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(Array(picks.enumerated()), id: \.element.id) { i, pick in
                    PickRow(index: i + 1, pick: pick, now: now) { open(pick) }
                    if i < picks.count - 1 { Divider().overlay(Lamp.line) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Lamp.bg, in: UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26))
        .shadow(color: .black.opacity(0.35), radius: 20, y: -6)
    }

    private func open(_ pick: Candidate) {
        switch pick.kind {
        case .gathering:
            if let g = gatherings.first(where: { $0.id == pick.id }) { path.append(g) }
        case .drop:
            if let k = kitchens.first(where: { $0.id == pick.id }) { path.append(k) }
        }
    }
}

enum MapFilter: Equatable {
    case now, later
    case category(Genre)
}

struct PickRow: View {
    var index: Int
    var pick: Candidate
    var now: Date
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                CategoryDot(category: pick.category, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(pick.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if pick.isSample { SampleTag() }
                    }
                    Text(Wren.reason(pick, now: now))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Lamp.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                Text(pick.start <= now ? "on now" : When.short(pick.start, now: now))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(pick.start <= now ? pick.category.color : Lamp.ink)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
