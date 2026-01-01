from __future__ import annotations

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_prefix="RADIOBUDDY_",
        extra="ignore",
    )

    environment: str = "dev"
    log_level: str = "INFO"
    database_url: str | None = None


settings = Settings()
