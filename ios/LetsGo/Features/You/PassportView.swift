import SwiftUI
import SwiftData

/// Your passport: stamps for places you showed up, and what you're into.
struct PassportView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocationService.self) private var location
    @Query(sort: \Stamp.earnedAt, order: .reverse) private var stamps: [Stamp]
    @Query(sort: \TasteNote.createdAt) private var notes: [TasteNote]
    @Query private var gatherings: [Gathering]
    @Query private var orders: [Order]

    @Environment(SyncStatus.self) private var sync
    @State private var newNote = ""
    @AppStorage(SampleNeighborhood.enabledKey) private var samplesOn = true
    @AppStorage(APIClient.nameKey) private var displayName = ""
    @AppStorage(APIConfig.overrideKey) private var serverURL = ""
    @AppStorage(Appearance.storageKey) private var appearance: Appearance = .system

    /// Stamps you can work toward, shown locked until earned.
    private let goals: [(key: String, title: String, symbol: String, category: Genre)] = [
        ("first-checkin", "First show-up", "figure.wave", .play),
        ("first-host", "Hosted one", "flag.fill", .party),
        ("opened-kitchen", "Opened a kitchen", "house.fill", .food),
        ("first-review", "First review", "text.bubble.fill", .food),
        ("checkins-5", "Five show-ups", "star.circle", .move),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Your passport").eyebrow()
                        Text("Around here").display(28)
                    }
                    counts
                    stampGrid
                    knows
                    appearancePicker
                    sampleSettings
                    serverSettings
                }
                .padding(18)
            }
            .background(Palette.bg)
        }
    }

    private var counts: some View {
        let showUps = gatherings.filter { $0.checkedInAt != nil }.count
        let joined = gatherings.filter(\.isJoined).count
        let kitchensTried = Set(orders.compactMap { $0.kitchen?.id }).count
        return HStack(spacing: 8) {
            count("\(showUps)", "show-ups")
            count("\(joined)", "joined")
            count("\(kitchensTried)", "kitchens tried")
        }
    }

    private func count(_ v: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v).display(22).monospacedDigit()
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.muted)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }

    private var stampGrid: some View {
        let earnedKeys = Set(stamps.map(\.key))
        let locked = goals.filter { !earnedKeys.contains($0.key) }
        return VStack(alignment: .leading, spacing: 12) {
            Text("Stamps").eyebrow()
            if stamps.isEmpty {
                Text("Show up to something on the map and check in when you're there. Stamps only count in person.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 14) {
                ForEach(stamps) { s in
                    stampCell(StampBadge(symbol: s.symbol, color: s.category.color), s.title, dim: false)
                }
                ForEach(locked, id: \.key) { g in
                    stampCell(StampBadge(symbol: g.symbol, color: g.category.color, locked: true), g.title, dim: true)
                }
            }
        }
    }

    private func stampCell(_ badge: StampBadge, _ title: String, dim: Bool) -> some View {
        VStack(spacing: 5) {
            badge
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(dim ? Palette.muted : Palette.ink)
        }
    }

    private var knows: some View {
        let visible = notes.filter { !$0.isHidden }
        return VStack(alignment: .leading, spacing: 10) {
            Text("What you're into").eyebrow()
            if visible.isEmpty {
                Text("Nothing yet. This fills in from what you join, show up to and order, and it shapes what the map shows first.")
                    .font(.system(size: 14)).foregroundStyle(Palette.muted)
            }
            FlowLayout(spacing: 7) {
                ForEach(visible) { n in
                    HStack(spacing: 6) {
                        if let c = n.category { Image(systemName: c.symbol).font(.system(size: 10, weight: .bold)).foregroundStyle(c.color) }
                        Text(n.text).font(.system(size: 13, weight: .semibold))
                        Button {
                            n.isHidden = true
                            Ledger.save(context, "forget note")
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.muted)
                                .frame(width: 18, height: 18).background(Palette.raise, in: .circle)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Forget \(n.text)")
                    }
                    .padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 5)
                    .card(radius: 999)
                }
            }
            HStack {
                TextField("Add one, like \"pickup basketball\"", text: $newNote)
                    .font(.system(size: 14))
                    .onSubmit(addNote)
                Button("Add", action: addNote).disabled(newNote.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .card(radius: 14)
        }
    }

    private var appearancePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Appearance").eyebrow()
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Glass is the dark look, Paper the light one. Match phone follows your phone's setting.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
        }
        .padding(14)
        .card()
    }

    private var sampleSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample neighborhood").eyebrow()
            Toggle("Show sample things nearby", isOn: $samplesOn)
                .font(.system(size: 15))
                .onChange(of: samplesOn) { _, on in
                    if on {
                        let center = location.center
                        Task { await SampleNeighborhood.seed(around: center, context: context) }
                    } else {
                        SampleNeighborhood.clear(context: context)
                    }
                }
            Text("Until neighbors post for real, example games and kitchens are placed around you so the map isn't empty. They're placed at real parks, courts and cafés near you, and each page says it's a sample.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted)
            if samplesOn {
                Button("Refresh samples around me") {
                    let center = location.center
                    Task { await SampleNeighborhood.seed(around: center, context: context) }
                }
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .padding(14)
        .card()
    }

    private var serverSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Server").eyebrow()
            TextField("Your name, as neighbors see it", text: $displayName)
                .font(.system(size: 15))
                .textContentType(.givenName)
                .submitLabel(.done)
                .onSubmit {
                    let name = displayName
                    Task { await sync.run { () throws(APIError) in try await Sync.saveName(name) } }
                }
            TextField("Server address, like https://….ngrok.app", text: $serverURL)
                .font(.system(size: 14, design: .monospaced))
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Text(serverLine)
                .font(.system(size: 12))
                .foregroundStyle(sync.problem == nil ? Palette.muted : Genre.food.color)
            if APIConfig.isConfigured {
                Button(sync.syncing ? "Syncing…" : "Sync now") {
                    let center = location.center
                    Task { await sync.run { () throws(APIError) in try await Sync.refresh(around: center, context: context) } }
                }
                .font(.system(size: 14, weight: .semibold))
                .disabled(sync.syncing)
            }
        }
        .padding(14)
        .card()
    }

    private var serverLine: String {
        if !APIConfig.isConfigured { return "No server: everything stays on this phone, and only you see what you post." }
        if let problem = sync.problem { return problem }
        if let at = sync.lastSynced { return "Synced \(at.formatted(date: .omitted, time: .shortened)). What you post reaches people nearby." }
        return "Not synced yet."
    }

    private func addNote() {
        let text = newNote.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let q = SearchQuery.parse(text)
        context.insert(TasteNote(key: "said:\(text.lowercased())", text: text, category: q.categories.first))
        Ledger.save(context, "add note")
        newNote = ""
    }
}
