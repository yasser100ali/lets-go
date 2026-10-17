import SwiftUI

/// A map pin that glows. Live things pulse; later things sit dimmer and smaller.
struct GlowPin: View {
    var category: Genre
    var badge: String?
    var live: Bool
    var later: Bool = false
    var mine: Bool = false

    private var size: CGFloat { later ? 28 : 36 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if live && !later { PulseRing(color: category.color) }
                Circle()
                    .fill(category.color)
                    .frame(width: size, height: size)
                    .shadow(color: category.color.opacity(0.55), radius: later ? 4 : 12)
                    .overlay(Circle().stroke(category.color.opacity(0.25), lineWidth: 5).padding(-5))
                Image(systemName: category.symbol)
                    .font(.system(size: later ? 13 : 16, weight: .bold))
                    .foregroundStyle(Lamp.bg)
            }
            .frame(width: size, height: size)
            .opacity(later ? 0.85 : 1)
            if let badge {
                Text(badge)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(category.color)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Lamp.bg, in: .capsule)
                    .overlay(Capsule().stroke(category.color, lineWidth: 1.2))
                    .fixedSize()
                    .offset(x: 14, y: -8)
            }
            if mine {
                Circle().fill(Lamp.accent).frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Lamp.bg, lineWidth: 2))
                    .offset(x: 2, y: size - 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(category.label + (badge.map { ", \($0)" } ?? ""))
    }
}

struct PulseRing: View {
    var color: Color
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 2)
            .frame(width: 40, height: 40)
            .scaleEffect(on ? 2.0 : 1)
            .opacity(on ? 0 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { on = true }
            }
    }
}

struct CategoryDot: View {
    var category: Genre
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(category.color)
            .frame(width: size, height: size)
            .background(category.color.opacity(0.16), in: .rect(cornerRadius: size * 0.32))
    }
}

struct FilterChip: View {
    var title: String
    var symbol: String?
    var on: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .bold)) }
                Text(title).font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(on ? Lamp.bg : Lamp.ink)
            .background(on ? Lamp.ink : Color.clear, in: .capsule)
            .glassEffect(on ? .identity : .regular, in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// One bar per spot: filled for taken, dim for open.
struct SeatsBar: View {
    var taken: Int
    var capacity: Int
    var color: Color

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(capacity, 1), id: \.self) { i in
                RoundedRectangle(cornerRadius: 3)
                    .fill(i < taken ? color : Lamp.raise)
                    .frame(height: 8)
            }
        }
    }
}

struct LeftBar: View {
    var left: Int
    var total: Int
    var color: Color = Genre.food.color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Lamp.raise)
                Capsule().fill(color)
                    .frame(width: geo.size.width * CGFloat(total > 0 ? Double(total - left) / Double(total) : 0))
            }
        }
        .frame(height: 6)
    }
}

struct SampleTag: View {
    var body: some View {
        Text("Sample")
            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
            .textCase(.uppercase)
            .foregroundStyle(Lamp.muted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().stroke(Lamp.muted.opacity(0.5)))
            .accessibilityLabel("Sample listing")
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
        .foregroundStyle(Lamp.star)
        .accessibilityLabel(String(format: "%.1f stars", value))
    }
}

/// A line from Wren, set off with its spark.
struct WrenNote: View {
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Lamp.accent)
                .padding(.top, 1)
            Text(markdown: text)
                .font(.system(size: 14))
                .foregroundStyle(Lamp.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Lamp.accent.opacity(0.1), in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Lamp.accent.opacity(0.3)))
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Lamp.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Lamp.accentInk)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(color, in: .rect(cornerRadius: 16))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension Text {
    /// Renders Wren's bold figures; falls back to plain text if the markdown is bad.
    init(markdown: String) {
        if let attributed = try? AttributedString(markdown: markdown) {
            self.init(attributed)
        } else {
            self.init(verbatim: markdown)
        }
    }
}
