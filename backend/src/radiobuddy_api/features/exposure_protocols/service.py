from __future__ import annotations

import json
from pathlib import Path
from typing import Any

_RESOURCE_PATH = Path(__file__).resolve().parents[4] / "resources" / "exposure_protocol.json"


def get_chest_pa_protocol() -> dict[str, Any]:
    return json.loads(_RESOURCE_PATH.read_text(encoding="utf-8"))
