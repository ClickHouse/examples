"""Bound JSON request bodies before FastAPI parses them, including streamed bodies."""

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send


class BookingBodyLimit:
    def __init__(self, app: ASGIApp, max_bytes: int = 4096):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"] != "POST" or scope["path"] != "/bookings":
            await self.app(scope, receive, send)
            return

        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            if len(body) + len(chunk) > self.max_bytes:
                response = JSONResponse({"detail": "Request body exceeds 4096 bytes."}, 413)
                await response(scope, receive, send)
                return
            body.extend(chunk)
            if not message.get("more_body", False):
                break

        sent = False

        async def buffered_receive():
            nonlocal sent
            if not sent:
                sent = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, buffered_receive, send)
