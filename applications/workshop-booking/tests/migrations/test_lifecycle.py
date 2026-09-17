"""Destructive migration test: run explicitly on an empty example schema."""

import os
from dataclasses import replace
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import text

from app.config import Settings
from app.database import build_engine


def test_upgrade_downgrade_reapply(monkeypatch):
    if os.environ.get("WORKSHOP_ALLOW_SCHEMA_RESET") != "1":
        pytest.fail(
            "This test drops the example tables. Use an empty, dedicated test service "
            "and explicitly set WORKSHOP_ALLOW_SCHEMA_RESET=1."
        )
    password = os.environ.get("WORKSHOP_MIGRATOR_PASSWORD")
    if not password:
        pytest.fail("Set WORKSHOP_MIGRATOR_PASSWORD to run migration tests.")
    settings = replace(
        Settings.from_env(require_tokens=False),
        user="workshop_booking_migrator",
        password=password,
    )
    monkeypatch.setenv("PGUSER", settings.user)
    monkeypatch.setenv("PGPASSWORD", settings.password)
    engine = build_engine(settings)
    config = Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))

    def table_names():
        with engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            return set(
                connection.scalars(
                    text("SELECT tablename FROM pg_tables WHERE schemaname = 'workshop_booking'")
                )
            )

    # A deliberate second guard: even the opt-in cannot destroy populated data.
    for table in table_names() - {"alembic_version"}:
        if table not in {"workshops", "attendees", "bookings"}:
            pytest.fail("The schema contains an unexpected table; refusing to reset it.")
        with engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            if connection.scalar(text(f"SELECT count(*) FROM workshop_booking.{table}")):
                pytest.fail("The example schema contains data; refusing to reset it.")

    try:
        command.upgrade(config, "head")
        assert table_names() == {"workshops", "attendees", "bookings", "alembic_version"}
        with engine.begin() as connection:
            connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
            owners = set(
                connection.scalars(
                    text("SELECT tableowner FROM pg_tables WHERE schemaname = 'workshop_booking'")
                )
            )
            assert owners == {"workshop_booking_owner"}
            assert (
                connection.scalar(text("SELECT version_num FROM workshop_booking.alembic_version"))
                == "001_initial"
            )

        command.downgrade(config, "base")
        assert table_names() == {"alembic_version"}
        command.upgrade(config, "head")
        assert table_names() == {"workshops", "attendees", "bookings", "alembic_version"}
        command.upgrade(config, "head")  # Already at head is a harmless no-op.
    finally:
        engine.dispose()
