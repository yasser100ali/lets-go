import uuid
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user
from app.db import get_session
from app.models import Drop, MenuItem, Order, OrderLine, Review, User
from app.pricing import service_fee
from app.schemas import OrderCreate, OrderOut, ReviewCreate
from app.views import now, order_out

router = APIRouter(prefix="/v1/orders", tags=["orders"])

SLOT = timedelta(minutes=15)


@router.post("", response_model=OrderOut, status_code=201)
async def reserve(
    body: OrderCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> OrderOut:
    """Reserve from a drop. Safe to retry: the same client_id returns the same order."""
    existing = await session.scalar(
        select(Order).where(Order.buyer_id == user.id, Order.client_id == body.client_id)
    )
    if existing is not None:
        return order_out(existing)

    # Lock the drop: stock and slot counts are checked and taken in one go.
    drop = await session.scalar(select(Drop).where(Drop.id == body.drop_id).with_for_update())
    if drop is None:
        raise HTTPException(404, "Drop not found")
    if drop.ends_at <= now():
        raise HTTPException(409, "This drop is over")
    await session.refresh(drop, ["kitchen"])
    if drop.kitchen.owner_id == user.id:
        raise HTTPException(409, "You can't order from your own kitchen")

    offset = body.pickup_at - drop.starts_at
    if body.pickup_at < drop.starts_at or body.pickup_at >= drop.ends_at or offset % SLOT != timedelta(0):
        raise HTTPException(422, "Pick one of the drop's 15-minute pickup slots")
    if body.pickup_at + SLOT < now():
        raise HTTPException(409, "That pickup slot has passed")

    ids = [line.menu_item_id for line in body.lines]
    items = {m.id: m for m in await session.scalars(select(MenuItem).where(MenuItem.id.in_(ids)))}
    for line in body.lines:
        m = items.get(line.menu_item_id)
        if m is None or m.kitchen_id != drop.kitchen_id or not m.active:
            raise HTTPException(422, "That item isn't on this kitchen's menu")

    count = sum(line.quantity for line in body.lines)
    if count > drop.total - drop.sold:
        raise HTTPException(409, f"Only {drop.total - drop.sold} left")
    in_slot = await session.scalar(
        select(func.count())
        .select_from(Order)
        .where(Order.drop_id == drop.id, Order.pickup_at == body.pickup_at)
    )
    if in_slot >= drop.per_slot:
        raise HTTPException(409, "That pickup slot is full")
    if body.eat_on_porch and drop.kitchen.porch_tables == 0:
        raise HTTPException(422, "This kitchen has no porch seating")

    subtotal = sum(items[line.menu_item_id].price_cents * line.quantity for line in body.lines)
    order = Order(
        client_id=body.client_id,
        buyer_id=user.id,
        kitchen_id=drop.kitchen_id,
        drop_id=drop.id,
        pickup_at=body.pickup_at,
        eat_on_porch=body.eat_on_porch,
        subtotal_cents=subtotal,
        service_cents=service_fee(subtotal),
        lines=[
            OrderLine(menu_item_id=m.id, name=m.name, price_cents=m.price_cents, quantity=line.quantity)
            for line in body.lines
            for m in [items[line.menu_item_id]]
        ],
    )
    drop.sold += count
    session.add(order)
    await session.commit()
    order = await session.scalar(select(Order).where(Order.id == order.id))
    return order_out(order)


@router.get("", response_model=list[OrderOut])
async def my_orders(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    orders = await session.scalars(
        select(Order).where(Order.buyer_id == user.id).order_by(Order.pickup_at.desc()).limit(50)
    )
    return [order_out(o) for o in orders.unique()]


async def _my_order(session: AsyncSession, order_id: uuid.UUID, user: User) -> Order:
    o = await session.get(Order, order_id)
    if o is None or o.buyer_id != user.id:
        raise HTTPException(404, "Order not found")
    return o


@router.post("/{order_id}/picked-up", response_model=OrderOut)
async def picked_up(
    order_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> OrderOut:
    o = await _my_order(session, order_id, user)
    if o.status == "reserved":
        o.status = "picked_up"
        await session.commit()
    return order_out(o)


@router.post("/{order_id}/review", response_model=OrderOut)
async def review(
    order_id: uuid.UUID,
    body: ReviewCreate,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
) -> OrderOut:
    """One review per order, after pickup."""
    o = await _my_order(session, order_id, user)
    if o.status == "reserved":
        raise HTTPException(409, "Pick it up first")
    if o.status == "reviewed":
        raise HTTPException(409, "Already reviewed")
    session.add(
        Review(
            kitchen_id=o.kitchen_id,
            order_id=o.id,
            author_id=user.id,
            stars=body.stars,
            tags=[t.strip()[:40] for t in body.tags if t.strip()],
            text=body.text.strip(),
        )
    )
    o.status = "reviewed"
    await session.commit()
    return order_out(o)
