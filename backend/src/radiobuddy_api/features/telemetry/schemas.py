from __future__ import annotations

from datetime import datetime
from typing import Any, Literal
from uuid import UUID

from pydantic import BaseModel, Field

TelemetryEventType = Literal[
    "session_start",
    "session_end",
    "prompt_emitted",
    "ready_state_entered",
    "habitus_estimated",
    "habitus_overridden",
    "exposure_suggested",
    "vision_low_confidence",
]


class TelemetryDevice(BaseModel):
    platform: Literal["android", "ios"] | None = None
    model: str | None = None
    app_version: str | None = None


class TelemetryPrompt(BaseModel):
    prompt_id: str | None = None
    rule_id: str | None = None
    spoken: bool | None = None


class TelemetryHabitus(BaseModel):
    size_class_estimated: Literal["small", "average", "large"] | None = None
    size_class_final: Literal["small", "average", "large"] | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    source: Literal["camera_estimate", "manual"] | None = None


class TelemetryExposure(BaseModel):
    kvp: float | None = None
    mas: float | None = None
    protocol_id: str | None = None


class TelemetryPerformance(BaseModel):
    frame_latency_ms: float | None = None
    fps: float | None = None


class TelemetryEventIn(BaseModel):
    schema_version: str = Field(..., pattern=r"^v\d+$")
    event_id: UUID
    timestamp: datetime
    event_type: TelemetryEventType
    procedure_id: str

    procedure_version: str | None = None
    session_id: UUID | None = None
    stage_id: str | None = None

    device: TelemetryDevice | None = None
    metrics: dict[str, float] | None = None
    prompt: TelemetryPrompt | None = None
    habitus: TelemetryHabitus | None = None
    exposure: TelemetryExposure | None = None
    performance: TelemetryPerformance | None = None


class TelemetryEventAccepted(BaseModel):
    status: Literal["accepted"] = "accepted"
    event_id: UUID


class ErrorResponse(BaseModel):
    error: str
    detail: Any | None = None
