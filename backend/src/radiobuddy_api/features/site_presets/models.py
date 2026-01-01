from __future__ import annotations

import datetime as dt

from sqlalchemy import DateTime, ForeignKey, ForeignKeyConstraint, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from radiobuddy_api.platform.db.base import Base


class Site(Base):
    __tablename__ = "sites"

    site_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: dt.datetime.now(dt.timezone.utc),
    )


class Room(Base):
    __tablename__ = "rooms"

    site_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("sites.site_id", ondelete="CASCADE"),
        primary_key=True,
    )
    room_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: dt.datetime.now(dt.timezone.utc),
    )


class RoomExposureProtocol(Base):
    __tablename__ = "room_exposure_protocols"

    __table_args__ = (
        ForeignKeyConstraint(
            ["site_id", "room_id"],
            ["rooms.site_id", "rooms.room_id"],
            ondelete="CASCADE",
        ),
    )

    site_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    room_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    procedure_id: Mapped[str] = mapped_column(String(128), primary_key=True)

    payload: Mapped[dict] = mapped_column(JSONB, nullable=False)
    updated_at: Mapped[dt.datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        default=lambda: dt.datetime.now(dt.timezone.utc),
    )
