from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from radiobuddy_api.features.site_presets.schemas import (
    ErrorResponse,
    ExposureProtocolOut,
    ExposureProtocolUpsertIn,
    RoomCreate,
    RoomOut,
    SiteCreate,
    SiteOut,
)
from radiobuddy_api.features.site_presets.service import (
    create_room,
    create_site,
    get_room_exposure_protocol,
    list_rooms,
    list_sites,
    upsert_room_exposure_protocol,
)
from radiobuddy_api.platform.db.session import get_db

router = APIRouter(prefix="/sites", tags=["site_presets"])


@router.post("", response_model=SiteOut, responses={503: {"model": ErrorResponse}})
def create_site_endpoint(payload: SiteCreate, db: Session = Depends(get_db)) -> SiteOut:
    site = create_site(db, site_id=payload.site_id, name=payload.name)
    return SiteOut(site_id=site.site_id, name=site.name, created_at=site.created_at)


@router.get("", response_model=list[SiteOut], responses={503: {"model": ErrorResponse}})
def list_sites_endpoint(db: Session = Depends(get_db)) -> list[SiteOut]:
    return [
        SiteOut(site_id=s.site_id, name=s.name, created_at=s.created_at) for s in list_sites(db)
    ]


@router.post(
    "/{site_id}/rooms",
    response_model=RoomOut,
    responses={503: {"model": ErrorResponse}},
)
def create_room_endpoint(
    site_id: str,
    payload: RoomCreate,
    db: Session = Depends(get_db),
) -> RoomOut:
    room = create_room(db, site_id=site_id, room_id=payload.room_id, name=payload.name)
    return RoomOut(
        site_id=room.site_id,
        room_id=room.room_id,
        name=room.name,
        created_at=room.created_at,
    )


@router.get(
    "/{site_id}/rooms",
    response_model=list[RoomOut],
    responses={503: {"model": ErrorResponse}},
)
def list_rooms_endpoint(site_id: str, db: Session = Depends(get_db)) -> list[RoomOut]:
    rooms = list_rooms(db, site_id=site_id)
    return [
        RoomOut(site_id=r.site_id, room_id=r.room_id, name=r.name, created_at=r.created_at)
        for r in rooms
    ]


@router.put(
    "/{site_id}/rooms/{room_id}/exposure-protocols/{procedure_id}",
    response_model=ExposureProtocolOut,
    responses={503: {"model": ErrorResponse}},
)
def upsert_exposure_protocol_endpoint(
    site_id: str,
    room_id: str,
    procedure_id: str,
    payload: ExposureProtocolUpsertIn,
    db: Session = Depends(get_db),
) -> ExposureProtocolOut:
    protocol = upsert_room_exposure_protocol(
        db,
        site_id=site_id,
        room_id=room_id,
        procedure_id=procedure_id,
        payload=payload,
    )
    return ExposureProtocolOut(**protocol.payload, updated_at=protocol.updated_at)


@router.get(
    "/{site_id}/rooms/{room_id}/exposure-protocols/{procedure_id}",
    response_model=ExposureProtocolOut,
    responses={404: {"model": ErrorResponse}, 503: {"model": ErrorResponse}},
)
def get_exposure_protocol_endpoint(
    site_id: str,
    room_id: str,
    procedure_id: str,
    db: Session = Depends(get_db),
) -> ExposureProtocolOut:
    protocol = get_room_exposure_protocol(
        db,
        site_id=site_id,
        room_id=room_id,
        procedure_id=procedure_id,
    )
    if protocol is None:
        raise HTTPException(status_code=404, detail="protocol_not_found")
    return ExposureProtocolOut(**protocol.payload, updated_at=protocol.updated_at)
