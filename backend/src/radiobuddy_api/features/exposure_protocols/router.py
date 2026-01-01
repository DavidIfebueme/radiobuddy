from __future__ import annotations

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from radiobuddy_api.features.exposure_protocols.service import get_chest_pa_protocol, get_protocol

router = APIRouter(prefix="/exposure-protocols", tags=["exposure_protocols"])


@router.get("/chest-pa")
def get_chest_pa_protocol_endpoint() -> JSONResponse:
    return JSONResponse(content=get_chest_pa_protocol())


@router.get("/{procedure_id}")
def get_protocol_for_procedure(
    procedure_id: str,
    site_id: str | None = None,
    room_id: str | None = None,
) -> JSONResponse:
    payload = get_protocol(procedure_id=procedure_id, site_id=site_id, room_id=room_id)
    if payload is None:
        raise HTTPException(status_code=404, detail="protocol_not_found")
    return JSONResponse(content=payload)
