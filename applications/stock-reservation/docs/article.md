---
title: 'Build a stock reservation API with Hono, Bun, and ClickHouse Managed Postgres'
slug: build-stock-reservation-api-hono-bun-postgres
description: 'Build a small inventory API with Hono and Bun.SQL. Use Postgres transactions to prevent overselling, replay successful requests, and release stock safely.'
target_query: 'bun postgres'
type: howto
---

# Build a stock reservation API with Hono, Bun, and ClickHouse Managed Postgres

A shop has ten camping mugs left. Two customers each try to reserve the final
units, and one client's connection drops before it receives a response. Can it
retry without placing a second reservation? Can the other client reserve stock
that has already gone?

These questions make a small inventory API an effective introduction to
transactions. The promise is concrete: **successful reservations consume stock
once, and available stock never becomes negative.**

Let's build that API with [Hono](https://hono.dev/docs/getting-started/bun),
Bun 1.4.2, Bun's built-in SQL client, and
[ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres). The
[complete example](../README.md) includes four routes, SQL migrations, sample
inventory, and tests. Keep its README open for the full setup and cleanup commands.

## What we're building

After setup, an authenticated client reserves two mugs with one request:

```sh
curl http://127.0.0.1:3000/reservations \
  -H "Authorization: Bearer $API_TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: order-1042' \
  --data '{"sku":"CAMP-MUG","quantity":2}'
```

The API returns HTTP `201` and a reservation:

```json
{
  "id": "8a109f49-d9e2-4be7-a3c3-d3d89e371862",
  "sku": "CAMP-MUG",
  "quantity": 2,
  "status": "active",
  "created_at": "2026-09-17T12:00:00.000Z",
  "released_at": null
}
```

Your ID and timestamp will differ. `GET /inventory` now shows eight mugs.
Repeating the same successful request returns the original response and leaves
eight available. `DELETE /reservations/:id` releases those two units, and
`GET /reservations/:id` shows the current state.

There are no payments or automatic expiry. This is a bounded reservation workflow
for a trusted set of API clients, with behavior we can inspect and test.

## One application, three tables

Hono handles routing and request validation. Bun runs the server, and Bun.SQL
sends parameterized queries to Postgres over verified TLS.

```mermaid
flowchart LR
  Client[API client] --> Hono[Hono on Bun]
  Hono -->|Bun.SQL over TLS| Postgres[ClickHouse Managed Postgres]
```

The [schema](../sql/migrations/001_initial.sql) has three tables:

| Table | What it remembers |
| --- | --- |
| `inventory` | Each SKU and its available quantity |
| `reservations` | The client, SKU, quantity, and active or released state |
| `idempotency_keys` | A successful request's inputs and original response |

Postgres provides the transactions, constraints, and row locking this workflow
needs. Every decision uses authoritative application state. This app therefore
starts with standalone Managed Postgres; it has no analytical replica to operate.
For an application that also needs historical analytics, see
[Shortwave's Postgres and ClickHouse architecture](../../shortwave/README.md).

## Reserve stock with a conditional update

A separate “read stock, then subtract” sequence can oversell: two requests may
both read the same available quantity before either writes its change.

Instead, make the availability check part of the write. The important statement
has this shape, with values bound as parameters:

```sql
UPDATE stock_reservation.inventory
SET available = available - $1
WHERE sku = $2 AND available >= $1
RETURNING sku, available;
```

If no row is returned, the reservation cannot proceed. When two requests compete
for the same row, Postgres coordinates the updates and rechecks the condition
against the updated row. This follows its
[Read Committed behavior](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-READ-COMMITTED).

The application runs this update, inserts the reservation, and saves the successful
response in one transaction. A later failure rolls everything back, including
the stock decrement. A database constraint also prevents negative inventory.
The guarantee survives multiple application processes because the coordination
happens in Postgres.

## Make retries describe the same operation

The caller supplies an `Idempotency-Key`. The database scopes it to the
authenticated client, so two different clients can use `order-1042` independently.
A unique constraint coordinates concurrent requests using the same client and
key; an in-memory cache is unnecessary.

For a successful request, the API stores the requested SKU, quantity, response
status, and body with the reservation. A retry with matching inputs replays that
response. Changing the inputs under the same successful key returns `409`.
Rejected requests roll back their key, so the caller can retry after circumstances
change.

The saved response has a specific meaning. If you release a reservation and later
retry its original POST, the API still returns the original active creation
response. It is a receipt for that request. Use GET for the reservation's current
state and a new key for a new reservation.

Release has its own transaction: lock the client's reservation, check its state,
restore its stock, and mark it released. A repeat release sees the released state
and returns it without adding stock again.

## Connect Bun.SQL to Managed Postgres

Follow the [README setup](../README.md#set-up-the-example) to create Postgres
with `clickhousectl`, save its returned credentials, wait for `running`, and
download its CA certificate. Apply the visible bootstrap, migration, grant, and
seed SQL files with `psql`.

The runtime uses its own database login. The administrator creates roles; the
migrator applies schema changes. Neither privileged credential belongs in the
application's environment.

Configure Bun.SQL with a plain URL:

```dotenv
DATABASE_URL=postgres://stock_reservation_app:PASSWORD@HOST:5432/postgres
PG_CA_CERT_PATH=.deployment/postgres-ca.pem
```

Keep URL query parameters out of this example's connection string. The
[connection code](../src/database.ts) supplies the downloaded CA and checks the server
certificate and hostname explicitly. This preserves a clear, tested connection
path instead of copying options intended for a different Postgres client. See
[Bun's SQL documentation](https://bun.sh/docs/runtime/sql) for its native
parameterized-query and transaction APIs.

## Check the promise under contention

First follow the README's reserve, retry, inspect, and release requests. Then run
the integration suite against a disposable managed-service fixture. It exercises
competing reservations, simultaneous retries, rollback, and concurrent release.

The decisive check is in the database: for each SKU, **available stock plus active
reservation quantities equals the starting stock**. Counting successful HTTP
responses alone would miss a stock decrement left behind by a failed operation.
Two-client checks also confirm that one client cannot read or release another's
reservation. The [verification record](verification.md) lists the actual versions,
commands, and observed results.

The example retains successful request keys indefinitely and requires explicit
release. An expiry feature would need a database transaction that claims an
active reservation once before restoring stock, preserving the same rule as
manual release. Start from this working flow, choose the lifecycle your users
need, and extend the tests with it. Use the README's cost and cleanup instructions
when you've finished trying the service.
