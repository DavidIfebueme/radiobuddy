from __future__ import annotations

import uuid

import pytest
from fastapi.testclient import TestClient

from radiobuddy_api.main import app
from radiobuddy_api.platform.config import settings


@pytest.mark.skipif(not settings.database_url, reason="RADIOBUDDY_DATABASE_URL not set")
def test_unified_exposure_protocol_prefers_db() -> None:
    site_id = f"test_site_{uuid.uuid4().hex[:8]}"
    room_id = f"room_{uuid.uuid4().hex[:8]}"
    procedure_id = "chest_pa_erect"

    client = TestClient(app)

    settings.admin_api_key = "test_admin_key"
    headers = {"x-api-key": settings.admin_api_key}

    resp = client.post(
        "/sites",
        json={"site_id": site_id, "name": "Test Site"},
        headers=headers,
    )
    assert resp.status_code == 200

    resp = client.post(
        f"/sites/{site_id}/rooms",
        json={"room_id": room_id, "name": "Room"},
        headers=headers,
    )
    assert resp.status_code == 200

    payload = {
        "schema_version": "v1",
        "protocol_id": f"protocol_{uuid.uuid4().hex[:8]}",
        "protocol_name": "Chest PA (Erect)",
        "protocol_version": "v1",
        "procedure_id": procedure_id,
        "assumptions": ["Starting point only"],
        "recommendations": [
            {
                "inputs": {"projection": procedure_id, "size_class": "average"},
                "output": {"kvp": 120, "mas": 1.6},
            }
        ],
    }

    resp = client.put(
        f"/sites/{site_id}/rooms/{room_id}/exposure-protocols/{procedure_id}",
        json=payload,
        headers=headers,
    )
    assert resp.status_code == 200

    resp = client.get(
        f"/exposure-protocols/{procedure_id}",
        params={"site_id": site_id, "room_id": room_id},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["protocol_id"] == payload["protocol_id"]
