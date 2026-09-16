# Infrastructure SQL and ClickPipe mapping

Follow the [commands in the project README](../README.md#deploy-your-own-instance).
This directory contains inputs to those commands, not a provisioning program.
The repository keeps its existing migration paths; `clickhousectl local init`
is only needed when scaffolding a new project.

| File | Run as | Purpose |
| --- | --- | --- |
| [postgres/001_roles.sql](postgres/001_roles.sql) | Postgres administrator | Create migration/runtime/CDC logins; grant schema access |
| [postgres/002_grants.sql](postgres/002_grants.sql) | Postgres migration login | Grant table access; enable full replica identity |
| [postgres/003_publication.sql](postgres/003_publication.sql) | Postgres administrator | Require logical WAL and publish only public.links |
| [postgres/verify.sql](postgres/verify.sql) | Postgres runtime login | Check privilege boundaries, publication, replica identity and TLS |
| [clickhouse/001_database.sql](clickhouse/001_database.sql) | Cloud Query API | Create analytics database |
| [clickhouse/002_app_user.sql](clickhouse/002_app_user.sql) | Cloud Query API | Template for a runtime user; render its hash privately before execution |
| [clickhouse/003_events_grant.sql](clickhouse/003_events_grant.sql) | Cloud Query API | Grant event reads/inserts |
| [clickhouse/004_cdc_grant.sql](clickhouse/004_cdc_grant.sql) | Cloud Query API | Grant CDC reads after ClickPipes creates the table |
| [clickhouse/verify-events.sql](clickhouse/verify-events.sql) | Runtime or Query API | Compare raw rows with distinct event IDs |
| [clickhouse/verify-cdc.sql](clickhouse/verify-cdc.sql) | Runtime or Query API | Inspect CDC engine and version/delete columns |
| [clickpipe-links.json](clickpipe-links.json) | clickhousectl create postgres | Explicit links-only CDC mapping |

ClickHouse's Cloud query command accepts **one statement per file** in the checked
0.4.2 CLI. Postgres files use `psql`, with `-X` and `ON_ERROR_STOP=1`. The role file
also uses `psql` environment variables and identifier/literal quoting. No SQL
extension is needed for the current schema. App table definitions live in
[migrations](../migrations/README.md).

The Cloud Query API's migration credential and Cloud management API keys stay
with the operator. The app receives only its restricted runtime login. Postgres
also has separate migration and replication logins; the replication login reads
only links. Passwords and rendered SQL stay under `.deployment/`.

## Verify data flow

Schema inspection in README does not establish runtime connectivity or CDC.
The fixture verifier uses the application's runtime database credentials and
changes only its synthetic source rows:

```sh
node --env-file=.deployment/runtime.env scripts/verify-cdc.mjs
```

It checks insert, update of tags while preserving large unchanged URL fields,
and a delete tombstone. It cleans its source account/link and keeps a private
receipt in `.deployment/`; a synthetic destination tombstone remains. Failed
cleanup can be retried using its exact receipt:

```sh
node --env-file=.deployment/runtime.env scripts/verify-cdc.mjs \
  --cleanup .deployment/cdc-YOUR_RUN_ID.json
```

For a **disposable test deployment only**, verify a populated resnapshot with
browser/integration runs and other flushers stopped. Start this in one terminal:

```sh
node --env-file=.deployment/runtime.env scripts/verify-cdc.mjs --await-snapshot
```

Wait until it prints that the fixture is ready, then run this explicit management
command in another terminal with the recorded IDs and ClickHouse CLI authenticated:

```sh
clickhousectl cloud clickpipe resync "$CH_SERVICE_ID" "$CLICKPIPE_ID" \
  --org-id "$CH_ORG_ID"
```

Resync snapshots the whole pipe. The verifier waits up to ten minutes for the
CDC table UUID to change, then verifies the populated snapshot, updates and
persistent tombstone. It never runs infrastructure commands or receives management
keys. Do not resync a production pipe merely to test setup.

Run the [hosted acceptance checklist](../docs/v1-readiness.md) separately to verify
authentication, authorization, redirects, event delivery and Worker networking.
The direct-command setup needs a fresh-deployment rehearsal before publication;
CLI syntax checks and ordinary tests are not a Cloud acceptance pass.
