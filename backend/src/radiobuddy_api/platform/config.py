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
    admin_api_key: str | None = None
    do_model_access_key: str | None = None
    do_model_id: str = "llama3.3-70b-instruct"
    do_inference_timeout_seconds: float = 8.0


settings = Settings()
