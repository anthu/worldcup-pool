from __future__ import annotations

from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Snowflake connection
    snowflake_account: str = ""
    snowflake_database: str = "WORLDCUP_POOL"
    snowflake_schema: str = "APP_DATA"

    # Admin emails (comma-separated)
    admin_emails: str = ""

    # Match predictions close this many hours before each match kickoff
    prediction_lock_before_kickoff_hours: int = Field(default=1, ge=1, le=168)

    # After this instant (UTC), champion and top-scorer picks are read-only
    tournament_picks_lock_at_utc: str = "2026-06-11T18:00:00+00:00"

    # Max top scorer picks
    max_top_scorer_picks: int = 5

    # football-data.org competition code (for player directory)
    football_data_competition: str = "WC"


@lru_cache
def get_settings() -> Settings:
    return Settings()
