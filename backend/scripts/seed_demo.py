from __future__ import annotations

import json
from pathlib import Path

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from radiobuddy_api.features.site_presets.schemas import ExposureProtocolUpsertIn
from radiobuddy_api.features.site_presets.service import (
    create_room,
    create_site,
    upsert_room_exposure_protocol,
)
from radiobuddy_api.platform.config import settings


def main() -> None:
    if not settings.database_url:
        raise SystemExit("RADIOBUDDY_DATABASE_URL is not set")

    engine = create_engine(settings.database_url, pool_pre_ping=True)

    repo_root = Path(__file__).resolve().parents[2]
    exposure_protocol_path = repo_root / "backend" / "resources" / "exposure_protocol.json"
    payload = json.loads(exposure_protocol_path.read_text(encoding="utf-8"))

    site_id = payload.get("site_id") or "demo_site"
    room_id = payload.get("room_id") or "room_1"
    procedure_id = payload.get("procedure_id") or "chest_pa_erect"

    upsert_in = ExposureProtocolUpsertIn.model_validate(payload)

    with Session(engine) as db:
        try:
            create_site(db, site_id=site_id, name="Demo Site")
        except Exception:
            db.rollback()

        try:
            create_room(db, site_id=site_id, room_id=room_id, name="Room 1")
        except Exception:
            db.rollback()

        upsert_room_exposure_protocol(
            db,
            site_id=site_id,
            room_id=room_id,
            procedure_id=procedure_id,
            payload=upsert_in,
        )

    print(f"Seeded site_id={site_id} room_id={room_id} procedure_id={procedure_id}")


if __name__ == "__main__":
    main()
