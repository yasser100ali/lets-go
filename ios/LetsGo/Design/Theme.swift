import SwiftUI
import UIKit

/// Two looks, one set of names. Dark is Glass: Apple Maps-dark ground, Liquid Glass
/// chrome, small muted tints. Light is Paper: off-white, ink-black, a serif for titles.
/// Every color here resolves per appearance, so views never branch on the theme.
enum Palette {
    static let bg = dynamic(dark: 0x15181D, light: 0xFAFAF8)
    static let surface = dynamic(dark: 0x1F232A, light: 0xFFFFFF)
    static let raise = dynamic(dark: 0x2A2F37, light: 0xF0EFEA)
    static let ink = dynamic(dark: 0xFFFFFF, light: 0x111111)
    static let muted = dynamic(dark: 0xEBEBF5, darkAlpha: 0.6, light: 0x77756F)
    static let line = dynamic(dark: 0xFFFFFF, darkAlpha: 0.1, light: 0xE6E4DE)
    /// Buttons and selection: system-ish blue on Glass, ink on Paper.
    static let accent = dynamic(dark: 0x5E9EFF, light: 0x111111)
    static let accentInk = dynamic(dark: 0xFFFFFF, light: 0xFFFFFF)
    static let star = dynamic(dark: 0xFFC766, light: 0xB7791F)
    static let me = dynamic(dark: 0x0A84FF, light: 0x2B5CE6)
    /// "On now".
    static let live = dynamic(dark: 0x30D158, light: 0x14915A)

    private static func dynamic(dark: UInt32, darkAlpha: Double = 1, light: UInt32, lightAlpha: Double = 1) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: lightAlpha)
        })
    }
}

/// The look you picked under You → Appearance.
enum Appearance: String, CaseIterable, Identifiable {
    case system, glass, paper

    static let storageKey = "appearance"
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Match phone"
        case .glass: "Glass"
        case .paper: "Paper"
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .glass: .dark
        case .paper: .light
        }
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
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
    static let label = Font.system(size: 11, weight: .semibold)
}

/// Titles: SF Pro bold on Glass, New York (the system serif) on Paper.
struct DisplayFont: ViewModifier {
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: scheme == .dark ? .bold : .medium, design: scheme == .dark ? .default : .serif))
            .tracking(scheme == .dark ? -0.4 : -0.3)
    }
}

extension View {
    func display(_ size: CGFloat) -> some View { modifier(DisplayFont(size: size)) }

    /// A grouped-list block: soft fill on Glass, white with a hairline on Paper.
    func card(radius: CGFloat = 18) -> some View { modifier(CardStyle(radius: radius)) }

    func eyebrow(_ color: Color = Palette.muted) -> some View {
        self.font(.system(size: 12, weight: .semibold)).textCase(.uppercase).tracking(0.4).foregroundStyle(color)
    }
}

struct CardStyle: ViewModifier {
    var radius: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background(scheme == .dark ? Color.white.opacity(0.06) : Palette.surface, in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(scheme == .dark ? Color.clear : Palette.line))
    }
}
