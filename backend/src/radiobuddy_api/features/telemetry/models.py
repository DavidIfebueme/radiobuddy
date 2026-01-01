from __future__ import annotations

import datetime as dt
import uuid

from sqlalchemy import DateTime, String
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from radiobuddy_api.platform.db.base import Base


class TelemetryEvent(Base):
    __tablename__ = "telemetry_events"

    event_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    timestamp: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), nullable=False)

    schema_version: Mapped[str] = mapped_column(String(64), nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    procedure_id: Mapped[str] = mapped_column(String(128), nullable=False)

    procedure_version: Mapped[str | None] = mapped_column(String(64), nullable=True)
    session_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    stage_id: Mapped[str | None] = mapped_column(String(64), nullable=True)

    device: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    metrics: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    prompt: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    habitus: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    exposure: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    performance: Mapped[dict | None] = mapped_column(JSONB, nullable=True)

    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: dt.datetime.now(dt.timezone.utc),
    )
