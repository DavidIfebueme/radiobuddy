from __future__ import annotations

from fastapi import Header, HTTPException

from radiobuddy_api.platform.config import settings


def require_admin_api_key(x_api_key: str | None = Header(default=None)) -> None:
    expected = settings.admin_api_key
    if not expected:
        raise HTTPException(status_code=503, detail="RADIOBUDDY_ADMIN_API_KEY is not set")
    if not x_api_key or x_api_key != expected:
        raise HTTPException(status_code=401, detail="unauthorized")
