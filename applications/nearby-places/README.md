# Nearby places

A small Deno/Oak browser form and JSON API search a synthetic place directory in ClickHouse Managed
Postgres. PostGIS stores `geography(Point,4326)` and returns spheroidal geodesic
distances in meters. The results describe proximity over the Earth's surface, not routes or travel
time.

The app has no accounts or mutation routes. Its database role can select the directory, while
separate administrator and schema-owner commands install PostGIS, migrate and seed. All labels are
fictional; coordinates are explicit test fixtures. It does not request geolocation, use map tiles,
geocode addresses or collect a real location directory.

## Pinned stack

- Deno 2.9.7, Oak 17.2.0 and npm Postgres.js 3.4.9.
- Committed `deno.lock` pins transitive JSR/npm dependencies. There is no npm install or
  node_modules requirement for the application.
- Actual Cloud fixture on 2 October 2026: PostgreSQL 18.6, PostGIS 3.6.4. Setup prints
  `pg_extension` and `PostGIS_Full_Version()`; inspect your service's actual version rather than
  assuming this one.

The query lives in [src/places.ts](src/places.ts), validation in [src/input.ts](src/input.ts), and
connection verification in [src/database.ts](src/database.ts). Oak's standard `handle()` API runs
its middleware on Deno's HTTP server; shutdown awaits `server.finished`, removes signal listeners
and closes the database pool.

## Create a dedicated Cloud fixture

Use an authenticated clickhousectl and a dedicated test service. The following modest shape was
verified in `us-east-1`; check current availability/pricing before allocating your own. This example
has no HA.

```bash
export ORG_ID=your-organization-id
clickhousectl cloud postgres create --org-id "$ORG_ID" \
  --name nearby-places --provider aws --region us-east-1 \
  --size c6gd.large --pg-version 18 --ha-type none --json \
  > /private/path/service.json
chmod 600 /private/path/service.json
export SERVICE_ID=your-returned-service-id
```

Save the returned hostname, port, username and password privately. Repeat this command until its
state is `running`:

```bash
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres certs get "$SERVICE_ID" --org-id "$ORG_ID" \
  --output /private/path/cloud-ca.pem
```

See
[ClickHouse Managed Postgres extensions](https://clickhouse.com/docs/products/managed-postgres/extensions).
Running services incur charges. Keep receipts, credentials and CA files out of Git.

## Install, migrate and seed

Install the pinned Deno release and a PostgreSQL client. From this application directory, populate
the dependency cache from the committed lock:

```bash
deno install --frozen --entrypoint src/server.ts test/domain_test.ts test/cloud_test.ts
deno task fmt:check
deno task lint
deno task check
deno task test
```

Create a private setup environment file. Use the administrator credentials from the receipt and two
distinct random role passwords of at least 24 characters:

```dotenv
PGHOST=your-service-hostname
PGPORT=5432
PGDATABASE=postgres
PGSSLROOTCERT=/absolute/path/cloud-ca.pem
PGSSLMODE=verify-full
ADMIN_USER=receipt-username
ADMIN_PASSWORD=receipt-password
MIGRATION_PASSWORD=distinct-random-schema-owner-password
APP_PASSWORD=distinct-random-read-only-password
```

Export fields to child processes and bootstrap as the administrator:

```bash
set -a
source /private/path/setup.env
set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/bootstrap.sql
export PGUSER=places_migration PGPASSWORD="$MIGRATION_PASSWORD"
psql -X -f sql/migrate.sql
psql -X -f sql/seed.sql
```

`bootstrap.sql` installs the available PostGIS extension in `public`, creates both roles and the
owned application schema, and prints the actual extension version. It runs once. The dedicated
database's public schema CREATE and database CREATE/TEMP privileges are revoked from PUBLIC. The
schema owner needs no database CREATE grant because the administrator creates its schema explicitly.

`migrate.sql` records version 1, creates the places table and GiST geography/category indexes, and
grants SELECT on that table to the reader. `seed.sql` upserts the 12 explicit fixtures and analyzes
the table. Repeat migration and seed to verify reproduction. Administrator cleanup offers a
destructive fixture reset; no production downgrade path is included. Runtime startup never performs
DDL or seed writes.

## Start with restricted permissions

Create a private runtime file from [.env.example](.env.example), containing only the reader's
credentials, connection fields and optional `PORT=4000`. Do not include administrator or migration
passwords.

```bash
set -a; source /private/path/runtime.env; set +a
unset ADMIN_USER ADMIN_PASSWORD MIGRATION_PASSWORD APP_PASSWORD
bash scripts/run.sh
```

Open `http://127.0.0.1:4000`. The browser offers London, equator and dateline fixtures,
category/limit controls and sorted result cards. A zero radius shows only coincident points. Display
distances are rounded; ordering uses the database's full returned distances.

The [run script](scripts/run.sh) uses `--frozen --cached-only` and grants:

- Network access only to `127.0.0.1:$PORT` and the configured Cloud hostname/port.
- File reading only for `public` assets and the configured CA file.
- Environment reading only for `PG*`, `PORT`, `NODE_DEBUG` and `NODE_EXTRA_CA_CERTS`. The PG prefix
  is needed because Postgres.js reads its configuration defaults; the two Node variables support the
  verified compatibility path.

It grants no write, subprocess, FFI or blanket `-A` permission. Postgres.js supplies the downloaded
CA, `rejectUnauthorized:true` and the actual hostname to Node-compatible TLS.
`PGSSLMODE=verify-full` configures `psql`; the application sets verification explicitly instead of
relying on that variable.

The reader's default read-only transaction setting is a client-changeable convenience. Table grants
enforce persistent read-only access even if that default is disabled; schema/database grants prevent
persistent and temporary DDL. The Cloud test disables the default before asserting SQLSTATE 42501
for writes and DDL. The role can use public PostGIS functions needed by SELECT queries, and
PostgreSQL's ordinary system catalog access.

This is a public read-only sample bound to loopback, with a three-connection pool and two-second
statement timeout. Public deployment would need HTTPS, traffic limits and appropriate operational
monitoring. Searches aren't written to an application table or logged by this example;
infrastructure/access logs are outside that claim.

## JSON search

```bash
curl -sS 'http://127.0.0.1:4000/api/nearby?longitude=0&latitude=0&radiusMeters=1200&limit=20'
curl -sS 'http://127.0.0.1:4000/api/nearby?longitude=179.999&latitude=0&radiusMeters=300&category=park'
```

`GET /api/nearby` returns `{ search, places, sampleData: true }`. Each place includes ID, label,
category, longitude, latitude and `distanceMeters`. The search echoes validated inputs. Results are
bounded by the supplied limit; there is no pagination or total-match count. Unsupported mutations
return `405`.

| Parameter      | Bounds                                             |
| -------------- | -------------------------------------------------- |
| `longitude`    | Required finite decimal, −180 through 180          |
| `latitude`     | Required finite decimal, −90 through 90            |
| `radiusMeters` | Required finite decimal, 0 through 50,000          |
| `category`     | Optional `cafe`, `library` or `park`; omit for all |
| `limit`        | Optional integer 1–50; defaults to 20              |

Unknown/repeated parameters, nonfinite numbers, malformed decimals and values outside bounds return
`400`. URLs longer than 2,048 characters return `414`. A database failure returns a generic `503`
without connection details.

The query constructs its origin in **longitude, latitude** order. Parameterized
`ST_DWithin(geography, geography, meters, true)` restricts candidates and can use the GiST index.
`ST_Distance(..., true)` supplies spheroidal meters for ordering, followed by place ID as the
deterministic tie-breaker, then the bounded limit. It does not use a degree-based radius or
spherical KNN distance as a substitute for the requested ordering.

## Native Cloud and browser acceptance

Use a freshly bootstrapped dedicated fixture. After exporting setup.env, switch to the reader:

```bash
export PGUSER=places_reader PGPASSWORD="$APP_PASSWORD"
export EVIDENCE_DIR=/private/path/evidence
mkdir -p "$EVIDENCE_DIR"
deno test --frozen --cached-only \
  --allow-env='PG*,EVIDENCE_DIR,NODE_DEBUG,NODE_EXTRA_CA_CERTS' \
  --allow-net="$PGHOST:$PGPORT" --allow-read="$PGSSLROOTCERT,/tmp" \
  --allow-write="/tmp,$EVIDENCE_DIR" --allow-run=openssl test/cloud_test.ts
```

The test needs OpenSSL only to generate an unrelated CA and writes evidence only to the configured
location. It checks known equatorial meters, identical points, radius/category filters, coordinate
order, stable ties/limits, antimeridian and polar behavior, grant denials after disabling the
read-only default, and negative TLS controls with a positive connection afterward. It saves an
actual `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` for the application query. No index is forced; a
tiny fixture's plan is evidence of that query shape, not a performance benchmark.

The optional browser/HTTP harness uses Node 24.21.0 and Playwright 1.63.0 in an isolated development
directory. It starts the same restricted application command, checks desktop/mobile cards and
malformed HTTP requests, confirms the original process exits, then restarts it and compares durable
results:

```bash
export BROWSER_DIR=/private/path/browser-dependencies
mkdir -p "$BROWSER_DIR"
npm --prefix "$BROWSER_DIR" install --save-exact playwright@1.63.0
"$BROWSER_DIR/node_modules/.bin/playwright" install --with-deps chromium
cp test/browser.mjs "$BROWSER_DIR/browser.mjs"
export APP_DIR="$PWD" EVIDENCE_DIR=/private/path/evidence
# Use runtime.env, with only reader credentials, for this harness.
node "$BROWSER_DIR/browser.mjs"
```

CI runs frozen installation, formatting, lint, type checking and the three domain tests without
Cloud secrets. Cloud/browser evidence belongs to the dedicated development fixture.

## Cleanup

Stop the application before resetting schemas or deleting the service. To reset only this fixture,
explicitly restore administrator credentials:

```bash
set -a; source /private/path/setup.env; set +a
export PGUSER="$ADMIN_USER" PGPASSWORD="$ADMIN_PASSWORD"
psql -X -f sql/cleanup.sql
```

The reset keeps the administrator-owned PostGIS extension so bootstrap can be repeated.
Database/public-schema privilege revocations also remain. To remove the billable fixture, use its
exact recorded ID and verify absence after asynchronous deletion:

```bash
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID"
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Deletion destroys that service's data. Preserve needed source and evidence first.

## Primary references

- [PostGIS ST_DWithin](https://postgis.net/docs/ST_DWithin.html)
- [PostGIS ST_Distance](https://postgis.net/docs/ST_Distance.html)
- [Deno's npm Postgres example](https://docs.deno.com/examples/postgres/)
- [Oak 17.2.0 source](https://jsr.io/@oak/oak@17.2.0)
- [Postgres.js 3.4.9 source](https://github.com/porsager/postgres/tree/v3.4.9)
