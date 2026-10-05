# Fieldwork: a live planning board

A small shared task board using **Electric, TanStack DB, Hono and Drizzle**, backed by **ClickHouse Managed Postgres**. Electric streams two scoped collections. TanStack DB joins tasks to projects and runs the status/project filters locally. Hono owns writes; the browser never writes directly to Postgres.

![Fieldwork planning board](docs/local-query-board.png)

_Local seeded workflow capture; Managed Postgres verification is described below._

Create a task in one tab and watch it arrive in another. Change its status or priority, then filter the board. Writes use an expected revision; competing updates cannot silently overwrite one another. The UI distinguishes a committed write from a stream that is still catching up. This is a trusted loopback workbench without accounts or offline writes.

## Requirements

Run dependencies and containers on Linux, for example inside an OrbStack VM. The verified stack uses Bun 1.4.2, Postgres 18, Electric 1.8.1, TanStack DB 0.11.3, its React adapter 0.5.3 and Electric adapter 0.5.4, Hono 4.13.13 and Drizzle 0.45.3. Install Docker with Buildx, Git, `psql`, `jq`, and [clickhousectl](https://github.com/ClickHouse/clickhousectl). Package versions are pinned in `package.json` and `bun.lock`.

```sh
curl -fsSL https://bun.sh/install | bash -s "bun-v1.4.2"
export PATH="$HOME/.bun/bin:$HOME/.local/bin:$PATH"
curl -fsSL https://clickhouse.com/cli | sh
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/local-query-board
bun install --frozen-lockfile
```

## Create the database with clickhousectl

Interactive Cloud authentication uses your Admin API key and secret. A disposable Cloud database incurs ordinary database costs until deleted. Create your own resource, keep its credentials private and record its ID for cleanup.

```sh
umask 077
mkdir -p .deployment
chmod 700 .deployment
clickhousectl cloud org list
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name fieldwork-demo --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json > .deployment/create.json
export SERVICE_ID="$(jq -r .id .deployment/create.json)"
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
# Wait until the get response reports running, then retrieve its CA.
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" \
  --output .deployment/postgres-ca.pem
```

Use the hostname and owner username/password returned by the service. Use port 5432 and database `postgres` for this direct-service setup; the service response remains authoritative. Keep owner credentials separate from the runtime roles.

```sh
export PGHOST=the-service-hostname PGPORT=5432 PGDATABASE=postgres
export PGSSLMODE=verify-full PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
export PG_OWNER_USER=the-owner-username
read -r -s PG_OWNER_PASSWORD; export PG_OWNER_PASSWORD
export PG_MIGRATION_PASSWORD="Aa1_$(openssl rand -hex 24)"
export PG_APP_PASSWORD="Aa1_$(openssl rand -hex 24)"
export PG_SYNC_PASSWORD="Aa1_$(openssl rand -hex 24)"
# Save them privately for the run instructions or an interrupted setup retry.
printf 'PG_MIGRATION_PASSWORD=%s\nPG_APP_PASSWORD=%s\nPG_SYNC_PASSWORD=%s\n' \
  "$PG_MIGRATION_PASSWORD" "$PG_APP_PASSWORD" "$PG_SYNC_PASSWORD" > .deployment/role-passwords.env
PGUSER="$PG_OWNER_USER" PGPASSWORD="$PG_OWNER_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/roles.sql
PGUSER=planning_migration PGPASSWORD="$PG_MIGRATION_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/schema.sql
PGUSER=planning_migration PGPASSWORD="$PG_MIGRATION_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/seed.sql
PGUSER="$PG_OWNER_USER" PGPASSWORD="$PG_OWNER_PASSWORD" \
  psql -X -v ON_ERROR_STOP=1 -f sql/publication.sql
```

The migration role owns `planning`. The application role can read projects and read/insert/update tasks. The sync role has `REPLICATION`, schema usage and table `SELECT`, with no continuing database `CREATE` privilege. Manual publication includes only the two app tables, both using `REPLICA IDENTITY FULL`. Seed data includes a separate `private-lab` board to make the shape scope observable.

## Build and start Electric

The verified route builds the official Electric release source. During development, anonymous pulls from the documented Docker Hub repository were unavailable; no alternate mirror is required. This source build pins the exact 1.8.1 release commit and uses its original Dockerfile plus the telemetry build context.

```sh
git clone --depth 1 --branch '@core/sync-service@1.8.1' \
  https://github.com/electric-sql/electric.git .deployment/electric-source
cd .deployment/electric-source
test "$(git rev-parse HEAD)" = 0f404200402f918a4b1596bc5c8a53479a435349
docker build --build-arg ELECTRIC_VERSION=1.8.1 \
  --build-context electric-telemetry=packages/electric-telemetry \
  -f packages/sync-service/Dockerfile \
  -t fieldwork-electric:1.8.1 packages/sync-service
cd ../..
```

Create `.deployment/electric.env` with these values, then `chmod 600` it. Replace the hostname/password and generate a secret used only by Hono and Electric. Do not prefix it with `VITE_`.

```dotenv
DATABASE_URL=postgresql://planning_sync:replace-me@the-service-hostname:5432/postgres?sslmode=require
ELECTRIC_SECRET=replace-with-a-random-server-secret
ELECTRIC_DATABASE_CA_CERTIFICATE_FILE=/certs/postgres-ca.pem
ELECTRIC_REPLICATION_STREAM_ID=local_query_board
ELECTRIC_MANUAL_TABLE_PUBLISHING=true
ELECTRIC_DB_POOL_SIZE=3
ELECTRIC_TELEMETRY=false
ELECTRIC_STORAGE_DIR=/var/lib/electric
```

Electric's URL parser supports `sslmode=require`, rather than `verify-full`. Supplying `ELECTRIC_DATABASE_CA_CERTIFICATE_FILE` enables certificate and hostname verification in its connector; do not omit the CA to bypass a connection error.

```sh
docker run -d --name fieldwork-electric \
  --env-file .deployment/electric.env -p 127.0.0.1:3005:3000 \
  -v "$PWD/.deployment/postgres-ca.pem:/certs/postgres-ca.pem:ro" \
  -v fieldwork-electric:/var/lib/electric fieldwork-electric:1.8.1
curl -fsS http://127.0.0.1:3005/v1/health
```

## Run the board

Copy `.env.example` to `.env` and fill in the `planning_app` password, direct hostname, CA path and the same Electric secret. Keep `.env` private. The app accepts a plain Postgres URL without TLS query overrides. For the tested Bun runtime, the connector narrowly retries individual supplied CA anchors only if a rotation bundle triggers `CERT_SIGNATURE_FAILURE`; every attempt retains certificate and hostname checks.

```sh
cp .env.example .env
chmod 600 .env
bun run typecheck
bun run build
bun run start
```

When using a VM, forward only the loopback app port from your laptop:

```sh
ssh -N -L 3000:127.0.0.1:3000 YOUR_MACHINE@orb
```

Open `http://127.0.0.1:3000` in two tabs. The UI uses Electric's HTTP shape stream, including long polling for changes; it does not repeatedly fetch tasks from the write API. Two eager collections keep this demo small. For remote deployment, add actual authentication and server-selected per-user scopes, and use HTTPS/HTTP2 for concurrent shape streams.

## How the pieces connect

- `src/client/collections.ts` creates Electric-backed TanStack DB collections with Zod schemas and stable row keys.
- `src/client/main.tsx` uses `useLiveQuery` to join tasks with projects and apply local filters. There are no optimistic local inserts: a task appears when its committed row arrives through Electric.
- `src/server/proxy.ts` fixes the table, columns and `board_id = 'studio'` scope. Only supported stream continuation parameters pass through; caller-supplied tables, filters, columns, secrets and subset queries are refused.
- `src/server/writes.ts` uses Drizzle transactions. An update matches the expected revision and increments it atomically. The transaction returns `pg_current_xact_id()::xid::text`; `awaitTxId` waits for that same committed transaction in the task collection.

A delayed stream does not undo a committed write. The input clears after the API confirms creation, and the UI says the stream is catching up if synchronization times out. A stale update returns `409` and leaves the database unchanged.

## Verify

```sh
bun run test
bun run test:integration
bunx playwright install --with-deps chromium
bun run test:browser
# Optional real container interruption/recovery check (stops only this named engine):
ELECTRIC_TEST_CONTAINER=fieldwork-electric bun run test:browser
```

The secret-free CI checks frozen installation, typecheck, build and proxy unit checks. Integration checks exercise the actual database: eight competing revisions produce one winner, invalid project/status writes leave stored state unchanged, and runtime DDL/deletion grants are refused. The browser check uses two real tabs for snapshot, CDC, local join/filter, an actual hidden-project API rejection, a simulated UI error-state control and shape override refusal. Managed verification also exercised wrong CA/hostname controls in both connectors, an actual engine interruption during a committed create, and fresh browser state after real app/engine restart. Integration/browser commands need a running seeded database and Electric/app processes. The interruption test explicitly skips unless `ELECTRIC_TEST_CONTAINER` names this owned engine; the regular two-tab test always runs.

For local Postgres, use `clickhousectl local postgres start --name fieldwork --version 18`. Set `wal_level=logical` and restart that owned container before configuring roles/publication. The app's local mode is restricted to loopback; Electric connects over a dedicated Docker network with `sslmode=disable` and no CA only for this local fixture.

## Cleanup

Stop Electric before removing its replication slot; stopping the app alone leaves the sync engine active. Use the owner connection to inspect and remove only this example's publication/slot, then delete your database service.

```sh
docker stop fieldwork-electric
PGUSER="$PG_OWNER_USER" PGPASSWORD="$PG_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 \
  -c "SELECT slot_name, active FROM pg_replication_slots WHERE slot_name LIKE '%local_query_board%';"
# Substitute the exact inactive slot name returned above.
PGUSER="$PG_OWNER_USER" PGPASSWORD="$PG_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 \
  -c "SELECT pg_drop_replication_slot('the-owned-slot-name');"
PGUSER="$PG_OWNER_USER" PGPASSWORD="$PG_OWNER_PASSWORD" psql -X -v ON_ERROR_STOP=1 \
  -c 'DROP PUBLICATION electric_publication_local_query_board;'
docker rm fieldwork-electric
docker volume rm fieldwork-electric
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
# Verify your owned ID is absent. Never delete another service by name similarity.
```

See the [Electric configuration](https://electric.ax/docs/sync/api/config), [Postgres permissions](https://electric.ax/docs/sync/guides/postgres-permissions), [shape authorization](https://electric.ax/docs/sync/guides/auth) and [TanStack Electric collection](https://tanstack.com/db/latest/docs/collections/electric-collection) references for deployment beyond this workbench.
