from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from radiobuddy_api.platform.json_schema import validate_instance

_RESOURCE_PATH = Path(__file__).resolve().parents[4] / "resources" / "chest_pa_rules.json"


def get_chest_pa_rules() -> dict[str, Any]:
    payload = json.loads(_RESOURCE_PATH.read_text(encoding="utf-8"))
    validate_instance("procedure_rules.schema.json", payload)
    return payload


def _normalize_procedure_id(procedure_id: str) -> str:
    normalized = procedure_id.strip().lower().replace("-", "_")
    if normalized == "chest_pa":
        return "chest_pa_erect"
    return normalized


def get_rules(procedure_id: str) -> dict[str, Any] | None:
    normalized_procedure_id = _normalize_procedure_id(procedure_id)

    if normalized_procedure_id == "chest_pa_erect":
        return get_chest_pa_rules()

    return None
