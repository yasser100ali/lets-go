import Testing
import Foundation
import CoreLocation
@testable import LetsGo

@Suite("Your people tonight")
struct CrowdTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let here = CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)

    func gathering(_ title: String, startsIn minutes: Double, east: Double, north: Double,
                   capacity: Int = 0, going: Int = 0, friends: [UUID] = []) -> Candidate {
        let at = here.offset(east: east, north: north)
        return Candidate(
            id: UUID(), kind: .gathering, title: title, category: .party,
            start: now.addingTimeInterval(minutes * 60), end: now.addingTimeInterval((minutes + 120) * 60),
            meters: here.distance(to: at), capacity: capacity, going: going, place: "The Dubliner",
            lat: at.latitude, lon: at.longitude, friendIDs: friends
        )
    }

    func sample(_ name: String, _ role: String) -> Friend {
        Friend(id: UUID(), name: name, isSample: true, sampleRole: role)
    }

    @Test func theSampleTeamGoesToTheFirstThingWithRoom() throws {
        let open = gathering("Open mic", startsIn: 20, east: 300, north: 0)
        let trivia = gathering("Trivia", startsIn: 60, east: -400, north: -600, capacity: 6, going: 4)
        let friends = [sample("Maya", "team"), sample("Theo", "team"), sample("Jun", "solo"), sample("Ana", "home")]
        let tonight = Crowd.resolve(friends, picks: [open, trivia], here: here, now: now)

        let maya = try #require(tonight.first { $0.name == "Maya" }?.out)
        let theo = try #require(tonight.first { $0.name == "Theo" }?.out)
        #expect(maya.gatheringID == trivia.id)
        #expect(theo.gatheringID == trivia.id)
        #expect(maya.state == .heading)
        // Jun takes the other one; Ana stays home.
        #expect(tonight.first { $0.name == "Jun" }?.out?.gatheringID == open.id)
        #expect(tonight.first { $0.name == "Ana" }?.out == nil)
        #expect(Crowd.going(to: trivia, among: tonight).count == 2)
    }

    @Test func realFriendsAreLeftAsTheServerSaid() {
        let real = Friend(id: UUID(), name: "Sam", isSample: false, sampleRole: "team")
        let trivia = gathering("Trivia", startsIn: 60, east: 0, north: 400, capacity: 6)
        let tonight = Crowd.resolve([real], picks: [trivia], here: here, now: now)
        #expect(tonight[0].out == nil)
        // Going according to the server's list.
        let listed = gathering("Trivia", startsIn: 60, east: 0, north: 400, friends: [real.id])
        #expect(Crowd.going(to: listed, among: [real]).map(\.name) == ["Sam"])
    }

    @Test func namesReadLikeASentence() {
        let f = ["Maya", "Theo", "Jun", "Ben"].map { Friend(id: UUID(), name: $0, isSample: true) }
        #expect(Crowd.names(Array(f.prefix(1))) == "Maya")
        #expect(Crowd.names(Array(f.prefix(2))) == "Maya and Theo")
        #expect(Crowd.names(Array(f.prefix(3))) == "Maya, Theo and Jun")
        #expect(Crowd.names(f) == "Maya, Theo and 2 others")
    }

    @Test func porchLightsAreOnlyTheOnesStillOn() {
        var priya = sample("Priya", "porch")
        priya.porchUntil = now.addingTimeInterval(3600)
        var omar = sample("Omar", "porch")
        omar.porchUntil = now.addingTimeInterval(-60)
        #expect(Crowd.porchLights([priya, omar], now: now).map(\.name) == ["Priya"])
    }

    @Test func wrenRoutesYouPastAFriendOnTheWay() throws {
        let trivia = gathering("Trivia", startsIn: 40, east: 0, north: 1200)
        var maya = sample("Maya", "team")
        let halfway = here.offset(east: 80, north: 600)
        maya.latitude = halfway.latitude
        maya.longitude = halfway.longitude
        maya.out = Friend.Out(state: .heading, title: "Trivia", place: "The Dubliner", start: trivia.start, gatheringID: trivia.id)
        let meet = try #require(MeetUp.best(here: here, friends: [maya], to: trivia, now: now))
        #expect(meet.friendName == "Maya")
        #expect(meet.leave > now)
        #expect(meet.leave < meet.meetAt)
        #expect(meet.meetAt < trivia.start)
        #expect(meet.extraMinutes <= 2)
    }

    @Test func noDetourThatDoublesTheWalk() {
        let trivia = gathering("Trivia", startsIn: 60, east: 0, north: 800)
        var maya = sample("Maya", "team")
        let away = here.offset(east: 0, north: -900)
        maya.latitude = away.latitude
        maya.longitude = away.longitude
        maya.out = Friend.Out(state: .heading, title: "Trivia", place: "", start: trivia.start, gatheringID: trivia.id)
        #expect(MeetUp.best(here: here, friends: [maya], to: trivia, now: now) == nil)
    }

    @Test func wrenLeadsWithFriends() {
        let trivia = gathering("Trivia", startsIn: 60, east: 0, north: 1200, capacity: 6, going: 4)
        let friends = [sample("Maya", "team"), sample("Theo", "team")]
        let meet = MeetUp(friendID: friends[0].id, friendName: "Maya", leave: now.addingTimeInterval(1800),
                          meetAt: now.addingTimeInterval(2400), latitude: 0, longitude: 0, extraMinutes: 1)
        let line = HomeLine.sentence(for: trivia, now: now, friends: friends, meet: meet, clock: { _ in "T" })
        #expect(line.lead.hasPrefix("Maya and Theo are going to trivia at The Dubliner"))
        #expect(line.emphasis == "they need two.")
        #expect(line.tail == " Leave at T and you'll walk in with Maya.")
    }
}
