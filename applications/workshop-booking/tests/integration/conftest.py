"""Live Postgres fixtures. Missing credentials are a failure, never a skip."""

import os
import secrets
from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import Engine, text
from sqlalchemy.orm import sessionmaker

from app.config import Settings
from app.database import build_engine
from app.main import create_app


@dataclass
class LiveDatabase:
    settings: Settings
    engine: Engine
    owner_engine: Engine
    attendees: tuple[UUID, UUID, UUID]
    tokens: dict[UUID, str]
    workshops: list[UUID]

    def headers(self, attendee: int = 0) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.tokens[self.attendees[attendee]]}"}

    def active_count(self, workshop_id: UUID) -> int:
        with self.engine.connect() as connection:
            return connection.scalar(
                text(
                    "SELECT count(*) FROM workshop_booking.bookings "
                    "WHERE workshop_id = :id AND cancelled_at IS NULL"
                ),
                {"id": workshop_id},
            )


@pytest.fixture(scope="session")
def live_db() -> LiveDatabase:
    required = (
        "PGHOST",
        "PGDATABASE",
        "PGUSER",
        "PGPASSWORD",
        "PGSSLROOTCERT",
        "WORKSHOP_MIGRATOR_PASSWORD",
    )
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        pytest.fail("Live integration tests require: " + ", ".join(missing))
    settings = Settings.from_env(require_tokens=False)
    if settings.user != "workshop_booking_app":
        pytest.fail("Run integration tests with PGUSER=workshop_booking_app.")

    attendees = (uuid4(), uuid4(), uuid4())
    tokens = {attendee_id: secrets.token_urlsafe(32) for attendee_id in attendees}
    settings = replace(settings, bearer_tokens=tokens)
    engine = build_engine(settings)
    owner_engine = build_engine(
        replace(
            settings,
            user="workshop_booking_migrator",
            password=os.environ["WORKSHOP_MIGRATOR_PASSWORD"],
        )
    )
    database = LiveDatabase(settings, engine, owner_engine, attendees, tokens, [])
    try:
        with owner_engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            for index, attendee_id in enumerate(attendees):
                connection.execute(
                    text(
                        "INSERT INTO workshop_booking.attendees (id, name, email) "
                        "VALUES (:id, :name, :email)"
                    ),
                    {
                        "id": attendee_id,
                        "name": f"Integration attendee {index}",
                        "email": f"integration-{attendee_id}@example.test",
                    },
                )
        yield database
    finally:
        # Test-created rows are identified by fresh UUIDs, never by broad names
        # or a table truncate. A failed test does not touch the sample data.
        with owner_engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            for attendee_id in attendees:
                connection.execute(
                    text("DELETE FROM workshop_booking.bookings WHERE attendee_id = :id"),
                    {"id": attendee_id},
                )
            for workshop_id in database.workshops:
                connection.execute(
                    text("DELETE FROM workshop_booking.workshops WHERE id = :id"),
                    {"id": workshop_id},
                )
            for attendee_id in attendees:
                connection.execute(
                    text("DELETE FROM workshop_booking.attendees WHERE id = :id"),
                    {"id": attendee_id},
                )
        engine.dispose()
        owner_engine.dispose()


@pytest.fixture(scope="session")
def client(live_db: LiveDatabase):
    factory = sessionmaker(live_db.engine, expire_on_commit=False)
    application = create_app(settings=live_db.settings, session_factory=factory)
    with TestClient(application) as test_client:
        yield test_client


@pytest.fixture
def workshop(live_db: LiveDatabase):
    def create(capacity: int = 2, *, started: bool = False) -> UUID:
        workshop_id = uuid4()
        starts_at = datetime.now(UTC) + (timedelta(days=-1) if started else timedelta(days=30))
        with live_db.owner_engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            connection.execute(
                text(
                    "INSERT INTO workshop_booking.workshops "
                    "(id, title, description, starts_at, duration_minutes, capacity) "
                    "VALUES (:id, :title, '', :starts_at, 60, :capacity)"
                ),
                {
                    "id": workshop_id,
                    "title": f"Integration workshop {workshop_id}",
                    "starts_at": starts_at,
                    "capacity": capacity,
                },
            )
        live_db.workshops.append(workshop_id)
        return workshop_id

    return create
