from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import current_user, hash_token, new_token
from app.db import get_session
from app.models import User
from app.schemas import UserCreate, UserCreated, UserOut

router = APIRouter(prefix="/v1", tags=["users"])


@router.post("/users", response_model=UserCreated, status_code=201)
async def create_user(body: UserCreate, session: AsyncSession = Depends(get_session)) -> UserCreated:
    token = new_token()
    user = User(display_name=body.display_name.strip(), token_hash=hash_token(token))
    session.add(user)
    await session.commit()
    return UserCreated(user=UserOut.model_validate(user), token=token)


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(current_user)) -> User:
    return user


@router.patch("/me", response_model=UserOut)
async def rename(
    body: UserCreate, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)
) -> User:
    user.display_name = body.display_name.strip()
    await session.commit()
    return user
