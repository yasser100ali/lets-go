import Foundation
import Observation
import OSLog
import FoundationModels

/// How Wren talks. The plan and the picks always come from the plain types (`Planner`,
/// `Wren`), from what's really nearby; when Apple Intelligence is on the phone, the
/// on-device model rewrites the sentence around them. Without it, the sentence stands.
@Observable
final class WrenVoice {
    @ObservationIgnored private var session: LanguageModelSession?
    @ObservationIgnored private let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "wren")

    var isOnDevice: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    /// Wren's line for a plan, in its own words. Nil keeps the plain one.
    func reply(for plan: Plan, asked: String, names: String, clock: (Date) -> String = HomeLine.clock) async -> String? {
        let stops = plan.stops.map { "- \(clock($0.start)): \($0.title) (\($0.note))" }.joined(separator: "\n")
        return await say("""
        The person asked: "\(asked)"
        The plan, for \(plan.title.replacingOccurrences(of: ", sorted.", with: "")) with \(names.isEmpty ? "just them" : names):
        \(stops)
        Write one or two short sentences offering this plan, naming the stops in order, and end by asking \(names.isEmpty ? "if they want you to hold it" : "if they want you to ask \(names)"). Only mention the stops listed.
        """)
    }

    /// Wren's line for picks that match a mood.
    func reply(for answer: Wren.Answer, asked: String, now: Date) async -> String? {
        guard !answer.picks.isEmpty else { return nil }
        let listing = answer.picks
            .map { "- \($0.title) (\($0.category.label)), \(When.relative($0.start, end: $0.end, now: now)), \(Picks.reason($0, now: now))" }
            .joined(separator: "\n")
        return await say("""
        The person asked: "\(asked)"
        What's nearby that matches, best first:
        \(listing)
        Reply in at most two short sentences. Only mention items from the list, by name.
        """)
    }

    private func say(_ prompt: String) async -> String? {
        guard isOnDevice else { return nil }
        do {
            let session = self.session ?? LanguageModelSession(instructions: """
                You are Wren, the guide inside Let's Go, an app for getting out and being with people: pickup games, \
                live music, game nights, neighbors selling home cooking, all within walking distance. You do the \
                logistics so people can just show up. Talk like a friend who knows the neighborhood: plain, warm, brief. \
                Never invent events, people, places, times or prices.
                """)
            self.session = session
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            log.error("On-device model failed: \(error.localizedDescription, privacy: .public)")
            session = nil
            return nil
        }
    }
}
