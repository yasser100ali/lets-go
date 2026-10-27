import Foundation
import SwiftData
import CoreLocation

/// Your porch light, as this phone knows it. The server has the shared copy.
enum MyPorchLight {
    static let untilKey = "porch.until"
    static let noteKey = "porch.note"
    /// Two hours, like the board says.
    static let hours: Double = 2

    static var until: Date? {
        let t = UserDefaults.standard.double(forKey: untilKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static func set(until: Date?, note: String = "") {
        UserDefaults.standard.set(until?.timeIntervalSince1970 ?? 0, forKey: untilKey)
        UserDefaults.standard.set(note, forKey: noteKey)
    }
}

/// Friends, crews, porch lights and invites. Real friends live on the server; sample ones
/// stay on this phone, and anything you do with them (a wave, an invite) stays here too.
extension Sync {
    // MARK: Pull

    static func refreshPeople(around c: CLLocationCoordinate2D, context: ModelContext) async throws(APIError) {
        let dto: PeopleDTO = try await api.send(.get("/v1/people", query: [
            URLQueryItem(name: "lat", value: String(c.latitude)),
            URLQueryItem(name: "lon", value: String(c.longitude)),
        ]))
        apply(dto, context: context)
    }

    static func apply(_ dto: PeopleDTO, context: ModelContext) {
        let local = fetch(context, FetchDescriptor<Person>(predicate: #Predicate { !$0.isSample }))
        var byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Invites carry a gathering; make sure it's on the phone so the invite can open it.
        let remoteGatherings = fetch(context, FetchDescriptor<Gathering>(predicate: #Predicate { $0.remoteID != nil }))
        var gatherings = Dictionary(remoteGatherings.compactMap { g in g.remoteID.map { ($0, g) } }, uniquingKeysWith: { a, _ in a })
        for g in gatherings.values { g.invitedBy = "" }
        for invite in dto.invites {
            let d = invite.gathering
            let g: Gathering
            if let found = gatherings[d.id] {
                g = found
            } else {
                g = Gathering(
                    title: d.title, category: Genre(rawValue: d.genre) ?? .party, placeName: d.placeName,
                    coordinate: .init(latitude: d.lat, longitude: d.lon), start: d.startsAt, end: d.endsAt, hostName: d.hostName
                )
                g.remoteID = d.id
                context.insert(g)
                gatherings[d.id] = g
            }
            update(g, from: d)
            g.invitedBy = invite.sender.displayName
        }

        for f in dto.friends {
            let p = byID.removeValue(forKey: f.id) ?? {
                let new = Person(id: f.id, name: f.displayName, isSample: false)
                context.insert(new)
                return new
            }()
            p.name = f.displayName
            p.porchUntil = f.porchLight?.onUntil
            p.porchNote = f.porchLight?.note ?? ""
            p.latitude = f.porchLight?.lat
            p.longitude = f.porchLight?.lon
            p.wavedAt = f.wavedAt
            if let out = f.out {
                p.outStateRaw = out.state
                p.outTitle = out.title
                p.outPlace = out.placeName
                p.outStart = out.startsAt
                p.outGatheringID = gatherings[out.gatheringId]?.id
                p.outLatitude = out.lat
                p.outLongitude = out.lon
                if out.state == Friend.OutState.there.rawValue {
                    p.latitude = out.lat
                    p.longitude = out.lon
                }
            } else {
                p.outStateRaw = ""
                p.outGatheringID = nil
            }
        }
        // No longer friends.
        for p in byID.values { context.delete(p) }

        // Crews: the server's list replaces the phone's real ones.
        for c in fetch(context, FetchDescriptor<Crew>(predicate: #Predicate { !$0.isSample })) { context.delete(c) }
        let friendIDs = Set(dto.friends.map(\.id))
        for c in dto.crews {
            context.insert(Crew(id: c.id, name: c.name, memberIDs: c.members.map(\.id).filter { friendIDs.contains($0) }, isMine: c.isMine))
        }

        MyPorchLight.set(until: dto.porchLight?.onUntil, note: dto.porchLight?.note ?? "")
        Ledger.save(context, "apply people")
    }

    // MARK: Friends

    static func friendCode() async throws(APIError) -> FriendCodeDTO {
        try await api.send(.post("/v1/friends/code"))
    }

    /// Accept a code someone gave you. Returns who you're now friends with.
    static func accept(code: String, around c: CLLocationCoordinate2D, context: ModelContext) async throws(APIError) -> String {
        let friend: PersonDTO = try await api.send(.post("/v1/friends/accept", AcceptCodeDTO(code: code)))
        try await refreshPeople(around: c, context: context)
        return friend.displayName
    }

    static func unfriend(_ p: Person, context: ModelContext) async throws(APIError) {
        if !p.isSample {
            let _: Empty = try await api.send(.delete("/v1/friends/\(p.id.uuidString)"))
        }
        context.delete(p)
        Ledger.save(context, "unfriend")
    }

    static func wave(_ p: Person, context: ModelContext) async throws(APIError) {
        if !p.isSample {
            let _: Empty = try await api.send(.post("/v1/friends/\(p.id.uuidString)/wave"))
        }
        p.youWavedAt = .now
        Ledger.save(context, "wave")
    }

    // MARK: Porch light

    /// On for two hours, or off. Returns when it goes off.
    @discardableResult
    static func porchLight(on: Bool, note: String = "", at c: CLLocationCoordinate2D?) async throws(APIError) -> Date? {
        if on {
            let until = Date.now.addingTimeInterval(MyPorchLight.hours * 3600)
            if APIConfig.isConfigured {
                let dto: PorchLightDTO = try await api.send(.put("/v1/me/porch-light", PorchLightInDTO(
                    hours: MyPorchLight.hours, note: note, lat: c?.latitude, lon: c?.longitude
                )))
                MyPorchLight.set(until: dto.onUntil, note: dto.note)
                return dto.onUntil
            }
            MyPorchLight.set(until: until, note: note)
            return until
        }
        if APIConfig.isConfigured {
            let _: Empty = try await api.send(.delete("/v1/me/porch-light"))
        }
        MyPorchLight.set(until: nil)
        return nil
    }

    // MARK: Invites and crews

    /// Ask friends along. Real friends get it through the server when the gathering lives
    /// there; sample friends are just marked asked on this phone. Returns how many were asked.
    @discardableResult
    static func invite(_ people: [Person], to g: Gathering, context: ModelContext) async throws(APIError) -> Int {
        let real = people.filter { !$0.isSample }
        var asked = people.count - real.count
        if let id = g.remoteID, !real.isEmpty {
            let dto: InvitedDTO = try await api.send(.post(
                "/v1/gatherings/\(id.uuidString)/invites", InviteFriendsDTO(userIds: real.map(\.id))
            ))
            asked += dto.invited
        } else if !real.isEmpty {
            // Only on this phone: nobody else can see it yet.
            throw .rejected(status: 409, reason: "This one isn't on the server, so friends can't be invited to it yet.")
        }
        Ledger.save(context, "invite")
        return asked
    }

    static func makeCrew(_ name: String, members: [Person], context: ModelContext) async throws(APIError) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let real = members.filter { !$0.isSample }
        if APIConfig.isConfigured, real.count == members.count, !real.isEmpty {
            let dto: CrewDTO = try await api.send(.post("/v1/crews", NewCrewDTO(name: trimmed, memberIds: real.map(\.id))))
            context.insert(Crew(id: dto.id, name: dto.name, memberIDs: real.map(\.id), isMine: true))
        } else {
            // A crew with any sample people in it stays on this phone.
            context.insert(Crew(name: trimmed, memberIDs: members.map(\.id), isMine: true, isSample: real.count != members.count))
        }
        Ledger.save(context, "make crew")
    }

    static func leave(_ crew: Crew, context: ModelContext) async throws(APIError) {
        if !crew.isSample, APIConfig.isConfigured {
            let _: Empty = try await api.send(.delete("/v1/crews/\(crew.id.uuidString)"))
        }
        context.delete(crew)
        Ledger.save(context, "leave crew")
    }
}
