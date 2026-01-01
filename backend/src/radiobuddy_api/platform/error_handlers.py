from __future__ import annotations

import logging

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("radiobuddy_api.errors")


def _request_id(request: Request) -> str | None:
    return getattr(request.state, "request_id", None)


async def http_exception_handler(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    rid = _request_id(request)
    return JSONResponse(
        status_code=exc.status_code,
        content={"error": "http_error", "detail": exc.detail, "request_id": rid},
    )


async def validation_exception_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    rid = _request_id(request)
    return JSONResponse(
        status_code=422,
        content={"error": "validation_error", "detail": exc.errors(), "request_id": rid},
    )


async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    rid = _request_id(request)
    logger.exception("Unhandled error request_id=%s", rid)
    return JSONResponse(
        status_code=500,
        content={"error": "internal_error", "detail": None, "request_id": rid},
    )
