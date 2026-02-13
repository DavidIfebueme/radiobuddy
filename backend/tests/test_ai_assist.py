from __future__ import annotations

from fastapi.testclient import TestClient

from radiobuddy_api.main import app


def test_ai_assist_local_without_model_key(monkeypatch) -> None:
    from radiobuddy_api.features.ai_assist import service

    monkeypatch.setattr(service.settings, "do_inference_enabled", True)
    monkeypatch.setattr(service.settings, "do_model_access_key", None)

    client = TestClient(app)
    payload = {
        "procedure_id": "chest_pa",
        "stage_id": "coarse",
        "metrics": {
            "pose_confidence": 0.9,
            "framing_score": 0.9,
            "motion_score": 0.1,
            "rotation_risk": 0.8,
            "tilt_risk": 0.1,
            "chin_risk": 0.1,
            "scapula_risk": 0.1,
        },
    }
    response = client.post("/ai/positioning/analyze", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["source"] == "local"
    assert isinstance(data["instruction"], str)
    assert len(data["instruction"]) > 0


def test_ai_assist_fallback_when_remote_errors(monkeypatch) -> None:
    from radiobuddy_api.features.ai_assist import service

    async def failing_remote(payload):
        raise RuntimeError("boom")

    monkeypatch.setattr(service.settings, "do_inference_enabled", True)
    monkeypatch.setattr(service.settings, "do_model_access_key", "test_key")
    monkeypatch.setattr(service.settings, "do_model_id", "llama3.3-70b-instruct")
    monkeypatch.setattr(service, "_do_inference_instruction", failing_remote)

    client = TestClient(app)
    payload = {
        "procedure_id": "chest_pa",
        "stage_id": "fine",
        "metrics": {
            "pose_confidence": 0.9,
            "framing_score": 0.8,
            "motion_score": 0.1,
            "rotation_risk": 0.2,
            "tilt_risk": 0.2,
            "chin_risk": 0.1,
            "scapula_risk": 0.1,
        },
    }
    response = client.post("/ai/positioning/analyze", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["source"] == "do_inference_fallback"
    assert isinstance(data["instruction"], str)
    assert len(data["instruction"]) > 0


def test_ai_assist_local_when_remote_disabled(monkeypatch) -> None:
    from radiobuddy_api.features.ai_assist import service

    monkeypatch.setattr(service.settings, "do_inference_enabled", False)
    monkeypatch.setattr(service.settings, "do_model_access_key", "test_key")

    client = TestClient(app)
    payload = {
        "procedure_id": "chest_pa",
        "stage_id": "coarse",
        "metrics": {
            "pose_confidence": 0.4,
            "framing_score": 0.4,
            "motion_score": 0.1,
            "rotation_risk": 0.1,
            "tilt_risk": 0.1,
            "chin_risk": 0.1,
            "scapula_risk": 0.1,
        },
    }
    response = client.post("/ai/positioning/analyze", json=payload)

    assert response.status_code == 200
    data = response.json()
    assert data["source"] == "local"
