import SwiftUI
import SwiftData

/// The bar above the tab bar, like Music's mini player: how many things are on now
/// and what they are. Tap it to open the list.
struct NowBar: View {
    @Environment(HomeModel.self) private var model
    @Environment(LocationService.self) private var location
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Query(sort: \Gathering.start) private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let now = timeline.date
            let all = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: location.center, now: now)
            let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
            let picks = Picks.picks(all, now: now, taste: taste, limit: 40)
            let on = picks.filter { $0.start <= now }
            Button { model.showList() } label: {
                HStack(spacing: 10) {
                    Text("\(on.isEmpty ? picks.count : on.count)")
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(on.isEmpty ? Palette.accent : Palette.live)
                        .frame(width: 30, height: 30)
                        .background((on.isEmpty ? Palette.accent : Palette.live).opacity(0.18), in: .circle)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title(on: on.count, soon: picks.count))
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                        if placement != .inline {
                            Text(names(on.isEmpty ? picks : on))
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.horizontal, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(title(on: on.count, soon: picks.count)). Show the list.")
        }
    }

    private func title(on: Int, soon: Int) -> String {
        if on > 0 { return "On now near you" }
        if soon > 0 { return "Coming up near you" }
        return "Nothing on right now"
    }

    private func names(_ items: [Candidate]) -> String {
        guard !items.isEmpty else { return "See what's on tonight and this weekend" }
        let first = items.prefix(2).map(\.title).joined(separator: " · ")
        return items.count > 2 ? "\(first) · +\(items.count - 2)" : first
    }
}
