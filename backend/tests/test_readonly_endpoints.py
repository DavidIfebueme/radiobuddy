from __future__ import annotations

from fastapi.testclient import TestClient

from radiobuddy_api.main import app


def test_procedure_rules_chest_pa() -> None:
    client = TestClient(app)
    resp = client.get("/procedure-rules/chest-pa")
    assert resp.status_code == 200
    data = resp.json()
    assert data["procedure_id"] == "chest_pa_erect"


def test_exposure_protocols_chest_pa() -> None:
    client = TestClient(app)
    resp = client.get("/exposure-protocols/chest-pa")
    assert resp.status_code == 200
    data = resp.json()
    assert data["procedure_id"] == "chest_pa_erect"
