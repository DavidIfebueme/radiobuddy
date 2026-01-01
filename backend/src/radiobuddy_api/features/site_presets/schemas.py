from __future__ import annotations

from datetime import datetime
from typing import Any

from pydantic import BaseModel, ConfigDict, Field


class SiteCreate(BaseModel):
    site_id: str = Field(..., pattern=r"^[a-z0-9_-]+$", min_length=1, max_length=64)
    name: str | None = Field(default=None, max_length=200)


class SiteOut(BaseModel):
    site_id: str
    name: str | None
    created_at: datetime


class RoomCreate(BaseModel):
    room_id: str = Field(..., pattern=r"^[a-z0-9_-]+$", min_length=1, max_length=64)
    name: str | None = Field(default=None, max_length=200)


class RoomOut(BaseModel):
    site_id: str
    room_id: str
    name: str | None
    created_at: datetime


class ExposureProtocolRecommendation(BaseModel):
    inputs: dict[str, Any]
    output: dict[str, Any]


class ExposureProtocolPayload(BaseModel):
    model_config = ConfigDict(extra="allow")

    schema_version: str = Field(..., pattern=r"^v\d+$", max_length=64)
    protocol_id: str = Field(..., pattern=r"^[a-z0-9_]+$", min_length=1, max_length=128)
    protocol_name: str = Field(..., min_length=1, max_length=200)
    protocol_version: str = Field(..., min_length=1, max_length=64)
    procedure_id: str = Field(..., pattern=r"^[a-z0-9_]+$", min_length=1, max_length=128)

    assumptions: list[str] = Field(default_factory=list)
    recommendations: list[ExposureProtocolRecommendation] = Field(default_factory=list)


class ExposureProtocolUpsertIn(ExposureProtocolPayload):
    model_config = ConfigDict(
        json_schema_extra={
            "examples": [
                {
                    "schema_version": "v1",
                    "protocol_id": "demo_chest_pa_protocol",
                    "protocol_name": "Chest PA (Erect)",
                    "protocol_version": "v1",
                    "procedure_id": "chest_pa_erect",
                    "assumptions": ["Starting point only"],
                    "recommendations": [
                        {
                            "inputs": {
                                "projection": "chest_pa_erect",
                                "size_class": "average",
                                "grid": True,
                                "sid_cm": 180,
                                "detector": "dr",
                            },
                            "output": {"kvp": 120, "mas": 1.6},
                        }
                    ],
                }
            ]
        }
    )


class ExposureProtocolOut(ExposureProtocolPayload):
    site_id: str
    room_id: str
    updated_at: datetime


class ErrorResponse(BaseModel):
    error: str
    detail: Any | None = None
    request_id: str | None = None
