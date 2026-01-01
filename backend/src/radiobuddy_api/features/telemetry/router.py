from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from radiobuddy_api.features.telemetry.schemas import (
    ErrorResponse,
    TelemetryEventAccepted,
    TelemetryEventIn,
)
from radiobuddy_api.features.telemetry.service import store_event
from radiobuddy_api.platform.db.session import get_db

router = APIRouter(prefix="/telemetry", tags=["telemetry"])


@router.post(
    "/events",
    response_model=TelemetryEventAccepted,
    responses={503: {"model": ErrorResponse}},
)
def ingest_event(
    payload: TelemetryEventIn, db: Session = Depends(get_db)
) -> TelemetryEventAccepted:
    try:
        store_event(db, payload)
    except RuntimeError as exc:
        # Most likely missing DB config.
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    return TelemetryEventAccepted(event_id=payload.event_id)
