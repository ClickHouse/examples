# Workshop appointment calendar

Move a workshop appointment between quarter-hour slots, edit its details, and compare stored booked minutes across three bays. Vue Router switches between the calendar and utilization views; Pinia shares the selected day, bay, and appointment. PrimeVue supplies controls and a modal, VeeValidate validates the details form, FullCalendar Standard handles native dragging, Chart.js renders utilization, and ts-rest shares the typed API contract with Express.

ClickHouse Managed Postgres stores the service catalogue, appointments, revisions and timezone-aware instants. A GiST exclusion constraint rejects overlapping appointments in the same bay, including concurrent writes. Service duration comes from the server catalogue. A failed drag calls FullCalendar's `revert()` and reloads the saved state.

This is a local, trusted workshop demonstration with synthetic customers, no sign-in, one location, fixed service durations, and 09:00–17:00 Europe/London opening hours. It does not create bookings or connect external calendars. PrimeVue **4.5.5** is pinned to its verified MIT release; this example does not require a PrimeVue v5 license key. FullCalendar uses Standard plugins only.

## Create Postgres with clickhousectl

Install Node.js 24 or newer, `psql`, and clickhousectl using the [official installation instructions](https://github.com/ClickHouse/clickhousectl). Use your own Cloud organization and API credentials. A Cloud service incurs ordinary database charges until deleted.

```sh
export CLICKHOUSE_CLOUD_API_KEY='your-key'
export CLICKHOUSE_CLOUD_API_SECRET='your-secret'
export ORG_ID='your-organization-id'
clickhousectl cloud postgres create --help
```

Create one disposable non-HA service. The following shape was accepted for this example; availability depends on your organization. Creation returns credentials once. Keep its receipt private.

```sh
umask 077
clickhousectl cloud postgres create --name workshop-calendar \
  --region us-east-1 --size c6gd.large --provider aws \
  --pg-version 18 --ha-type none --org-id "$ORG_ID" --json > create.private.json
export SERVICE_ID='id-from-your-create-receipt'
clickhousectl cloud postgres get "$SERVICE_ID" --org-id "$ORG_ID" --json
# Wait until state is running.
clickhousectl cloud postgres certs get "$SERVICE_ID" \
  --org-id "$ORG_ID" --output postgres-ca.pem
```

Copy `.env.example` to `.env`. Use the direct hostname, database and administrator credentials from your receipt. Choose separate owner/application passwords and set `PG_OWNER_PASSWORD` and `PG_APP_PASSWORD` for bootstrap. Configure psql TLS and apply the files explicitly:

```sh
export PGHOST='direct-hostname' PGPORT=5432 PGDATABASE='database-from-receipt'
export PGSSLROOTCERT="$PWD/postgres-ca.pem" PGSSLMODE=verify-full
export PGUSER='administrator-from-receipt' PGPASSWORD='administrator-password'
export PG_OWNER_PASSWORD='your-owner-password' PG_APP_PASSWORD='your-app-password'
psql -X -v ON_ERROR_STOP=1 -f sql/bootstrap.sql
export PGUSER=appointment_calendar_owner PGPASSWORD="$PG_OWNER_PASSWORD"
psql -X -v ON_ERROR_STOP=1 -f sql/schema.sql
export PGUSER='administrator-from-receipt' PGPASSWORD='administrator-password'
psql -X -v ON_ERROR_STOP=1 -f sql/grants.sql
```

The migration files are a one-time setup for a fresh service. They do not reset an existing database.

## Native build

```sh
npm ci
npm run check
npm run build
```

Copy `.env.example` to `.env` and set the direct database fields. Keep the administrator, schema owner, and runtime users separate. Never expose their credentials to the browser. Run `sql/bootstrap.sql` as the administrator, then `sql/schema.sql` as the owner and `sql/grants.sql` as the administrator. The bootstrap requires the supported `btree_gist` extension; the runtime has catalogue/appointment SELECT and only the appointment UPDATE columns needed by this workflow.

```sh
set -a
. ./.env
set +a
npm start
```

Open http://127.0.0.1:4331/calendar. The seed date is **5 October 2026**. Drag Morgan's booking to a free quarter-hour slot, reload, then drag it into Ellis's booking. The server rejects the overlap and restores the committed appointment. Select a booking to edit its customer, service, bay, start, or note. The service's stored duration determines the end. Open Utilization to see minutes calculated from those same saved bookings.

## Time and database behavior

The workshop zone is `Europe/London`. The API requires an explicit timestamp offset, stores instants as `timestamptz`, and derives local day boundaries with Temporal so daylight-saving days are handled correctly. The details form rejects ambiguous wall times. Appointments use half-open ranges `[start, end)`, allowing a booking to start exactly when another ends. The exclusion constraint also protects direct SQL writes.

Updates include the previously read revision. The conditional UPDATE rejects a stale edit with HTTP 409. Catalogue duration is read server-side and constrained by a composite foreign key; the browser cannot supply an end time or override service duration. Utilization reads bookings and totals in one repeatable-read snapshot.

## Verify and clean up

Managed validation used PostgreSQL 18.6 with `btree_gist` 1.8, Node 24 and verified Cloud TLS. Integration checks exercise concurrent overlap rejection, persisted rescheduling after a genuine process restart, stale revisions, invalid timestamps and tampered request fields, runtime grant boundaries, totals and a 23-hour daylight-saving day.

```sh
# Export .env, including separate DB_OWNER_USER/DB_OWNER_PASSWORD for fixture setup.
# Stop the interactive server first: the tests start their own production process.
npm run test:integration
npm exec playwright install chromium
npm run test:browser
npm exec tsx tests/ui-state.ts # local response controls; no Cloud database required
npm run db:probe
npm run db:probe -- --wrong-host # must exit 1
PG_CA_CERT_PATH=/etc/ssl/certs/ca-certificates.crt npm run db:probe # must exit 1
```

Browser checks use the synthetic seed date and restore Morgan's appointment afterward. They exercise real FullCalendar mouse dragging, successful persistence/reload, rejected occupied-slot reversion, PrimeVue/VeeValidate details editing, router navigation and Chart.js totals. The managed delayed-response control verifies the earlier day's response cannot overwrite the current selection. A separate UI-only control uses response fixtures after cleanup to prove delayed/failing new days hide previous chart bars and totals. Chart animation is disabled; the control checks painted pixels before capturing its screenshot. Browser validation uses a UTC browser while displaying the Europe/London workshop.

The tests require a dedicated disposable service: integration fixtures use reserved IDs 800000001–800000003 and date 4 February 2030. Do not run them against an existing workshop database. The build currently reports a large single client bundle; this teaching example loads its calendar and chart together. It is not a public deployment configuration.

Delete your owned service when finished and verify its ID is absent:

```sh
clickhousectl cloud postgres delete "$SERVICE_ID" --org-id "$ORG_ID" --json
clickhousectl cloud postgres list --org-id "$ORG_ID" --json
```

Keep your receipt and CA outside Git. This repository's scoped CI runs a clean install, typecheck and production build without Cloud credentials.
