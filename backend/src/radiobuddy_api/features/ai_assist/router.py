from __future__ import annotations

from fastapi import APIRouter

from radiobuddy_api.features.ai_assist.schemas import AiAssistAnalyzeIn, AiAssistAnalyzeOut
from radiobuddy_api.features.ai_assist.service import analyze_position

router = APIRouter(prefix="/ai", tags=["ai_assist"])


@router.post("/positioning/analyze", response_model=AiAssistAnalyzeOut)
async def analyze_positioning(payload: AiAssistAnalyzeIn) -> AiAssistAnalyzeOut:
    return await analyze_position(payload)
