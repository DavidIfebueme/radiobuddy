from __future__ import annotations

from fastapi.testclient import TestClient

from radiobuddy_api.main import app
from radiobuddy_api.platform.config import settings
from radiobuddy_api.platform.db import session as db_session


def test_sites_returns_503_when_db_not_configured() -> None:
    original_url = settings.database_url
    original_engine = db_session._engine
    original_session_local = db_session._SessionLocal

    settings.database_url = None
    db_session._engine = None
    db_session._SessionLocal = None

    try:
        client = TestClient(app)
        resp = client.get("/sites")
        assert resp.status_code == 503
        assert resp.headers.get("x-request-id")
        body = resp.json()
        assert body["error"] == "http_error"
        assert body["request_id"]
        assert body["detail"] == "RADIOBUDDY_DATABASE_URL is not set"
    finally:
        settings.database_url = original_url
        db_session._engine = original_engine
        db_session._SessionLocal = original_session_local
