from __future__ import annotations

from fastapi.testclient import TestClient

from radiobuddy_api.main import app


def test_unified_exposure_protocol_fallback_chest_pa_erect() -> None:
    client = TestClient(app)
    resp = client.get("/exposure-protocols/chest_pa_erect")
    assert resp.status_code == 200
    data = resp.json()
    assert data["procedure_id"] == "chest_pa_erect"


def test_unified_exposure_protocol_unknown_returns_404_envelope() -> None:
    client = TestClient(app)
    resp = client.get("/exposure-protocols/not_a_real_procedure")
    assert resp.status_code == 404
    body = resp.json()
    assert body["error"] == "http_error"
    assert body["request_id"]
