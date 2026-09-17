# Stock Reservation API

Reserve and release limited inventory with **Hono**, **Bun 1.4.2**, and
**Bun.SQL**, backed by [ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres).
Competing requests cannot reserve more units than are available. Retrying a
successful request with its original idempotency key returns the original
reservation without consuming stock again.

Read the walkthrough: [Build a stock reservation API with Hono, Bun, and ClickHouse Managed Postgres](https://clickhouse.com/resources/engineering/build-stock-reservation-api-hono-bun-postgres).

The example contains four authenticated routes, three application tables, seed
data, explicit SQL setup, and tests. It is an API for a small, trusted set of
clients; payments, expiring reservations, and a browser interface are outside its
scope. See [Verify changes](#verify-changes) for the test commands.

**[Create a ClickHouse Cloud account and start a free 30-day trial with $300 in credits](https://clickhouse.com/cloud).**

## How it works

```mermaid
flowchart LR
  Client[Authenticated API client] --> App[Hono on Bun]
  App -->|Bun.SQL: verified TLS| PG[ClickHouse Managed Postgres]
  PG --> Inventory[Inventory]
  PG --> Reservations[Reservations]
  PG --> Keys[Successful idempotency responses]
```

All stock changes happen in Postgres transactions. A conditional inventory
update rejects a reservation when too few units remain. The reservation and its
successful response commit with that update. A unique constraint coordinates
requests that use the same client identity and idempotency key, including across
different application processes. Releasing a reservation restores its quantity
once, even when release requests arrive together.

| Route | Purpose | Success |
| --- | --- | --- |
| `GET /inventory` | List the shared inventory | `200` |
| `POST /reservations` | Reserve `{ "sku": "CAMP-MUG", "quantity": 2 }` | `201` |
| `GET /reservations/:id` | Read your reservation's current state | `200` |
| `DELETE /reservations/:id` | Release your reservation | `200` |

Every route requires `Authorization: Bearer <token>`. Creation also requires
`Idempotency-Key`. Client identity comes from the server's token configuration;
clients cannot nominate a reservation owner. Another client's reservation is
reported as `404` on both read and release.

This application uses standalone Postgres. There is no analytical workload or
ClickPipe to provision. [Shortwave](../shortwave) demonstrates the larger
Postgres, ClickHouse, and ClickPipes architecture.

## Set up the example

The instructions use Bash, a [ClickHouse Cloud account](https://clickhouse.com/cloud)
with Managed Postgres access, Git, `curl`, `jq`, OpenSSL, and `psql` 15 or later.
Run Bun and application dependencies in a Linux development environment.
Maintainers on macOS use the
[isolated OrbStack machines](https://docs.orbstack.dev/machines/isolated); install
no Node.js or Bun packages on the host.

### 1. Get the source and install pinned dependencies

```sh
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/stock-reservation
```

Inside your Linux environment, install the OS tools and Bun:

```sh
sudo apt-get update
sudo apt-get install -y ca-certificates curl git unzip postgresql-client jq openssl
curl -fsSL https://bun.sh/install -o /tmp/bun-install.sh
less /tmp/bun-install.sh
bash /tmp/bun-install.sh bun-v1.4.2
export PATH="$HOME/.bun/bin:$PATH"
bun --version
bun install --frozen-lockfile --ignore-scripts
```

The version output must be `1.4.2`. The lockfile pins the dependencies; the
application uses Bun's built-in SQL client and needs no separate Postgres driver.
The [Bun installation guide](https://bun.sh/docs/installation) explains the
versioned installer. Run subsequent application commands from this directory.

### 2. Sign in and save the provisioning inputs

Install [clickhousectl](https://clickhouse.com/docs/interfaces/cli) on the machine
you use to manage Cloud resources. For the isolated maintainer workflow, this is
the host; Cloud management credentials stay outside the VM.

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
```

Creation requires an Admin API key. Create one using the
[Cloud API instructions](https://clickhouse.com/docs/cloud/manage/openapi) and
enter it at the interactive prompt; OAuth authentication is read-only for these
operations. Keep the CLI credential store private.

Create a private directory for inputs, returned credentials, and command receipts:

```sh
umask 077
mkdir -p .deployment
```

In an editor, create `.deployment/resources.env` with your own values:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
DEPLOYMENT_NAME=stock-reservation-example
CLOUD_REGION=YOUR_AVAILABLE_AWS_REGION
PG_SIZE=YOUR_AVAILABLE_POSTGRES_SIZE
```

Choose a supported region and instance size in your Cloud organization. Review
the [Managed Postgres pricing](https://clickhouse.com/pricing) before creation.
This example requests one Postgres 18 service with `--ha-type none`; running it
incurs database charges until you delete it. Storage, backups, network usage, and
a future application host may add costs. Stopping Bun or the VM does not stop
the database service.

```sh
source .deployment/resources.env
```

### 3. Create Managed Postgres and wait for readiness

Run creation once and preserve the private response, which contains the initial
administrator password:

```sh
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name "$DEPLOYMENT_NAME" \
  --provider aws --region "$CLOUD_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none \
  --tag project=stock-reservation --tag environment=development --json \
  > .deployment/postgres-create.json

PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
printf 'PG_SERVICE_ID=%s\n' "$PG_SERVICE_ID" >> .deployment/resources.env
```

Inspect the service until `state` is `running`. Repeat **get**, not **create**:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --json > .deployment/postgres-status.json
jq '{id, state, hostname, username, postgresVersion, size}' \
  .deployment/postgres-status.json
```

If creation failed or the terminal disconnected, first run
`clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json` and reconcile the
service against the saved receipt. A missing local response does not prove that
creation failed. Do not create another service just to recover a password.

Download the service CA as a PEM file:

```sh
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --output .deployment/postgres-ca.pem
```

Use `--output` explicitly. Redirecting JSON-mode certificate output to a `.pem`
file produces an unusable certificate file.

Record `PGHOST` and `PGADMIN` from the service's `hostname` and `username`, plus
its direct port and database, in `.deployment/resources.env`:

```dotenv
PGHOST=YOUR_POSTGRES_HOSTNAME
PGPORT=5432
PGDATABASE=postgres
PGADMIN=YOUR_SERVICE_ADMIN_USERNAME
```

Use the direct Postgres endpoint for this example. Match the connection details
returned for your service rather than copying a hostname from another deployment.
The recorded test setup uses the direct port `5432` and database `postgres`.
For an isolated VM, transfer only the source files, CA, and credentials needed
for the current step into its own filesystem. Keep Cloud API credentials on the
host and administrator credentials separate from the runtime configuration.

### 4. Create roles, apply the schema, and seed inventory

Generate passwords once. Keep this file on retries; do not regenerate a password
file for roles that already exist:

```sh
cat > .deployment/passwords.env <<PASSWORDS
PG_MIGRATION_PASSWORD=Aa1_$(openssl rand -hex 30)
PG_APP_PASSWORD=Aa1_$(openssl rand -hex 30)
PASSWORDS
source .deployment/resources.env
source .deployment/passwords.env
export PGHOST PGPORT PGDATABASE PG_MIGRATION_PASSWORD PG_APP_PASSWORD
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
```

Bootstrap reads the passwords from the environment using `psql`'s `\getenv` and
quotes them as SQL values. They do not appear in command arguments:

```sh
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/bootstrap.sql
```

The bootstrap creates a non-login schema owner, `stock_reservation_owner`, and
separate `stock_reservation_migrator` and `stock_reservation_app` logins. The
migrator can assume the owner role to apply SQL. The application receives only
the grants it needs to serve requests.

Switch to the migration login and apply the named files in order:

```sh
export PGPASSWORD="$PG_MIGRATION_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -U stock_reservation_migrator \
  -f sql/migrations/001_initial.sql
psql -X -v ON_ERROR_STOP=1 -U stock_reservation_migrator -f sql/grants.sql
psql -X -v ON_ERROR_STOP=1 -U stock_reservation_migrator -f sql/seed.sql
unset PGPASSWORD
```

| SQL file | Responsibility |
| --- | --- |
| [bootstrap.sql](sql/bootstrap.sql) | Roles and schema ownership |
| [001_initial.sql](sql/migrations/001_initial.sql) | Inventory, reservations, idempotency records, constraints, and indexes |
| [grants.sql](sql/grants.sql) | Runtime privileges |
| [seed.sql](sql/seed.sql) | Three sample products |
| [cleanup.sql](sql/cleanup.sql) | Explicit removal of this example's database objects |

Bootstrap and the initial migration run once and fail if their objects already
exist. Each is transactional, so an error rolls that file back. Keep a private
record of successfully applied filenames and the repository revision, and resume
at the next unapplied file. Grants can be reapplied; seeding inserts missing SKUs
without resetting existing stock. Apply only reviewed, named migrations when
upgrading; never execute an entire SQL directory, which also contains destructive
cleanup. Fresh seed data starts with 25 `FIELD-NOTES`, 10 `CAMP-MUG`, and 5
`TRAIL-PACK` units.

### 5. Configure and start the API

Generate an API token and a runtime-only environment file:

```sh
API_TOKEN="$(openssl rand -hex 32)"
cat > .deployment/app.env <<RUNTIME
DATABASE_URL=postgres://stock_reservation_app:${PG_APP_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}
PG_CA_CERT_PATH=.deployment/postgres-ca.pem
API_KEYS_JSON='{"warehouse-demo":"${API_TOKEN}"}'
HOST=127.0.0.1
PORT=3000
PG_MAX_CONNECTIONS=5
RUNTIME
unset PG_MIGRATION_PASSWORD PG_APP_PASSWORD
```

The generated password uses URL-safe characters. If supplying your own password,
percent-encode it as a URL component. **Use a plain Postgres URL with no query
string.** The application supplies TLS options explicitly with the downloaded
CA, server hostname, and certificate verification. Do not append `sslmode` or
`channel_binding`, and do not disable verification to resolve a connection error.
See [the connection implementation](src/database.ts) and
[Bun's SQL connection options](https://bun.sh/docs/runtime/sql#connection-options).

The connection factory enforces `verify-full` internally. With Bun 1.4.2, a
provider bundle containing multiple roots with the same subject can produce
`CERT_SIGNATURE_FAILURE`. The factory first tries the complete bundle; only for
that error does it try its individual certificates. Every attempt verifies the
certificate and hostname against a CA you supplied. It establishes a connection
before starting the server and closes failed pools. If a single anchor is selected,
it stays in use for that process; refresh the downloaded bundle and restart the
application after a CA rotation.

`API_KEYS_JSON` maps a stable client identity to a unique token of at least 32
characters. Keep client IDs stable when rotating tokens so existing reservations
and idempotency records still belong to the same client. A second client needs
its own ID and token. Restart the app after changing this configuration. These
are server-to-server credentials, not browser keys.
See [.env.example](.env.example) for the complete runtime configuration.

Inside Linux, start the application with this explicit environment file:

```sh
bun --env-file=.deployment/app.env run start
```

Use a separate terminal in the same Linux environment for the following
requests. Set `API_TOKEN` to the generated value from your private file, or load
it without displaying it:

```sh
source .deployment/app.env
API_TOKEN="$(printf '%s' "$API_KEYS_JSON" | jq -er '."warehouse-demo"')"
BASE_URL=http://127.0.0.1:3000
```

## Try the complete flow

### Check the stock and reserve two mugs

```sh
curl --fail-with-body -sS "$BASE_URL/inventory" \
  -H "Authorization: Bearer $API_TOKEN" | jq
```

The initial response contains three products. The `CAMP-MUG` entry has
`"available": 10`. Create a reservation and save its response:

```sh
curl --fail-with-body -sS -D .deployment/reservation-headers.txt \
  "$BASE_URL/reservations" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: first-mug-order' \
  --data '{"sku":"CAMP-MUG","quantity":2}' \
  > .deployment/reservation.json
jq . .deployment/reservation.json
RESERVATION_ID="$(jq -er '.id' .deployment/reservation.json)"
```

Expected status: `201`, with `Idempotency-Replayed: false`. The body has this
shape; your UUID and timestamps differ:

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

Inventory now shows eight mugs. Repeat the creation command with the same key
and body: it returns `201`, `Idempotency-Replayed: true`, and the original response,
and inventory stays at eight. Using that successful key with a different quantity
returns `409` with error code `idempotency_conflict`.

### Read and release the reservation

```sh
curl --fail-with-body -sS "$BASE_URL/reservations/$RESERVATION_ID" \
  -H "Authorization: Bearer $API_TOKEN" | jq
curl --fail-with-body -sS -X DELETE \
  "$BASE_URL/reservations/$RESERVATION_ID" \
  -H "Authorization: Bearer $API_TOKEN" | jq
```

Release returns `200`, `"status": "released"`, and a non-null `released_at`.
Repeating DELETE returns the released reservation without adding more inventory.
The mug count returns to ten.

Replaying the original POST after release still returns the original **active**
creation response. That response is a receipt for the earlier successful request,
not a fresh read. GET returns the current **released** state. Start a new
reservation with a new idempotency key.

### Exercise a failure

```sh
curl -sS -i "$BASE_URL/reservations" \
  -H "Authorization: Bearer $API_TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Idempotency-Key: too-many-mugs' \
  --data '{"sku":"CAMP-MUG","quantity":11}'
```

With ten mugs available, this returns `409`:

```json
{"error":{"code":"insufficient_inventory","message":"There is not enough inventory for this reservation."}}
```

Inventory remains ten. Rejected requests do
not consume an idempotency key. You can retry a failed request later after stock
becomes available, or change its payload. Only successful creation responses are
retained for replay.

Missing or invalid credentials return `401`. Creation accepts only `sku` and
`quantity`: the SKU must begin with an ASCII letter or digit and contain 1–64
letters, digits, underscores, or hyphens; quantity must be an integer from 1 to
1,000. The idempotency key begins with a letter or digit and permits 1–128 letters,
digits, dots, underscores, colons, or hyphens. Invalid bodies are rejected before
a transaction begins. JSON requests have a 4 KiB limit; the server also rejects
bodies above its 64 KiB transport cap, which may return Bun's own `413` response.
A valid second client can see shared inventory but gets `404` when reading or
releasing the first client's reservation.

## Verify changes

Run these checks inside the isolated Linux environment:

```sh
bun run typecheck
bun run test:unit
```

The integration suite exercises the live Postgres transaction path, including
competing requests, duplicate keys, rollback, release retries, two-client
ownership, and TLS failures. Use a dedicated example service. The suite creates
and deletes its own uniquely named fixtures and briefly changes a table
constraint to force a rollback; do not run it alongside real reservations.

Copy the runtime configuration to a separate private test file:

```sh
cp .deployment/app.env .deployment/test.env
```

In an editor, add `TEST_ADMIN_DATABASE_URL` with the fixture administrator's plain
Postgres URL. Percent-encode the username and password components, omit query
parameters, and use the same service, port, and database as `DATABASE_URL`:

```dotenv
TEST_ADMIN_DATABASE_URL=postgres://YOUR_ADMIN:YOUR_ENCODED_PASSWORD@YOUR_POSTGRES_HOSTNAME:5432/postgres
```

This privileged URL belongs only in the test file, never in `app.env`. Run the
suite explicitly:

```sh
bun --env-file=.deployment/test.env run test:integration
```

Missing test credentials fail the run rather than skipping database checks. See
[tests/README.md](tests/README.md) for fixture permissions, scope, and cleanup.

The important accounting check is that available stock plus active reservation
quantities remains equal to the starting stock for each SKU. HTTP responses
alone cannot establish that invariant. A successful database connection alone
does not establish concurrency correctness.

## Scope and operating limits

- Inventory is shared; reservations belong to one configured client. Authorization
  is enforced in the application. The runtime database login is shared and is
  not a separate database tenant boundary.
- Reservations remain active until explicitly released. There is no payment
  confirmation, automatic expiry, restocking endpoint, or background worker.
- Successful idempotency records are retained indefinitely. A retention policy
  must define how long old request keys remain safe to replay before deleting
  them. A new request needs a new key.
- Each process defaults to five database connections, configurable from one to
  twenty with `PG_MAX_CONNECTIONS`; multiply that limit by the number of replicas
  before scaling. The runtime role has a three-second lock timeout and a
  five-second statement timeout. This example is not an application capacity
  benchmark.
- The default listener is local. For a hosted deployment, run Bun under a process
  supervisor, inject only runtime secrets, and place it behind HTTPS with request
  limits and appropriate network access. Do not expose the development HTTP
  listener or put API tokens in client-side code. A hosted platform deployment is
  a separate validation step from the recorded Linux development run.

## Troubleshooting and cleanup

For a TLS error, check that the CA file is PEM, the hostname matches this service,
and the runtime file contains the plain URL. For authentication errors, distinguish
the Cloud API key, database administrator, migrator, application database password,
and HTTP API token; each has a different purpose. For lock timeouts, retry a
reservation using its same idempotency key because a lost response may have
followed a successful commit.

If you lost the database administrator password, reset it for the recorded
service instead of recreating the database:

```sh
clickhousectl cloud postgres reset-password "$PG_SERVICE_ID" \
  --org-id "$CH_ORG_ID" --generate --json \
  > .deployment/postgres-password-reset.json
```

Store the returned password privately and use it for the admin connection. This
does not rotate the application's separately created role password.

Stop the app with Ctrl-C. To remove only this example from a database you intend
to keep, inspect [cleanup.sql](sql/cleanup.sql), reconnect as its administrator,
and run it explicitly:

```sh
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/cleanup.sql
unset PGPASSWORD
```

Use your reset password instead if it has changed. The cleanup removes this
example's data and roles; it is destructive. It does not delete or stop the Cloud
service.

For a service created exclusively for this example, delete the service itself
when finished. Check the ID against the receipt before deleting:

```sh
source .deployment/resources.env
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Deletion removes the service and its data. Confirm that the recorded ID is absent
from the service list. Preserve receipts until the outcome is clear, then remove
unneeded private credential files and the dedicated development VM. Never delete
a shared service to clean up this example.
