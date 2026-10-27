import Foundation
import CoreLocation

/// Where your people are tonight, and how to end up with them. Plain functions, so they're tested.
///
/// Real friends are wherever the server says they joined. Sample friends (until you have
/// real ones) are placed on the best things near you, so the map, Wren and "who's in"
/// have someone to show. Every sample person is labeled as one wherever they appear.
enum Crowd {
    /// Your friends with tonight filled in. Sample ones go on the top picks: the "team"
    /// pair on the first thing with a cap and room, the "solo" one on the next.
    static func resolve(_ friends: [Friend], picks: [Candidate], here: CLLocationCoordinate2D, now: Date) -> [Friend] {
        let gatherings = picks.filter { $0.kind == .gathering && $0.spotsLeft != 0 }
        let teamPick = gatherings.first { $0.capacity > 0 } ?? gatherings.first
        let soloPick = gatherings.first { $0.id != teamPick?.id }
        var teamSeen = 0
        return friends.map { (friend: Friend) -> Friend in
            guard friend.isSample else { return friend }
            var f = friend
            switch f.sampleRole {
            case "team":
                guard let c = teamPick else { return f }
                // The first of the pair is on the way; the rest are already there if it's started.
                let state: Friend.OutState = teamSeen == 0 || c.start.timeIntervalSince(now) > 30 * 60 ? .heading : .there
                teamSeen += 1
                place(&f, at: c, state: state, here: here)
            case "solo":
                guard let c = soloPick else { return f }
                place(&f, at: c, state: c.start <= now ? .there : .heading, here: here)
            default:
                break
            }
            return f
        }
    }

    private static func place(_ f: inout Friend, at c: Candidate, state: Friend.OutState, here: CLLocationCoordinate2D) {
        let there = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
        let at: CLLocationCoordinate2D
        switch state {
        case .there:
            // A few steps off the pin, so they don't sit on it.
            at = there.offset(east: 30 * (Art.unit(f.name, 3) - 0.5) * 2, north: 30 * (Art.unit(f.name, 4) - 0.5) * 2)
        case .heading:
            // Partway there, off the straight line a little: walking over from their place.
            let t = 0.45 + 0.2 * Art.unit(f.name, 5)
            at = CLLocationCoordinate2D(
                latitude: here.latitude + (there.latitude - here.latitude) * t,
                longitude: here.longitude + (there.longitude - here.longitude) * t
            ).offset(east: 60 * (Art.unit(f.name, 6) - 0.5), north: 60 * (Art.unit(f.name, 8) - 0.5))
        }
        f.out = Friend.Out(state: state, title: c.title, place: c.place, start: c.start, gatheringID: c.id,
                           latitude: at.latitude, longitude: at.longitude)
        f.latitude = at.latitude
        f.longitude = at.longitude
    }

    /// Friends going to this: on its list from the server, or placed there.
    static func going(to c: Candidate, among friends: [Friend]) -> [Friend] {
        friends.filter { c.friendIDs.contains($0.id) || $0.out?.gatheringID == c.id }
    }

    /// Out now: there first, then heading, soonest first.
    static func outNow(_ friends: [Friend]) -> [Friend] {
        friends.filter { $0.out != nil }.sorted { a, b in
            let ra = a.out?.state == .there ? 0 : 1, rb = b.out?.state == .there ? 0 : 1
            if ra != rb { return ra < rb }
            return (a.out?.start ?? .distantFuture) < (b.out?.start ?? .distantFuture)
        }
    }

    static func porchLights(_ friends: [Friend], now: Date) -> [Friend] {
        friends.filter { $0.porchOn(at: now) && $0.out == nil }.sorted { ($0.porchUntil ?? now) > ($1.porchUntil ?? now) }
    }

    /// "Maya", "Maya and Theo", "Maya, Theo and Jun", "Maya, Theo and 2 others".
    static func names(_ friends: [Friend]) -> String {
        let first = friends.map(\.firstName)
        switch first.count {
        case 0: return ""
        case 1: return first[0]
        case 2: return "\(first[0]) and \(first[1])"
        case 3: return "\(first[0]), \(first[1]) and \(first[2])"
        default: return "\(first[0]), \(first[1]) and \(first.count - 2) others"
        }
    }

    /// Where a friend's porch light or night puts them on the map, if anywhere.
    static func mapped(_ friends: [Friend], now: Date) -> [Friend] {
        friends.filter { $0.coordinate != nil && ($0.out != nil || $0.porchOn(at: now)) }
    }
}

/// Wren routing your walk past a friend who's heading to the same thing.
struct MeetUp: Equatable, Sendable {
    var friendID: UUID
    var friendName: String
    /// When you leave.
    var leave: Date
    /// When you meet them, on their way.
    var meetAt: Date
    var latitude: Double
    var longitude: Double
    /// How much longer than walking straight there.
    var extraMinutes: Int

    /// Worth suggesting when going via them costs at most a third more walking (or a couple of
    /// blocks) and there's still time. They're walking from where they are now.
    static func plan(here: CLLocationCoordinate2D, friend: Friend, to destination: CLLocationCoordinate2D,
                     start: Date, now: Date) -> MeetUp? {
        guard friend.out?.state == .heading, let p = friend.coordinate else { return nil }
        let direct = here.distance(to: destination)
        let toFriend = here.distance(to: p)
        let onward = p.distance(to: destination)
        guard toFriend + onward <= direct * 1.35 + 160 else { return nil }
        let meetAt = start.addingTimeInterval(-Double(Walk.minutes(onward)) * 60)
        let leaveRaw = meetAt.addingTimeInterval(-Double(Walk.minutes(toFriend)) * 60)
        let whole = (leaveRaw.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        let leave = Date(timeIntervalSinceReferenceDate: whole)
        guard leave > now else { return nil }
        let extra = max(0, Walk.minutes(toFriend + onward) - Walk.minutes(direct))
        return MeetUp(friendID: friend.id, friendName: friend.firstName, leave: leave, meetAt: meetAt,
                      latitude: p.latitude, longitude: p.longitude, extraMinutes: extra)
    }

    /// The first heading friend it's worth walking past.
    static func best(here: CLLocationCoordinate2D, friends: [Friend], to c: Candidate, now: Date) -> MeetUp? {
        let there = CLLocationCoordinate2D(latitude: c.lat, longitude: c.lon)
        return friends.lazy.compactMap { plan(here: here, friend: $0, to: there, start: c.start, now: now) }.first
    }
}
