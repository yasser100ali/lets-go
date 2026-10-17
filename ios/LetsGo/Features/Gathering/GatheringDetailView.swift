import SwiftUI
import SwiftData
import MapKit

struct GatheringDetailView: View {
    @Bindable var gathering: Gathering
    @Environment(LocationService.self) private var location
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allGatherings: [Gathering]
    @State private var earned: Stamp?
    @State private var confirmDelete = false

    /// Close enough to count as being there.
    private let checkInRadius: CLLocationDistance = 200

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VStack(alignment: .leading, spacing: 14) {
                        titleBlock(now: now)
                        capacityCard
                        if let note = wrenNote(now: now) { WrenNote(text: note) }
                        if !gathering.details.isEmpty {
                            Text(gathering.details).font(.system(size: 15)).foregroundStyle(Lamp.ink.opacity(0.9))
                        }
                        hostLine
                        checkInHint(now: now)
                        if gathering.isMine {
                            Button("Cancel this gathering", role: .destructive) { confirmDelete = true }
                                .font(.system(size: 14, weight: .semibold))
                                .padding(.top, 6)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
            }
            .background(Lamp.bg)
            .safeAreaInset(edge: .bottom) { actions(now: now) }
        }
        .ignoresSafeArea(edges: .top)
        .sheet(item: $earned) { StampEarnedView(stamp: $0) }
        .confirmationDialog("Cancel \(gathering.title)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Cancel it", role: .destructive) {
                context.delete(gathering)
                Ledger.save(context, "cancel gathering")
                dismiss()
            }
        } message: {
            Text("It comes off the map for everyone.")
        }
    }

    private var header: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: gathering.coordinate, distance: 900)), interactionModes: []) {
            UserAnnotation()
            Annotation("", coordinate: gathering.coordinate) {
                GlowPin(category: gathering.category, badge: nil, live: true)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 230)
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Lamp.bg], startPoint: .top, endPoint: .bottom).frame(height: 60)
        }
    }

    private func titleBlock(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(gathering.recurring.isEmpty ? gathering.category.label : "\(gathering.category.label) · \(gathering.recurring)")
                    .eyebrow(gathering.category.color)
                if gathering.isSample { SampleTag() }
            }
            Text(gathering.title).font(.display(28)).foregroundStyle(Lamp.ink)
            HStack(spacing: 14) {
                Label(gathering.placeName, systemImage: "mappin")
                Label(gathering.isLive(at: now) ? "On now, until \(gathering.end.formatted(date: .omitted, time: .shortened))" : When.short(gathering.start, now: now), systemImage: "clock")
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Lamp.muted)
            Text(Walk.label(location.center.distance(to: gathering.coordinate)))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Lamp.muted)
        }
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(gathering.capacity > 0 ? "\(gathering.going) of \(gathering.capacity) in" : "\(gathering.going) going")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                if let left = gathering.spotsLeft {
                    Text(left == 0 ? "Full" : "\(left) open")
                        .font(.label)
                        .foregroundStyle(left == 0 ? Lamp.muted : gathering.category.color)
                }
            }
            if gathering.capacity > 0 {
                SeatsBar(taken: gathering.going, capacity: gathering.capacity, color: gathering.category.color)
            }
            if !gathering.bring.isEmpty {
                Text("Bring: \(gathering.bring)").font(.system(size: 13)).foregroundStyle(Lamp.muted)
            }
        }
        .padding(14)
        .card()
    }

    private var hostLine: some View {
        HStack(spacing: 10) {
            Text(initials(gathering.hostName))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Lamp.bg)
                .frame(width: 34, height: 34)
                .background(gathering.category.color, in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(gathering.isMine ? "You're hosting" : "\(gathering.hostName) runs this").font(.system(size: 14, weight: .semibold))
                if !gathering.recurring.isEmpty {
                    Text(gathering.recurring).font(.system(size: 12)).foregroundStyle(Lamp.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func checkInHint(now: Date) -> some View {
        if gathering.checkedInAt != nil {
            Label("You showed up. Stamp collected.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(gathering.category.color)
        } else {
            Label("Check in when you're there to collect the \(gathering.placeName) stamp.", systemImage: "seal")
                .font(.system(size: 13))
                .foregroundStyle(Lamp.muted)
        }
    }

    private func actions(now: Date) -> some View {
        let distance = location.center.distance(to: gathering.coordinate)
        let canCheckIn = !location.isUsingFallback && distance <= checkInRadius && gathering.checkInOpen(at: now)
        return HStack(spacing: 10) {
            if gathering.checkedInAt != nil {
                Button("You're here") {}.buttonStyle(PrimaryButtonStyle(color: gathering.category.color)).disabled(true)
            } else if canCheckIn {
                Button("Check in") {
                    earned = Ledger.checkIn(gathering, context: context, now: now)
                }
                .buttonStyle(PrimaryButtonStyle(color: gathering.category.color))
            } else if gathering.isJoined {
                Button("You're in") {}
                    .buttonStyle(PrimaryButtonStyle(color: Lamp.raise))
                    .disabled(true)
                if !gathering.isMine {
                    Button("Leave") { Ledger.leave(gathering, context: context) }
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 15)
                        .card()
                }
            } else {
                Button(gathering.isFull ? "Full" : "I'm in") { Ledger.join(gathering, context: context) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(gathering.isFull)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Lamp.bg)
    }

    private func wrenNote(now: Date) -> String? {
        let sameKind = allGatherings.filter { $0.id != gathering.id && $0.category == gathering.category && $0.checkedInAt != nil }.count
        var parts: [String] = []
        if let left = gathering.spotsLeft, left > 0, left <= 3 {
            parts.append(left == 1 ? "They need **one more**." : "They need **\(left) more**.")
        }
        if sameKind > 0 {
            parts.append("You've shown up to \(sameKind) \(gathering.category.noun) before.")
        } else if gathering.going >= 6 {
            parts.append("Good one to try first: \(gathering.going) people, all from around here.")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

struct StampEarnedView: View {
    var stamp: Stamp
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            StampBadge(symbol: stamp.symbol, color: stamp.category.color, size: 120)
                .padding(.top, 30)
            Text("Stamp collected").eyebrow(stamp.category.color)
            Text(stamp.title).font(.display(26)).multilineTextAlignment(.center)
            Text("It's in your passport.").foregroundStyle(Lamp.muted)
            Spacer()
            Button("Nice") { dismiss() }.buttonStyle(PrimaryButtonStyle(color: stamp.category.color))
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Lamp.bg)
    }
}

struct StampBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 56
    var locked = false

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(locked ? 0.08 : 0.18))
            Circle()
                .stroke(color.opacity(locked ? 0.3 : 0.7), style: StrokeStyle(lineWidth: max(1.5, size / 40), dash: [size / 18, size / 22]))
                .padding(size * 0.07)
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(locked ? Lamp.muted : color)
        }
        .frame(width: size, height: size)
        .opacity(locked ? 0.6 : 1)
    }
}
