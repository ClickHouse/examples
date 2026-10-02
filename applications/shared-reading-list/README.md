# Shared reading list

Save useful links, add notes and tags, and search a shared collection with
SvelteKit, Drizzle ORM, Postgres.js and Better Auth, backed by
[ClickHouse Managed Postgres (public beta)](https://clickhouse.com/cloud/postgres).
All readers sign in. Only the person who saved a link can edit or delete it.

The example has two application screens: the collection, with search and a save
form, and a link detail screen, with editing for its owner. Authentication is a
separate screen. The app stores submitted text; it does not fetch URLs, scrape
pages or generate embeddings.

[ClickHouse Cloud](https://clickhouse.com/cloud) is the managed data platform.
This application uses its transactional Postgres service; the collection,
accounts and sessions live in Postgres. See [Shortwave](../shortwave) for an
application with an additional ClickHouse analytical database and ClickPipes.

```mermaid
flowchart LR
  Browser --> App[SvelteKit on Node.js]
  App --> Auth[Better Auth]
  Auth --> ORM[Drizzle + Postgres.js]
  App --> ORM
  ORM -->|Verified TLS| PG[ClickHouse Managed Postgres]
```

## Rules worth reading

- The server obtains the current user from Better Auth's database session.
  It never accepts an owner ID from form input. All collection reads require
  sign-in; signed-in people share the same collection.
- Every update and delete includes both the link ID and authenticated owner ID.
  A version predicate also rejects stale or competing edits. Refresh to see the
  current value after a conflict; the app does not merge edits.
- A unique `(owner_id, url)` index prevents a person saving the same normalized
  URL twice, including concurrent saves. Other readers can save their own copy.
- A generated `tsvector` covers title and notes. GIN indexes support full-text
  search and exact tag filtering. Both filters can be combined. Search uses
  English word normalization, not arbitrary substring matching. The URL is not
  part of the searchable document.
- Tags are lowercase, unique per link, and limited to eight short labels.
  Updates replace the complete tag array atomically with the other link fields.
- Better Auth stores users, password hashes, accounts and sessions in Postgres.
  Session cookie caching is disabled, so each request checks the durable session.

Read [library.ts](src/lib/server/library.ts), [input.ts](src/lib/server/input.ts)
and the migration in [drizzle](drizzle/) for the implementation.

## Set up

Use Node.js **24.21.0**, npm **11.19.0**, Git, OpenSSL, `jq` and `psql` 16 or
later, plus a ClickHouse Cloud organization with Managed Postgres access. Install
runtimes and dependencies in your development environment. This example was
built and tested inside an Ubuntu 24.04 OrbStack VM; no app dependencies are
needed on the macOS host.

```sh
# Optional VM on macOS; run the remaining setup inside it.
orb create --memory 3G --cpus 2 ubuntu:24.04 reading-list-dev
orb -m reading-list-dev bash
```

On Ubuntu:

```sh
sudo apt-get update
sudo apt-get install -y git curl jq openssl postgresql-client
# Install Node 24 using the official distribution: https://nodejs.org/en/download
curl -fsSL https://clickhouse.com/cli | sh
export PATH="$HOME/.local/bin:$PATH"
git clone https://github.com/ClickHouse/examples.git
cd examples/applications/shared-reading-list
npm ci --ignore-scripts
```

Dependencies are pinned in the lockfile. Two overrides pin patched `cookie`
and migration-tool `esbuild` dependencies; review them when upgrading the
framework or Drizzle Kit. Better Auth 1.7.7 declares support for
SvelteKit 2; this example pins SvelteKit 2.70.3 and adapter-node 5.5.7 rather than
bypassing peer dependency checks for SvelteKit 3.

### 1. Create a dedicated Cloud service

Create an Admin API key following the
[Cloud API guide](https://clickhouse.com/docs/cloud/manage/openapi). Use interactive
login so the secret stays out of command arguments:

```sh
clickhousectl cloud auth login --interactive
clickhousectl cloud auth status
clickhousectl cloud org list
umask 077
mkdir -p .deployment
```

Create `.deployment/resources.env` with your organization ID and a supported
configuration. The validation used AWS `us-east-1`, `c6gd.large`, Postgres 18 and
no HA; the shape is shown in the
[official CLI guide](https://clickhouse.com/blog/clickhousectl-v0-2-0-postgres-clickpipes-more).
Availability varies by region and organization. Review current
[pricing](https://clickhouse.com/docs/products/managed-postgres/pricing) before
creating a service. A running Cloud service incurs charges even when the app or
VM is stopped.

```dotenv
CH_ORG_ID=YOUR_ORGANIZATION_UUID
CLOUD_REGION=us-east-1
PG_SIZE=c6gd.large
```

```sh
source .deployment/resources.env
clickhousectl cloud postgres create --org-id "$CH_ORG_ID" \
  --name shared-reading-list-example --provider aws --region "$CLOUD_REGION" \
  --size "$PG_SIZE" --pg-version 18 --ha-type none --json \
  > .deployment/create.json
PG_SERVICE_ID="$(jq -er '.id' .deployment/create.json)"
```

Record `PG_SERVICE_ID` in `.deployment/resources.env`. The private receipt
contains the initial password, returned only at creation. Keep it. If the
command is interrupted, reconcile `cloud postgres list --json` before retrying
creation. Do not create a duplicate service.

Repeat the following inspection until `state` is `running`, then download its CA:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres certs get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" \
  --output .deployment/ca.pem
```

Add the actual direct `hostname` and `username` to `.deployment/resources.env`:

```dotenv
PGHOST=YOUR_DIRECT_HOST
PGPORT=5432
PGDATABASE=postgres
PGADMIN=postgres
```

Use the returned username if it differs. These instructions use the direct
endpoint, not a transaction pooler.

### 2. Create migration and runtime roles

Generate and preserve role passwords once. Rerunning generation will not change
existing database passwords:

```sh
cat > .deployment/passwords.env <<PASSWORDS
PG_MIGRATION_PASSWORD=Aa1_$(openssl rand -hex 24)
PG_APP_PASSWORD=Aa1_$(openssl rand -hex 24)
PASSWORDS
source .deployment/resources.env
source .deployment/passwords.env
export PGHOST PGPORT PGDATABASE PG_MIGRATION_PASSWORD PG_APP_PASSWORD
export PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/ca.pem"
export PGPASSWORD="$(jq -er '.password' .deployment/create.json)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/001_roles.sql
unset PGPASSWORD
```

Run role creation once on an empty dedicated database. The schema owner,
`reading_migration`, owns `reading` and `reading_migrations`. It needs database
`CREATE` for Drizzle's migration bootstrap, even when the history schema already
exists. The runtime role, `reading_app`, receives schema usage and explicit row
permissions after migration. It cannot create tables or read migration history.
The setup revokes `CREATE` on `public` from `PUBLIC`, so use a dedicated service.

### 3. Apply the migration and seed

```sh
cat > .deployment/migration.env <<MIGRATION
MIGRATION_DATABASE_URL=postgresql://reading_migration:${PG_MIGRATION_PASSWORD}@${PGHOST}:${PGPORT}/${PGDATABASE}
DATABASE_CA_PATH=.deployment/ca.pem
MIGRATION
npm run db:migrate
export PGPASSWORD="$PG_MIGRATION_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -U reading_migration -f sql/002_grants.sql
unset PGPASSWORD
cp .env.example .env
```

Edit `.env` with the restricted runtime URL, CA path and a random auth secret:

```dotenv
DATABASE_URL=postgresql://reading_app:YOUR_APP_PASSWORD@YOUR_DIRECT_HOST:5432/postgres
DATABASE_CA_PATH=.deployment/ca.pem
BETTER_AUTH_SECRET=YOUR_RANDOM_SECRET_OF_AT_LEAST_32_CHARACTERS
BETTER_AUTH_URL=http://localhost:3000
ORIGIN=http://localhost:3000
HOST=127.0.0.1
PORT=3000
SIGNUP_ENABLED=true
```

Use `openssl rand -hex 32` to generate the auth secret. Supply a plain Postgres
URL with no query parameters; percent-encode any special characters in passwords.
[connection.ts](src/lib/server/connection.ts) sets the downloaded CA,
`rejectUnauthorized: true` and the TLS server name explicitly. It rejects URL
parameters that could alter these connection defaults.

```sh
chmod 600 .env .deployment/*.env .deployment/create.json
npm run db:seed
```

The seed adds two links owned by a demo identity that has no password account.
Migration and seed reruns are safe; migration history records applied files.
For schema changes, edit `schema.ts`, run `npm run db:generate`, inspect and commit
the resulting SQL and snapshots, then apply with `db:migrate`. Don't edit a
migration already applied. Review grants when adding tables.

### 4. Start and try it

```sh
npm run check
npm test
npm run build
npm start
```

Open [localhost:3000](http://localhost:3000), create an account and save a link.
Open its detail screen, edit its tags, then search from the collection. Use a
second browser profile to sign in as another reader: they can browse and search
your link, but cannot edit it. Sign out and back in; saved content remains.

`SIGNUP_ENABLED=true` enables self-service account creation. After onboarding
trusted readers, set it to `false` and restart the process. The UI then says that
account creation is closed; existing accounts can still sign in. For a deployment,
set `BETTER_AUTH_URL` and `ORIGIN` to the exact HTTPS origin without a trailing
slash. Run behind an HTTPS reverse proxy and process supervisor. This is a Node
server, not a static site. Keep runtime credentials and the CA on the server;
keep Cloud API keys and migration credentials separate.

## Validate against your dedicated service

With the production app running on localhost:3000:

```sh
npm run test:integration
npm run test:tls
npm run test:persistence
npm exec playwright install -- --with-deps chromium
npm run test:browser
```

The suite signs up temporary test users, then exercises validation, duplicate
URLs, foreign edits/deletes, stale competing edits, combined filters, runtime
role restrictions and sign-out revocation. Persistence testing starts its own
production process on port 3001, saves a link, stops it, then checks the same
session and content after restart. The TLS suite proves a verified connection
works and that unrelated CAs and an incorrect TLS hostname are rejected.
`WRONG_CA_PATH` can specify an unrelated CA bundle on non-Linux systems.

The browser test uses two browser contexts for signup, save, edit and search;
it captures `/tmp/reading-list.png`. Use `SCREENSHOT_PATH` to choose a location.
The integration and persistence suites remove their test users and links.
Browser-created users are test fixtures on the dedicated service.

## Boundaries

There is one shared collection, not separate organizations or private lists.
This example is intended for trusted readers. Signup has no email verification,
password-reset email delivery, invitation workflow or moderation. Better Auth's
built-in auth rate limits remain enabled; configure trusted proxy IP forwarding
and an external limiter for a production deployment. Auth rate limits do not
limit link writes. The runtime role can access all collection and auth tables;
per-user authorization is enforced by the server, not row-level security.

The collection shows at most 100 links, newest first; it does not paginate or
report a total count. Two different URLs that lead to the same page may both be
saved. No server fetch means saving an unreachable URL is allowed. English
full-text search and exact tags provide bounded filtering, not a relevance model.

## Cleanup

Stop the app before cleanup. To remove this example's schemas and roles while
keeping the dedicated service:

```sh
source .deployment/resources.env
export PGHOST PGPORT PGDATABASE PGSSLMODE=verify-full
export PGSSLROOTCERT="$PWD/.deployment/ca.pem"
export PGPASSWORD="$(jq -er '.password' .deployment/create.json)"
psql -X -v ON_ERROR_STOP=1 -U "$PGADMIN" -f sql/003_cleanup.sql
unset PGPASSWORD
```

To stop Cloud service charges, inspect its ID/name and delete only your dedicated
example service. Deletion permanently removes its data:

```sh
clickhousectl cloud postgres get "$PG_SERVICE_ID" --org-id "$CH_ORG_ID" --json
clickhousectl cloud postgres delete "$PG_SERVICE_ID" --org-id "$CH_ORG_ID"
clickhousectl cloud postgres list --org-id "$CH_ORG_ID" --json
```

Remove private local credentials when no longer needed. Stop your optional VM
with `orb stop reading-list-dev` after preserving source and evidence.
