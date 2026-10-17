from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    database_url: str = "postgresql+asyncpg://letsgo:letsgo_dev@localhost:5433/letsgo"
    # How close you have to be to check in, in meters.
    check_in_radius_m: float = 200
    # Check-in opens this many minutes before a gathering starts.
    check_in_early_min: int = 30
    # The default "near you" radius for the map.
    nearby_radius_m: float = 2500

    @field_validator("database_url")
    @classmethod
    def _async_driver(cls, url: str) -> str:
        """Railway hands out postgresql:// (or postgres://); SQLAlchemy async needs the asyncpg driver."""
        for prefix in ("postgres://", "postgresql://"):
            if url.startswith(prefix):
                return "postgresql+asyncpg://" + url[len(prefix) :]
        return url


settings = Settings()
