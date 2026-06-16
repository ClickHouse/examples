#!/usr/bin/env bash
# The exact commands from the article "How to convert TSV to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert TSV -> CSV in one line (header carried over) =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
echo "wrote events.csv"

echo
echo "== 2. Look at the result (first 6 lines: header + 5 rows) =="
head -n 6 events.csv

echo
echo "== 3. Confirm the schema survived the round trip (types inferred from the TSV header) =="
clickhouse local -q "DESCRIBE file('events.csv')"

echo
echo "== 4. Convert with NO header row in the output (plain CSV) =="
clickhouse local -q "SELECT * FROM file('events.tsv') INTO OUTFILE 'events_noheader.csv' TRUNCATE FORMAT CSV"
head -n 3 events_noheader.csv

echo
echo "== 5. Project / rename / cast columns during the conversion =="
clickhouse local -q "
SELECT
  event_date,
  upper(country)        AS country_code,
  amount::Decimal(10,2) AS amount
FROM file('events.tsv')
INTO OUTFILE 'events_clean.csv' TRUNCATE FORMAT CSVWithNames"
head -n 4 events_clean.csv

echo
echo "== 6. Row counts match (no data lost) =="
echo "TSV rows: $(clickhouse local -q "SELECT count() FROM file('events.tsv')")"
echo "CSV rows: $(clickhouse local -q "SELECT count() FROM file('events.csv')")"

echo
echo "== 7. Perf: convert the 3M-row, ~106 MB events_large.tsv -> CSV (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('events_large.tsv') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames" # warm cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('events_large.tsv') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames" 2> /tmp/_tsv_time.txt
  echo "run $i: $(grep real /tmp/_tsv_time.txt)"
done
ls -la events_large.csv
