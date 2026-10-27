from tests.conftest import HERE, at, make_user, offset
from tests.test_gatherings import host_game


async def befriend(client, a, b):
    """b accepts a's code."""
    code = (await client.post("/v1/friends/code", headers=a)).json()["code"]
    r = await client.post("/v1/friends/accept", json={"code": code}, headers=b)
    assert r.status_code == 200, r.text
    return r.json()


async def me_id(client, headers):
    return (await client.get("/v1/me", headers=headers)).json()["id"]


async def test_a_code_makes_two_people_friends(client):
    maya, you = await make_user(client, "Maya"), await make_user(client, "You")
    friend = await befriend(client, maya, you)
    assert friend["display_name"] == "Maya"
    mine = (await client.get("/v1/people", headers=you)).json()
    theirs = (await client.get("/v1/people", headers=maya)).json()
    assert [f["display_name"] for f in mine["friends"]] == ["Maya"]
    assert [f["display_name"] for f in theirs["friends"]] == ["You"]


async def test_codes_are_one_use_and_forgiving_to_type(client):
    maya, you, theo = (
        await make_user(client, "Maya"),
        await make_user(client, "You"),
        await make_user(client, "Theo"),
    )
    code = (await client.post("/v1/friends/code", headers=maya)).json()["code"]
    messy = f" {code[:4].lower()}-{code[4:]} "
    assert (await client.post("/v1/friends/accept", json={"code": messy}, headers=you)).status_code == 200
    # Accepting again is fine; someone else can't.
    assert (await client.post("/v1/friends/accept", json={"code": code}, headers=you)).status_code == 200
    assert (await client.post("/v1/friends/accept", json={"code": code}, headers=theo)).status_code == 404
    assert len((await client.get("/v1/people", headers=you)).json()["friends"]) == 1


async def test_your_own_code_and_a_bad_code_are_refused(client):
    maya = await make_user(client, "Maya")
    code = (await client.post("/v1/friends/code", headers=maya)).json()["code"]
    assert (await client.post("/v1/friends/accept", json={"code": code}, headers=maya)).status_code == 409
    assert (
        await client.post("/v1/friends/accept", json={"code": "NOPE1234"}, headers=maya)
    ).status_code == 404


async def test_unfriending_goes_both_ways(client):
    maya, you = await make_user(client, "Maya"), await make_user(client, "You")
    friend = await befriend(client, maya, you)
    assert (await client.delete(f"/v1/friends/{friend['id']}", headers=you)).status_code == 204
    assert (await client.get("/v1/people", headers=maya)).json()["friends"] == []


async def test_porch_light_is_seen_by_friends_only(client):
    priya, you, stranger = (
        await make_user(client, "Priya"),
        await make_user(client, "You"),
        await make_user(client, "Stranger"),
    )
    await befriend(client, priya, you)
    lat, lon = offset(200, 0)
    r = await client.put(
        "/v1/me/porch-light",
        json={"hours": 2, "note": "up for a walk", "lat": lat, "lon": lon},
        headers=priya,
    )
    assert r.status_code == 200
    assert (await client.get("/v1/people", headers=priya)).json()["porch_light"]["note"] == "up for a walk"

    seen = (await client.get("/v1/people", params={"lat": HERE[0], "lon": HERE[1]}, headers=you)).json()
    light = seen["friends"][0]["porch_light"]
    assert light["note"] == "up for a walk"
    assert 150 < light["distance_m"] < 250
    assert (await client.get("/v1/people", headers=stranger)).json()["friends"] == []

    await client.delete("/v1/me/porch-light", headers=priya)
    assert (await client.get("/v1/people", headers=you)).json()["friends"][0]["porch_light"] is None


async def test_porch_light_lasts_at_most_four_hours(client):
    you = await make_user(client, "You")
    assert (await client.put("/v1/me/porch-light", json={"hours": 6}, headers=you)).status_code == 422


async def test_out_now_comes_from_what_friends_joined(client):
    sam, maya, you = (
        await make_user(client, "Sam"),
        await make_user(client, "Maya"),
        await make_user(client, "You"),
    )
    await befriend(client, maya, you)
    g = await host_game(client, sam, title="Trivia", starts_at=at(30), capacity=6)
    await client.post(f"/v1/gatherings/{g['id']}/join", headers=maya)
    friend = (await client.get("/v1/people", headers=you)).json()["friends"][0]
    assert friend["out"]["title"] == "Trivia"
    assert friend["out"]["state"] == "heading"
    # Something tomorrow doesn't make you "out".
    later = await host_game(client, sam, title="Tomorrow", starts_at=at(60 * 20), ends_at=at(60 * 22))
    await client.post(f"/v1/gatherings/{later['id']}/join", headers=you)
    assert (await client.get("/v1/people", headers=maya)).json()["friends"][0]["out"] is None


async def test_gatherings_name_only_your_friends(client):
    sam, maya, ben, you = (
        await make_user(client, "Sam"),
        await make_user(client, "Maya"),
        await make_user(client, "Ben"),
        await make_user(client, "You"),
    )
    await befriend(client, maya, you)
    g = await host_game(client, sam, capacity=6)
    await client.post(f"/v1/gatherings/{g['id']}/join", headers=maya)
    await client.post(f"/v1/gatherings/{g['id']}/join", headers=ben)
    seen = (await client.get(f"/v1/gatherings/{g['id']}", headers=you)).json()
    assert seen["going"] == 3
    assert [p["display_name"] for p in seen["friends_going"]] == ["Maya"]
    nearby = (await client.get("/v1/nearby", params={"lat": HERE[0], "lon": HERE[1]}, headers=you)).json()
    assert [p["display_name"] for p in nearby["gatherings"][0]["friends_going"]] == ["Maya"]
    # Joining yourself shows your friends straight away.
    joined = (await client.post(f"/v1/gatherings/{g['id']}/join", headers=you)).json()
    assert [p["display_name"] for p in joined["friends_going"]] == ["Maya"]


async def test_invites_go_to_friends_and_show_on_people(client):
    sam, maya, you, stranger = (
        await make_user(client, "Sam"),
        await make_user(client, "Maya"),
        await make_user(client, "You"),
        await make_user(client, "Stranger"),
    )
    await befriend(client, maya, you)
    g = await host_game(client, sam)
    await client.post(f"/v1/gatherings/{g['id']}/join", headers=maya)
    you_id, stranger_id = await me_id(client, you), await me_id(client, stranger)

    r = await client.post(f"/v1/gatherings/{g['id']}/invites", json={"user_ids": [stranger_id]}, headers=maya)
    assert r.status_code == 422
    r = await client.post(f"/v1/gatherings/{g['id']}/invites", json={"user_ids": [you_id]}, headers=maya)
    assert r.json()["invited"] == 1
    # Asking twice is a no-op.
    r = await client.post(f"/v1/gatherings/{g['id']}/invites", json={"user_ids": [you_id]}, headers=maya)
    assert r.json()["invited"] == 0

    invites = (await client.get("/v1/people", headers=you)).json()["invites"]
    assert [(i["gathering"]["title"], i["sender"]["display_name"]) for i in invites] == [
        ("Pickup soccer", "Maya")
    ]
    # Once you're in, the invite has done its job.
    await client.post(f"/v1/gatherings/{g['id']}/join", headers=you)
    assert (await client.get("/v1/people", headers=you)).json()["invites"] == []


async def test_waves_reach_friends(client):
    priya, you, stranger = (
        await make_user(client, "Priya"),
        await make_user(client, "You"),
        await make_user(client, "Stranger"),
    )
    friend = await befriend(client, priya, you)
    assert (await client.post(f"/v1/friends/{friend['id']}/wave", headers=you)).status_code == 204
    assert (await client.get("/v1/people", headers=priya)).json()["friends"][0]["waved_at"] is not None
    priya_id = friend["id"]
    assert (await client.post(f"/v1/friends/{priya_id}/wave", headers=stranger)).status_code == 404


async def test_crews_are_made_of_friends(client):
    maya, theo, you, stranger = (
        await make_user(client, "Maya"),
        await make_user(client, "Theo"),
        await make_user(client, "You"),
        await make_user(client, "Stranger"),
    )
    maya_id = (await befriend(client, maya, you))["id"]
    theo_id = (await befriend(client, theo, you))["id"]
    stranger_id = await me_id(client, stranger)
    r = await client.post("/v1/crews", json={"name": "Trivia lot", "member_ids": [stranger_id]}, headers=you)
    assert r.status_code == 422
    r = await client.post(
        "/v1/crews", json={"name": "Trivia lot", "member_ids": [maya_id, theo_id]}, headers=you
    )
    assert r.status_code == 201, r.text
    crew = r.json()
    assert crew["is_mine"] and {m["display_name"] for m in crew["members"]} == {"You", "Maya", "Theo"}

    seen = (await client.get("/v1/people", headers=maya)).json()["crews"]
    assert [c["name"] for c in seen] == ["Trivia lot"] and not seen[0]["is_mine"]
    # Maya leaves; you still have it. Then you delete it.
    assert (await client.delete(f"/v1/crews/{crew['id']}", headers=maya)).status_code == 204
    assert (await client.get("/v1/people", headers=maya)).json()["crews"] == []
    assert len((await client.get("/v1/people", headers=you)).json()["crews"][0]["members"]) == 2
    assert (await client.delete(f"/v1/crews/{crew['id']}", headers=you)).status_code == 204
    assert (await client.get("/v1/people", headers=theo)).json()["crews"] == []


# Third time's a friend


async def check_in_together(client, host, people, n):
    """n gatherings, all of `people` checked in to each."""
    for i in range(n):
        g = await host_game(client, host, title=f"Trivia {i}", starts_at=at(5), capacity=0)
        for p in people:
            r = await client.post(
                f"/v1/gatherings/{g['id']}/check-in", json={"lat": g["lat"], "lon": g["lon"]}, headers=p
            )
            assert r.status_code == 200, r.text


async def test_three_check_ins_together_offer_an_intro(client):
    sam, you, ben = (
        await make_user(client, "Sam"),
        await make_user(client, "You"),
        await make_user(client, "Ben"),
    )
    await check_in_together(client, sam, [you, ben], 2)
    assert (await client.get("/v1/people", headers=you)).json()["intros"] == []
    ben_id = await me_id(client, ben)
    assert (await client.post(f"/v1/intros/{ben_id}/hi", headers=you)).status_code == 404

    await check_in_together(client, sam, [you, ben], 1)
    intros = (await client.get("/v1/people", headers=you)).json()["intros"]
    assert [i["person"]["display_name"] for i in intros] == ["Ben"]
    assert len(intros[0]["together"]) == 3 and not intros[0]["said_hi"]


async def test_both_saying_hi_makes_friends_and_one_tells_nothing(client):
    sam, you, ben = (
        await make_user(client, "Sam"),
        await make_user(client, "You"),
        await make_user(client, "Ben"),
    )
    await check_in_together(client, sam, [you, ben], 3)
    you_id, ben_id = await me_id(client, you), await me_id(client, ben)

    r = await client.post(f"/v1/intros/{ben_id}/hi", headers=you)
    assert r.json() == {"connected": False}
    # Ben's card looks exactly the same as before you said hi.
    bens = (await client.get("/v1/people", headers=ben)).json()
    assert bens["intros"][0]["said_hi"] is False and bens["friends"] == []
    assert (await client.get("/v1/people", headers=you)).json()["intros"][0]["said_hi"] is True

    r = await client.post(f"/v1/intros/{you_id}/hi", headers=ben)
    assert r.json() == {"connected": True}
    mine = (await client.get("/v1/people", headers=you)).json()
    assert [f["display_name"] for f in mine["friends"]] == ["Ben"] and mine["intros"] == []


async def test_not_now_hides_the_card(client):
    sam, you, ben = (
        await make_user(client, "Sam"),
        await make_user(client, "You"),
        await make_user(client, "Ben"),
    )
    await check_in_together(client, sam, [you, ben], 3)
    ben_id = await me_id(client, ben)
    assert (await client.post(f"/v1/intros/{ben_id}/not-now", headers=you)).status_code == 204
    assert (await client.get("/v1/people", headers=you)).json()["intros"] == []
    # Ben still sees his; saying hi from his side alone connects nothing.
    you_id = await me_id(client, you)
    assert (await client.post(f"/v1/intros/{you_id}/hi", headers=ben)).json() == {"connected": False}
