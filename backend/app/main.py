from fastapi import FastAPI

from app.routes import gatherings, kitchens, listings, orders, people, users

app = FastAPI(title="Let's Go", version="0.1.0")
app.include_router(users.router)
app.include_router(gatherings.router)
app.include_router(kitchens.router)
app.include_router(orders.router)
app.include_router(listings.router)
app.include_router(people.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
