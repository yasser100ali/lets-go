import SwiftUI
import SwiftData

/// Wren's tab: say what you're in the mood for and get real things nearby, or say
/// "host …" and get a draft to post.
struct WrenView: View {
    @Environment(LocationService.self) private var location
    @Query(sort: \Gathering.start) private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    @State private var input = ""
    @State private var exchanges: [Exchange] = []
    @State private var draft: GatheringDraft?
    @State private var path = NavigationPath()
    @FocusState private var focused: Bool

    struct Exchange: Identifiable {
        var id = UUID()
        var question: String
        var answer: Wren.Answer
    }

    private let suggestions = ["Something chill tonight under $15", "Live music this weekend", "Pickup game in the next hour", "Host a slow jog Saturday 8am"]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        WrenHeader()
                        if exchanges.isEmpty {
                            Text(Wren.hello)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(suggestions, id: \.self) { s in
                                    Button { ask(s) } label: {
                                        Text(s)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color(hex: 0xE4E0E9))
                                            .padding(.horizontal, 14)
                                            .frame(height: 36)
                                            .background(Color.white.opacity(0.06), in: .capsule)
                                            .overlay(Capsule().stroke(Color.white.opacity(0.14)))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        ForEach(exchanges) { e in
                            exchange(e).id(e.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .onChange(of: exchanges.count) {
                    if let last = exchanges.last?.id { withAnimation { proxy.scrollTo(last, anchor: .top) } }
                }
            }
            .safeAreaInset(edge: .bottom) { inputBar }
            .background(Palette.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .navigationDestination(for: Kitchen.self) { KitchenView(kitchen: $0) }
            .navigationDestination(for: Order.self) { OrderStatusView(order: $0) }
            .sheet(item: $draft) { NewGatheringView(draft: $0) }
        }
    }

    private func exchange(_ e: Exchange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            YouBubble(text: e.question)
            Text(e.answer.reply)
                .font(.system(size: 19, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if !e.answer.picks.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(e.answer.picks.enumerated()), id: \.element.id) { i, p in
                        PickRow(pick: p, now: .now) { open(p) }
                            .padding(.horizontal, 14)
                        if i < e.answer.picks.count - 1 { Divider().overlay(Palette.line).padding(.leading, 66) }
                    }
                }
                .card(radius: 22)
            }
            if let d = e.answer.draft { DraftCard(draft: d) { draft = d } }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("What are you in the mood for?", text: $input, axis: .vertical)
                .lineLimit(1...3)
                .font(.system(size: 16))
                .focused($focused)
                .submitLabel(.send)
                .onSubmit { ask(input) }
            Button { ask(input) } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Palette.accentInk)
                    .frame(width: 42, height: 42)
                    .background(Palette.accent, in: .circle)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Ask Wren")
        }
        .padding(.leading, 18)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.07), in: .rect(cornerRadius: 27))
        .overlay(RoundedRectangle(cornerRadius: 27).stroke(Color.white.opacity(0.14)))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func ask(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        let now = Date.now
        let candidates = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: location.center, now: now)
        let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
        let answer = Wren.answer(text, candidates: candidates, taste: taste, now: now)
        withAnimation(.snappy) { exchanges.append(Exchange(question: text, answer: answer)) }
    }

    private func open(_ p: Candidate) {
        switch p.kind {
        case .gathering: if let g = gatherings.first(where: { $0.id == p.id }) { path.append(g) }
        case .drop: if let k = kitchens.first(where: { $0.id == p.id }) { path.append(k) }
        }
    }
}

/// Wren's name plate at the top of its tab.
struct WrenHeader: View {
    var body: some View {
        HStack(spacing: 12) {
            WrenOrb(size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text("Wren").font(.poster(26, weight: .black))
                Text("Does the logistics. You show up.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: 0xB5B0BF))
            }
            Spacer()
        }
        .padding(.top, 6)
    }
}

/// What you said, in an ember bubble on the right.
struct YouBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Palette.accentInk)
            .padding(.horizontal, 15)
            .padding(.vertical, 11)
            .background(Palette.accent, in: UnevenRoundedRectangle(topLeadingRadius: 22, bottomLeadingRadius: 22, bottomTrailingRadius: 6, topTrailingRadius: 22))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, 60)
    }
}

/// A gathering Wren drafted, ready to check and post.
struct DraftCard: View {
    var draft: GatheringDraft
    var action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Draft").eyebrow(Palette.accentSoft)
                Spacer()
                Label(draft.category.label, systemImage: draft.category.symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(draft.category.color)
            }
            Text(draft.title).font(.system(size: 17, weight: .bold))
            Text([When.short(draft.start), draft.placeName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
            Button("Review and post", action: action)
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, 6)
        }
        .padding(16)
        .background(Palette.accent.opacity(0.08), in: .rect(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }
}
