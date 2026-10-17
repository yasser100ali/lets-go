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

    /// How Wren talks about it: "you're into pickup games".
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

    var color: Color {
        switch self {
        case .play: Color(hex: 0x4FE0A0)
        case .move: Color(hex: 0x5CCBFF)
        case .music: Color(hex: 0xC8A2FF)
        case .party: Color(hex: 0xFF6FA8)
        case .food: Color(hex: 0xFF8C5E)
        }
    }

    /// Words that point at this category, for Wren's plain-text matching.
    var keywords: [String] {
        switch self {
        case .play: ["soccer", "football", "basketball", "hoops", "pickup", "volleyball", "tennis", "frisbee", "game", "sport", "play"]
        case .move: ["run", "jog", "walk", "hike", "bike", "ride", "yoga", "5k", "workout", "move"]
        case .music: ["music", "dj", "band", "jam", "set", "concert", "open mic", "sing"]
        case .party: ["party", "hang", "board game", "game night", "trivia", "drinks", "chill", "bbq", "cookout"]
        case .food: ["food", "eat", "pizza", "ice cream", "tacos", "tamales", "curry", "dinner", "lunch", "dessert", "hungry", "bake"]
        }
    }
}
