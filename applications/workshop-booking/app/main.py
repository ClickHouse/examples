import logging
from contextlib import asynccontextmanager
from typing import Annotated
from uuid import UUID

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError, SQLAlchemyError
from sqlalchemy.orm import Session, sessionmaker

from app.auth import get_attendee_id
from app.config import ConfigurationError, Settings
from app.database import build_engine, get_session
from app.middleware import BookingBodyLimit
from app.models import Attendee
from app.schemas import BookingCreate, BookingResponse, WorkshopResponse
from app.services import cancel_booking, create_booking, get_booking, list_workshops

logger = logging.getLogger("workshop_booking")
DatabaseSession = Annotated[Session, Depends(get_session)]
CurrentAttendee = Annotated[UUID, Depends(get_attendee_id)]


def create_app(
    settings: Settings | None = None, session_factory: sessionmaker | None = None
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(application: FastAPI):
        configured = settings or Settings.from_env()
        engine = None
        factory = session_factory
        if factory is None:
            engine = build_engine(configured)
            factory = sessionmaker(engine, expire_on_commit=False)
        try:
            # A typo in identity configuration must fail at startup, not impersonate
            # an arbitrary client-selected attendee during a request.
            with factory() as session:
                found = set(
                    session.scalars(
                        select(Attendee.id).where(Attendee.id.in_(configured.bearer_tokens))
                    )
                )
            if not configured.bearer_tokens or found != set(configured.bearer_tokens):
                raise ConfigurationError("Every configured attendee must exist in the seed data.")
            application.state.settings = configured
            application.state.session_factory = factory
            yield
        except SQLAlchemyError:
            raise RuntimeError(
                "Database startup check failed. Check connection and migrations."
            ) from None
        finally:
            if engine is not None:
                engine.dispose()

    application = FastAPI(
        title="Workshop Booking API",
        version="1.0.0",
        description=(
            "Reserve one seat in a workshop using a client-generated booking UUID. "
            "Reuse the same UUID to safely retry a request. Configure attendee tokens "
            "on the server, then use the Authorize button for booking routes."
        ),
        lifespan=lifespan,
    )
    application.add_middleware(BookingBodyLimit)

    @application.exception_handler(SQLAlchemyError)
    async def database_error(_request: Request, error: SQLAlchemyError) -> JSONResponse:
        # Never log the exception string: it can contain SQL, parameters or credentials.
        logger.warning("Database operation failed (%s)", type(error).__name__)
        return JSONResponse(
            status_code=503,
            content={
                "detail": "Database temporarily unavailable. Retry using the same booking ID."
            },
            headers={"Retry-After": "1"},
        )

    @application.exception_handler(RequestValidationError)
    async def validation_error(_request: Request, error: RequestValidationError) -> JSONResponse:
        # Keep useful field errors without reflecting submitted bodies or secret values.
        return JSONResponse(
            status_code=422,
            content={
                "detail": [
                    {"loc": list(item["loc"]), "msg": item["msg"], "type": item["type"]}
                    for item in error.errors()
                ]
            },
        )

    @application.get("/workshops", response_model=list[WorkshopResponse], tags=["workshops"])
    def workshops(
        session: DatabaseSession,
        limit: Annotated[int, Query(ge=1, le=100)] = 20,
        offset: Annotated[int, Query(ge=0, le=10000)] = 0,
    ):
        """List upcoming workshops with current seat availability."""
        with session.begin():
            return list_workshops(session, limit, offset)

    @application.post(
        "/bookings",
        response_model=BookingResponse,
        status_code=201,
        responses={200: {"description": "Existing booking returned for an idempotent retry."}},
        tags=["bookings"],
    )
    def book(
        body: BookingCreate,
        response: Response,
        attendee_id: CurrentAttendee,
        session: DatabaseSession,
    ):
        """Reserve one seat. A cancelled UUID stays cancelled; rebook with a new UUID."""
        try:
            with session.begin():
                booking, created = create_booking(session, attendee_id, body)
        except IntegrityError as error:
            # Includes the rare case of one UUID raced across two different workshops.
            if getattr(error.orig, "sqlstate", None) == "23505":
                raise HTTPException(
                    409, "Booking ID or active booking has already been used."
                ) from None
            raise
        response.status_code = 201 if created else 200
        return booking

    @application.get("/bookings/{booking_id}", response_model=BookingResponse, tags=["bookings"])
    def booking(booking_id: UUID, attendee_id: CurrentAttendee, session: DatabaseSession):
        """Read your own booking; other attendees' bookings return 404."""
        with session.begin():
            return get_booking(session, attendee_id, booking_id)

    @application.delete("/bookings/{booking_id}", response_model=BookingResponse, tags=["bookings"])
    def cancel(booking_id: UUID, attendee_id: CurrentAttendee, session: DatabaseSession):
        """Cancel before the workshop starts. Repeated cancellation is safe."""
        with session.begin():
            return cancel_booking(session, attendee_id, booking_id)

    return application


app = create_app()
