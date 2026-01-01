from __future__ import annotations

import datetime as dt

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from radiobuddy_api.features.site_presets.models import Room, RoomExposureProtocol, Site
from radiobuddy_api.features.site_presets.schemas import ExposureProtocolPayload
from radiobuddy_api.platform.json_schema import validate_instance


def create_site(db: Session, site_id: str, name: str | None) -> Site:
    site = Site(site_id=site_id, name=name)
    db.add(site)
    db.commit()
    db.refresh(site)
    return site


def list_sites(db: Session) -> list[Site]:
    return list(db.scalars(select(Site).order_by(Site.site_id)))


def create_room(db: Session, site_id: str, room_id: str, name: str | None) -> Room:
    room = Room(site_id=site_id, room_id=room_id, name=name)
    db.add(room)
    db.commit()
    db.refresh(room)
    return room


def list_rooms(db: Session, site_id: str) -> list[Room]:
    return list(db.scalars(select(Room).where(Room.site_id == site_id).order_by(Room.room_id)))


def upsert_room_exposure_protocol(
    db: Session,
    site_id: str,
    room_id: str,
    procedure_id: str,
    payload: ExposureProtocolPayload,
) -> RoomExposureProtocol:
    now = dt.datetime.now(dt.timezone.utc)
    payload_dict = payload.model_dump(mode="json")
    payload_dict["site_id"] = site_id
    payload_dict["room_id"] = room_id
    payload_dict["procedure_id"] = procedure_id

    validate_instance("exposure_protocol.schema.json", payload_dict)

    stmt = insert(RoomExposureProtocol).values(
        site_id=site_id,
        room_id=room_id,
        procedure_id=procedure_id,
        payload=payload_dict,
        updated_at=now,
    )
    stmt = stmt.on_conflict_do_update(
        index_elements=[
            RoomExposureProtocol.site_id,
            RoomExposureProtocol.room_id,
            RoomExposureProtocol.procedure_id,
        ],
        set_={"payload": payload_dict, "updated_at": now},
    )

    db.execute(stmt)
    db.commit()

    return db.get(
        RoomExposureProtocol,
        {"site_id": site_id, "room_id": room_id, "procedure_id": procedure_id},
    )


def get_room_exposure_protocol(
    db: Session, site_id: str, room_id: str, procedure_id: str
) -> RoomExposureProtocol | None:
    return db.get(
        RoomExposureProtocol,
        {"site_id": site_id, "room_id": room_id, "procedure_id": procedure_id},
    )
