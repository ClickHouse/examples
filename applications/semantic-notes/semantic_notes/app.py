import os
from contextlib import asynccontextmanager
from pathlib import Path
from uuid import UUID

import anyio
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles
from fastapi.templating import Jinja2Templates
from pydantic import ValidationError
from sqlalchemy.exc import SQLAlchemyError

from .database import make_engine
from .embeddings import Encoder, TokenLimitError
from .service import (
    DomainError,
    create_note,
    list_notes,
    read_note,
    search_notes,
    update_note,
    verify_collection,
)
from .validation import NoteInput, SearchInput, UpdateInput
from .worker import EmbeddingWorker

ROOT = Path(__file__).resolve().parent.parent


class BrowserBoundary:
    def __init__(self, app):
        self.app = app
        self.origin = os.environ.get("APP_ORIGIN", "http://127.0.0.1:8000")
        if self.origin != "http://127.0.0.1:8000":
            raise ValueError(
                "This example uses the fixed loopback origin http://127.0.0.1:8000."
            )

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] in {"GET", "HEAD", "OPTIONS"}:
            return await self.app(scope, receive, send)
        origins = [
            value.decode("latin1")
            for name, value in scope["headers"]
            if name == b"origin"
        ]
        if origins != [self.origin]:
            return await JSONResponse(
                {"detail": "A request from the notebook origin is required."}, 403
            )(scope, receive, send)
        body = bytearray()
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            body.extend(message.get("body", b""))
            if len(body) > 16384:
                return await JSONResponse({"detail": "Request exceeds 16 KiB."}, 413)(
                    scope, receive, send
                )
            if not message.get("more_body", False):
                break
        delivered = False

        async def bounded_receive():
            nonlocal delivered
            if not delivered:
                delivered = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, bounded_receive, send)


@asynccontextmanager
async def lifespan(app):
    engine = make_engine()
    try:
        encoder = await anyio.to_thread.run_sync(Encoder)
        await anyio.to_thread.run_sync(verify_collection, engine)
        app.state.engine = engine
        app.state.worker = EmbeddingWorker(encoder)
        yield
    finally:
        engine.dispose()


app = FastAPI(title="Semantic notes", lifespan=lifespan)
app.add_middleware(BrowserBoundary)
app.mount("/static", StaticFiles(directory=ROOT / "static"), name="static")
templates = Jinja2Templates(directory=ROOT / "templates")


@app.exception_handler(RequestValidationError)
async def invalid_request(request, error):
    # Do not echo rejected input: lone JSON surrogates cannot be UTF-8 encoded.
    return JSONResponse(
        {"detail": "Invalid input. Check field types, bounds, and Unicode."}, 422
    )


@app.exception_handler(DomainError)
async def domain_error(request, error):
    return JSONResponse({"detail": str(error)}, error.status)


@app.exception_handler(TokenLimitError)
async def token_error(request, error):
    return JSONResponse({"detail": str(error)}, 422)


@app.exception_handler(SQLAlchemyError)
async def database_error(request, error):
    # Do not query an unavailable database to construct an error response.
    return JSONResponse(
        {
            "detail": "The notebook could not save or read this request. Try again shortly."
        },
        503,
    )


async def encode_document(fields):
    return await app.state.worker.embed(
        Encoder.document_text(fields.title, fields.body)
    )


@app.get("/api/notes")
async def api_list(page: int = 1):
    return await anyio.to_thread.run_sync(list_notes, app.state.engine, page)


@app.get("/api/notes/{note_id}")
async def api_read(note_id: UUID):
    return await anyio.to_thread.run_sync(read_note, app.state.engine, note_id)


@app.post("/api/notes", status_code=201)
async def api_create(fields: NoteInput):
    vector = await encode_document(fields)
    return await anyio.to_thread.run_sync(create_note, app.state.engine, fields, vector)


@app.put("/api/notes/{note_id}")
async def api_update(note_id: UUID, fields: UpdateInput):
    vector = await encode_document(fields)
    return await anyio.to_thread.run_sync(
        update_note, app.state.engine, note_id, fields, vector
    )


@app.post("/api/search")
async def api_search(fields: SearchInput):
    vector = await app.state.worker.embed(fields.q)
    results = await anyio.to_thread.run_sync(
        search_notes, app.state.engine, fields, vector
    )
    return {"results": results, "k": fields.k, "query": fields.q}


@app.get("/")
async def home(request: Request, page: int = 1):
    board = await anyio.to_thread.run_sync(list_notes, app.state.engine, page)
    return templates.TemplateResponse(request, "index.html", {"board": board})


@app.get("/notes/{note_id}")
async def edit(request: Request, note_id: UUID):
    note = await anyio.to_thread.run_sync(read_note, app.state.engine, note_id)
    return templates.TemplateResponse(request, "edit.html", {"note": note, "error": ""})


async def form_fields(request, model):
    form = await request.form(max_fields=5, max_files=0)
    values = dict(form)
    if len(form.multi_items()) != len(values):
        raise DomainError("Duplicate form fields are not allowed.")
    for key in ("revision", "k"):
        if key in values:
            if (
                not isinstance(values[key], str)
                or not values[key].isascii()
                or not values[key].isdigit()
                or len(values[key]) > (10 if key == "revision" else 2)
            ):
                raise DomainError(f"{key} must be an integer.")
            values[key] = int(values[key])
    return model.model_validate(values)


@app.post("/notes")
async def add(request: Request):
    try:
        fields = await form_fields(request, NoteInput)
        vector = await encode_document(fields)
        note = await anyio.to_thread.run_sync(
            create_note, app.state.engine, fields, vector
        )
    except (ValidationError, DomainError, TokenLimitError) as error:
        return templates.TemplateResponse(
            request,
            "error.html",
            {"error": str(error)},
            status_code=getattr(error, "status", 422),
        )
    return RedirectResponse(f"/notes/{note['id']}?saved=1", status_code=303)


@app.post("/notes/{note_id}")
async def save(request: Request, note_id: UUID):
    form = await request.form(max_fields=5, max_files=0)
    values = dict(form)
    try:
        revision = values.get("revision", "")
        if len(form.multi_items()) != len(values):
            raise DomainError("Duplicate form fields are not allowed.")
        if (
            not isinstance(revision, str)
            or not revision.isascii()
            or not revision.isdigit()
            or len(revision) > 10
        ):
            raise DomainError("Revision must be an integer.")
        fields = UpdateInput.model_validate({**values, "revision": int(revision)})
        vector = await encode_document(fields)
        await anyio.to_thread.run_sync(
            update_note, app.state.engine, note_id, fields, vector
        )
    except (ValidationError, DomainError, TokenLimitError) as error:
        # Keep the submitted revision and text. Only an explicit reload fetches new values.
        return templates.TemplateResponse(
            request,
            "edit.html",
            {"note": {**values, "id": str(note_id)}, "error": str(error)},
            status_code=getattr(error, "status", 422),
        )
    return RedirectResponse(f"/notes/{note_id}?saved=1", status_code=303)


@app.post("/search")
async def search(request: Request):
    try:
        fields = await form_fields(request, SearchInput)
        vector = await app.state.worker.embed(fields.q)
        results = await anyio.to_thread.run_sync(
            search_notes, app.state.engine, fields, vector
        )
    except (ValidationError, DomainError, TokenLimitError) as error:
        return templates.TemplateResponse(
            request,
            "error.html",
            {"error": str(error)},
            status_code=getattr(error, "status", 422),
        )
    return templates.TemplateResponse(
        request, "search.html", {"fields": fields, "results": results}
    )
