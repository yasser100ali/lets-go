import SwiftUI

/// Lamplight: the night map. Deep navy ground, sodium-amber accent,
/// one saturated color per kind of thing so a pin reads at a glance.
enum Lamp {
    static let bg = Color(hex: 0x0D1322)
    static let surface = Color(hex: 0x161E33)
    static let raise = Color(hex: 0x1E2844)
    static let ink = Color(hex: 0xEEF1F8)
    static let muted = Color(hex: 0x8B96B2)
    static let line = Color.white.opacity(0.08)
    static let accent = Color(hex: 0xFFB347)
    static let accentInk = Color(hex: 0x1C1204)
    static let star = Color(hex: 0xFFC766)
    static let me = Color(hex: 0x6FB8FF)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

extension Font {
    /// Wide, heavy system face for titles; the app's display voice.
    static func display(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    static let label = Font.system(size: 11, weight: .semibold, design: .monospaced)
}

extension View {
    /// The standard raised card: surface fill, hairline edge.
    func card(radius: CGFloat = 16) -> some View {
        self
            .background(Lamp.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Lamp.line))
    }

    func eyebrow(_ color: Color = Lamp.muted) -> some View {
        self.font(.label).tracking(0.6).textCase(.uppercase).foregroundStyle(color)
    }
}
