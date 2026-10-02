# Capacity Board

A small C#/Blazor Interactive Server board allocates a synthetic sprint's 30 effort points on [ClickHouse Managed Postgres (public beta)](https://clickhouse.com/docs/products/managed-postgres/overview). An editor changes a complete set of up to twenty work items and saves against the revision displayed in that editor. The committed summary stays separate from the unsaved draft.

This is one trusted local operator workspace with **no authentication or tenant isolation**. It binds loopback and checks Host/browser Origin; those controls are not operator identity. There is no employee data, external issue tracker, productivity score or calendar integration.

## Transactions and circuit lifetime

The repository acquires one connection from a singleton NpgsqlDataSource per operation. It never retains an open connection or transaction in a Blazor circuit or across user think time. The component retains only bounded draft values, the loaded snapshot/revision and an uncertain original save request.

One joined read observes the parent and ordered children from one statement snapshot, including an empty child set. A save:

1. Validates and canonicalizes its complete ordered item set, expected revision and operation UUID.
2. Locks the single board row; checks retained operations before stale-revision and save-limit checks.
3. Rejects a changed payload under a retained UUID, stale revision or aggregate total above capacity.
4. Deletes the old children and inserts the complete replacement on that same connection/transaction.
5. Increments the revision and inserts an immutable audit/result row, then **awaits COMMIT** before returning saved state.

A failed insertion or COMMIT rolls back child replacement, revision and audit. Matching operation retries return their original saved snapshot even after later saves. A changed ordered set, point/name or expected revision conflicts. Names are trimmed before fingerprinting; row order is retained. The fixture allows 25 successful saves (initial revision 1 through revision 26). Exact retained retries still work at that limit; new operations are rejected. History is not automatically deleted.

Names must contain 1–80 UTF-16 code units after trimming; controls and malformed surrogate pairs are rejected before UTF-8 encoding. A raw name is bounded before trimming. UUIDs must be nonzero/unique within the complete set; effort is an exact integer 0–30. The browser retains point fields as bounded strings until validation, so malformed numeric input cannot silently save an earlier parsed value. There are no currency values.

The circuit disables local repeated dispatch while a save is pending. A stale save preserves its values and displayed revision, with an explicit reload action; it never silently rebases edits. An uncertain save pauses editing and retains the exact request for the Retry original save button. Reload discards the draft/retry. Cancellation or a disconnect does not prove that an operation did not commit. After actual process restart, a new circuit reloads committed Postgres state; unsaved circuit values have no durable guarantee.

## Role and resource bounds

The runtime role can SELECT the board/items/saves, UPDATE only board revision, INSERT/DELETE children, and INSERT retained saves. It cannot change capacity/title, update children, mutate/delete existing audit, access migration history, become the migration role, or create schema/application/temp objects. The schema owner alone runs reviewed migrations.

Database constraints enforce bounded per-item points, nonzero UUIDs, FK, unique item positions and retained operation/revision uniqueness. **Direct trusted runtime SQL can bypass the application's aggregate-capacity, revision and audit protocol** by changing children or permitted revision metadata. The Cloud check explicitly demonstrates an aggregate total above capacity through direct SQL. The API's parent lock and validation coordinate cooperating application operations; shared server credentials are not per-user RLS.

Npgsql uses VerifyFull with the full official Cloud CA. Pool size is 4, minimum idle 0, open/acquisition timeout 5 seconds, command timeout 4 seconds, idle lifetime 60 seconds and connection lifetime 300 seconds. Postgres statement/lock/idle-transaction limits are 4/2/6 seconds. Four local admission slots reject additional operations as busy; repository operations request cancellation after 10 seconds. These controls don't guarantee an end-to-end HTTP deadline or undo a possible commit.

Kestrel permits 32 normal and 32 upgraded connections, 16 KiB request bodies, five-second request headers and thirty-second keepalive. SignalR retains its one parallel invocation per circuit, has 16 KiB received messages/buffers and allows WebSockets/LongPolling. Disconnected circuits retain at most ten entries for thirty seconds; JS interop timeout is five seconds. WebSocket compression is disabled; frame ancestors are denied. Native antiforgery remains enabled for component form posts. SignalR negotiation/messages and WebSocket upgrade require the configured local Origin; any supplied foreign Origin and mismatched Host are rejected. Non-browser clients can forge these headers, reinforcing the local trusted-workspace scope.

## Native build

Tested 2 October 2026 on Ubuntu 24.04 ARM64: .NET SDK 10.0.401, ASP.NET Core/runtime 10.0.12, Dapper 2.1.89 and Npgsql 10.0.3. global.json pins the SDK; both projects have committed NuGet lockfiles.

```sh
sudo apt-get update
sudo apt-get install -y curl ca-certificates git postgresql-client python3 libicu74 xz-utils
curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
bash /tmp/dotnet-install.sh --version 10.0.401 --install-dir "$HOME/.dotnet"
export DOTNET_ROOT="$HOME/.dotnet" PATH="$HOME/.dotnet:$PATH"
cd /path/to/examples/applications/capacity-board
dotnet restore --locked-mode
dotnet restore Tests/Tests.csproj --locked-mode
dotnet format --verify-no-changes --no-restore
dotnet format Tests/Tests.csproj --verify-no-changes --no-restore
dotnet build -c Release --no-restore
dotnet run --project Tests/Tests.csproj -c Release --no-restore
dotnet publish -c Release --no-restore -o /private/path/capacity-published
python3 test/preflight.py /private/path/capacity-published/CapacityBoard
```

Four local domain groups cover canonical fingerprints, UUID/count/revision bounds, Unicode/controls and bounded integer parsing. Separate compiled preflight verifies listener/Host/Origin rejection and confirmed SIGTERM exit without a database. CI uses no Cloud credentials. Launch the published executable; its content root is the published directory, so assets resolve independently of the shell's directory.

## Create a dedicated Cloud fixture

Creating the service starts billing. Check your organization's supported shape; the tested modest AWS shape was:

```sh
umask 077
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name capacity-board-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json > /private/path/create.json
export PG_ID=your-created-service-id
clickhousectl cloud postgres get "$PG_ID" --org-id "$ORG_ID"
# Repeat get until state is running before fetching the official CA.
clickhousectl cloud postgres certs get "$PG_ID" --org-id "$ORG_ID" \
  --output /private/path/ca.pem
```

Save the returned hostname, administrator username and one-time password privately. `--output` writes the PEM; preserve the full official bundle and refresh it after rotation. The runtime factory checks both certificate and hostname, without a trust callback bypass.

## Explicit roles, migration and seed

Copy .env.example to a private mode-600 setup.env outside the checkout. Fill in the service connection/CA, administrator credentials, separate migration password and runtime password in PGPASSWORD. Quote shell-sensitive values and export fields to children:

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full
APP_PASSWORD=$PGPASSWORD
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD
psql -X -v MIGRATION_PASSWORD="$MIGRATION_PASSWORD" -v APP_PASSWORD="$APP_PASSWORD" -f sql/bootstrap.sql
export PGUSER=capacity_migration PGPASSWORD=$MIGRATION_PASSWORD
/private/path/capacity-published/CapacityBoard migrate
psql -X -f sql/grants.sql
psql -X -f sql/seed.sql
```

Bootstrap creates schema/roles and revokes PUBLIC database CREATE/TEMP and public-schema CREATE on this dedicated fixture. The schema owner needs no database CREATE. Embedded versioned SQL and an advisory transaction lock make repeated migration safe. Seed repeats without resetting an existing board, revision or allocation. Startup never performs DDL; migration mode rejects runtime credentials.

## Run and edit

```sh
export PGUSER=capacity_app PGPASSWORD=$APP_PASSWORD
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD
/private/path/capacity-published/CapacityBoard
```

Open http://127.0.0.1:5000. APP_ORIGIN can select another local port at or above 1024; it must remain an HTTP origin using 127.0.0.1, without path/query/userinfo. Use that exact origin in the browser. Startup checks runtime connectivity before serving. Health checks process readiness rather than continuously probing the database.

The seeded Workshop sprint has three items totaling nine points. Edit several names/point values and compare the draft total with the committed summary; Save allocation commits the complete set. A second browser tab has its own loaded revision. If another tab saves first, stale values stay visible until you explicitly reload. Local pending/uncertain state doesn't replace the database's lock/revision checks.

## Destructive dedicated acceptance

Stop the app first. Export a private setup/test shell with both runtime and owner/admin fields; the compiled browser child receives only runtime connection/CA/origin fields. Native tests assume a freshly seeded dedicated fixture. For empty-schema reproduction, restore administrator credentials and run cleanup, then repeat the documented bootstrap/migrate/grants/seed. Repeat migrate and seed twice to verify retained setup state.

```sh
set -a; source /private/path/setup.env; set +a
export PGSSLMODE=verify-full PGUSER=capacity_app
export WRONG_CA=/private/path/wrong-ca.pem
openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj /CN=UnrelatedAcceptanceCA \
  -keyout /private/path/wrong-ca.key -out "$WRONG_CA"
dotnet run --project Tests/Tests.csproj -c Release --no-build -- --cloud
# Reseed an isolated owner fixture for the browser suite:
APP_PASSWORD=$PGPASSWORD
export PGUSER=capacity_migration PGPASSWORD=$MIGRATION_PASSWORD
psql -X -c 'TRUNCATE capacity_board.saves,capacity_board.work_items,capacity_board.boards'
psql -X -f sql/seed.sql
export PGUSER=capacity_app PGPASSWORD=$APP_PASSWORD
export CAPACITY_EXECUTABLE=/private/path/capacity-published/CapacityBoard
export EVIDENCE_DIR=/private/path/acceptance
cd test
npm ci
npx playwright install --with-deps chromium
node browser.mjs
```

Browser tools were tested with Node 24.21.0/Playwright 1.63.0/Chromium 153.0.8010.12. Install them natively; test/package-lock.json pins the browser dependency. Seven native Cloud groups cover typed UUID/int/null/UTC mapping, retained changed-payload conflict, second-child rollback, actual deferred COMMIT failure, two observed blocked sessions/read progress/stale rejection, all 25 saves/replay at cap, actual grants/native constraints and certificate-specific negatives with same-service positive control. Test-only pool warm-up does not change runtime limits.

The browser helper covers two real circuits, preserved stale form, overcapacity/invalid input, security defaults, saved UI only after an independently observed deferred COMMIT hold, uncertain-commit retry, original-process exit before replacement, and desktop/mobile bounds. Owner-only fault triggers and reseeding are test fixtures. No production downgrade or durable unsaved-draft claim is made. Evidence stays outside the checkout.

## Cleanup

Stop the app. Optional schema cleanup must restore administrator fields that the run shell unset:

```sh
set -a; source /private/path/setup.env; set +a
export PGUSER=$ADMIN_USER PGPASSWORD=$ADMIN_PASSWORD PGSSLMODE=verify-full
psql -X -f sql/cleanup.sql
clickhousectl cloud postgres delete "$PG_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID"
```

Confirm the exact ID is absent; PUBLIC revocations remain after schema cleanup.

Primary references: [Blazor circuit DI lifetime](https://learn.microsoft.com/en-us/aspnet/core/blazor/fundamentals/dependency-injection?view=aspnetcore-10.0), [server security guidance](https://learn.microsoft.com/en-us/aspnet/core/blazor/security/interactive-server-side-rendering?view=aspnetcore-10.0), [Dapper 2.1.89 CommandDefinition](https://github.com/DapperLib/Dapper/blob/2.1.89/Dapper/CommandDefinition.cs), [Npgsql data source and transactions](https://www.npgsql.org/doc/basic-usage.html), [Npgsql VerifyFull](https://www.npgsql.org/doc/security.html). The pinned ASP.NET Core 10 release exposes dispatcher settings through endpoint metadata; the source uses that released path rather than assuming a later ConfigureConnection property.
