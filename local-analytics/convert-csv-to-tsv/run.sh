#!/usr/bin/env bash
# The exact commands from the article "How to convert CSV to TSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert CSV -> TSV in one line (header kept) =="
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders.tsv' TRUNCATE FORMAT TSVWithNames"
head -5 orders.tsv

echo
echo "== 2. The header is preserved by TSVWithNames =="
clickhouse local -q "DESCRIBE file('orders.tsv', 'TSVWithNames')"

echo
echo "== 3. Drop the header: FORMAT TSV writes data rows only =="
clickhouse local -q "SELECT * FROM file('orders.csv') INTO OUTFILE 'orders_noheader.tsv' TRUNCATE FORMAT TSV"
head -3 orders_noheader.tsv

echo
echo "== 4. Tab and comma handling: convert notes.csv and inspect the bytes =="
clickhouse local -q "SELECT * FROM file('notes.csv') INTO OUTFILE 'notes.tsv' TRUNCATE FORMAT TSVWithNames"
echo "-- raw TSV bytes (note the comma stays literal, the embedded tab becomes \\t) --"
od -c notes.tsv
echo "-- read it back: the original tab is restored, round-trip is lossless --"
clickhouse local -q "SELECT * FROM file('notes.tsv') FORMAT Vertical"

echo
echo "== 5. Perf: convert the ~3M-row orders_large.csv to TSV (best-of-3, warm) =="
clickhouse local -q "SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large.tsv' TRUNCATE FORMAT TSVWithNames"  # warm
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "SELECT * FROM file('orders_large.csv') INTO OUTFILE 'orders_large.tsv' TRUNCATE FORMAT TSVWithNames" 2> /tmp/_tsv_time.txt
  echo "run $i: $(grep real /tmp/_tsv_time.txt)"
done
echo "rows written: $(clickhouse local -q "SELECT count() FROM file('orders_large.tsv', 'TSVWithNames')")"
ls -la orders_large.csv orders_large.tsv

echo
echo "== 6. chDB (Python) equivalent — same SELECT ... FORMAT, written to a file =="
python3 ../run.py
