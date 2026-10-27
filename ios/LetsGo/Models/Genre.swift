import SwiftUI

/// What kind of thing a gathering is. Food drops are always `.food`.
enum Genre: String, CaseIterable, Codable, Identifiable, Sendable {
    case play, move, music, party, food

    var id: String { rawValue }

    var label: String {
        switch self {
        case .play: "Play"
        case .move: "Move"
        case .music: "Music"
        case .party: "Hang"
        case .food: "Food"
        }
    }

    /// The chip on the map: "Sports", "Runs".
    var plural: String {
        switch self {
        case .play: "Sports"
        case .move: "Runs"
        case .music: "Music"
        case .party: "Hangs"
        case .food: "Food"
        }
    }

    /// How the app talks about it: "you're into pickup games".
    var noun: String {
        switch self {
        case .play: "pickup games"
        case .move: "runs and walks"
        case .music: "live music"
        case .party: "hangs and game nights"
        case .food: "home cooking"
        }
    }

    var symbol: String {
        switch self {
        case .play: "soccerball"
        case .move: "figure.run"
        case .music: "music.note"
        case .party: "dice.fill"
        case .food: "fork.knife"
        }
    }

    /// The pin's glow on the night map.
    var color: Color {
        switch self {
        case .play: Color(hex: 0x4FD08E)
        case .move: Color(hex: 0x5AB4F0)
        case .music: Color(hex: 0xB497F5)
        case .party: Color(hex: 0xF07BB0)
        case .food: Color(hex: 0xFFA24C)
        }
    }

    /// The icon on top of `color`: the same hue, nearly black.
    var ink: Color {
        switch self {
        case .play: Color(hex: 0x052414)
        case .move: Color(hex: 0x03192A)
        case .music: Color(hex: 0x170A33)
        case .party: Color(hex: 0x2E0716)
        case .food: Color(hex: 0x2B1300)
        }
    }

    /// The badge text over a dark chip: "4/6", "16 left".
    var light: Color {
        switch self {
        case .play: Color(hex: 0xB8F0D2)
        case .move: Color(hex: 0xB5DDF8)
        case .music: Color(hex: 0xD9CCFF)
        case .party: Color(hex: 0xFFC2DC)
        case .food: Color(hex: 0xFFC58E)
        }
    }

    /// Words that point at this category, for search.
    var keywords: [String] {
        switch self {
        case .play: ["soccer", "football", "basketball", "hoops", "pickup", "volleyball", "tennis", "frisbee", "game", "sport", "play"]
        case .move: ["run", "jog", "walk", "hike", "bike", "ride", "yoga", "5k", "workout", "move"]
        case .music: ["music", "dj", "band", "jam", "set", "concert", "open mic", "sing", "jazz", "symphony"]
        case .party: ["party", "hang", "board game", "game night", "trivia", "drinks", "chill", "bbq", "cookout", "comedy", "stand-up", "standup", "improv"]
        case .food: ["food", "eat", "pizza", "ice cream", "tacos", "tamales", "curry", "dinner", "lunch", "dessert", "hungry", "bake"]
        }
    }
}
