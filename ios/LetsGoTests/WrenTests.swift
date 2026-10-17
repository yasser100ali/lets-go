import Testing
import Foundation
@testable import LetsGo

@Suite("Wren picks")
struct WrenPickTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func candidate(_ title: String, _ category: Genre = .play, startsIn minutes: Double, meters: Double = 400,
                   capacity: Int = 0, going: Int = 0) -> Candidate {
        Candidate(
            id: UUID(), kind: .gathering, title: title, category: category,
            start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + 90) * 60),
            meters: meters, capacity: capacity, going: going
        )
    }

    @Test func endedAndFullThingsAreNeverPicked() {
        let ended = candidate("Ended", startsIn: -200)
        let full = candidate("Full", startsIn: 20, capacity: 10, going: 10)
        let open = candidate("Open", startsIn: 20)
        let picks = Wren.picks([ended, full, open], now: now, taste: Taste())
        #expect(picks.map(\.title) == ["Open"])
    }

    @Test func soonAndCloseBeatsLaterAndFar() {
        let near = candidate("Near", startsIn: 15, meters: 300)
        let far = candidate("Far", startsIn: 150, meters: 1500)
        #expect(Wren.picks([far, near], now: now, taste: Taste()).first?.title == "Near")
    }

    @Test func nothingBeyondTheHorizon() {
        let tomorrow = candidate("Tomorrow", startsIn: 60 * 20)
        #expect(Wren.picks([tomorrow], now: now, taste: Taste()).isEmpty)
    }

    @Test func tasteBreaksATie() {
        let soccer = candidate("Soccer", .play, startsIn: 30)
        let music = candidate("Music", .music, startsIn: 30)
        let taste = Taste(weights: [.music: 1])
        #expect(Wren.picks([soccer, music], now: now, taste: taste).first?.title == "Music")
    }

    @Test func lineCallsOutAShortGame() {
        let soccer = candidate("Pickup soccer", startsIn: 38, capacity: 14, going: 12)
        let line = Wren.line([soccer], now: now)
        #expect(line.contains("**2 short**"))
    }

    @Test func emptyLineInvitesYouToHost() {
        #expect(Wren.line([], now: now).contains("Start something"))
    }
}

@Suite("Reading what you ask Wren")
struct WrenQueryTests {
    // A Friday evening, so "sat 8am" means tomorrow morning.
    let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 16; c.hour = 18; c.minute = 12
        return Calendar.current.date(from: c)!
    }()

    @Test func moodWithPrice() {
        let q = WrenQuery.parse("something chill tonight, outside, under $15", now: now)
        #expect(q.wantsQuiet)
        #expect(q.maxPriceCents == 1500)
        #expect(q.day == .today)
        #expect(!q.wantsToCreate)
    }

    @Test func planBecomesADraft() {
        let q = WrenQuery.parse("make a slow jog sat 8am around the lake", now: now)
        #expect(q.wantsToCreate)
        #expect(q.categories.contains(.move))
        let draft = GatheringDraft.from(q, now: now)
        #expect(draft.category == .move)
        #expect(draft.placeName == "The lake")
        #expect(draft.title.hasPrefix("Slow"))
        #expect(Calendar.current.component(.hour, from: draft.start) == 8)
        #expect(Calendar.current.component(.weekday, from: draft.start) == 7)
    }

    @Test func gameNightIsAHangNotASport() {
        let q = WrenQuery.parse("any board game night?", now: now)
        #expect(q.categories.contains(.party))
        #expect(!q.categories.contains(.play))
    }

    @Test func knowIsNotNow() {
        #expect(WrenQuery.parse("do you know any runs", now: now).day == .any)
        #expect(WrenQuery.parse("anything now?", now: now).day == .today)
    }

    @Test func foodWords() {
        #expect(WrenQuery.parse("who's selling pizza", now: now).categories == [.food])
    }
}

@Suite("Money and walking")
struct SmallMathTests {
    @Test func serviceFeeHasAFloor() {
        #expect(Pricing.serviceFee(for: 0) == 0)
        #expect(Pricing.serviceFee(for: 600) == 50)
        #expect(Pricing.serviceFee(for: 3000) == 150)
    }

    @Test func walkMinutes() {
        #expect(Walk.minutes(10) == 1)
        #expect(Walk.minutes(800) == 10)
    }

    @Test func lowercasingKeepsNames() {
        #expect("Pickup soccer".lowercasedFirst == "pickup soccer")
        #expect("Dana's Porch Pizza".lowercasedFirst == "Dana's Porch Pizza")
    }
}
