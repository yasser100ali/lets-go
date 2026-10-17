import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

Genre = Literal["play", "move", "music", "party", "food"]


class Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


# Users


class UserCreate(BaseModel):
    display_name: str = Field(min_length=1, max_length=60)


class UserOut(Out):
    id: uuid.UUID
    display_name: str


class UserCreated(BaseModel):
    user: UserOut
    token: str


# Gatherings


class GatheringCreate(BaseModel):
    title: str = Field(min_length=1, max_length=120)
    genre: Genre
    details: str = Field(default="", max_length=2000)
    place_name: str = Field(min_length=1, max_length=120)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    starts_at: datetime
    ends_at: datetime
    capacity: int = Field(default=0, ge=0, le=500)
    bring: str = Field(default="", max_length=200)
    recurring: str = Field(default="", max_length=60)

    @model_validator(mode="after")
    def _ends_after_start(self):
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        if self.genre == "food":
            raise ValueError("food is sold through kitchens, not gatherings")
        return self


class GatheringOut(Out):
    id: uuid.UUID
    title: str
    genre: Genre
    details: str
    place_name: str
    lat: float
    lon: float
    starts_at: datetime
    ends_at: datetime
    capacity: int
    bring: str
    recurring: str
    host_name: str
    going: int
    is_mine: bool
    is_joined: bool
    checked_in_at: datetime | None
    distance_m: float | None = None


class CheckIn(BaseModel):
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)


# Kitchens


class KitchenCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    cuisine: str = Field(min_length=1, max_length=60)
    story: str = Field(default="", max_length=1000)
    lat: float = Field(ge=-90, le=90)
    lon: float = Field(ge=-180, le=180)
    pickup_note: str = Field(default="", max_length=300)
    porch_tables: int = Field(default=0, ge=0, le=20)
    permit_confirmed: bool = False
    handler_card_confirmed: bool = False


class KitchenUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=80)
    cuisine: str | None = Field(default=None, min_length=1, max_length=60)
    story: str | None = Field(default=None, max_length=1000)
    pickup_note: str | None = Field(default=None, max_length=300)
    porch_tables: int | None = Field(default=None, ge=0, le=20)
    permit_confirmed: bool | None = None
    handler_card_confirmed: bool | None = None


class MenuItemCreate(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    note: str = Field(default="", max_length=160)
    price_cents: int = Field(gt=0, le=100_000)


class MenuItemOut(Out):
    id: uuid.UUID
    name: str
    note: str
    price_cents: int


class DropCreate(BaseModel):
    starts_at: datetime
    ends_at: datetime
    total: int = Field(gt=0, le=1000)
    per_slot: int = Field(default=4, gt=0, le=100)

    @model_validator(mode="after")
    def _ends_after_start(self):
        if self.ends_at <= self.starts_at:
            raise ValueError("ends_at must be after starts_at")
        return self


class DropOut(Out):
    id: uuid.UUID
    starts_at: datetime
    ends_at: datetime
    total: int
    sold: int
    per_slot: int
    left: int


class ReviewOut(Out):
    stars: int
    tags: list[str]
    text: str
    author_name: str
    created_at: datetime


class KitchenOut(Out):
    id: uuid.UUID
    name: str
    cook_name: str
    cuisine: str
    story: str
    lat: float
    lon: float
    porch_tables: int
    permitted: bool
    rating: float | None
    review_count: int
    next_drop: DropOut | None
    is_mine: bool
    distance_m: float | None = None


class KitchenDetail(KitchenOut):
    menu: list[MenuItemOut]
    reviews: list[ReviewOut]
    # Present only for the owner and for people with an order here.
    pickup_note: str | None


class Nearby(BaseModel):
    gatherings: list[GatheringOut]
    kitchens: list[KitchenOut]


# Orders


class OrderLineIn(BaseModel):
    menu_item_id: uuid.UUID
    quantity: int = Field(gt=0, le=50)


class OrderCreate(BaseModel):
    client_id: uuid.UUID
    drop_id: uuid.UUID
    pickup_at: datetime
    lines: list[OrderLineIn] = Field(min_length=1, max_length=20)
    eat_on_porch: bool = False


class OrderLineOut(Out):
    name: str
    price_cents: int
    quantity: int


class OrderOut(Out):
    id: uuid.UUID
    client_id: uuid.UUID
    kitchen_id: uuid.UUID
    kitchen_name: str
    drop_id: uuid.UUID
    pickup_at: datetime
    eat_on_porch: bool
    status: Literal["reserved", "picked_up", "reviewed"]
    lines: list[OrderLineOut]
    subtotal_cents: int
    service_cents: int
    total_cents: int
    pickup_note: str


class ReviewCreate(BaseModel):
    stars: int = Field(ge=1, le=5)
    tags: list[str] = Field(default_factory=list, max_length=8)
    text: str = Field(default="", max_length=2000)
