from __future__ import annotations

import json
from pathlib import Path

from radiobuddy_api.platform.json_schema import validate_instance


def test_resources_conform_to_schemas() -> None:
    repo_root = Path(__file__).resolve().parents[2]

    procedure_rules = json.loads(
        (repo_root / "backend" / "resources" / "chest_pa_rules.json").read_text(encoding="utf-8")
    )
    exposure_protocol = json.loads(
        (repo_root / "backend" / "resources" / "exposure_protocol.json").read_text(encoding="utf-8")
    )

    validate_instance("procedure_rules.schema.json", procedure_rules)
    validate_instance("exposure_protocol.schema.json", exposure_protocol)
