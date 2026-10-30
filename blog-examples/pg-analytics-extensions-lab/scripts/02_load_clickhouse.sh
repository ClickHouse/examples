#!/usr/bin/env bash
# Copy the Postgres heap tables into ClickHouse MergeTree with the postgresql() table function.
# (In production this would be continuous CDC, e.g. ClickPipes for Postgres; a one-shot copy is enough here.)
set -euo pipefail
source "$(dirname "$0")/env.sh"
CH="docker exec -i lab-ch clickhouse-client --password lab --time"
$CH --multiquery < $LAB/sql/ch_schema.sql
echo "events load:"; $CH -q "INSERT INTO lab.events SELECT * FROM postgresql('lab-pgch:5432', 'postgres', 'events', 'postgres', 'lab')"
echo "users load:";  $CH -q "INSERT INTO lab.users  SELECT * FROM postgresql('lab-pgch:5432', 'postgres', 'users',  'postgres', 'lab')"
$CH -q "OPTIMIZE TABLE lab.events FINAL"; $CH -q "OPTIMIZE TABLE lab.users FINAL"
$CH -q "SELECT table, sum(rows), formatReadableSize(sum(data_compressed_bytes)) AS compressed, formatReadableSize(sum(data_uncompressed_bytes)) AS uncompressed, count() AS parts FROM system.parts WHERE database='lab' AND active GROUP BY table FORMAT PrettyCompactMonoBlock"
psql_c lab-pgch -f /lab/sql/pgch_setup.sql
