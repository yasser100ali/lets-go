from datetime import UTC, date, datetime, timedelta

import pytest
from pydantic import ValidationError
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.listings_import import upsert
from app.schemas import ListingIn


def listing(title: str, **over) -> ListingIn:
    body = {
        "title": title,
        "genre": "music",
        "venue": "The Independent",
        "address": "628 Divisadero St, San Francisco, CA 94117",
        "lat": 37.7755,
        "lon": -122.4377,
        "schedule": {"weekday": "Saturday", "start": "21:00", "end": None},
        "price": "See tickets",
        "url": "https://example.com/show",
        "confidence": "high",
    } | over
    return ListingIn.model_validate(body)


def day(offset: int) -> str:
    return (date.today() + timedelta(days=offset)).isoformat()


async def load(engine, items: list[ListingIn], source: str = "manual") -> dict[str, int]:
    async with async_sessionmaker(engine, expire_on_commit=False)() as s:
        return await upsert(s, items, "sf", source, datetime.now(UTC))


async def test_weekly_and_upcoming_are_listed_past_ones_are_not(client, engine):
    await load(
        engine,
        [
            listing("Weekly jam"),
            listing("Next week's show", schedule={"date": day(7), "start": "20:00"}),
            listing("Last month's show", schedule={"date": day(-30), "start": "20:00"}),
        ],
    )
    r = await client.get("/v1/listings")
    assert r.status_code == 200, r.text
    got = {item["title"]: item for item in r.json()["listings"]}
    assert set(got) == {"Next week's show", "Weekly jam"}
    assert got["Weekly jam"]["schedule"] == [
        {"weekday": "Saturday", "date": None, "start": "21:00", "end": None}
    ]
    assert got["Next week's show"]["schedule"][0]["date"] == day(7)


async def test_reimport_updates_and_marks_dropped_ones_gone(client, engine):
    first = await load(engine, [listing("Weekly jam"), listing("Old residency")])
    assert first == {"added": 2, "updated": 0, "gone": 0}

    second = await load(engine, [listing("Weekly jam", price="Free"), listing("New thing")])
    assert second == {"added": 1, "updated": 1, "gone": 1}
    got = {item["title"]: item for item in (await client.get("/v1/listings")).json()["listings"]}
    assert set(got) == {"Weekly jam", "New thing"}
    assert got["Weekly jam"]["price"] == "Free"


async def test_another_source_leaves_manual_ones_alone(client, engine):
    await load(engine, [listing("Weekly jam")])
    counts = await load(engine, [listing("Ticketed show")], source="ticketmaster")
    assert counts == {"added": 1, "updated": 0, "gone": 0}
    assert len((await client.get("/v1/listings")).json()["listings"]) == 2


async def test_other_cities_are_separate(client, engine):
    await load(engine, [listing("Weekly jam")])
    r = await client.get("/v1/listings", params={"city": "la"})
    assert r.json()["listings"] == []


@pytest.mark.parametrize(
    "schedule",
    [
        {"start": "20:00"},
        {"weekday": "Saturday", "date": "2026-10-24", "start": "20:00"},
        {"weekday": "Caturday", "start": "20:00"},
        {"weekday": "Saturday", "start": "8pm"},
    ],
)
async def test_bad_slots_are_rejected(schedule):
    with pytest.raises(ValidationError):
        listing("Broken", schedule=schedule)
