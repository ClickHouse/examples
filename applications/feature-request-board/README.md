# Feature Request Board

[Read the accompanying article](https://clickhouse.com/resources/engineering/build-feature-request-board-nextjs-prisma-postgres).

A small feature request board built with **Next.js, Prisma ORM, node-postgres,
Clerk, and [ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres)**.
Submit ideas, vote once per request, and filter by status. Authors can edit or
delete their requests; designated maintainers can change their status.

**[Sign up for ClickHouse Cloud with $300 in trial credits](https://clickhouse.com/cloud).**

## What runs where

[ClickHouse Cloud](https://clickhouse.com/cloud) is the platform that offers both
managed ClickHouse for analytics and
[ClickHouse Managed Postgres](https://clickhouse.com/cloud/postgres) for
transactional workloads. ClickHouse Managed Postgres provides PostgreSQL with
local NVMe storage and managed database operations. These services are connected
through a unified data stack: ClickPipes can replicate Postgres data into
ClickHouse, and `pg_clickhouse` can query ClickHouse from Postgres.

This example uses Managed Postgres as an ordinary PostgreSQL database. All
application records, relationships, and vote counts stay there. No ClickHouse
analytical service, ClickPipe, or extension is needed. See
[Shortwave](../shortwave/README.md) for a complete application with explicit
ClickHouse and ClickPipes setup.

```mermaid
flowchart LR
  Browser --> App[Next.js on Node.js]
  Browser --> Clerk[Clerk sign-in]
  App --> Clerk
  App --> Prisma[Prisma ORM + node-postgres]
  Prisma -->|verified TLS| PG[ClickHouse Managed Postgres]
```

The board and request details are public. Sign-in is required for every write.
Names submitted with requests are public display-name snapshots; emails and
Clerk session tokens are not stored in Postgres.

The important rules live in [the application service](src/lib/board.ts) and
[the SQL migration](prisma/migrations/20260917000000_initial/migration.sql):

- A composite primary key on `(request_id, user_id)` enforces one vote per user,
  including competing requests. Adding and removing votes are separate,
  repeatable operations. Counts are derived from the rows.
- Every edit/delete includes the verified author's ID in its database predicate.
  Hiding buttons is only a convenience; the server checks authorization.
- Status changes require an exact Clerk user ID in `MAINTAINER_USER_IDS`.
- A foreign key removes a request's votes when the request is deleted.

## Run your own board

Run the following commands from this application directory in Bash or zsh on
Linux or macOS. Each infrastructure operation is shown explicitly. Use a
dedicated development service; setup changes its schema permissions.

### 1. Install prerequisites and dependencies

You need Node.js **24.21.0**, npm, Git, `psql` 16 or later, `jq`, OpenSSL,
a ClickHouse Cloud account with Managed Postgres available, and a
[Clerk application](https://dashboard.clerk.com/).

On Ubuntu/Debian, install the system tools:

```sh
sudo apt-get update
sudo apt-get install -y git curl postgresql-client jq openssl
```

On macOS with Homebrew:

```sh
brew install libpq jq openssl@3
export PATH="$(brew --prefix libpq)/bin:$(brew --prefix openssl@3)/bin:$PATH"
```

Install [Node.js](https://nodejs.org/en/download) in the environment where you
will build and run the app. Then install the Cloud CLI and clone the example:

```sh
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
clickhousectl --version
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/feature-request-board
npm ci --ignore-scripts
npm run db:generate
```

Dependencies are pinned in `package-lock.json`. Installation does not need
database credentials. Prisma generation is an explicit step.

This example selects Prisma ORM 7.10.0 with its PostgreSQL driver adapter.
The two overrides in `package.json` pin patched Prisma tooling dependencies
(`deepmerge-ts` and `mysql2`); re-evaluate them when upgrading Prisma.

For an isolated OrbStack development environment, create a machine before
installing Node or dependencies:

```sh
orbctl create ubuntu:noble feature-board-dev --isolated
orbctl run -m feature-board-dev -w /home/$USER bash
```

Run the Linux setup inside that machine. `--isolated` disables host file sharing
and system integration; use explicit file copies if needed. The example does
not require access to your laptop's filesystem or SSH agent.

### 2. Sign in to ClickHouse Cloud and create Postgres

Create an Admin API key in your Cloud organization following the
[Cloud API guide](https://clickhouse.com/docs/cloud/manage/openapi), then use
interactive login so credentials do not become shell-history arguments:

```sh
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
```

Cloud resource creation requires API-key authentication. Save private setup
inputs and receipts in the ignored `.deployment` directory:

```sh
umask 077
mkdir -p .deployment
```

Create `.deployment/resources.env` in an editor, substituting your organization
ID and an available region/size:

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
CLOUD_REGION=eu-west-1
PG_SIZE=m6gd.large
```

This example uses one non-HA Postgres 18 service. Review current
[pricing](https://clickhouse.com/pricing) and availability before creation.
Postgres compute/storage and Clerk usage may incur charges; stopping the Node
process does not stop database billing.

```sh
source .deployment/resources.env
clickhousectl cloud postgres create \
  --org-id "$CH_ORG_ID" --name feature-request-board-example \
  --provider aws --region "$CLOUD_REGION" --size "$PG_SIZE" \
  --pg-version 18 --ha-type none --json \
  > .deployment/postgres-create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/postgres-create.json)"
```

Save `PG_SERVICE_ID` in `.deployment/resources.env`. The create receipt contains
the initial password, returned once: keep it private and do not overwrite it.
If creation is interrupted, inspect `clickhousectl cloud postgres list --json`
before retrying so you do not create a duplicate service.

Check until `state` is `running`; repeat inspection, not creation:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --output .deployment/postgres-ca.pem
```

Add the returned direct endpoint to `.deployment/resources.env`:

```dotenv
PGHOST=YOUR_POSTGRES_HOSTNAME
PGPORT=5432
PGDATABASE=postgres
PGADMIN=postgres
```

Use the service's actual connection details and direct endpoint for migrations.
Do not substitute a transaction-pooler endpoint.

### 3. Create separate migration and application roles

Generate passwords once. Keep the file on retries; recreating passwords does
not change existing database roles.

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
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/001_roles.sql
unset PGPASSWORD
```

[001_roles.sql](sql/001_roles.sql) reads the passwords from the environment,
creates `feature_board_migration` and `feature_board_app`, and creates the
`feature_board` schema. The runtime user cannot own or change the schema.
Passwords stay out of the SQL files and command arguments.

### 4. Apply the checked-in Prisma migration and seed data

The application uses Prisma ORM 7 with its node-postgres adapter. The schema is
in [schema.prisma](prisma/schema.prisma); the actual DDL is the checked-in
[migration.sql](prisma/migrations/20260917000000_initial/migration.sql).
`migrate deploy` applies pending migrations and records their history. No
shadow database or `db push` is needed to run this example.

Create a private migration environment. The generated hex passwords and the
example directory path are URL-safe; percent-encode special characters if you
supply your own credentials or a certificate path containing spaces.

```sh
cat > .deployment/migration.env <<MIGRATION
MIGRATION_DATABASE_URL='postgresql://feature_board_migration:${PG_MIGRATION_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}?schema=feature_board&sslmode=require&sslaccept=strict&sslcert=${PWD}/.deployment/postgres-ca.pem'
MIGRATION
```

Prisma's migration connector uses `sslcert` with strict certificate validation;
the runtime below uses node-postgres's explicit TLS object. Run the migration
in a subshell so its credentials are not exported to the app process:

```sh
(
  set -a
  source .deployment/migration.env
  set +a
  npm run db:migrate
)
export PGPASSWORD="$PG_MIGRATION_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -U feature_board_migration -f sql/002_grants.sql
psql -X -v ON_ERROR_STOP=1 -U feature_board_migration -f sql/003_seed.sql
unset PGPASSWORD PG_MIGRATION_PASSWORD PG_APP_PASSWORD
```

The grants allow the runtime role to access application rows, but not Prisma's
migration history. The seed inserts four requests and six votes with stable
IDs; running it again does not duplicate them. Demo authors are labels, not
Clerk accounts, so they cannot sign in or own subsequent requests.

For later schema changes, create and review a new migration in a disposable
development database, commit its SQL, and apply it with `migrate deploy`.
Never edit a migration that has already been applied. Review runtime grants
when adding tables or columns; future objects are not granted automatically.

### 5. Configure Clerk and runtime credentials

Use development keys for local testing. In Clerk, enable the sign-in methods
you want and configure your deployed domain before using production keys.
Restrict signup to your intended users for a private trial deployment.

```sh
cp .env.example .env
```

Edit `.env` with the runtime role's connection and Clerk keys:

```dotenv
DATABASE_URL="postgresql://feature_board_app:YOUR_APP_PASSWORD@YOUR_POSTGRES_HOSTNAME:5432/postgres"
DATABASE_CA_PATH=".deployment/postgres-ca.pem"
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY="pk_test_YOUR_KEY"
CLERK_SECRET_KEY="sk_test_YOUR_KEY"
NEXT_PUBLIC_CLERK_SIGN_IN_URL="/sign-in"
NEXT_PUBLIC_CLERK_SIGN_UP_URL="/sign-up"
MAINTAINER_USER_IDS="user_YOUR_MAINTAINER_ID"
```

Copy the maintainer's exact user ID from the Clerk dashboard after signing up.
Separate multiple IDs with commas. An empty value means nobody can change
status. Being an author does not confer maintainer permissions.

Use a plain runtime URL with **no query parameters**. The
[connection configuration](src/lib/database-config.ts) sets the CA,
`rejectUnauthorized: true`, connection timeout and a five-connection pool.
The Prisma adapter selects `feature_board`. URL TLS parameters can overwrite
the node-postgres TLS object, so this example rejects them. Never use
`rejectUnauthorized: false` or `NODE_TLS_REJECT_UNAUTHORIZED=0`.

Keep `.env`, `.deployment/`, Cloud management keys and migration credentials
out of Git. Give a deployed app only the runtime environment and CA file.

### 6. Start the application

```sh
npm run dev
```

Open [localhost:3000](http://localhost:3000). Expect four seeded requests with
statuses Open, Planned, In progress, and Shipped. Sign in, submit a request,
open its detail page, and vote. Refreshing preserves your request and vote.

For a production Node process:

```sh
npm run build
npm start
```

Build with the same Clerk publishable key that will be used at runtime; Next.js
embeds `NEXT_PUBLIC_` values into the browser bundle. Deploy on a Node-capable
host with access to the Postgres endpoint, a readable CA file, production Clerk
keys and HTTPS. Use a process supervisor and reverse proxy for unattended
operation. This is a Node server, not a static export or an edge-runtime app.

## Check the important behavior

```sh
npm test
npm run typecheck
npm run build
```

The integration suite writes temporary requests to a configured test database
and removes its own rows. Use this dedicated example service, never a
production application database:

```sh
npm run test:integration
```

It checks competing/repeated votes, ownership, status permissions, cascading
deletes and runtime database privileges. See [tests](tests/) for exact cases.

Also check the UI with separate browser profiles:

1. As user A, create and edit a request, then vote from two tabs. Expect one vote.
2. As user B, vote on A's request. Expect two votes; B must not edit or delete it.
3. As a maintainer, change status and verify the corresponding board filter.
4. As A, delete the request. Its votes must disappear with it.
5. Signed out, read the board and detail pages. All writes require sign-in.

## Scope and operations

This is one public board, with plain-text content and current vote totals.
There are no teams, notifications, rich text, audit log, moderation queue,
anti-abuse quota or per-tenant isolation. Put signup restrictions and appropriate
rate limits in place before exposing writes to a broad audience. Database
permissions constrain the app login; per-person authorization is enforced by
the server, not by PostgreSQL row-level security.

Clerk account deletion does not automatically erase historical requests or
votes. Add an explicit retention/deletion policy and webhook workflow if your
product needs one. Changes to a Clerk display name do not rewrite old snapshots.

If a connection fails, check service readiness, direct hostname/port, password,
and the downloaded CA. Don't weaken TLS verification to clear an error. If
Prisma reports migration drift or a failed migration, inspect its migration
history and the SQL before applying further changes.

## Cleanup

Stop the Node process first. To remove this example's schema, records and roles
while retaining the dedicated service, run the destructive SQL explicitly:

```sh
source .deployment/resources.env
export PGHOST PGPORT PGDATABASE
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/postgres-ca.pem"
export PGPASSWORD="$(jq -er '.password' .deployment/postgres-create.json)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/004_cleanup.sql
unset PGPASSWORD
```

To stop Cloud charges, delete the dedicated service after checking its ID and
name. This permanently removes the database and its contents:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
```

Remove any dedicated Clerk test application/users and local credential files
when no longer needed. If you used OrbStack, stop the VM with
`orbctl stop feature-board-dev`; delete it only when its source and artifacts
have been saved elsewhere.
