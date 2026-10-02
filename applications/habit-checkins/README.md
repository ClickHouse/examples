# Habit check-ins with ASP.NET Core and EF Core

A small account-scoped API backed by ClickHouse Managed Postgres in ClickHouse Cloud. Create habits, mark an explicit calendar date complete, undo it, and archive a habit while keeping history. Repeating a check-in returns the stored completion, including its original ID, instead of inserting a duplicate. There is no frontend, streak calculation or inferred timezone.

Pinned stack: .NET SDK 10.0.401 / ASP.NET Core 10.0.12, EF Core 10.0.12 (including Relational, Design and dotnet-ef), Npgsql and its EF provider 10.0.3. The provider's NuGet metadata supports EF versions 10.0.4–10.x; all Microsoft EF packages are explicitly aligned to 10.0.12. NuGet lockfiles pin transitive dependencies. `global.json` disables SDK roll-forward and preview SDKs.

## API and date contract

Demo bearer tokens in `APP_TOKENS` bind to immutable user IDs. Generate different random tokens with `openssl rand -hex 24` and keep them secret. Retain the same identity when rotating a token. Ownership is derived from the server mapping; a submitted `ownerId` is an unknown JSON property and rejected. Token digests use SHA-256 and constant-time comparison. There is no registration, token issuance or persisted revocation system.

Every habit operation filters by authenticated owner. An inaccessible/missing habit returns 404. The shared runtime database role is trusted application infrastructure: API ownership checks are not Postgres row-level security, and that database credential can access both users' rows. End users receive API tokens, not database passwords. Remote deployment requires HTTPS at a trusted proxy; the API binds to loopback by default and has no cookie authentication or CORS configuration.

| Method | Route | Behavior |
|---|---|---|
| GET | `/health` | Anonymous process liveness, not database readiness |
| POST | `/habits` | JSON `name`; returns 201 and habit |
| GET | `/habits` | Newest 100 owned habits, including archived |
| PUT | `/habits/{id}/check-ins/{date}` | 200 on creation/replay; 409 for a new archived completion |
| DELETE | `/habits/{id}/check-ins/{date}` | Undo; repeated undo returns 204 |
| POST | `/habits/{id}/archive` | Repeat-safe archive; retains existing history |
| GET | `/habits/{id}/history?month=2026-10` | Owned monthly completions, ascending date, at most 31 |

Supply dates exactly as `yyyy-MM-dd`, from 2000-01-01 through 2100-12-31; supply months as `yyyy-MM` in that range. A date is a client-chosen calendar label, represented by `DateOnly` and Postgres `date`. The server does not derive it from a clock, timezone or timestamp. Dates can be in the past or future within the documented range. Names must be nonblank, no embedded NUL, and at most 100 input UTF-16 code units; stored names are trimmed. JSON request bodies are capped at 4096 bytes.

Archive rejects a **new** completion with 409. An existing habit/date completion can still be replayed with 200. Undo remains allowed after archive; once undone, completing that date again is a new completion and returns 409. There is no unarchive or API habit deletion. Lists order by `createdAt DESC, id DESC`, with no pagination or total count. Errors use 400 for invalid input, 401 for invalid/missing tokens, 404 for inaccessible habits, 409 for new archived completion and 413 for oversized JSON.

## Build

Install the pinned .NET SDK, Python 3 and a PostgreSQL client. In this directory:

```sh
dotnet restore --locked-mode
dotnet tool restore
dotnet build -c Release --no-restore
dotnet test -c Release --no-build --filter 'Category!=Cloud'
```

Three database-independent tests cover explicit date/month boundaries and token identity mapping. CI uses these commands without Cloud credentials. Cloud tests do not use EF's in-memory provider or a local database.

## Create a dedicated Cloud service

Install [clickhousectl](https://github.com/ClickHouse/clickhousectl) and authenticate using your Cloud API credentials. These visible commands match clickhousectl 0.5.0. Select a supported size/region for your account; the fixture used c6gd.large in us-east-1, Postgres 18, without HA. Creating a service incurs charges. Check current service options in the [ClickHouse Managed Postgres quickstart](https://clickhouse.com/docs/products/managed-postgres/quickstart) and delete your dedicated test service afterward.

```sh
clickhousectl cloud postgres create --name habit-checkins-demo \
  --provider aws --region us-east-1 --size c6gd.large \
  --pg-version 18 --ha-type none --json > service-private.json
chmod 600 service-private.json
# Set SERVICE_ID to the returned id. Poll until state is running:
clickhousectl cloud postgres get "$SERVICE_ID" --json
clickhousectl cloud postgres certs get "$SERVICE_ID" --output cloud-ca.pem
```

Save the receipt outside the repository: it contains the initial administrator password, which later `get` calls do not return. Copy `.env.example` to a private environment file and fill the hostname, absolute CA path, runtime password and generated tokens. Do not paste connection strings or credentials into source/history.

`PgConfig` builds a connection with `SSL Mode=VerifyFull` and the downloaded `Root Certificate`; there is no arbitrary certificate-validation callback or trust bypass. `PGSSLMODE=verify-full` also protects the visible `psql` commands. The Npgsql 10 GSS encryption preference is disabled explicitly so this example uses the specified TLS path.

## Bootstrap, migrate, grant and seed

Use a fresh dedicated service. Set `PGHOST`, `PGPORT=5432`, `PGDATABASE=postgres`, `PGSSLMODE=verify-full`, `PGSSLROOTCERT` and administrator `PGUSER` / `PGPASSWORD`. Privately export two different random database passwords as `MIGRATION_PASSWORD` and `APP_PASSWORD`.

```sh
psql -X -v ON_ERROR_STOP=1 \
  -v migration_password="$MIGRATION_PASSWORD" \
  -v app_password="$APP_PASSWORD" -f sql/bootstrap.sql
```

The administrator creates two roles and a schema `habits` owned by `habit_migration`. Runtime `habit_app` receives schema USAGE. PUBLIC loses CREATE on `public` on this dedicated fixture. No database CREATE grant is needed for migrations in the existing owned schema. psql password arguments can be visible to other local users on a shared machine; keep fixture setup private.

Run the committed EF migration explicitly with the migration credential:

```sh
PGUSER=habit_migration PGPASSWORD="$MIGRATION_PASSWORD" \
  dotnet ef database update --project HabitApi --configuration Release --no-build
PGUSER=habit_migration PGPASSWORD="$MIGRATION_PASSWORD" \
  dotnet ef migrations has-pending-model-changes --project HabitApi --configuration Release --no-build
```

The design-time factory uses only the credential supplied to that command. The migration creates habits, child check-ins, their foreign key, a named unique habit/date index and an owner/list index. EF history is in `habits.__EFMigrationsHistory`. First migration on an empty schema may log a missing-history SELECT before creating the table; the command then applies the initial migration. Normal API startup never calls `Migrate`, `EnsureCreated` or any DDL method.

With the administrator credential still in the shell, grant only table CRUD, then seed using runtime:

```sh
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
PGUSER=habit_app PGPASSWORD="$APP_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
```

Repeat migration and seed safely: EF reports up-to-date and the seed's fixed IDs/natural key use `ON CONFLICT DO NOTHING`. Runtime cannot create tables or read EF migration history. To add a future migration, change the model, run `dotnet ef migrations add NAME --project HabitApi`, review the generated migration/snapshot, and apply it through the same owner-only path.

## Start and try a check-in

Start a fresh shell and load only the runtime environment/tokens. Keep administrator and migration credentials out of the API process.

```sh
dotnet HabitApi/bin/Release/net10.0/HabitApi.dll
```

The default address is `http://127.0.0.1:8080`. An explicit `APP_URL` override supports a trusted deployment. Set `USER_TOKEN` privately to a configured token:

```sh
curl -sS http://127.0.0.1:8080/habits \
  -H "Authorization: Bearer $USER_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name":"Read a chapter"}'
# Set HABIT_ID to the response id.
curl -sS -X PUT http://127.0.0.1:8080/habits/$HABIT_ID/check-ins/2026-10-05 \
  -H "Authorization: Bearer $USER_TOKEN"
# Repeat the same PUT: 200, the same persisted completion id.
curl -sS 'http://127.0.0.1:8080/habits/'"$HABIT_ID"'/history?month=2026-10' \
  -H "Authorization: Bearer $USER_TOKEN"
```

A check-in transaction first locks the owned habit row with parameterized `FOR UPDATE`. Completion, undo and archive all follow this cooperative locking protocol. If completion commits before archive, it stays in history; if archive commits first, the waiting new completion returns 409. Direct writers that ignore this protocol could break archive behavior. The unique index remains a database backstop for duplicate habit/date rows, independent of cooperative locking.

EF inserts the check-in after checking for an existing row. Only SQLSTATE 23505 for `uq_check_in_habit_date` is treated as a repeat: the transaction is rolled back and the durable winner is read. Other database errors propagate. Monthly history uses a half-open range from the first day to the next month, projects only completion fields, orders by date, and caps at 31. The unique index also supports that range query.

## Cloud acceptance

Use a dedicated fixture with the two `.env.example` identities and runtime credentials:

```sh
dotnet test -c Release --no-build --filter 'Category=Cloud'
python3 scripts/acceptance.py
```

Six native Cloud tests exercise independent duplicate writers (one success, one exact named 23505), both archive/check-in lock orderings, real rollback after saving, runtime permission denials/encrypted connection, and wrong-CA certificate failure with a positive same-endpoint control. Ordering tests hold a parent lock, observe a blocked service through `pg_blocking_pids` with refreshed statistics snapshots, then commit and assert the result.

The HTTP script starts the production DLL on loopback 8081 with only runtime credentials. It checks date/name/body bounds, forged ownership and cross-user reads/writes, eight concurrent duplicate check-ins returning one stored ID, four archive/check-in races, retained history, archived replay/undo behavior, ascending monthly projection and persistence after process restart. Tests remove their generated rows using the runtime credential; do not point them at production data. `APP_LOG` selects a private application log, default `/tmp/habit-api.log`. The wrong-CA control uses the system CA bundle, which must not include the dedicated Cloud CA.

## Cleanup

Stop the application. Switch to administrator credentials on your dedicated fixture and optionally remove only the example schema/roles, then delete the dedicated service:

```sh
psql -X -v ON_ERROR_STOP=1 -f sql/cleanup.sql
clickhousectl cloud postgres delete "$SERVICE_ID"
clickhousectl cloud postgres list --json
```

Deletion is asynchronous. Confirm your recorded ID disappears; do not delete an unrelated resource. Remove private local receipts when no longer needed.

## Sources

[Npgsql security](https://www.npgsql.org/doc/security.html), [Npgsql EF provider](https://www.npgsql.org/efcore/), [EF concurrency](https://learn.microsoft.com/en-us/ef/core/saving/concurrency), [ASP.NET Core APIs](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/apis?view=aspnetcore-10.0), [EF migration application](https://learn.microsoft.com/en-us/ef/core/managing-schemas/migrations/applying).
