import Foundation
import Observation
import OSLog
import FoundationModels

struct ChatMessage: Identifiable, Equatable {
    enum Role { case you, wren }
    var id = UUID()
    var role: Role
    var text: String
    var picks: [Candidate] = []
    var draft: GatheringDraft?
}

/// Wren's chat. The suggestions always come from what's really nearby
/// (`WrenQuery` + `Wren.picks`); when Apple Intelligence is on the phone,
/// the on-device model writes the sentence around them.
@Observable
final class WrenChat {
    private(set) var messages: [ChatMessage] = [
        ChatMessage(role: .wren, text: "Ask me for a mood, like \"something chill tonight under $15\", or tell me a plan, like \"slow jog Saturday 8am around the lake\", and I'll draft it."),
    ]
    private(set) var thinking = false

    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "wren")

    var usesOnDeviceModel: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func send(_ raw: String, candidates: [Candidate], taste: Taste, notes: [String], now: Date = .now) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(role: .you, text: text))
        thinking = true
        defer { thinking = false }

        let query = WrenQuery.parse(text, now: now)
        if query.wantsToCreate {
            let draft = GatheringDraft.from(query, now: now)
            messages.append(ChatMessage(
                role: .wren,
                text: "Here's a draft. Check the place and time, then post it and people nearby will see it.",
                draft: draft
            ))
            return
        }

        var matches = candidates.filter { query.matches($0, now: now) }
        // Asked about a specific day: rank inside that day, not just the next 3 hours.
        let ranked: [Candidate]
        if query.day == .any || query.day == .today {
            ranked = Wren.picks(matches, now: now, taste: taste, limit: 3)
        } else {
            matches.sort { $0.start < $1.start }
            ranked = Array(matches.prefix(3))
        }

        let reply: String
        if usesOnDeviceModel {
            reply = await modelReply(to: text, picks: ranked, notes: notes, now: now) ?? fallbackReply(query, ranked, now: now)
        } else {
            reply = fallbackReply(query, ranked, now: now)
        }
        messages.append(ChatMessage(role: .wren, text: reply, picks: ranked))
    }

    private func fallbackReply(_ q: WrenQuery, _ picks: [Candidate], now: Date) -> String {
        guard let first = picks.first else {
            return q.categories.isEmpty
                ? "Nothing like that near you yet. Want to start one? Tell me what and when."
                : "No \(q.categories.map(\.noun).sorted().joined(separator: " or ")) near you for that. Say \"host\" and what you have in mind, and I'll draft one."
        }
        if picks.count == 1 { return "One that fits: \(first.title), \(Wren.reason(first, now: now))." }
        let quiet = q.wantsQuiet ? " Both are small." : ""
        return "\(picks.count == 2 ? "Two" : "A few") that fit.\(quiet) \(first.title) is the closest to starting."
    }

    private func modelReply(to text: String, picks: [Candidate], notes: [String], now: Date) async -> String? {
        let listing = picks.isEmpty
            ? "(nothing nearby matches)"
            : picks.map { "- \($0.title) (\($0.category.label)), \(When.relative($0.start, end: $0.end, now: now)), \(Wren.reason($0, now: now))" }.joined(separator: "\n")
        let prompt = """
        The person asked: "\(text)"
        What's nearby that matches, best first:
        \(listing)
        What you know about them: \(notes.isEmpty ? "nothing yet" : notes.joined(separator: "; "))
        Reply in at most two short sentences. Only mention items from the list, by name. If the list is empty, suggest they host something.
        """
        do {
            let session = self.session ?? LanguageModelSession(instructions: """
                You are Wren, the guide inside Let's Go, an app for finding things to do within walking distance: pickup games, runs, backyard music, game nights, and neighbors selling home cooking. You talk like a friend who knows the neighborhood: plain, warm, brief. Never invent events, people, places or prices.
                """)
            self.session = session
            let response = try await session.respond(to: prompt)
            let reply = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return reply.isEmpty ? nil : reply
        } catch {
            log.error("On-device model failed: \(error.localizedDescription, privacy: .public)")
            session = nil
            return nil
        }
    }
}
