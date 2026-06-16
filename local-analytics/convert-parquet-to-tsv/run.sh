#!/usr/bin/env bash
# The exact commands from the article "How to convert Parquet to TSV".
# Run ./generate.sh first to create the sample Parquet in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Parquet -> TSV in one line =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events.tsv' TRUNCATE FORMAT TSV"
head -5 events.tsv

echo
echo "== 2. Inspect the Parquet schema (types carried from the footer) =="
clickhouse local -q "DESCRIBE file('events.parquet')"

echo
echo "== 3. Keep the column names: TSVWithNames writes a header row =="
clickhouse local -q "SELECT * FROM file('events.parquet') INTO OUTFILE 'events_named.tsv' TRUNCATE FORMAT TSVWithNames"
head -3 events_named.tsv

echo
echo "== 4. Read the TSV back: types re-inferred, the array survives the round-trip =="
clickhouse local -q "DESCRIBE file('events_named.tsv', 'TSVWithNames')"
clickhouse local -q "SELECT tags, length(tags) AS n FROM file('events_named.tsv', 'TSVWithNames') LIMIT 3"

echo
echo "== 5. Flatten the nested array to one tag per row before export =="
clickhouse local -q "SELECT event_id, country, arrayJoin(tags) AS tag FROM file('events.parquet') ORDER BY event_id LIMIT 5 FORMAT TSV"

echo
echo "== 6. Perf: convert the 3M-row events_large.parquet -> TSV (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.tsv' TRUNCATE FORMAT TSV"  # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.parquet') INTO OUTFILE 'events_large.tsv' TRUNCATE FORMAT TSV" > /dev/null 2> /tmp/_p2t_time.txt
  echo "run $i: $(grep real /tmp/_p2t_time.txt)"
done
echo "rows: $(clickhouse local -q "SELECT count() FROM file('events_large.tsv', 'TSV')")"
echo "tsv size: $(ls -lh events_large.tsv | awk '{print $5}')"
