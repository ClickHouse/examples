# Stock Reservation API: reserve limited inventory with Hono, Bun.SQL, and ClickHouse Managed Postgres

A JSON API that reserves and releases limited stock, built with Hono on Bun 1.4 and Bun's built-in SQL client (`Bun.SQL`), backed by ClickHouse Managed Postgres and provisioned with `clickhousectl`. Competing requests can never reserve more units than are available, and retrying a request with the same `Idempotency-Key` returns the original reservation without taking stock twice. Postgres enforces both rules with a conditional `UPDATE`, a unique key and a single transaction.

**[Start a ClickHouse Cloud free trial with $300 in credits](https://clickhouse.com/cloud)** to run this example on ClickHouse Managed Postgres.

Read the walkthrough: [Build a stock reservation API with Hono, Bun, and ClickHouse Managed Postgres](https://clickhouse.com/resources/engineering/build-stock-reservation-api-hono-bun-postgres)

[ClickHouse Cloud](https://clickhouse.com/cloud) is a managed data platform. It runs [ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres) for transactional application data and ClickHouse for real-time analytics, managed together with one CLI, [`clickhousectl`](https://clickhouse.com/docs/concepts/features/interfaces/cli).

## Stack

| Layer | Choice |
| --- | --- |
| Framework | Hono 4.13.8 |
| Runtime | Bun 1.4.2 |
| Database | ClickHouse Managed Postgres (PostgreSQL 18) |
| Database access | `Bun.SQL` (built into Bun, no driver package) |
| Migrations | Numbered SQL files applied with `psql` |
| UI | None (JSON API) |
| Provisioning | `clickhousectl` 0.5.0 |

## How it works

```mermaid
flowchart LR
  Client[API client] -->|Bearer token| App[Hono on Bun] -->|Bun.SQL, verified TLS, app role| PG[(ClickHouse Managed Postgres)]
```

| Request | Handler | SQL |
| --- | --- | --- |
| `GET /inventory` | [`src/app.ts`](src/app.ts) | `SELECT sku, name, available FROM inventory` |
| `POST /reservations` `{ "sku", "quantity" }` | `app.post("/reservations")` | One transaction: `INSERT … ON CONFLICT DO NOTHING` into `idempotency_keys`, conditional `UPDATE inventory`, `INSERT INTO reservations` |
| `GET /reservations/:id` | `app.get("/reservations/:id")` | `SELECT … WHERE id = $1 AND client_id = $2` |
| `DELETE /reservations/:id` | `app.delete("/reservations/:id")` | One transaction: `SELECT … FOR UPDATE`, `UPDATE inventory` (+quantity), `UPDATE reservations SET status = 'released'` |

Every route needs `Authorization: Bearer <token>`. The server maps each token to a client ID (`API_KEYS_JSON`), so a client can't choose who owns a reservation, and another client's reservation returns `404`. `POST` also needs an `Idempotency-Key` header. The schema is three tables in [`sql/migrations/001_initial.sql`](sql/migrations/001_initial.sql): `inventory`, `reservations` and `idempotency_keys`.

**The no-overselling rule.** Reading the stock and then subtracting can oversell, because two requests can read the same number before either writes. Instead the check is part of the write ([`src/app.ts`](src/app.ts#L159)). Postgres locks the row, and a competing `UPDATE` re-checks `available >= quantity` against the committed value, so it changes no row once the stock is gone. A `CHECK (available >= 0)` constraint backs this up.

```ts
const changed = await tx`
  UPDATE stock_reservation.inventory SET available = available - ${quantity}
  WHERE sku = ${sku} AND available >= ${quantity} RETURNING sku
`;
if (changed.length === 0) {
  // … 404 for an unknown SKU, otherwise 409 insufficient_inventory
}
```

**The one-reservation-per-key rule.** The transaction first claims the key with `INSERT … ON CONFLICT (client_id, key) DO NOTHING` ([`src/app.ts`](src/app.ts#L138)). The primary key `(client_id, key)` makes a concurrent retry wait until the first transaction commits or rolls back. It then replays the stored response, or returns `409 idempotency_conflict` if the SKU or quantity differ. The key, the stock decrement and the reservation commit together, so a failed request leaves no key behind and can be retried. Release locks the reservation with `FOR UPDATE` and returns stock only when its status is still `active`, so a repeated `DELETE` changes nothing.

## Connect Bun.SQL to ClickHouse Managed Postgres

[`src/database.ts`](src/database.ts) is the only place the pool is created. This shortened version leaves out the CA bundle retry described after it.

```ts
// ClickHouse Managed Postgres: verify the server certificate and hostname against
// the service CA from `clickhousectl cloud postgres certs get`. Keep the URL plain
// (no sslmode or channel_binding); TLS is configured here. Everything else is plain
// Postgres.
export async function createDatabase(config: DatabaseConfig): Promise<SQL> {
  const url = validateDatabaseUrl(config.url); // rejects query parameters
  url.searchParams.set("sslmode", "verify-full");
  const ca = await Bun.file(config.caCertPath).text();

  const sql = new SQL(url, {
    max: config.maxConnections, // PG_MAX_CONNECTIONS, default 5
    idleTimeout: 30,
    maxLifetime: 1800,
    connectionTimeout: 10,
    tls: { ca, serverName: url.hostname, rejectUnauthorized: true },
  });
  await sql`SELECT 1`; // fail at startup, not on the first request
  return sql;
}
```

- **TLS:** `tls.ca` with `rejectUnauthorized: true` and `serverName` checks both the certificate chain and the hostname, the same as `sslmode=verify-full`. `DATABASE_URL` must be a plain `postgres://user:password@host:5432/postgres` URL. Don't copy the console's connection string with `channel_binding` or `sslmode` into it.
- **CA bundles:** Bun 1.4.2 can reject a CA bundle that contains two roots with the same subject. When that happens, `createDatabase` retries each certificate on its own, still with full verification. The comment in `database.ts` explains why.
- **Pool:** five connections per process by default (`PG_MAX_CONNECTIONS`, 1–20). Multiply by the number of processes before scaling out.
- **Timeouts:** the app role has `statement_timeout = 5s`, `lock_timeout = 3s` and `idle_in_transaction_session_timeout = 10s` set in [`sql/01_roles.sql`](sql/01_roles.sql), so every pooled connection gets them.

## Prerequisites

- Bun 1.4.2, `psql` 15 or later, `jq`, `openssl`, `curl`
- A ClickHouse Cloud account and an API key with permission to create services

```bash
bun install --frozen-lockfile
```

## Set up ClickHouse Managed Postgres with clickhousectl

```bash
# 1. Install the CLI and sign in (an API key is required to create services)
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl cloud auth login --api-key "$CLICKHOUSE_CLOUD_API_KEY" --api-secret "$CLICKHOUSE_CLOUD_API_SECRET"
clickhousectl cloud org list

# 2. Choose where the database runs
umask 077 && mkdir -p .deployment
export CH_ORG_ID="<your-org-id>"
export PG_REGION="us-east-1" PG_SIZE="m6gd.large"

# 3. Create ClickHouse Managed Postgres (save the one-time credentials)
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name stock-reservation \
  --provider aws --region "$PG_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none --tag project=stock-reservation \
  --json > .deployment/postgres-create.json
export PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"

# 4. Wait until it is running, then download the CA certificate
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json | jq '{state, hostname}'
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --output .deployment/postgres-ca.pem
```

Repeat the `get` command until `state` is `running`. Then point `psql` at the service as the admin user:

```bash
export PGHOST="$(clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json | jq -er '.hostname')"
export PGPORT=5432 PGDATABASE=postgres PGUSER=postgres
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
export PGSSLMODE=verify-full PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
psql -c 'select version()'
```

## Create the schema

```bash
export MIGRATOR_PASSWORD="$(openssl rand -hex 24)" APP_PASSWORD="$(openssl rand -hex 24)"
printf 'MIGRATOR_PASSWORD=%s\nAPP_PASSWORD=%s\n' "$MIGRATOR_PASSWORD" "$APP_PASSWORD" > .deployment/passwords.env

psql -X -v ON_ERROR_STOP=1 -f sql/01_roles.sql          # as postgres (admin)
export PGUSER=stock_reservation_migrator PGPASSWORD="$MIGRATOR_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -f sql/migrations/001_initial.sql
psql -X -v ON_ERROR_STOP=1 -f sql/02_grants.sql
psql -X -v ON_ERROR_STOP=1 -f sql/03_seed.sql
export PGUSER=postgres PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
```

| File | Runs as | What it does |
| --- | --- | --- |
| [`sql/01_roles.sql`](sql/01_roles.sql) | admin | Creates the schema owner `stock_reservation_owner` (no login), `stock_reservation_migrator` and `stock_reservation_app`, the `stock_reservation` schema, and the app role's timeouts. Passwords come from the environment via `\getenv`. |
| [`sql/migrations/001_initial.sql`](sql/migrations/001_initial.sql) | migrator | Creates `inventory`, `reservations` and `idempotency_keys` with their constraints. Runs once. Later changes go in new numbered files. |
| [`sql/02_grants.sql`](sql/02_grants.sql) | migrator | Gives the app role `SELECT` plus column-level `INSERT`/`UPDATE` only. No `DELETE`, `TRUNCATE` or DDL. Safe to re-run. |
| [`sql/03_seed.sql`](sql/03_seed.sql) | migrator | Adds 25 `FIELD-NOTES`, 10 `CAMP-MUG` and 5 `TRAIL-PACK`. Never resets existing stock. |

The migrator runs each file with `SET LOCAL ROLE stock_reservation_owner`, so the tables belong to the owner role rather than to a login.

## Run the app

The app connects as the least-privilege app role, never as admin:

```bash
export API_TOKEN="$(openssl rand -hex 32)"
cat > .env <<EOF
DATABASE_URL=postgres://stock_reservation_app:$APP_PASSWORD@$PGHOST:5432/postgres
PG_CA_CERT_PATH=.deployment/postgres-ca.pem
API_KEYS_JSON='{"warehouse-demo":"$API_TOKEN"}'
EOF
bun run start
```

The API listens on http://127.0.0.1:3000. Bun loads `.env` automatically. [`.env.example`](.env.example) lists every variable, including `HOST`, `PORT` and `PG_MAX_CONNECTIONS`. Each client in `API_KEYS_JSON` needs its own random token of 32 or more characters.

## Try it

Run these in a second terminal with `API_TOKEN` exported.

1. List stock. `CAMP-MUG` shows `"available": 10`.

   ```bash
   curl -sS http://127.0.0.1:3000/inventory -H "Authorization: Bearer $API_TOKEN" | jq
   ```

2. Reserve two mugs. You get `201` with `Idempotency-Replayed: false` and an `active` reservation, and inventory shows 8 mugs.

   ```bash
   curl -sS -i http://127.0.0.1:3000/reservations \
     -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
     -H 'Idempotency-Key: order-1042' --data '{"sku":"CAMP-MUG","quantity":2}'
   ```

3. Send exactly the same request again. You get the same body with `Idempotency-Replayed: true`, and inventory still shows 8. The same key with `"quantity":3` returns `409 idempotency_conflict`.
4. Release it. Copy the `id` from step 2. `DELETE` returns `"status": "released"`, inventory goes back to 10, and a second `DELETE` returns the same result without adding stock again.

   ```bash
   curl -sS -X DELETE http://127.0.0.1:3000/reservations/<id> -H "Authorization: Bearer $API_TOKEN" | jq
   ```

5. Race eight buyers for the five trail packs. Exactly five get `201` and three get `409`, and `TRAIL-PACK` ends at `0`.

   ```bash
   for i in $(seq 8); do
     curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/reservations \
       -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
       -H "Idempotency-Key: race-$i" --data '{"sku":"TRAIL-PACK","quantity":1}' &
   done | sort | uniq -c; wait
   ```

## Test

```bash
bun run test                    # typecheck + unit tests (no database)
TEST_ADMIN_DATABASE_URL="postgres://postgres:$PGPASSWORD@$PGHOST:5432/postgres" \
  bun run test:integration      # needs .env; proves no overselling and one reservation per key
```

The integration and TLS suites run against real Postgres as the app role, through two app instances with separate pools. They fail, rather than skip, when a variable is missing. They check that:

- 32 buyers competing for 9 units produce exactly 9 reservations, and remaining stock plus active reservations equals the starting stock;
- 24 simultaneous retries with one key create one reservation and replay the identical response;
- 20 concurrent releases restore stock once;
- a forced `INSERT` failure after the decrement rolls back both the stock and the key;
- clients can't read or release each other's reservations;
- the app role has no `CREATE`, `DELETE` or `TRUNCATE` privilege, and the connection uses TLS 1.2 or 1.3;
- an unrelated CA and a hostname not on the certificate are both rejected.

`TEST_ADMIN_DATABASE_URL` is used only to create and remove the suite's own `test-…` SKUs and to add a temporary constraint for the rollback tests. Use a dedicated service and run one copy at a time. If a run is killed mid-way, drop any leftover `test_reservation_*` constraint with the SQL in [`tests/fixtures/`](tests/fixtures).

## Build this with an AI coding agent

Install the ClickHouse agent skills with `clickhousectl skills --agent claude` (or your agent's name), then prompt:

```text
Build a stock reservation JSON API with Hono on Bun and Bun.SQL on ClickHouse Managed Postgres.
Provision the database with clickhousectl (postgres create, wait for running, certs get) and
connect with Bun.SQL tls { ca, serverName, rejectUnauthorized: true } and a plain URL.
Use an owner role, a migrator role and a least-privilege app role, with numbered SQL files run by psql.
Reserve stock with one transaction: claim the Idempotency-Key with INSERT ... ON CONFLICT DO NOTHING,
then UPDATE inventory SET available = available - $1 WHERE sku = $2 AND available >= $1,
then insert the reservation. Release with SELECT ... FOR UPDATE and restore stock once.
Add an integration test where 32 concurrent buyers compete for 9 units and exactly 9 succeed.
```

## Limits

- Bearer tokens from configuration stand in for real authentication, and all clients share one database login.
- Reservations stay active until released. There is no expiry, payment or restocking endpoint.
- Successful idempotency keys are kept indefinitely. A real system needs a retention policy.
- No deployment configuration. The listener binds to `127.0.0.1` by default; put any hosted deployment behind HTTPS.

## Clean up

```bash
psql -X -v ON_ERROR_STOP=1 -f sql/99_cleanup.sql     # optional if deleting the service
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json | jq '.[].name'
rm -rf .deployment .env
```

## Learn more

- [ClickHouse Managed Postgres docs](https://clickhouse.com/docs/products/managed-postgres/overview)
- [clickhousectl](https://clickhouse.com/docs/concepts/features/interfaces/cli)
- [Hono on Bun](https://hono.dev/docs/getting-started/bun)
- [Bun.SQL](https://bun.sh/docs/runtime/sql)
- [PostgreSQL: Read Committed isolation](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-READ-COMMITTED)
- Other examples: [Feature Request Board](../feature-request-board/README.md), [Workshop Booking API](../workshop-booking/README.md), [Shortwave](../shortwave/README.md)
