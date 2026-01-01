from __future__ import annotations

from fastapi import APIRouter, HTTPException
from fastapi.responses import JSONResponse

from radiobuddy_api.features.procedure_rules.service import get_chest_pa_rules, get_rules

router = APIRouter(prefix="/procedure-rules", tags=["procedure_rules"])


@router.get("/chest-pa")
def get_chest_pa_rules_endpoint() -> JSONResponse:
    return JSONResponse(content=get_chest_pa_rules())


@router.get("/{procedure_id}")
def get_rules_for_procedure(procedure_id: str) -> JSONResponse:
    payload = get_rules(procedure_id)
    if payload is None:
        raise HTTPException(status_code=404, detail="procedure_not_found")
    return JSONResponse(content=payload)
