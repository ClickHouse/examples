#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to Avro".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# Print the embedded Avro schema/codec from a file header. The Avro header
# stores its schema as plain JSON, so we read the first few KB and pull the
# matching line. Pipefail is disabled locally because `strings` receives
# SIGPIPE once the match is found, which is expected, not an error.
peek() { # peek <file> <grep-pattern>
  set +o pipefail
  strings "$1" | grep -A1 "avro.$2" | grep -E '^\{|deflate|snappy' || true
  set -o pipefail
}

echo "== 1. Convert CSV -> Avro in one line =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events.avro' TRUNCATE FORMAT Avro"
echo "wrote events.avro"

echo
echo "== 2. The inferred CSV schema (column names from the header, types from the data) =="
clickhouse local -q "DESCRIBE file('events.csv')"

echo
echo "== 3. The schema carried into Avro (read it straight back) =="
clickhouse local -q "DESCRIBE file('events.avro')"

echo
echo "== 4. The schema is embedded in the Avro header as JSON =="
peek events.avro schema

echo
echo "== 5. Read rows back from the Avro file =="
clickhouse local -q "SELECT * FROM file('events.avro') ORDER BY amount DESC LIMIT 5"

echo
echo "== 6. Pin the column types so the Avro schema has no null unions =="
clickhouse local -q "
SELECT * FROM file('events.csv', 'CSVWithNames',
  'event_date Date, event_id UInt32, country String, action String, amount Float64, items UInt8')
INTO OUTFILE 'events_typed.avro' TRUNCATE FORMAT Avro"
peek events_typed.avro schema

echo
echo "== 7. Choose the block compression codec (default is snappy) =="
clickhouse local -q "SELECT * FROM file('events.csv') INTO OUTFILE 'events_deflate.avro' TRUNCATE FORMAT Avro SETTINGS output_format_avro_codec='deflate'"
peek events_deflate.avro codec

echo
echo "== 8. Conversion throughput: 3,000,000-row, ~120 MB events_large.csv -> Avro (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.avro' TRUNCATE FORMAT Avro" # warm cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.csv') INTO OUTFILE 'events_large.avro' TRUNCATE FORMAT Avro" 2> /tmp/_avro_time.txt
  echo "run $i: $(grep real /tmp/_avro_time.txt)"
done
echo "row count round-trips:"
clickhouse local -q "SELECT count() FROM file('events_large.avro')"
ls -la events_large.csv events_large.avro
