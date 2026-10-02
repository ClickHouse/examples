# Incident Room

A small Phoenix LiveView application backed by ClickHouse Managed Postgres (public beta). A trusted team signs in, opens an incident, appends permanent notes and moves its status from investigating to monitoring to resolved. Monitoring can return to investigating; resolved incidents accept no further notes or transitions.

The status row and its timeline entry commit in one Ecto transaction. Browsers send an expected version; the row lock serializes writers and a stale version is rejected. Phoenix PubSub runs **after commit**. It is an ephemeral notification: reconnecting browsers load authoritative database rows rather than replay broadcasts.

This is one shared team, not a tenant isolation example. All authenticated accounts can read and update every incident. Author IDs come from the verified session, never a browser field. The newest 100 incidents and latest 200 entries per room are displayed, with stable timestamp/UUID ordering; older entries remain stored. There is no pagination or historical export UI.

## Versions and layout

Pinned and tested: Elixir 1.20.4 / Erlang OTP 28.5.0.7, Phoenix 1.8.15, LiveView 1.2.12, Ecto 3.14.2 / Ecto SQL 3.14.0, Postgrex 0.22.4, Bandit 1.12.5 and esbuild 0.28.2. Exact direct dependencies are in `mix.exs`, transitive dependencies in `mix.lock`, runtime versions in `.tool-versions`.

- `lib/incident_room/incidents.ex`: transactions, validation, locking and post-commit notifications.
- `lib/incident_room/auth.ex`: BCrypt passwords and expiring, hashed database sessions.
- `lib/incident_room_web`: authenticated HTTP routes and LiveView mounts/events.
- `priv/repo/migrations`: Ecto migration; `scripts/migrate.exs` is the separate owner-only entry point.
- `sql`: administrator role bootstrap, owner grants and optional dedicated-fixture cleanup.
- `test`: independent domain checks and opt-in real Cloud checks.

Install the pinned Elixir/OTP pair with your preferred version manager. All commands below run from this directory. Use a native Linux development environment if following the recorded acceptance setup. PostgreSQL client tools are needed for the visible role steps.

## Create a Cloud service

Authenticate `clickhousectl` using its supported private environment configuration. A service incurs charges until deleted. This example needs no analytical ClickHouse service and no high availability configuration. The verified small shape is `c6gd.large` in AWS `us-east-1`; consult current Cloud availability before choosing another shape.

```sh
mkdir -m 700 -p /tmp/incident-private
export ORG_ID=your-cloud-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" --name incident-room-demo \
  --provider aws --region us-east-1 --size c6gd.large \
  --pg-version 18 --ha-type none --json > /tmp/incident-private/create.json
# Record the returned id as SERVICE_ID; keep the full receipt private.
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
# Continue only when the state is running.
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" --output /tmp/incident-private/cloud-ca.pem
```

The create receipt contains the initial administrator password; later `get` calls do not return it. Set the returned hostname, port and database privately. Copy `.env.example` outside the repository, replace all placeholders and use an absolute CA path. Do not commit receipts, environment files, passwords or private endpoints. See the [Managed Postgres Phoenix guide](https://clickhouse.com/docs/products/managed-postgres/guides/phoenix).

`PGSSLMODE=verify-full` protects `psql`. The application explicitly supplies OTP `verify_peer`, the downloaded `cacertfile`, hostname SNI, and `pkix_verify_hostname_match_fun(:https)` through Postgrex. Setting `ssl: true` alone would not establish this verification claim.

## Bootstrap, migrate and seed

Generate different strong passwords for the migration and runtime roles. The administrator owns neither application tables nor the server process. Preserve a random `SECRET_KEY_BASE` of at least 64 bytes across restarts. Example generation inside your development environment:

```sh
openssl rand -base64 64
```

Load your private environment file with shell export enabled so the hostname, CA and origin reach Mix:

```sh
set -a
source /private/path/setup.env
set +a
```

Set `ADMIN_USER`, `ADMIN_PASSWORD`, `MIGRATION_PASSWORD` and `APP_PASSWORD` privately, then execute the following in order:

```sh
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -v migration_password="$MIGRATION_PASSWORD" \
  -v app_password="$APP_PASSWORD" -f sql/bootstrap.sql

export PGUSER=incident_migration PGPASSWORD="$MIGRATION_PASSWORD"
mix deps.get
mix run scripts/migrate.exs
# Repeating migrations is safe and reports that they are already applied.
mix run scripts/migrate.exs

# Supply these only for seeding; each must contain at least 16 bytes.
export SEED_CASEY_PASSWORD='replace-with-a-private-strong-password'
export SEED_MORGAN_PASSWORD='replace-with-a-different-private-strong-password'
mix run priv/repo/seeds.exs
mix run priv/repo/seeds.exs
psql -X -f sql/grants.sql
```

The bootstrap creates an owned `incident_room` schema. Ecto creates its history table there; no database `CREATE` privilege is required. The explicit migration script uses conventional `Ecto.Migrator.run` in the owner process; the HTTP server never migrates at startup. Seed reruns retain existing passwords/data. Seeded accounts are `casey@example.test` and `morgan@example.test`, with the supplied passwords. There is no public registration or password reset flow.

The runtime role can select users; select/insert/delete sessions; select/insert/update incidents; and select/insert entries. It cannot alter users, edit/delete timeline rows, read migration history or create tables. Cooperative row locking and state/version checks belong to the application; the shared trusted runtime role could bypass those rules if used outside this code. The migration owner can still administer all tables.

## Run and use the room

```sh
export PGUSER=incident_app PGPASSWORD="$APP_PASSWORD"
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD SEED_CASEY_PASSWORD SEED_MORGAN_PASSWORD
mix assets.build
mix phx.server
```

Open `http://127.0.0.1:4000`, sign in, open an incident and add a note. Sign in as the second account in another browser to see committed changes. The default listener is loopback. `APP_ORIGIN` must be a valid HTTP(S) origin and controls Phoenix's origin allowlist. If deploying, configure a deliberate proxy/listener and HTTPS origin. Secure cookies are enabled for an HTTPS origin; HTTP loopback development uses HttpOnly, SameSite=Lax encrypted/signed cookies. HTTP CSRF protection and WebSocket origin checks remain enabled.

Sessions contain a random token whose SHA-256 hash and eight-hour expiry live in Postgres. Every LiveView mount, write operation and received update validates the session. Sign-out removes the session and disconnects its sockets. Keeping `SECRET_KEY_BASE` stable lets surviving sessions work after a process restart. Seed/admin credentials are not needed by the server.

Titles allow 1–160 Unicode codepoints and notes 1–2,000 codepoints before trimming, reject whitespace-only input and embedded NUL. This matches PostgreSQL's character count; browser `maxlength` remains a convenience rather than the authority. HTTP bodies are capped at 16 KiB. Successful note submission clears its form; incoming updates preserve another responder's unsaved draft.

## Validate

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix assets.build
mix test
```

The default suite runs three domain checks without a database. CI uses only these checks and a build; it has no Cloud credentials. For the dedicated seeded Cloud fixture, set the runtime connection variables and additionally supply `MIGRATION_PASSWORD` to the **test process only**:

```sh
CLOUD_TEST=true mix test --include cloud
```

Cloud tests add rows to the dedicated fixture. They check TLS positive/negative controls, restricted permissions, concurrent expected-version updates, author/session authority, bounded Unicode/timeline behavior and actual blocked sessions. A temporary owner-only trigger, scoped to one test incident, forces the timeline insert to fail after the status update; the test verifies rollback and no broadcast, then removes the trigger. Never run this fault-injection suite against production.

For actual two-browser delivery/reconnect/restart checks, install Playwright in an isolated native environment and provide the seed passwords to the harness:

```sh
python3 -m venv /tmp/incident-browser-venv
/tmp/incident-browser-venv/bin/pip install playwright==1.58.0
/tmp/incident-browser-venv/bin/playwright install --with-deps chromium
export SEED_CASEY_PASSWORD='your-seeded-password'
export SEED_MORGAN_PASSWORD='your-other-seeded-password'
/tmp/incident-browser-venv/bin/python scripts/browser_acceptance.py
```

The harness starts an HTTP process containing only runtime credentials, uses separate Chromium contexts, counts actual received WebSocket frames, deliberately misses a broadcast, reconnects, and replaces the server process. A screenshot and private server log go to `EVIDENCE_DIR` (default `/tmp/incident-browser-evidence`). Keep logs outside Git.

## Cleanup and limits

Stop the application before cleanup. On a dedicated fixture only, the administrator can remove this schema and its roles after restoring the administrator credentials from your private setup file:

```sh
set -a
source /private/path/setup.env
set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/cleanup.sql
```

 This is destructive and not part of normal startup. It was used to verify clean bootstrap followed by repeated migration/seeding. Delete your own Cloud service when finished and verify its absence:

```sh
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

PubSub is local process coordination, not a durable queue or distributed-delivery guarantee. There is no monitoring ingestion, incident integration, email, escalation, tenant policy, account administration, expiry sweep, timeline pagination or performance claim. Provisioning here uses no HA. A larger deployment needs deliberate operational and authorization choices.

Primary references: [LiveView security model](https://phoenix-live-view.hexdocs.pm/security-model.html), [Ecto transactions](https://ecto.hexdocs.pm/Ecto.Repo.html#c:transact/2), [Ecto migrations](https://ecto-sql.hexdocs.pm/Ecto.Migration.html), [Postgrex connection options](https://postgrex.hexdocs.pm/Postgrex.html), [OTP 28 TLS options](https://www.erlang.org/docs/28/apps/ssl/ssl.html).
