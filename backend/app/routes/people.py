"""Friends, crews, porch lights and invites.

Everything here is between friends. You become friends by accepting a one-use code
someone gave you; nothing about you is visible to anyone who isn't one.
"""

import secrets
import uuid
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user
from app.db import get_session
from app.geo import distance_m
from app.models import (
    Crew,
    CrewMember,
    FriendCode,
    Friendship,
    Gathering,
    GatheringInvite,
    PorchLight,
    User,
    Wave,
)
from app.schemas import (
    CrewCreate,
    CrewOut,
    FriendCodeAccept,
    FriendCodeOut,
    FriendOut,
    GatheringInviteOut,
    People,
    PersonOut,
    PorchLightIn,
    PorchLightOut,
)
from app.social import are_friends, friend_ids, out_now
from app.views import gathering_out, now

router = APIRouter(prefix="/v1", tags=["people"])

# No 0/O or 1/I/L, so a code read aloud comes out right.
CODE_ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"
CODE_LENGTH = 8
CODE_DAYS = 7
WAVE_SHOWS_FOR = timedelta(hours=2)


def _normalize(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


def _porch_out(p: PorchLight, lat: float | None, lon: float | None) -> PorchLightOut:
    d = None
    if lat is not None and lon is not None and p.lat is not None and p.lon is not None:
        d = distance_m(lat, lon, p.lat, p.lon)
    return PorchLightOut(on_until=p.on_until, note=p.note, lat=p.lat, lon=p.lon, distance_m=d)


def _crew_out(c: Crew, viewer_id: uuid.UUID) -> CrewOut:
    return CrewOut(
        id=c.id,
        name=c.name,
        is_mine=c.owner_id == viewer_id,
        members=[PersonOut(id=m.user_id, display_name=m.user.display_name) for m in c.members],
    )


# Friends


@router.post("/friends/code", response_model=FriendCodeOut, status_code=201)
async def make_code(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    code = "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))
    row = FriendCode(code=code, from_id=user.id, expires_at=now() + timedelta(days=CODE_DAYS))
    session.add(row)
    await session.commit()
    return FriendCodeOut(code=code, expires_at=row.expires_at)


@router.post("/friends/accept", response_model=PersonOut)
async def accept_code(
    body: FriendCodeAccept, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> PersonOut:
    row = await session.scalar(
        select(FriendCode).where(FriendCode.code == _normalize(body.code)).with_for_update(of=FriendCode)
    )
    if row is None or row.expires_at <= now():
        raise HTTPException(404, "That code didn't work. Codes last a week; ask for a fresh one.")
    if row.from_id == user.id:
        raise HTTPException(409, "That's your own code. Send it to a friend.")
    if row.used_by_id is not None and row.used_by_id != user.id:
        raise HTTPException(404, "That code's been used. Ask for a fresh one.")
    friend = PersonOut(id=row.from_id, display_name=row.sender.display_name)
    if not await are_friends(session, user.id, row.from_id):
        session.add_all(
            [
                Friendship(user_id=user.id, friend_id=row.from_id),
                Friendship(user_id=row.from_id, friend_id=user.id),
            ]
        )
    row.used_by_id = user.id
    row.used_at = row.used_at or now()
    await session.commit()
    return friend


@router.delete("/friends/{friend_id}", status_code=204)
async def unfriend(
    friend_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> Response:
    await session.execute(
        delete(Friendship).where(
            ((Friendship.user_id == user.id) & (Friendship.friend_id == friend_id))
            | ((Friendship.user_id == friend_id) & (Friendship.friend_id == user.id))
        )
    )
    await session.commit()
    return Response(status_code=204)


@router.post("/friends/{friend_id}/wave", status_code=204)
async def wave(
    friend_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> Response:
    if not await are_friends(session, user.id, friend_id):
        raise HTTPException(404, "Not a friend")
    session.add(Wave(from_id=user.id, to_id=friend_id))
    await session.commit()
    return Response(status_code=204)


# Everything on the People tab, in one call


@router.get("/people", response_model=People)
async def people(
    lat: float | None = Query(default=None, ge=-90, le=90),
    lon: float | None = Query(default=None, ge=-180, le=180),
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> People:
    t = now()
    friendships = list(
        (await session.scalars(select(Friendship).where(Friendship.user_id == user.id))).unique()
    )
    ids = {f.friend_id for f in friendships}

    lights = {
        p.user_id: p
        for p in await session.scalars(
            select(PorchLight).where(PorchLight.user_id.in_(ids | {user.id}), PorchLight.on_until > t)
        )
    }
    waves: dict[uuid.UUID, datetime] = {}
    if ids:
        for w in await session.scalars(
            select(Wave)
            .where(Wave.to_id == user.id, Wave.from_id.in_(ids), Wave.created_at > t - WAVE_SHOWS_FOR)
            .order_by(Wave.created_at)
        ):
            waves[w.from_id] = w.created_at
    out = await out_now(session, ids)

    friends = [
        FriendOut(
            id=f.friend_id,
            display_name=f.friend.display_name,
            porch_light=_porch_out(lights[f.friend_id], lat, lon) if f.friend_id in lights else None,
            out=out.get(f.friend_id),
            waved_at=waves.get(f.friend_id),
        )
        for f in sorted(friendships, key=lambda f: f.friend.display_name.lower())
    ]

    crew_ids = select(CrewMember.crew_id).where(CrewMember.user_id == user.id)
    crew_rows = await session.scalars(select(Crew).where(Crew.id.in_(crew_ids)).order_by(Crew.name))
    crews = [_crew_out(c, user.id) for c in crew_rows.unique()]

    invites = []
    for inv, g in (
        await session.execute(
            select(GatheringInvite, Gathering)
            .join(Gathering, Gathering.id == GatheringInvite.gathering_id)
            .where(GatheringInvite.to_id == user.id, Gathering.cancelled_at.is_(None), Gathering.ends_at > t)
            .order_by(Gathering.starts_at)
        )
    ).unique():
        if any(m.user_id == user.id for m in g.members):
            continue
        invites.append(
            GatheringInviteOut(
                gathering=gathering_out(g, user.id, friend_ids=ids),
                sender=PersonOut(id=inv.from_id, display_name=inv.sender.display_name),
                created_at=inv.created_at,
            )
        )

    mine = lights.get(user.id)
    return People(
        porch_light=_porch_out(mine, None, None) if mine else None,
        friends=friends,
        crews=crews,
        invites=invites,
    )


# Porch light


@router.put("/me/porch-light", response_model=PorchLightOut)
async def porch_light_on(
    body: PorchLightIn, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> PorchLightOut:
    light = await session.get(PorchLight, user.id)
    until = now() + timedelta(hours=body.hours)
    if light is None:
        light = PorchLight(user_id=user.id, on_until=until)
        session.add(light)
    light.on_until = until
    light.note = body.note.strip()
    light.lat, light.lon = body.lat, body.lon
    await session.commit()
    return _porch_out(light, None, None)


@router.delete("/me/porch-light", status_code=204)
async def porch_light_off(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    await session.execute(delete(PorchLight).where(PorchLight.user_id == user.id))
    await session.commit()
    return Response(status_code=204)


# Crews


@router.post("/crews", response_model=CrewOut, status_code=201)
async def make_crew(
    body: CrewCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> CrewOut:
    wanted = set(body.member_ids) - {user.id}
    if not wanted <= await friend_ids(session, user.id):
        raise HTTPException(422, "Only friends can be in a crew")
    crew = Crew(owner_id=user.id, name=body.name.strip())
    crew.members = [CrewMember(user_id=uid) for uid in [user.id, *sorted(wanted)]]
    session.add(crew)
    await session.commit()
    crew = await session.scalar(
        select(Crew).where(Crew.id == crew.id).execution_options(populate_existing=True)
    )
    return _crew_out(crew, user.id)


@router.delete("/crews/{crew_id}", status_code=204)
async def leave_crew(
    crew_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> Response:
    """The owner deletes the crew; anyone else leaves it."""
    crew = await session.get(Crew, crew_id)
    if crew is None or not any(m.user_id == user.id for m in crew.members):
        raise HTTPException(404, "Crew not found")
    if crew.owner_id == user.id:
        await session.delete(crew)
    else:
        await session.execute(
            delete(CrewMember).where(CrewMember.crew_id == crew_id, CrewMember.user_id == user.id)
        )
    await session.commit()
    return Response(status_code=204)
