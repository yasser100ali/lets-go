from datetime import timedelta
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import Listing
from app.schemas import ListingOut, Listings
from app.views import now

router = APIRouter(prefix="/v1", tags=["listings"])

CITY_TIME = {"sf": ZoneInfo("America/Los_Angeles")}


@router.get("/listings", response_model=Listings)
async def listings(
    city: str = Query(default="sf", max_length=16), session: AsyncSession = Depends(get_session)
) -> Listings:
    """Everything live in `city` with a date still ahead. Weekly ones always have one. Public: you can
    see what's on before you have an account."""
    # From yesterday, so a show that runs past midnight is still there in the small hours.
    since = (now().astimezone(CITY_TIME.get(city, ZoneInfo("UTC"))) - timedelta(days=1)).date().isoformat()
    rows = await session.scalars(
        select(Listing).where(Listing.city == city, Listing.status == "live").order_by(Listing.title)
    )
    return Listings(
        listings=[
            ListingOut.model_validate(row)
            for row in rows
            if any("weekday" in s or s.get("date", "") >= since for s in row.schedule)
        ]
    )
