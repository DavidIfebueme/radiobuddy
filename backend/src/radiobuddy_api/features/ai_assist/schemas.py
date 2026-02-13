from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field


class AiAssistAnalyzeIn(BaseModel):
    procedure_id: str = Field(..., pattern=r"^[a-z0-9_]+$")
    stage_id: str = Field(..., pattern=r"^[a-z0-9_]+$")
    metrics: dict[str, float] = Field(default_factory=dict)


class AiAssistAnalyzeOut(BaseModel):
    instruction: str
    source: Literal["local", "do_inference", "do_inference_fallback"]
    model: str | None = None
