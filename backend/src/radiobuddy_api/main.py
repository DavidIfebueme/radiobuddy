from __future__ import annotations

from fastapi import FastAPI

from radiobuddy_api.features.exposure_protocols.router import router as exposure_protocols_router
from radiobuddy_api.features.health.router import router as health_router
from radiobuddy_api.features.procedure_rules.router import router as procedure_rules_router
from radiobuddy_api.features.telemetry.router import router as telemetry_router
from radiobuddy_api.platform.config import settings
from radiobuddy_api.platform.logging import configure_logging


def create_app() -> FastAPI:
    configure_logging(settings.log_level)

    app = FastAPI(
        title="Radio Buddy API",
        version="0.1.0",
    )

    app.include_router(health_router)
    app.include_router(procedure_rules_router)
    app.include_router(exposure_protocols_router)
    app.include_router(telemetry_router)

    return app


app = create_app()
