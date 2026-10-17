"""Tables. Schema changes go through Alembic (backend/alembic), never create_all in the app."""

import uuid
from datetime import datetime

from sqlalchemy import (
    ARRAY,
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

GENRES = ("play", "move", "music", "party", "food")


def _uuid() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)


def _created() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class User(Base):
    __tablename__ = "users"
    id: Mapped[uuid.UUID] = _uuid()
    display_name: Mapped[str] = mapped_column(String(60), nullable=False)
    token_hash: Mapped[str] = mapped_column(String(64), nullable=False, unique=True)
    created_at: Mapped[datetime] = _created()


class Gathering(Base):
    __tablename__ = "gatherings"
    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="gathering_ends_after_start"),
        CheckConstraint("capacity >= 0", name="gathering_capacity_nonnegative"),
    )
    id: Mapped[uuid.UUID] = _uuid()
    host_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    title: Mapped[str] = mapped_column(String(120), nullable=False)
    genre: Mapped[str] = mapped_column(String(16), nullable=False)
    details: Mapped[str] = mapped_column(Text, nullable=False, default="")
    place_name: Mapped[str] = mapped_column(String(120), nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False, index=True)
    lon: Mapped[float] = mapped_column(Float, nullable=False, index=True)
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    # 0 means open, no cap.
    capacity: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    bring: Mapped[str] = mapped_column(String(200), nullable=False, default="")
    recurring: Mapped[str] = mapped_column(String(60), nullable=False, default="")
    cancelled_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = _created()

    host: Mapped[User] = relationship(lazy="joined", innerjoin=True)
    members: Mapped[list["GatheringMember"]] = relationship(
        back_populates="gathering", cascade="all, delete-orphan", lazy="selectin"
    )


class GatheringMember(Base):
    __tablename__ = "gathering_members"
    gathering_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("gatherings.id", ondelete="CASCADE"), primary_key=True
    )
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    joined_at: Mapped[datetime] = _created()
    checked_in_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

    gathering: Mapped[Gathering] = relationship(back_populates="members")


class Kitchen(Base):
    __tablename__ = "kitchens"
    id: Mapped[uuid.UUID] = _uuid()
    owner_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False, unique=True
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    cuisine: Mapped[str] = mapped_column(String(60), nullable=False)
    story: Mapped[str] = mapped_column(Text, nullable=False, default="")
    lat: Mapped[float] = mapped_column(Float, nullable=False, index=True)
    lon: Mapped[float] = mapped_column(Float, nullable=False, index=True)
    # Only shown to the owner and to people with an order.
    pickup_note: Mapped[str] = mapped_column(String(300), nullable=False, default="")
    porch_tables: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    permit_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    handler_card_confirmed: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = _created()

    owner: Mapped[User] = relationship(lazy="joined", innerjoin=True)
    menu: Mapped[list["MenuItem"]] = relationship(
        back_populates="kitchen",
        cascade="all, delete-orphan",
        lazy="selectin",
        order_by="MenuItem.sort_index",
    )
    drops: Mapped[list["Drop"]] = relationship(
        back_populates="kitchen", cascade="all, delete-orphan", lazy="selectin", order_by="Drop.starts_at"
    )


class MenuItem(Base):
    __tablename__ = "menu_items"
    __table_args__ = (CheckConstraint("price_cents > 0", name="menu_price_positive"),)
    id: Mapped[uuid.UUID] = _uuid()
    kitchen_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("kitchens.id", ondelete="CASCADE"), nullable=False
    )
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    note: Mapped[str] = mapped_column(String(160), nullable=False, default="")
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    sort_index: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    # Removed items stay for old orders but leave the menu.
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    kitchen: Mapped[Kitchen] = relationship(back_populates="menu")


class Drop(Base):
    """A fixed batch at a set time."""

    __tablename__ = "drops"
    __table_args__ = (
        CheckConstraint("ends_at > starts_at", name="drop_ends_after_start"),
        CheckConstraint("sold >= 0 AND sold <= total", name="drop_sold_within_total"),
        CheckConstraint("per_slot > 0", name="drop_per_slot_positive"),
    )
    id: Mapped[uuid.UUID] = _uuid()
    kitchen_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("kitchens.id", ondelete="CASCADE"), nullable=False
    )
    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ends_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    total: Mapped[int] = mapped_column(Integer, nullable=False)
    sold: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    per_slot: Mapped[int] = mapped_column(Integer, nullable=False, default=4)

    kitchen: Mapped[Kitchen] = relationship(back_populates="drops")


class Order(Base):
    __tablename__ = "orders"
    __table_args__ = (UniqueConstraint("buyer_id", "client_id", name="orders_buyer_client_unique"),)
    id: Mapped[uuid.UUID] = _uuid()
    # Generated on the phone, so a retried request can't create a second order.
    client_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    buyer_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    kitchen_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("kitchens.id", ondelete="CASCADE"), nullable=False
    )
    drop_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("drops.id", ondelete="CASCADE"), nullable=False)
    pickup_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    eat_on_porch: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    # reserved → picked_up → reviewed
    status: Mapped[str] = mapped_column(String(16), nullable=False, default="reserved")
    subtotal_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    service_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = _created()

    kitchen: Mapped[Kitchen] = relationship(lazy="joined", innerjoin=True)
    lines: Mapped[list["OrderLine"]] = relationship(cascade="all, delete-orphan", lazy="selectin")


class OrderLine(Base):
    __tablename__ = "order_lines"
    __table_args__ = (CheckConstraint("quantity > 0", name="order_line_quantity_positive"),)
    id: Mapped[uuid.UUID] = _uuid()
    order_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), nullable=False)
    menu_item_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("menu_items.id"), nullable=False)
    # Copied at order time so a later price change doesn't rewrite history.
    name: Mapped[str] = mapped_column(String(80), nullable=False)
    price_cents: Mapped[int] = mapped_column(Integer, nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)


class Review(Base):
    __tablename__ = "reviews"
    __table_args__ = (CheckConstraint("stars BETWEEN 1 AND 5", name="review_stars_range"),)
    id: Mapped[uuid.UUID] = _uuid()
    kitchen_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("kitchens.id", ondelete="CASCADE"), nullable=False, index=True
    )
    order_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("orders.id", ondelete="CASCADE"), unique=True)
    author_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    stars: Mapped[int] = mapped_column(Integer, nullable=False)
    tags: Mapped[list[str]] = mapped_column(ARRAY(String(40)), nullable=False, default=list)
    text: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = _created()

    author: Mapped[User] = relationship(lazy="joined", innerjoin=True)
