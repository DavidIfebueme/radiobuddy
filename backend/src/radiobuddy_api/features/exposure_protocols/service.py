from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from radiobuddy_api.features.site_presets.models import RoomExposureProtocol
from radiobuddy_api.platform.config import settings
from radiobuddy_api.platform.json_schema import validate_instance

_RESOURCE_PATH = Path(__file__).resolve().parents[4] / "resources" / "exposure_protocol.json"


def get_chest_pa_protocol() -> dict[str, Any]:
    payload = json.loads(_RESOURCE_PATH.read_text(encoding="utf-8"))
    validate_instance("exposure_protocol.schema.json", payload)
    return payload


def _normalize_procedure_id(procedure_id: str) -> str:
    normalized = procedure_id.strip().lower().replace("-", "_")
    if normalized == "chest_pa":
        return "chest_pa_erect"
    return normalized


def _get_from_db(site_id: str, room_id: str, procedure_id: str) -> dict[str, Any] | None:
    if not settings.database_url:
        return None

    engine = create_engine(settings.database_url, pool_pre_ping=True)
    with Session(engine) as db:
        row = db.get(
            RoomExposureProtocol,
            {"site_id": site_id, "room_id": room_id, "procedure_id": procedure_id},
        )
        if row is None:
            return None
        validate_instance("exposure_protocol.schema.json", row.payload)
        return row.payload


def get_protocol(
    procedure_id: str,
    site_id: str | None,
    room_id: str | None,
) -> dict[str, Any] | None:
    normalized_procedure_id = _normalize_procedure_id(procedure_id)

    if site_id and room_id:
        payload = _get_from_db(
            site_id=site_id,
            room_id=room_id,
            procedure_id=normalized_procedure_id,
        )
        if payload is not None:
            return payload

    if normalized_procedure_id == "chest_pa_erect":
        return get_chest_pa_protocol()

    return None
