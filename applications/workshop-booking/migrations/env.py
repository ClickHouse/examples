"""Run SQL migrations with the separate migrator login and schema owner role."""

from alembic import context
from sqlalchemy import text

from app.config import Settings
from app.database import build_engine
from app.models import Base


def run_migrations_online() -> None:
    settings = Settings.from_env(require_tokens=False)
    if settings.user != "workshop_booking_migrator":
        raise RuntimeError("Run Alembic with PGUSER=workshop_booking_migrator.")

    engine = build_engine(settings)
    try:
        with engine.connect() as connection:
            # The login cannot create objects until it deliberately assumes the
            # non-login owner. Keep this and all DDL in a single transaction.
            with connection.begin():
                connection.execute(text("SET LOCAL ROLE workshop_booking_owner"))
                context.configure(
                    connection=connection,
                    target_metadata=Base.metadata,
                    version_table_schema="workshop_booking",
                    include_schemas=True,
                    transactional_ddl=True,
                )
                with context.begin_transaction():
                    context.run_migrations()
    finally:
        engine.dispose()


if context.is_offline_mode():
    raise RuntimeError(
        "Offline migrations are disabled. Inspect sql/migrations/*.sql, then run "
        "Alembic against the database with migrator credentials."
    )
else:
    run_migrations_online()
