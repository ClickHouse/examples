# Tests

Run these commands inside your Linux development environment from the example
directory, after installing `requirements-dev.txt` into `.venv`.

```bash
.venv/bin/pytest tests/unit -q
.venv/bin/ruff check app migrations tests
.venv/bin/ruff format --check app migrations tests
```

## Live Postgres tests

Use a dedicated ClickHouse Managed Postgres service, complete the README's
bootstrap and Alembic steps, and load the seed data. The tests call the FastAPI
application through its HTTP test client while using real, separately committed
Postgres transactions. SQLite and mocked database connections are not used.

Set `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER=workshop_booking_app`, `PGPASSWORD`,
and `PGSSLROOTCERT` as described in the main README. Also set
`WORKSHOP_MIGRATOR_PASSWORD` so fixtures can create and remove their own rows. All
connections use `sslmode=verify-full`. The tests create their own temporary
attendee token mapping; `API_BEARER_TOKENS` is not needed for these tests.

If you keep these values in a private, shell-compatible file, for example
`.deployment/test.env`, restrict its permissions and explicitly export it:

```bash
chmod 600 .deployment/test.env
set -a
source .deployment/test.env
set +a
.venv/bin/pytest tests/integration -q
```

The explicitly selected integration suite **fails** if credentials are missing.
It creates fresh UUIDs for all fixture attendees and workshops, and removes only
those rows when it finishes. It does not truncate tables or change sample rows.
An interrupted process may leave fixture rows behind; use the dedicated test
service for that reason. Do not run this suite against customer data.

The suite checks last-seat contention, repeated and concurrent cancellation,
booking UUID retries, ownership, start times after waiting for locks, transaction
rollback, database constraints, runtime role restrictions, TLS use, invalid CA
rejection, and hostname verification. Concurrency assertions inspect committed
database state as well as HTTP responses.

## Migration lifecycle

Run this separately, **after bootstrap and before seeding**. It upgrades to the
latest revision, checks ownership, downgrades to an empty schema, upgrades again,
and checks that upgrading an already current database is harmless.

```bash
WORKSHOP_ALLOW_SCHEMA_RESET=1 .venv/bin/pytest tests/migrations -q
```

This command uses the same exported connection settings and
`WORKSHOP_MIGRATOR_PASSWORD`. It assumes the migrator role itself. The opt-in is
required, and a second safety check refuses to reset a schema containing any
application rows or unexpected tables. Run `sql/seed.sql` after this test.

Keep local logs and validation receipts outside the example directory.
