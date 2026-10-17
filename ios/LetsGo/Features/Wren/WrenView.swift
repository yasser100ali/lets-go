import SwiftUI
import SwiftData

struct WrenView: View {
    @Environment(LocationService.self) private var location
    @Query private var gatherings: [Gathering]
    @Query private var kitchens: [Kitchen]
    @Query private var notes: [TasteNote]

    @State private var chat = WrenChat()
    @State private var input = ""
    @State private var draft: GatheringDraft?
    @State private var path = NavigationPath()
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(chat.messages) { m in
                                bubble(m).id(m.id)
                            }
                            if chat.thinking {
                                ProgressView().tint(Lamp.accent).padding(.leading, 8).id("thinking")
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: chat.messages.count) {
                        withAnimation { proxy.scrollTo(chat.messages.last?.id, anchor: .bottom) }
                    }
                }
                inputBar
            }
            .background(Lamp.bg)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .navigationDestination(for: Kitchen.self) { KitchenView(kitchen: $0) }
            .sheet(item: $draft) { NewGatheringView(draft: $0) }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Lamp.accentInk)
                .frame(width: 36, height: 36)
                .background(RadialGradient(colors: [Lamp.star, Lamp.accent], center: .topLeading, startRadius: 2, endRadius: 40), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text("Wren").font(.system(size: 17, weight: .bold))
                Text(chat.usesOnDeviceModel ? "Knows your block · on-device" : "Knows your block")
                    .font(.system(size: 12)).foregroundStyle(Lamp.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func bubble(_ m: ChatMessage) -> some View {
        switch m.role {
        case .you:
            Text(m.text)
                .font(.system(size: 15))
                .foregroundStyle(Lamp.accentInk)
                .padding(.horizontal, 13).padding(.vertical, 9)
                .background(Lamp.accent, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 6, topTrailingRadius: 18))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, 50)
        case .wren:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: m.text)
                    .font(.system(size: 15))
                    .padding(.horizontal, 13).padding(.vertical, 9)
                    .background(Lamp.surface, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18))
                    .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18).stroke(Lamp.line))
                    .padding(.trailing, 40)
                ForEach(m.picks) { p in
                    PickRow(index: 0, pick: p, now: .now) { open(p) }
                        .padding(.horizontal, 12)
                        .card(radius: 14)
                }
                if let d = m.draft { draftCard(d) }
            }
        }
    }

    private func draftCard(_ d: GatheringDraft) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Draft").eyebrow(Lamp.accent)
                Spacer()
                Label(d.category.label, systemImage: d.category.symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(d.category.color)
            }
            Text(d.title).font(.system(size: 16, weight: .bold))
            Text([When.short(d.start), d.placeName].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 13)).foregroundStyle(Lamp.muted)
            Button("Review and post") { draft = d }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Lamp.accentInk)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Lamp.accent, in: .capsule)
                .padding(.top, 2)
        }
        .padding(13)
        .background(Lamp.accent.opacity(0.06), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Lamp.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask Wren", text: $input, axis: .vertical)
                .lineLimit(1...4)
                .focused($focused)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Lamp.accentInk)
                    .frame(width: 32, height: 32)
                    .background(Lamp.accent, in: .circle)
            }
            .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.thinking)
        }
        .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func send() {
        let text = input
        input = ""
        let now = Date.now
        let candidates = Nearby.candidates(gatherings: gatherings, kitchens: kitchens, from: location.center, now: now)
        let taste = Nearby.taste(notes: notes, gatherings: gatherings, kitchens: kitchens)
        let visibleNotes = notes.filter { !$0.isHidden }.map(\.text)
        Task { await chat.send(text, candidates: candidates, taste: taste, notes: visibleNotes, now: now) }
    }

    private func open(_ p: Candidate) {
        switch p.kind {
        case .gathering: if let g = gatherings.first(where: { $0.id == p.id }) { path.append(g) }
        case .drop: if let k = kitchens.first(where: { $0.id == p.id }) { path.append(k) }
        }
    }
}
