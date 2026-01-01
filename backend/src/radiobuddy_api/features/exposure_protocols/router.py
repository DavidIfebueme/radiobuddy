from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from radiobuddy_api.features.exposure_protocols.service import get_chest_pa_protocol

router = APIRouter(prefix="/exposure-protocols", tags=["exposure_protocols"])


@router.get("/chest-pa")
def get_protocol() -> JSONResponse:
    return JSONResponse(content=get_chest_pa_protocol())
