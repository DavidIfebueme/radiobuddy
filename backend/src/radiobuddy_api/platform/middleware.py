from __future__ import annotations

import logging
import time
import uuid


class RequestIdMiddleware:
    def __init__(self, app):
        self.app = app
        self.logger = logging.getLogger("radiobuddy_api.http")

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        start = time.perf_counter()
        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        request_id = headers.get("x-request-id") or str(uuid.uuid4())
        scope.setdefault("state", {})["request_id"] = request_id

        method = scope.get("method")
        path = scope.get("path")
        status_code = None

        async def send_wrapper(message):
            nonlocal status_code

            if message["type"] == "http.response.start":
                status_code = message["status"]
                response_headers = list(message.get("headers", []))
                response_headers.append((b"x-request-id", request_id.encode()))
                message["headers"] = response_headers

            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            elapsed_ms = (time.perf_counter() - start) * 1000
            self.logger.info(
                "%s %s %s %.2fms request_id=%s",
                method,
                path,
                status_code if status_code is not None else "-",
                elapsed_ms,
                request_id,
            )
