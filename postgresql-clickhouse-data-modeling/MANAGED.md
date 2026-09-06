# Managed Postgres → ClickHouse Cloud with a CDC ClickPipe

This separate path uses Postgres managed by ClickHouse as the transactional database, ClickHouse Cloud for analytics, and an explicit Postgres CDC ClickPipe between them. The pipe performs the initial snapshot and ongoing inserts, updates, and deletes. No local PeerDB, Temporal, or MinIO containers are needed.

These commands create billable Cloud resources. Use fresh demonstration services and your own private credentials. Command syntax was checked against `clickhousectl 0.4.2` on 2026-09-06; this Cloud path was **not provisioned or runtime-validated** during the local recipe refresh. The [local walkthrough](./README.md) is the manually verified path.

Use Bash, Docker for disposable clients, and an already installed `clickhousectl` (a VM shell is fine). No local pip/npm or database client installation is required. Authenticate the CLI with a Cloud API key; see the [CLI documentation](https://github.com/ClickHouse/clickhousectl). Do not reuse the local Compose passwords.

## Create the two services

Choose a supported region, Postgres instance size, and your client IP/CIDR in the Cloud console, then set `REGION`, `PG_SIZE`, and `YOUR_IP_CIDR` in your shell. The CLI validates sizes server-side. From this recipe directory:

```bash
set -euo pipefail
: "${REGION:?Set a supported region}"
: "${PG_SIZE:?Set a supported Postgres size}"
: "${YOUR_IP_CIDR:?Set your client IP/CIDR}"
clickhousectl cloud postgres create --name cdc-source --region "$REGION" \
  --size "$PG_SIZE" --pg-version 17 --json
clickhousectl cloud service create --name cdc-analytics --provider aws \
  --region "$REGION" --ip-allow "$YOUR_IP_CIDR" --json
```

Save each returned service ID and initial password privately. Set `POSTGRES_ID` and `CLICKHOUSE_ID` to those IDs. Poll `cloud postgres get "$POSTGRES_ID" --json` and `cloud service get "$CLICKHOUSE_ID" --json` until both report `running`; provisioning can take several minutes. Record the Postgres direct endpoint (not a transaction-pooler endpoint), port, administrator username, password, and database as `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, and `PGDATABASE`, exporting those variables for the client container.

The Postgres service must permit your client connection and connections from your ClickPipe. Configure its IP allowlist/private connectivity using the [ClickPipes networking guide](https://clickhouse.com/docs/integrations/clickpipes/networking) and the [region's ClickPipes IPs](https://clickhouse.com/docs/integrations/clickpipes/static-ips). Database credentials alone do not establish network access.

## Apply the same schema and fixture

Fetch the Postgres CA as a PEM file. Use `--output` so agent JSON output cannot accidentally turn the certificate file into JSON:

```bash
clickhousectl cloud postgres certs get "$POSTGRES_ID" --output ca.pem
pg() {
  docker run --rm -i \
    -e PGHOST -e PGPORT -e PGUSER -e PGDATABASE -e PGPASSWORD \
    -e PGSSLMODE=verify-full -e PGSSLROOTCERT=/work/ca.pem \
    -v "$PWD:/work:ro" postgres:17-alpine psql -v ON_ERROR_STOP=1 "$@"
}
pg -c 'SELECT version()'
pg < volumes/postgres/docker-entrypoint-initdb.d/1_create_table.sql
pg < fixtures/seed.sql
pg -c 'SHOW wal_level'
pg -c 'SHOW max_wal_senders'
pg -c 'SHOW max_replication_slots'
```

Logical replication requires `wal_level=logical`, more than one WAL sender, and at least four replication slots. If the displayed settings do not satisfy those requirements, adjust the managed service configuration and restart before continuing:

```bash
clickhousectl cloud postgres config patch "$POSTGRES_ID" \
  --set wal_level=logical --set max_wal_senders=10 --set max_replication_slots=10
clickhousectl cloud postgres restart "$POSTGRES_ID"
```

Wait for `running` again and recheck the settings. Follow the [Postgres source setup guide](https://clickhouse.com/docs/integrations/clickpipes/postgres/source/generic) for service-specific configuration restrictions.

Set a private `CLICKPIPES_PASSWORD`, then create a dedicated replication user and a publication covering exactly the four fixture tables:

```bash
: "${CLICKPIPES_PASSWORD:?Set a private password for the CDC user}"
pg --set=cdc_password="$CLICKPIPES_PASSWORD" <<'SQL'
CREATE USER clickpipes_user WITH REPLICATION PASSWORD :'cdc_password';
GRANT USAGE ON SCHEMA public TO clickpipes_user;
GRANT SELECT ON public.users, public.posts, public.votes, public.comments TO clickpipes_user;
CREATE PUBLICATION stackoverflow_demo FOR TABLE public.users, public.posts, public.votes, public.comments;
SQL
```

## Explicitly create the CDC ClickPipe

The CLI creates destination tables in the ClickHouse service's `default` database. These names must be unused in the fresh service. Keep the default CDC replication mode, which includes the initial snapshot:

```bash
clickhousectl cloud clickpipe create postgres "$CLICKHOUSE_ID" \
  --name stackoverflow-demo --host "$PGHOST" --port "$PGPORT" \
  --pg-database "$PGDATABASE" --username clickpipes_user --password "$CLICKPIPES_PASSWORD" \
  --ca-certificate ca.pem --publication-name stackoverflow_demo \
  --table-mapping public.users:users --table-mapping public.posts:posts \
  --table-mapping public.votes:votes --table-mapping public.comments:comments \
  --sync-interval-seconds 5 --initial-load-parallelism 1 --snapshot-parallel-tables 1
clickhousectl cloud clickpipe list "$CLICKHOUSE_ID"
```

Save the returned ClickPipe ID as `CLICKPIPE_ID`. Source TLS verification stays enabled; the CA verifies the managed Postgres certificate. Do not substitute a Compose hostname such as `postgres` here. The managed ClickPipe must reach the actual managed Postgres endpoint.

## Verify the same initial and changed state

The local verifier and this path share [current-state.sql](./fixtures/current-state.sql). Change only the destination database prefix to `default`. The query uses `FINAL` and `_peerdb_is_deleted = 0`, so it compares logical current state despite asynchronous merging of physical versions. The disposable Python container only parses the CLI's JSON response; it installs no packages.

```bash
state_sql=$(sed 's/stackoverflow\./default./g' fixtures/current-state.sql)
cloud_state() {
  clickhousectl cloud service query --id "$CLICKHOUSE_ID" --query "$state_sql" --json |
    docker run --rm -i python:3.12-alpine python -c \
      'import json, sys; print(json.load(sys.stdin)["state"])'
}
assert_cloud_state() {
  local expected="$1" actual='' deadline=$(( $(date +%s) + 180 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if actual=$(cloud_state) && [ "$actual" = "$expected" ]; then
      printf 'OK: %s\n' "$actual"
      return 0
    fi
    sleep 2
  done
  printf 'CDC did not converge: expected %s; got %s\n' "$expected" "$actual" >&2
  return 1
}
assert_cloud_state "[(1,'Alice Example'),(2,'Bob Example')]|2|1|1"
pg < fixtures/changes.sql
assert_cloud_state "[(1,'Updated User'),(3,'New User')]|2|1|1"
clickhousectl cloud service query --id "$CLICKHOUSE_ID" \
  --query 'SELECT id, displayname FROM default.users FINAL WHERE _peerdb_is_deleted = 0 ORDER BY id' --json
```

Expected final users are exactly ID 1 / `Updated User` and ID 3 / `New User`; ID 2 is deleted. Posts, votes, and comments remain at 2, 1, and 1 respectively. Polling is bounded to 180 seconds plus an in-flight CLI request (the Query API has an approximately 30-second gateway timeout, with network/request handling potentially adding time). If a check fails, inspect the ClickPipe in the Cloud console; do not silently rerun the explicit-ID mutations.

## Cleanup and rerun

Local `docker compose down -v` does not delete these Cloud resources. When you are finished with the demonstration services, remove the pipe and both services using their saved IDs:

```bash
clickhousectl cloud clickpipe delete "$CLICKHOUSE_ID" "$CLICKPIPE_ID"
clickhousectl cloud service delete "$CLICKHOUSE_ID" --force
clickhousectl cloud postgres delete "$POSTGRES_ID"
```

These commands permanently delete the demonstration services and their data; check the IDs before running them. `--force` stops the ClickHouse service before deleting it. To rerun, create fresh services and repeat the schema/fixture/ClickPipe steps. Stopping a pipe alone does not remove the databases or their charges.

- [Postgres managed by ClickHouse](https://clickhouse.com/docs/cloud/managed-postgres)
- [Postgres CDC ClickPipes](https://clickhouse.com/docs/integrations/clickpipes/postgres)
- [clickhousectl Postgres and ClickPipes examples](https://clickhouse.com/blog/clickhousectl-v0-2-0-postgres-clickpipes-more)
