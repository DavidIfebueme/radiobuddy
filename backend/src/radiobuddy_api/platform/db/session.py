from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from radiobuddy_api.platform.config import settings


def _require_database_url() -> str:
    if not settings.database_url:
        raise RuntimeError(
            "RADIOBUDDY_DATABASE_URL is not set. "
            "Set it to something like: postgresql+psycopg://user:pass@localhost:5432/radiobuddy"
        )
    return settings.database_url


_engine = None
_SessionLocal = None


def get_engine():
    global _engine, _SessionLocal
    if _engine is None:
        database_url = _require_database_url()
        _engine = create_engine(database_url, pool_pre_ping=True)
        _SessionLocal = sessionmaker(bind=_engine, autoflush=False, autocommit=False)
    return _engine


def get_db() -> Generator[Session, None, None]:
    if _SessionLocal is None:
        get_engine()
    assert _SessionLocal is not None

    db: Session = _SessionLocal()
    try:
        yield db
    finally:
        db.close()
