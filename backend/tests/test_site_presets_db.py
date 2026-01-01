from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

from radiobuddy_api.main import app
from radiobuddy_api.platform.config import settings


@pytest.mark.skipif(not settings.database_url, reason="RADIOBUDDY_DATABASE_URL not set")
def test_site_room_protocol_roundtrip() -> None:
    assert settings.database_url

    site_id = f"test_site_{uuid.uuid4().hex[:8]}"
    room_id = f"room_{uuid.uuid4().hex[:8]}"
    procedure_id = "chest_pa_erect"

    client = TestClient(app)

    try:
        resp = client.post("/sites", json={"site_id": site_id, "name": "Test Site"})
        assert resp.status_code == 200
        assert resp.headers.get("x-request-id")
        assert resp.json()["site_id"] == site_id

        resp = client.post(
            f"/sites/{site_id}/rooms",
            json={"room_id": room_id, "name": "Room 1"},
        )
        assert resp.status_code == 200
        assert resp.json()["room_id"] == room_id

        payload = {
            "schema_version": "v1",
            "protocol_id": "demo_chest_pa_protocol",
            "protocol_name": "Chest PA (Erect)",
            "protocol_version": "v1",
            "procedure_id": procedure_id,
            "assumptions": ["Starting point only"],
            "recommendations": [
                {
                    "inputs": {
                        "projection": procedure_id,
                        "size_class": "average",
                        "grid": True,
                        "sid_cm": 180,
                        "detector": "dr",
                    },
                    "output": {"kvp": 120, "mas": 1.6},
                }
            ],
        }

        resp = client.put(
            f"/sites/{site_id}/rooms/{room_id}/exposure-protocols/{procedure_id}",
            json=payload,
        )
        assert resp.status_code == 200
        body = resp.json()
        assert body["site_id"] == site_id
        assert body["room_id"] == room_id
        assert body["procedure_id"] == procedure_id
        assert body["protocol_id"] == payload["protocol_id"]

        resp = client.get(f"/sites/{site_id}/rooms/{room_id}/exposure-protocols/{procedure_id}")
        assert resp.status_code == 200
        body = resp.json()
        assert body["site_id"] == site_id
        assert body["room_id"] == room_id
        assert body["procedure_id"] == procedure_id
        assert body["protocol_id"] == payload["protocol_id"]

    finally:
        engine = create_engine(settings.database_url)
        with engine.begin() as conn:
            conn.execute(
                text("DELETE FROM room_exposure_protocols WHERE site_id = :site_id"),
                {"site_id": site_id},
            )
            conn.execute(text("DELETE FROM rooms WHERE site_id = :site_id"), {"site_id": site_id})
            conn.execute(text("DELETE FROM sites WHERE site_id = :site_id"), {"site_id": site_id})
