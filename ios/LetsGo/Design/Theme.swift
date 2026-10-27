import SwiftUI
import UIKit

/// Afterglow: a city at night. Plum-black ground, warm paper ink, one ember accent,
/// and glass chrome over a custom-tinted map. The whole app is this one look; the
/// map's quick-decide mode (`Signal`) is the only other set of colors.
enum Palette {
    static let bg = Color(hex: 0x0D0C12)
    /// Sheets and pages that sit on the map.
    static let surface = Color(hex: 0x15131C)
    static let raise = Color(hex: 0x24212C)
    static let ink = Color(hex: 0xF6F2EA)
    static let muted = Color(hex: 0xA8A3B3)
    /// A step brighter than `muted`, for body copy on glass.
    static let soft = Color(hex: 0xC9C4D2)
    /// Street names and the quietest labels.
    static let faint = Color(hex: 0x8E8A9B)
    static let line = Color.white.opacity(0.1)
    /// Ember: buttons, Wren, the dots in LIVE. MORE.
    static let accent = Color(hex: 0xFF5B3A)
    static let accentSoft = Color(hex: 0xFF9A80)
    static let accentInk = Color(hex: 0x1A0703)
    static let star = Color(hex: 0xFFC766)
    static let me = Color(hex: 0x0A84FF)
    /// "On now", and a friend who's in.
    static let live = Color(hex: 0x4FD08E)
    /// A porch light: someone up for something.
    static let porch = Color(hex: 0xFFB547)
    static let porchSoft = Color(hex: 0xFFC88A)
    /// The walk ring and route lines.
    static let walk = Color(hex: 0x7FB2FF)
    /// The tint glass chrome takes over the map.
    static let glassTint = Color(hex: 0x16141E, opacity: 0.55)
}

/// The quick-decide look: black, white and one acid lime. Numbers instead of icons.
enum SignalPalette {
    static let bg = Color(hex: 0x050505)
    static let ink = Color.white
    static let muted = Color(hex: 0x9A9A9A)
    static let lime = Color(hex: 0xD4FF3A)
    static let panel = Color(hex: 0x121212, opacity: 0.72)
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

    /// The headline face: tall, tight and heavy, like a gig poster.
    static func poster(_ size: CGFloat, weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight).width(.condensed)
    }

    /// The quote and the quiet lines: the system serif.
    static func serif(_ size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }
}

extension View {
    /// Page and card titles in the poster face.
    func display(_ size: CGFloat) -> some View {
        font(.poster(size)).tracking(-0.2)
    }

    /// A grouped block: a faint fill with a hairline.
    func card(radius: CGFloat = 18) -> some View { modifier(CardStyle(radius: radius)) }

    /// Small spaced capitals over a section: "OUT NOW · 3".
    func eyebrow(_ color: Color = Palette.muted) -> some View {
        self.font(.system(size: 12, weight: .heavy)).textCase(.uppercase).tracking(1.4).foregroundStyle(color)
    }

    /// The dark glass every floating panel uses.
    func glassPanel(radius: CGFloat = 34) -> some View {
        glassEffect(.regular.tint(Palette.glassTint), in: .rect(cornerRadius: radius))
    }
}

struct CardStyle: ViewModifier {
    var radius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.05), in: .rect(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.white.opacity(0.08)))
    }
}

/// LIVE. MORE. with ember full stops. On one line, or stacked for the Signal header.
/// Shrinks to fit rather than wrap.
struct LiveMoreMark: View {
    var size: CGFloat = 46
    var stacked = false
    var dot: Color = Palette.accent
    var ink: Color = Palette.ink

    var body: some View {
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: -size * 0.16) {
                    word("LIVE")
                    word("MORE")
                }
            } else {
                Text("\(Text("LIVE").foregroundStyle(ink))\(Text(".").foregroundStyle(dot)) \(Text("MORE").foregroundStyle(ink))\(Text(".").foregroundStyle(dot))")
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .font(.poster(size, weight: .black))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live more.")
        .accessibilityAddTraits(.isHeader)
    }

    private func word(_ w: String) -> some View {
        Text("\(Text(w).foregroundStyle(ink))\(Text(".").foregroundStyle(dot))")
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}
