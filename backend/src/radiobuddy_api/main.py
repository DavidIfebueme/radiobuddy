from __future__ import annotations

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from radiobuddy_api.features.exposure_protocols.router import router as exposure_protocols_router
from radiobuddy_api.features.health.router import router as health_router
from radiobuddy_api.features.procedure_rules.router import router as procedure_rules_router
from radiobuddy_api.features.site_presets.router import router as site_presets_router
from radiobuddy_api.features.telemetry.router import router as telemetry_router
from radiobuddy_api.platform.config import settings
from radiobuddy_api.platform.error_handlers import (
    http_exception_handler,
    unhandled_exception_handler,
    validation_exception_handler,
)
from radiobuddy_api.platform.logging import configure_logging
from radiobuddy_api.platform.middleware import RequestIdMiddleware


def create_app() -> FastAPI:
    configure_logging(settings.log_level)

    app = FastAPI(
        title="Radio Buddy API",
        version="0.1.0",
    )

    app.add_middleware(RequestIdMiddleware)

    app.add_exception_handler(StarletteHTTPException, http_exception_handler)
    app.add_exception_handler(RequestValidationError, validation_exception_handler)
    app.add_exception_handler(Exception, unhandled_exception_handler)

    app.include_router(health_router)
    app.include_router(procedure_rules_router)
    app.include_router(exposure_protocols_router)
    app.include_router(telemetry_router)
    app.include_router(site_presets_router)

    return app


app = create_app()
