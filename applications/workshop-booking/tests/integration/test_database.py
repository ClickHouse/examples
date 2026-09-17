"""Check independent database invariants, role boundaries, and verified TLS."""

import socket
from dataclasses import replace
from uuid import uuid4

import psycopg
import pytest
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError, IntegrityError, OperationalError

from app.database import build_engine


def test_database_rejects_duplicate_active_booking_and_rolls_back(live_db, workshop):
    workshop_id, first_id = workshop(), uuid4()
    statement = text(
        "INSERT INTO workshop_booking.bookings (id, workshop_id, attendee_id) "
        "VALUES (:id, :workshop, :attendee)"
    )
    with pytest.raises(IntegrityError) as error:
        with live_db.engine.begin() as connection:
            parameters = {"id": first_id, "workshop": workshop_id, "attendee": live_db.attendees[0]}
            connection.execute(statement, parameters)
            connection.execute(statement, {**parameters, "id": uuid4()})
    assert error.value.orig.sqlstate == "23505"
    assert error.value.orig.diag.constraint_name == "bookings_one_active_per_attendee_workshop"
    assert live_db.active_count(workshop_id) == 0


def test_database_rejects_missing_foreign_keys(live_db, workshop):
    workshop_id = workshop()
    with pytest.raises(IntegrityError) as error:
        with live_db.engine.begin() as connection:
            connection.execute(
                text(
                    "INSERT INTO workshop_booking.bookings (id, workshop_id, attendee_id) "
                    "VALUES (:id, :workshop, :attendee)"
                ),
                {"id": uuid4(), "workshop": workshop_id, "attendee": uuid4()},
            )
    assert error.value.orig.sqlstate == "23503"
    assert live_db.active_count(workshop_id) == 0


def test_capacity_check_constraint(live_db, workshop):
    workshop_id = workshop()
    with pytest.raises(IntegrityError) as error:
        with live_db.owner_engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            connection.execute(
                text("UPDATE workshop_booking.workshops SET capacity = 0 WHERE id = :id"),
                {"id": workshop_id},
            )
    assert error.value.orig.sqlstate == "23514"


@pytest.mark.parametrize(
    "statement",
    [
        "CREATE TABLE workshop_booking.not_allowed (id integer)",
        "ALTER TABLE workshop_booking.workshops ADD COLUMN not_allowed integer",
        "UPDATE workshop_booking.workshops SET capacity = capacity + 1 WHERE id = :id",
        "UPDATE workshop_booking.attendees SET name = 'not allowed' WHERE id = :id",
        "UPDATE workshop_booking.bookings SET attendee_id = :id WHERE id = :id",
        "DELETE FROM workshop_booking.bookings WHERE id = :id",
        "SELECT * FROM workshop_booking.alembic_version",
        "SET ROLE workshop_booking_owner",
    ],
)
def test_runtime_role_cannot_mutate_schema_or_identity(live_db, workshop, statement):
    workshop_id = workshop()
    with pytest.raises(DBAPIError) as error:
        with live_db.engine.begin() as connection:
            connection.execute(text(statement), {"id": workshop_id})
    assert error.value.orig.sqlstate == "42501"


def test_tls_is_in_use_and_runtime_role_is_unprivileged(live_db):
    with live_db.engine.connect() as connection:
        assert (
            connection.scalar(text("SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid()"))
            is True
        )
        row = connection.execute(
            text(
                "SELECT rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls "
                "FROM pg_roles WHERE rolname = current_user"
            )
        ).one()
        assert not any(row)
        assert not connection.scalar(
            text("SELECT has_schema_privilege(current_user, 'workshop_booking', 'CREATE')")
        )


def test_invalid_ca_is_rejected(live_db, tmp_path):
    invalid_ca = tmp_path / "invalid-ca.pem"
    invalid_ca.write_text("This is deliberately not a certificate.\n")
    engine = build_engine(replace(live_db.settings, sslrootcert=invalid_ca))
    try:
        with pytest.raises(OperationalError):
            with engine.connect():
                pytest.fail("A connection must not accept an invalid CA file.")
    finally:
        engine.dispose()


def test_certificate_hostname_is_verified(live_db):
    settings = live_db.settings
    address = socket.getaddrinfo(settings.host, settings.port, type=socket.SOCK_STREAM)[0][4][0]
    # Connect to the real endpoint's address while asking libpq to verify a
    # different hostname. No password can be sent before TLS verification.
    with pytest.raises(psycopg.OperationalError, match="certificate"):
        psycopg.connect(
            host="deliberately-wrong-hostname.invalid",
            hostaddr=address,
            port=settings.port,
            dbname=settings.database,
            user=settings.user,
            password=settings.password,
            sslmode="verify-full",
            sslrootcert=str(settings.sslrootcert),
            connect_timeout=5,
        )
