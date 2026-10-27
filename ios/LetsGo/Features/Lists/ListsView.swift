import SwiftUI
import SwiftData
import CoreLocation

/// The city list, every place a San Franciscan should go once, closest first, with
/// what you've stamped and how far along you are. Pushed from Passport and Plans,
/// whose stacks show its places (`Spot`) and gatherings.
struct ListsView: View {
    @Environment(LocationService.self) private var location
    @Query(sort: \Stamp.earnedAt) private var stamps: [Stamp]
    @State private var bucket: Spot.Bucket?

    var body: some View {
        let done = Spots.stamped(stamps)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                progressCard(done: done)
                filters
                list(done: done)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .background(Palette.bg)
        .navigationTitle("Know your city")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func progressCard(done: [String: Date]) -> some View {
        let spots = Spots.all
        let doneIDs = Set(done.keys)
        let areas = Set(spots.map(\.area))
        let areasBeen = Set(spots.filter { doneIDs.contains($0.id) }.map(\.area))
        let thisMonth = done.values.filter { Calendar.current.isDate($0, equalTo: .now, toGranularity: .month) }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                ProgressRing(done: doneIDs.count, total: spots.count)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your city").eyebrow(Palette.accent)
                    Text(Spots.listTitle).display(22).foregroundStyle(Palette.ink)
                    Text(doneIDs.isEmpty
                         ? "Go to one and check in when you're there."
                         : "\(thisMonth) this month. You've been to \(areasBeen.count) of \(areas.count) neighborhoods on it.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                ForEach(Spots.progress(spots, done: doneIDs)) { p in
                    VStack(alignment: .leading, spacing: 5) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.line)
                                Capsule()
                                    .fill(color(p.bucket))
                                    .frame(width: geo.size.width * (p.total > 0 ? CGFloat(p.done) / CGFloat(p.total) : 0))
                            }
                        }
                        .frame(height: 5)
                        Text(p.bucket.label).font(.system(size: 11, weight: .bold)).foregroundStyle(Palette.ink)
                        Text("\(p.done) of \(p.total)").font(.system(size: 11)).foregroundStyle(Palette.muted).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(18)
        .card(radius: 24)
    }

    private func color(_ b: Spot.Bucket) -> Color {
        switch b {
        case .outdoors: Spot.Kind.hike.color
        case .food: Spot.Kind.food.color
        case .culture: Spot.Kind.culture.color
        case .night: Spot.Kind.night.color
        }
    }

    private var filters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                FilterChip(title: "All", on: bucket == nil) { bucket = nil }
                ForEach(Spot.Bucket.allCases) { b in
                    FilterChip(title: b.label, on: bucket == b) { bucket = bucket == b ? nil : b }
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func list(done: [String: Date]) -> some View {
        let shown = Spots.all.filter { bucket == nil || $0.kind.bucket == bucket }
        let todo = Spots.closest(shown.filter { done[$0.id] == nil }, to: location.center)
        let been = shown.filter { done[$0.id] != nil }.sorted { (done[$0.id] ?? .distantPast) > (done[$1.id] ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 18) {
            if !todo.isEmpty {
                section(location.isUsingFallback ? "Still to go" : "Closest first", todo, done: done)
            }
            if !been.isEmpty {
                section("Been there", been, done: done)
            }
        }
    }

    private func section(_ title: String, _ spots: [Spot], done: [String: Date]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 20, weight: .bold))
                Spacer()
                Text("\(spots.count)").font(.system(size: 15)).foregroundStyle(Palette.muted)
            }
            .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(spots.enumerated()), id: \.element.id) { i, s in
                    NavigationLink(value: s) {
                        SpotRow(spot: s, stampedAt: done[s.id], meters: location.center.distance(to: s.coordinate))
                    }
                    .buttonStyle(.plain)
                    if i < spots.count - 1 { Divider().overlay(Palette.line).padding(.leading, 58) }
                }
            }
            .card(radius: 20)
        }
    }
}

/// A place on the list: done or not, what it is, how far.
struct SpotRow: View {
    var spot: Spot
    var stampedAt: Date?
    var meters: Double

    var body: some View {
        HStack(spacing: 12) {
            if stampedAt != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Palette.bg)
                    .frame(width: 30, height: 30)
                    .background(Palette.live, in: .circle)
            } else {
                Image(systemName: spot.kind.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(spot.kind.color)
                    .frame(width: 30, height: 30)
                    .background(spot.kind.color.opacity(0.16), in: .circle)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(spot.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(stampedAt == nil ? Palette.ink : Palette.muted)
                    .lineLimit(1)
                Text(detail).font(.system(size: 12)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.muted.opacity(0.7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var detail: String {
        if let stampedAt { return "Stamped \(stampedAt.formatted(date: .abbreviated, time: .omitted)) · \(spot.area)" }
        return "\(spot.kind.label) · \(spot.area) · \(Walk.label(meters))"
    }
}
