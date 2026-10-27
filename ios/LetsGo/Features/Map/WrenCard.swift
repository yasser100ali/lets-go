import SwiftUI

/// Wren's line on a glass sheet over the map: the one thing worth going to, why, and
/// when to leave, with "I'm in" right there. "Not tonight" moves on to the next one.
/// Drag it up, or tap the handle, for the whole list.
struct WrenCard: View {
    var picks: [Candidate]
    var now: Date
    var busy: Bool
    var onOpen: (Candidate) -> Void
    var onJoin: (Candidate) -> Void
    var onSkip: (Candidate) -> Void
    var onList: () -> Void
    var onHost: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.28))
                .frame(width: 36, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                .onTapGesture(perform: onList)
                .accessibilityLabel("Show everything nearby")
                .accessibilityAddTraits(.isButton)
            header
            if let top = picks.first {
                line(HomeLine.sentence(for: top, now: now))
                    .onTapGesture { onOpen(top) }
                    .accessibilityAddTraits(.isButton)
                    .padding(.top, 10)
                actions(top)
                    .padding(.top, 14)
                if let next = picks.dropFirst().first {
                    NextRow(pick: next, now: now) { onOpen(next) }
                        .padding(.top, 14)
                        .mask(LinearGradient(colors: [.black, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                }
            } else {
                line(HomeLine.quiet).padding(.top, 10)
                Button(action: onHost) { Label("Host something", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .glassPanel(radius: 34)
        .gesture(DragGesture(minimumDistance: 24).onEnded { v in
            if v.translation.height < -30 { onList() }
        })
    }

    private var header: some View {
        HStack(spacing: 8) {
            WrenOrb(size: 26)
            Text("WREN")
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Palette.accentSoft)
            if picks.first?.isSample == true { SampleTag() }
            Spacer()
            if let top = picks.first, top.kind == .gathering {
                Text(verbatim: count(top))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.soft)
            }
        }
        .frame(height: 26)
    }

    private func count(_ c: Candidate) -> String {
        if c.capacity > 0 { return "\(c.going) of \(c.capacity)" }
        return c.going > 0 ? "\(c.going) going" : ""
    }

    private func line(_ l: HomeLine.Line) -> some View {
        Text("\(l.lead)\(Text(l.emphasis).foregroundStyle(Palette.accentSoft))\(l.tail)")
            .font(.system(size: 18, weight: .semibold))
            .tracking(-0.2)
            .lineSpacing(2)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actions(_ top: Candidate) -> some View {
        HStack(spacing: 10) {
            switch top.kind {
            case .gathering:
                if top.isJoined {
                    Button("You're in") { onOpen(top) }
                        .buttonStyle(PrimaryButtonStyle(color: Palette.accent.opacity(0.18), ink: Palette.accentSoft))
                } else {
                    Button(top.spotsLeft == 0 ? "Full" : "I'm in") { onJoin(top) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(top.spotsLeft == 0 || busy)
                }
            case .drop:
                Button("Reserve a pickup") { onOpen(top) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Button("Not tonight") { onSkip(top) }
                .buttonStyle(SecondaryButtonStyle())
        }
        .sensoryFeedback(.success, trigger: top.isJoined)
    }
}

/// The next pick under Wren's line, half faded: there if the first isn't it.
private struct NextRow: View {
    var pick: Candidate
    var now: Date
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                CategoryDot(category: pick.category, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(pick.title).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        if pick.isSample { SampleTag() }
                    }
                    Text(Picks.reason(pick, now: now))
                        .font(.system(size: 13))
                        .monospacedDigit()
                        .foregroundStyle(Palette.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text("\(pick.walkMinutes) min")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Palette.soft)
            }
            .foregroundStyle(Palette.ink)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The small outlined "Sample" on anything that stands in for a real person or listing.
struct SampleTag: View {
    var text = "Sample"

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.16)))
            .fixedSize()
    }
}
