import SwiftUI
import SwiftData

/// A house that's a restaurant tonight: its drop, menu and reviews.
struct KitchenView: View {
    @Bindable var kitchen: Kitchen
    @Environment(LocationService.self) private var location
    @State private var bag: [UUID: Int] = [:]
    @State private var ordering = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let now = timeline.date
            let drop = kitchen.nextDrop(after: now)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HouseHero(sign: "\(kitchen.cuisine) tonight")
                    VStack(alignment: .leading, spacing: 16) {
                        titleBlock
                        if let drop { dropCard(drop, now: now) } else { noDrop }
                        menu(drop: drop, now: now)
                        reviews
                    }
                    .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
            }
            .background(Lamp.bg)
            .safeAreaInset(edge: .bottom) {
                if bagCount > 0, let drop, !drop.isSoldOut {
                    Button("Order \(bagCount) · \(Pricing.format(bagSubtotal))") { ordering = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Lamp.bg)
                }
            }
            .sheet(isPresented: $ordering) {
                if let drop { OrderView(kitchen: kitchen, drop: drop, bag: $bag) }
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Home kitchen\(kitchen.permitConfirmed ? " · permitted" : "")").eyebrow(Genre.food.color)
                if kitchen.isSample { SampleTag() }
            }
            Text(kitchen.name).font(.display(27))
            HStack(spacing: 6) {
                if let r = kitchen.rating {
                    Stars(value: r)
                    Text(String(format: "%.1f", r)).fontWeight(.bold)
                    Text("· \(kitchen.reviewCount) reviews").foregroundStyle(Lamp.muted)
                } else {
                    Text("New kitchen").foregroundStyle(Lamp.muted)
                }
                if kitchen.regulars > 0 { Text("· \(kitchen.regulars) regulars").foregroundStyle(Lamp.muted) }
            }
            .font(.system(size: 13))
            Text(kitchen.story).font(.system(size: 15)).foregroundStyle(Lamp.ink.opacity(0.9)).padding(.top, 4)
            HStack(spacing: 14) {
                Label(Walk.label(location.center.distance(to: kitchen.coordinate)), systemImage: "figure.walk")
                if kitchen.porchTables > 0 { Label("\(kitchen.porchTables) porch tables", systemImage: "chair.lounge") }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Lamp.muted)
        }
    }

    private func dropCard(_ drop: Drop, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(drop.isLive(at: now) ? "Drop is on · until \(drop.end.formatted(date: .omitted, time: .shortened))" : "Next drop · \(When.short(drop.start, now: now))")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(drop.isSoldOut ? "SOLD OUT" : "\(drop.left) / \(drop.total) LEFT")
                    .font(.label)
                    .foregroundStyle(drop.isSoldOut ? Lamp.muted : Genre.food.color)
            }
            LeftBar(left: drop.left, total: drop.total)
            if !drop.isLive(at: now) && !drop.isSoldOut {
                Text("Reserve now, pick up when it opens.").font(.system(size: 12)).foregroundStyle(Lamp.muted)
            }
        }
        .padding(14)
        .card()
    }

    private var noDrop: some View {
        Text("No drop scheduled. Follow along and you'll hear about the next one.")
            .font(.system(size: 14))
            .foregroundStyle(Lamp.muted)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }

    private func menu(drop: Drop?, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Menu").eyebrow().padding(.bottom, 6)
            ForEach(kitchen.sortedMenu) { item in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 15, weight: .semibold))
                        if !item.note.isEmpty { Text(item.note).font(.system(size: 12)).foregroundStyle(Lamp.muted) }
                    }
                    Spacer()
                    Text(Pricing.format(item.priceCents)).font(.system(size: 14, weight: .semibold, design: .monospaced))
                    if let drop, !drop.isSoldOut, !kitchen.isMine {
                        Stepperish(count: bag[item.id] ?? 0, max: drop.left - bagCount + (bag[item.id] ?? 0)) { bag[item.id] = $0 }
                    }
                }
                .padding(.vertical, 10)
                Divider().overlay(Lamp.line)
            }
        }
    }

    @ViewBuilder
    private var reviews: some View {
        let mine = kitchen.reviews.sorted { $0.createdAt > $1.createdAt }
        if !mine.isEmpty || !kitchen.sampleReviews.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Reviews").eyebrow()
                ForEach(mine) { r in ReviewCard(stars: r.stars, text: r.text, author: r.isMine ? "You" : r.author, tags: r.tags) }
                ForEach(kitchen.sampleReviews, id: \.self) { r in ReviewCard(stars: r.stars, text: r.text, author: r.author, tags: []) }
            }
        }
    }

    private var bagCount: Int { bag.values.reduce(0, +) }

    private var bagSubtotal: Int {
        kitchen.menu.reduce(0) { $0 + $1.priceCents * (bag[$1.id] ?? 0) }
    }
}

struct ReviewCard: View {
    var stars: Int
    var text: String
    var author: String
    var tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(author).font(.system(size: 13, weight: .bold))
                Stars(value: Double(stars), size: 10)
            }
            if !text.isEmpty { Text(text).font(.system(size: 14)) }
            if !tags.isEmpty {
                Text(tags.joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(Lamp.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }
}

/// A compact minus / count / plus.
struct Stepperish: View {
    var count: Int
    var max: Int
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 8) {
            if count > 0 {
                button("minus") { onChange(count - 1) }
                Text("\(count)").font(.system(size: 14, weight: .bold, design: .monospaced)).frame(minWidth: 12)
            }
            button("plus") { onChange(count + 1) }.disabled(count >= max)
        }
    }

    private func button(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(symbol == "plus" ? Lamp.accent : Lamp.raise, in: .rect(cornerRadius: 9))
                .foregroundStyle(symbol == "plus" ? Lamp.accentInk : Lamp.ink)
        }
        .buttonStyle(.plain)
    }
}
