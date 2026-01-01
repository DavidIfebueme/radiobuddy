from __future__ import annotations

from fastapi.testclient import TestClient

from radiobuddy_api.main import app


def test_request_id_header_present() -> None:
    client = TestClient(app)
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.headers.get("x-request-id")


def test_404_uses_error_envelope() -> None:
    client = TestClient(app)
    resp = client.get("/does-not-exist")
    assert resp.status_code == 404
    body = resp.json()
    assert body["error"] == "http_error"
    assert body["request_id"]


def test_422_uses_error_envelope() -> None:
    client = TestClient(app)
    payload = {
        "schema_version": "nope",
        "event_id": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "timestamp": "2026-01-01T22:25:30.509Z",
        "event_type": "session_start",
        "procedure_id": "chest_pa",
    }
    resp = client.post("/telemetry/events", json=payload)
    assert resp.status_code == 422
    body = resp.json()
    assert body["error"] == "validation_error"
    assert body["request_id"]
    assert isinstance(body["detail"], list)
