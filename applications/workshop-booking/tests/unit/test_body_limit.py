import asyncio

from app.middleware import BookingBodyLimit


def run_request(chunks):
    output = []
    delivered = []
    messages = iter(
        {"type": "http.request", "body": body, "more_body": i < len(chunks) - 1}
        for i, body in enumerate(chunks)
    )

    async def receive():
        return next(messages)

    async def send(message):
        output.append(message)

    async def app(scope, receive, send):
        delivered.append(await receive())

    asyncio.run(
        BookingBodyLimit(app)(
            {"type": "http", "method": "POST", "path": "/bookings"}, receive, send
        )
    )
    return output, delivered


def test_rejects_streamed_body_without_content_length():
    output, delivered = run_request([b"x" * 2048, b"x" * 2049])
    assert output[0]["status"] == 413
    assert delivered == []


def test_boundary_body_is_delivered_to_parser_once():
    output, delivered = run_request([b"x" * 2048, b"x" * 2048])
    assert output == []
    assert delivered == [{"type": "http.request", "body": b"x" * 4096, "more_body": False}]
