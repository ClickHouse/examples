# ClickHouse with Kafka-compatible Redpanda

**For production, the recommended path is Redpanda → ClickHouse Cloud through the
managed [Redpanda ClickPipes connector](https://clickhouse.com/cloud/clickpipes).**
ClickPipes manages ingestion without requiring you to operate the Kafka-engine
and materialized-view plumbing shown in this local example.

This recipe teaches the Kafka protocol ingestion pattern with one Redpanda broker
and one ClickHouse server. The bundled `rpk` produces three JSONEachRow messages;
a ClickHouse `Kafka` table consumes them, a materialized view forwards them, and a
`MergeTree` table stores them for queries. Redpanda provides the Kafka API without
ZooKeeper or a JVM. This example does not test every Kafka ecosystem feature,
production availability, or failover.

## Requirements and local security

Use Docker with Compose v2 supporting `up --wait --wait-timeout`, a POSIX shell,
and approximately 4 GiB of Docker memory, 2 CPUs, and several GiB of image space.
The selected Redpanda and ClickHouse images publish Linux amd64 and arm64 builds;
Docker Desktop or OrbStack supplies the Linux environment on macOS. No host
Kafka, ClickHouse, Node.js, or Python installation is needed.

Redpanda is pinned to `v26.2.2`. ClickHouse defaults to `CHVER=latest`; export
`CHVER` before starting to select another version. The commands print the actual
versions. Last manually verified on 2026-09-06 using Docker/OrbStack on Linux
arm64: ClickHouse `26.8.2.7` and Redpanda/rpk `26.2.2`. The full walkthrough
returned all three fixture rows unchanged. Floating ClickHouse tags can change
after this verification date.

The ClickHouse HTTP endpoint is published only at `127.0.0.1:18123`, with the public
development credentials `demo` / `local-example-password`. Redpanda has no
authentication and is accessible only within the Compose network. This local
example uses plaintext connections; do not expose it or reuse its credentials for
production.

## Start, produce, and verify

From the repository root, change into
`docker-compose-recipes/recipes/ch-and-redpanda`, then run this complete block
from empty volumes. Compose waits at most 120 seconds for service health. Fixture
delivery has a 15-second per-record timeout; destination polling makes at most 30
attempts with a 10-second client receive timeout per query.

```sh
set -eu
docker compose up -d --wait --wait-timeout 120

query() {
  docker compose exec -T clickhouse clickhouse-client \
    --user demo --password local-example-password \
    --connect_timeout 5 --receive_timeout 10 --max_execution_time 10 \
    --query "$1"
}
query 'SELECT version()'
docker compose exec -T redpanda rpk version

# One topic, one partition, one replica: this is a disposable single-broker lesson.
docker compose exec -T redpanda rpk topic create events \
  --partitions 1 --replicas 1 -X brokers=redpanda:9092
docker compose exec -T clickhouse clickhouse-client \
  --user demo --password local-example-password \
  --connect_timeout 5 --receive_timeout 10 --max_execution_time 10 \
  --multiquery < setup.sql
docker compose exec -T redpanda rpk topic produce events \
  --delivery-timeout 15s -X brokers=redpanda:9092 < events.jsonl

attempt=0
ready=false
while [ "$attempt" -lt 30 ]; do
  if [ "$(query 'SELECT count() FROM events')" = 3 ]; then
    ready=true
    break
  fi
  attempt=$((attempt + 1))
  sleep 2
done
if [ "$ready" != true ]; then
  echo 'Timed out waiting for three ingested events' >&2
  docker compose logs --tail=100
  exit 1
fi

# Compare every field and row with the fixture, not just its count.
actual=$(query 'SELECT event_id, name FROM events ORDER BY event_id SETTINGS output_format_json_quote_64bit_integers = 0 FORMAT JSONEachRow')
[ "$actual" = "$(cat events.jsonl)" ]
printf '%s\n' "$actual"
echo 'OK: all three Redpanda events reached ClickHouse unchanged'
```

Expected rows are `(1, page_view)`, `(2, checkout)`, and `(3, purchase)`, followed
by the `OK` line. All clients run in the containers, so verification does not
depend on a host port forward. On failure, inspect `docker compose ps` and
`docker compose logs --tail=100`.

`setup.sql` deliberately uses plain `CREATE` statements so rerunning setup on
existing tables fails visibly. For a clean repeat of the complete walkthrough,
reset both services as described below.

## Consumer groups and repeated delivery

The group `clickhouse-events-demo` stores its committed offsets in Redpanda.
Restarting the services with their volumes resumes from those offsets; it does
not replay the fixture automatically. Consumers sharing a group divide its
partitions, while a different group consumes independently.

Delivery through the Kafka engine and materialized view can repeat messages after
failures or retries. This `MergeTree` table does not deduplicate them. Producing the
fixture again deliberately appends another three rows, so the exact-count check
assumes one production of the fixture into a fresh stack. Query `events`, not
`events_queue`: the Kafka table is a consuming source for the materialized view.

## Stop and reset

`docker compose stop` preserves the volumes for `docker compose start`. To remove
the entire example and rerun it from empty state:

```sh
docker compose down -v --remove-orphans
```

This deletes the recipe's broker messages, consumer offsets, and ClickHouse data.
The checked-in fixture and SQL remain.

## Managed production equivalent

Create a Redpanda ClickPipe into a ClickHouse Cloud service. With an authenticated
`clickhousectl`, an existing ClickHouse Cloud service, a Cloud-reachable Redpanda
broker/topic, and its credentials, the equivalent command is:

```sh
clickhousectl cloud clickpipe create kafka "$CLICKHOUSE_SERVICE_ID" \
  --name redpanda-events \
  --brokers "$REDPANDA_BROKERS" --topics events \
  --format JSONEachRow --kafka-type redpanda \
  --auth SCRAM-SHA-256 \
  --username "$REDPANDA_USERNAME" --password "$REDPANDA_PASSWORD" \
  --ca-certificate ./ca.crt \
  --database default --table events \
  --column "event_id:Int64" --column "name:String"
```

Choose authentication and CA settings for your production broker. The local
Compose hostname `redpanda:9092` is not reachable from ClickHouse Cloud. Configure
the broker's network access for ClickPipes, use a separate Cloud destination, and
produce the same `events.jsonl` fixture to verify the three rows there. This managed
path is separate from the local walkthrough and requires Cloud resources; creating
a service alone does not configure ingestion.

- [ClickPipes connectors](https://clickhouse.com/cloud/clickpipes)
- [clickhousectl Redpanda ClickPipe command](https://clickhouse.com/blog/clickhousectl-v0-2-0-postgres-clickpipes-more)
- [ClickHouse Kafka engine](https://clickhouse.com/docs/reference/engines/table-engines/integrations/kafka)
- [Redpanda single-broker container example](https://docs.redpanda.com/labs/docker-compose/single-broker/)
- [Redpanda Kafka client compatibility](https://docs.redpanda.com/streaming/current/develop/kafka-clients/)
