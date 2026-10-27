import uuid

from fastapi import APIRouter, Depends, HTTPException, Response
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user
from app.db import get_session
from app.models import Drop, Kitchen, MenuItem, Order, Review, User
from app.schemas import (
    DropCreate,
    DropOut,
    KitchenCreate,
    KitchenDetail,
    KitchenUpdate,
    MenuItemCreate,
    MenuItemOut,
    OrderOut,
    ReviewOut,
    TableFriend,
    TableOut,
)
from app.social import friend_ids
from app.views import drop_out, kitchen_out, next_drop, now, order_out, ratings

router = APIRouter(prefix="/v1/kitchens", tags=["kitchens"])


async def _mine(session: AsyncSession, user: User) -> Kitchen:
    k = await session.scalar(select(Kitchen).where(Kitchen.owner_id == user.id))
    if k is None:
        raise HTTPException(404, "You haven't opened a kitchen")
    return k


async def _detail(session: AsyncSession, k: Kitchen, user: User) -> KitchenDetail:
    rated = await ratings(session, [k.id])
    base = kitchen_out(k, user.id, rated.get(k.id))
    reviews = (
        await session.scalars(
            select(Review).where(Review.kitchen_id == k.id).order_by(Review.created_at.desc()).limit(20)
        )
    ).unique()
    has_order = await session.scalar(
        select(Order.id).where(Order.kitchen_id == k.id, Order.buyer_id == user.id).limit(1)
    )
    return KitchenDetail(
        table=await _table(session, k, user),
        **base.model_dump(),
        menu=[MenuItemOut.model_validate(m) for m in k.menu if m.active],
        reviews=[
            ReviewOut(
                stars=r.stars,
                tags=r.tags,
                text=r.text,
                author_name=r.author.display_name,
                created_at=r.created_at,
            )
            for r in reviews
        ],
        pickup_note=k.pickup_note if (k.owner_id == user.id or has_order) else None,
    )


async def _table(session: AsyncSession, k: Kitchen, user: User) -> TableOut | None:
    """The porch table at the next drop: four seats a table, first come. Names only your friends."""
    drop = next_drop(k, now())
    if k.porch_tables == 0 or drop is None:
        return None
    porch = list(
        (
            await session.scalars(
                select(Order)
                .where(Order.drop_id == drop.id, Order.eat_on_porch.is_(True))
                .order_by(Order.pickup_at)
            )
        ).unique()
    )
    friends = await friend_ids(session, user.id)
    names = {}
    if friends:
        buyers = {o.buyer_id for o in porch if o.buyer_id in friends}
        names = {u.id: u.display_name for u in await session.scalars(select(User).where(User.id.in_(buyers)))}
    return TableOut(
        seats=k.porch_tables * 4,
        taken=len(porch),
        friends=[
            TableFriend(id=o.buyer_id, display_name=names[o.buyer_id], pickup_at=o.pickup_at)
            for o in porch
            if o.buyer_id in names
        ],
    )


@router.post("", response_model=KitchenDetail, status_code=201)
async def open_kitchen(
    body: KitchenCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> KitchenDetail:
    k = Kitchen(owner_id=user.id, **body.model_dump())
    k.menu, k.drops = [], []
    session.add(k)
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "You already have a kitchen") from None
    k = await _mine(session, user)
    return await _detail(session, k, user)


@router.get("/me", response_model=KitchenDetail)
async def my_kitchen(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    return await _detail(session, await _mine(session, user), user)


@router.patch("/me", response_model=KitchenDetail)
async def update_kitchen(
    body: KitchenUpdate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> KitchenDetail:
    k = await _mine(session, user)
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(k, field, value)
    await session.commit()
    return await _detail(session, k, user)


@router.post("/me/menu", response_model=MenuItemOut, status_code=201)
async def add_menu_item(
    body: MenuItemCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> MenuItem:
    k = await _mine(session, user)
    item = MenuItem(kitchen_id=k.id, sort_index=len(k.menu), **body.model_dump())
    session.add(item)
    await session.commit()
    return item


@router.delete("/me/menu/{item_id}", status_code=204)
async def remove_menu_item(
    item_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> Response:
    k = await _mine(session, user)
    item = await session.get(MenuItem, item_id)
    if item is not None and item.kitchen_id == k.id:
        item.active = False
        await session.commit()
    return Response(status_code=204)


@router.post("/me/drops", response_model=DropOut, status_code=201)
async def post_drop(
    body: DropCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> DropOut:
    k = await _mine(session, user)
    if not any(m.active for m in k.menu):
        raise HTTPException(409, "Add something to the menu first")
    if not (k.permit_confirmed and k.handler_card_confirmed):
        raise HTTPException(409, "Confirm your permit and food handler card first")
    if body.ends_at <= now():
        raise HTTPException(422, "That drop has already ended")
    d = Drop(kitchen_id=k.id, **body.model_dump())
    session.add(d)
    await session.commit()
    return drop_out(d)


@router.get("/me/orders", response_model=list[OrderOut])
async def kitchen_orders(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    k = await _mine(session, user)
    orders = await session.scalars(select(Order).where(Order.kitchen_id == k.id).order_by(Order.pickup_at))
    return [order_out(o) for o in orders.unique()]


@router.get("/{kitchen_id}", response_model=KitchenDetail)
async def get_kitchen(
    kitchen_id: uuid.UUID, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> KitchenDetail:
    k = await session.get(Kitchen, kitchen_id)
    if k is None:
        raise HTTPException(404, "Kitchen not found")
    return await _detail(session, k, user)
