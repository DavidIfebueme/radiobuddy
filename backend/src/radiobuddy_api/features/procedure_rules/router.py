from __future__ import annotations

from fastapi import APIRouter
from fastapi.responses import JSONResponse

from radiobuddy_api.features.procedure_rules.service import get_chest_pa_rules

router = APIRouter(prefix="/procedure-rules", tags=["procedure_rules"])


@router.get("/chest-pa")
def get_rules() -> JSONResponse:
    return JSONResponse(content=get_chest_pa_rules())
