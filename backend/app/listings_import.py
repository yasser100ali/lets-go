"""Load a listings file (the shape of the app's sf_happenings.json) into the listings table.

    python -m app.listings_import ../ios/LetsGo/Resources/sf_happenings.json
    DATABASE_URL=<Railway Postgres public URL> python -m app.listings_import ../ios/...  # deployed

Rows match on city, title and venue: a match is updated, anything new is added, and rows from the same
source that the file no longer has are marked gone. One bad entry stops the whole import.
"""

import argparse
import asyncio
from datetime import datetime
from pathlib import Path

from pydantic import TypeAdapter
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import SessionLocal, engine
from app.models import Listing
from app.schemas import ListingIn
from app.views import now


def listing_key(city: str, title: str, venue: str) -> str:
    return f"{city}|{title.strip().lower()}|{venue.strip().lower()}"


def load(path: Path) -> list[ListingIn]:
    return TypeAdapter(list[ListingIn]).validate_json(path.read_bytes())


async def upsert(
    session: AsyncSession, items: list[ListingIn], city: str, source: str, at: datetime
) -> dict[str, int]:
    existing = {row.key: row for row in await session.scalars(select(Listing).where(Listing.city == city))}
    seen: set[str] = set()
    counts = {"added": 0, "updated": 0, "gone": 0}
    for item in items:
        key = listing_key(city, item.title, item.venue)
        if key in seen:
            continue
        seen.add(key)
        fields = item.model_dump(mode="json", exclude={"schedule"})
        fields["schedule"] = [s.model_dump(mode="json", exclude_none=True) for s in item.schedule]
        row = existing.get(key)
        if row is None:
            session.add(Listing(key=key, city=city, source=source, status="live", last_seen_at=at, **fields))
            counts["added"] += 1
            continue
        for name, value in fields.items():
            setattr(row, name, value)
        row.last_seen_at = at
        if row.status == "gone":
            row.status = "live"
        counts["updated"] += 1
    for key, row in existing.items():
        if key not in seen and row.source == source and row.status != "gone":
            row.status = "gone"
            counts["gone"] += 1
    await session.commit()
    return counts


async def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("path", type=Path)
    parser.add_argument("--city", default="sf")
    parser.add_argument("--source", default="manual")
    args = parser.parse_args()
    items = load(args.path)
    async with SessionLocal() as session:
        counts = await upsert(session, items, args.city, args.source, now())
    await engine.dispose()
    print(f"{len(items)} in {args.path.name}: " + ", ".join(f"{n} {k}" for k, n in counts.items()))


if __name__ == "__main__":
    asyncio.run(main())
