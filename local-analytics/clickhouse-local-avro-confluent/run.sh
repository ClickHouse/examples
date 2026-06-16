#!/usr/bin/env bash
# The exact commands from the article "Read Avro from a schema registry with clickhouse-local".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Read a plain .avro file (schema embedded, no declaration) =="
clickhouse local -q "SELECT * FROM file('events.avro') FORMAT PrettyCompact"

echo
echo "== 2. See the schema clickhouse local read from the file =="
clickhouse local -q "DESCRIBE file('events.avro')"

echo
echo "== 3. Aggregate directly on the Avro file =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount), 2) AS total
FROM file('events.avro')
GROUP BY country
ORDER BY country
FORMAT PrettyCompact"

echo
echo "== 4. Plain Avro vs the Confluent wire format: the first bytes differ =="
echo "Plain Avro Object Container File starts with the magic 'Obj\\x01':"
clickhouse local -q "SELECT hex(substring(file('events.avro', 'RawBLOB'), 1, 4)) AS magic_hex"
echo "(A Confluent wire-format message instead starts with a 0x00 magic byte"
echo " followed by a 4-byte big-endian schema id, then the Avro body.)"

echo
echo "== 5. AvroConfluent on a plain .avro file fails on the magic byte (expected) =="
echo "This proves the two framings are NOT interchangeable:"
clickhouse local -q "SELECT * FROM file('events.avro', 'AvroConfluent') SETTINGS format_avro_schema_registry_url='http://localhost:8081'" 2>&1 | head -3 || true

echo
echo "== 6. The AvroConfluent command form (requires a RUNNING Schema Registry) =="
echo "Against real Confluent-framed messages, point clickhouse local at the registry:"
cat <<'CMD'
clickhouse local -q "
SELECT *
FROM file('messages.bin', 'AvroConfluent')
SETTINGS format_avro_schema_registry_url = 'http://schema-registry:8081'"
CMD
echo "(Not run here: there is no live registry in this folder. The error in step 5"
echo " is exactly what you would see if you aimed AvroConfluent at a plain .avro file.)"

echo
echo "== 7. Perf: group-by over the 3M-row, ~62 MB events_large.avro (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(amount),2) AS total, round(avg(amount),3) AS avg_amt FROM file('events_large.avro') GROUP BY country ORDER BY total DESC"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"
