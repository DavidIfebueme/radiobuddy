from __future__ import annotations

from sqlalchemy import desc, select
from sqlalchemy.orm import Session

from radiobuddy_api.features.telemetry.models import TelemetryEvent
from radiobuddy_api.features.telemetry.schemas import TelemetryEventIn


def store_event(db: Session, event: TelemetryEventIn) -> None:
    row = TelemetryEvent(
        event_id=event.event_id,
        timestamp=event.timestamp,
        schema_version=event.schema_version,
        event_type=event.event_type,
        procedure_id=event.procedure_id,
        procedure_version=event.procedure_version,
        session_id=event.session_id,
        stage_id=event.stage_id,
        device=event.device.model_dump() if event.device else None,
        metrics=event.metrics,
        prompt=event.prompt.model_dump() if event.prompt else None,
        habitus=event.habitus.model_dump() if event.habitus else None,
        exposure=event.exposure.model_dump() if event.exposure else None,
        performance=event.performance.model_dump() if event.performance else None,
    )

    db.add(row)
    db.commit()


def list_events(db: Session, session_id: str | None, limit: int) -> list[TelemetryEvent]:
    safe_limit = max(1, min(int(limit), 500))
    stmt = select(TelemetryEvent).order_by(desc(TelemetryEvent.timestamp)).limit(safe_limit)
    if session_id:
        stmt = stmt.where(TelemetryEvent.session_id == session_id)
    return list(db.scalars(stmt))
