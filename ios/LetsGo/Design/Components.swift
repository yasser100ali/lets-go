import SwiftUI

/// The top picks on the map: Apple Maps' own marker shape, with a caption under it.
/// Tinted on Glass, ink on Paper.
struct MapMarker: View {
    var genre: Genre
    var caption: String
    var detail: String?
    var selected = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: genre.symbol)
                .font(.system(size: selected ? 16 : 13, weight: .semibold))
                .foregroundStyle(scheme == .dark ? .white : Palette.bg)
                .frame(width: selected ? 38 : 30, height: selected ? 38 : 30)
                .background(scheme == .dark ? genre.color : Palette.ink, in: .circle)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
            HStack(spacing: 3) {
                Text(caption).fontWeight(.semibold)
                if let detail { Text(detail).fontWeight(.medium).opacity(0.7) }
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink)
            .shadow(color: scheme == .dark ? .black.opacity(0.8) : .white, radius: 2)
            .fixedSize()
        }
        .animation(.snappy, value: selected)
        .accessibilityElement(children: .combine)
    }
}

/// Everything else on the map: a small dot. Hollow when it's later.
struct MapDot: View {
    var genre: Genre
    var later: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let fill = scheme == .dark ? genre.color : Palette.ink
        Circle()
            .fill(later ? Palette.bg : fill)
            .frame(width: 10, height: 10)
            .overlay(Circle().stroke(later ? fill : .white, lineWidth: later ? 1.5 : 1.5))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .padding(8)
            .contentShape(Circle())
            .accessibilityLabel(genre.label)
    }
}

/// The tinted circle at the start of a list row.
struct CategoryDot: View {
    var category: Genre
    var size: CGFloat = 36
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(scheme == .dark ? category.color : Palette.ink)
            .frame(width: size, height: size)
            .background(scheme == .dark ? category.color.opacity(0.2) : Palette.raise, in: .circle)
    }
}

/// A chip in the map's filter row.
struct FilterChip: View {
    var title: String
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14)
                .frame(height: 34)
                .foregroundStyle(on ? Palette.bg : Palette.ink)
                .background(on ? Palette.ink : Color.clear, in: .capsule)
                .glassEffect(on ? .identity : .regular.interactive(), in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// A warm out-of-focus "photo" for a kitchen until cooks upload their own.
struct PhotoHero: View {
    var kitchen: Kitchen
    var height: CGFloat = 220
    var radius: CGFloat = 0

    var body: some View {
        let hue = KitchenLook.hue(for: kitchen.cuisine)
        ZStack {
            Color(hue: hue, saturation: 0.55, brightness: 0.16)
            RadialGradient(colors: [Color(hue: hue, saturation: 0.55, brightness: 1).opacity(0.75), .clear], center: UnitPoint(x: 0.62, y: 0.46), startRadius: 4, endRadius: height * 0.75)
            RadialGradient(colors: [Color(hue: hue + 0.03, saturation: 0.7, brightness: 0.95).opacity(0.5), .clear], center: UnitPoint(x: 0.34, y: 0.62), startRadius: 2, endRadius: height * 0.45)
            RadialGradient(colors: [Color(hue: hue - 0.02, saturation: 0.3, brightness: 1).opacity(0.35), .clear], center: UnitPoint(x: 0.72, y: 0.72), startRadius: 2, endRadius: height * 0.3)
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: radius))
        .accessibilityHidden(true)
    }
}

enum KitchenLook {
    /// A hue that suits the food: tomato for pizza, pistachio for ice cream, corn for tamales.
    static func hue(for cuisine: String) -> Double {
        let c = cuisine.lowercased()
        let table: [(String, Double)] = [
            ("pizza", 0.05), ("ice cream", 0.92), ("tamal", 0.11), ("curry", 0.09), ("bread", 0.1), ("sourdough", 0.1),
            ("jollof", 0.03), ("bao", 0.08), ("bbq", 0.04), ("barbecue", 0.04), ("manakish", 0.13), ("cookie", 0.08),
            ("pho", 0.12), ("arepa", 0.14), ("dumpling", 0.07), ("taco", 0.06),
        ]
        return table.first { c.contains($0.0) }?.1 ?? 0.07
    }
}

/// App Store-style strip of three facts.
struct InfoStrip: View {
    struct Item: Identifiable {
        var id: String { label }
        var label: String
        var value: String
        var detail: String
    }

    var items: [Item]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                if i > 0 { Divider().overlay(Palette.line).frame(height: 36) }
                VStack(spacing: 2) {
                    Text(item.label).font(.system(size: 10, weight: .semibold)).textCase(.uppercase).foregroundStyle(Palette.muted)
                    Text(item.value).font(.system(size: 18, weight: .bold)).monospacedDigit()
                    Text(item.detail).font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
    }
}

/// One bar per spot: filled for taken, empty for open.
struct SeatsBar: View {
    var taken: Int
    var capacity: Int
    var color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(capacity, 1), id: \.self) { i in
                Capsule().fill(i < taken ? color : Palette.raise).frame(height: 5)
            }
        }
    }
}

struct LeftBar: View {
    var left: Int
    var total: Int
    var color: Color = Palette.ink

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raise)
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(total > 0 ? Double(total - left) / Double(total) : 0))
            }
        }
        .frame(height: 3)
    }
}

/// Footnote on a sample listing's page. Lists stay clean; the page says it once.
struct SampleNote: View {
    var body: some View {
        Label("Sample listing. Real ones appear as neighbors post.", systemImage: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(Palette.muted)
    }
}

struct Stars: View {
    var value: Double
    var size: CGFloat = 12

    var body: some View {
        HStack(spacing: 1) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= value + 0.25 ? "star.fill" : (Double(i) - 0.5 <= value ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
            }
        }
        .foregroundStyle(Palette.star)
        .accessibilityLabel(String(format: "%.1f stars", value))
    }
}

/// A short tip, set off from the page.
struct TipNote: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.top, 1)
            Text(markdown: text)
                .font(.system(size: 14))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .card(radius: 14)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.accentInk)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(color.opacity(isEnabled ? 1 : 0.35), in: .capsule)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 22)
            .frame(height: 52)
            .glassEffect(.regular.interactive(), in: .capsule)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension Text {
    /// Renders bold figures; falls back to plain text if the markdown is bad.
    init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}
