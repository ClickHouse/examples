#!/usr/bin/env bash
# The exact commands from the article "How to convert Arrow to CSV".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

echo "== 1. Convert Arrow -> CSV in one line (header from the embedded schema) =="
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events.csv' TRUNCATE FORMAT CSVWithNames"
head -n 8 events.csv

echo
echo "== 2. The schema came from the Arrow file itself (no structure supplied) =="
clickhouse local -q "DESCRIBE file('events.arrow')"

echo
echo "== 3. Nested Array column flattens to a quoted JSON-ish string in CSV (the gotcha) =="
clickhouse local -q "SELECT event_id, tags FROM file('events.arrow') LIMIT 3"
echo "-> in events.csv the tags column becomes:"
clickhouse local -q "SELECT event_id, tags FROM file('events.csv') LIMIT 3"

echo
echo "== 4. No header? Use FORMAT CSV instead of CSVWithNames =="
clickhouse local -q "SELECT * FROM file('events.arrow') INTO OUTFILE 'events_noheader.csv' TRUNCATE FORMAT CSV"
head -n 3 events_noheader.csv

echo
echo "== 5. Transform during conversion: project, filter, aggregate =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount),2) AS total
FROM file('events.arrow')
GROUP BY country
ORDER BY total DESC
INTO OUTFILE 'by_country.csv' TRUNCATE FORMAT CSVWithNames"
cat by_country.csv

echo
echo "== 6. Perf: convert the 3,000,000-row events_large.arrow (~63 MB) -> CSV (best-of-3, warm) =="
Q="SELECT * FROM file('events_large.arrow') INTO OUTFILE 'events_large.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "$Q" > /dev/null   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_arrow_time.txt
  echo "run $i: $(grep real /tmp/_arrow_time.txt)"
done
echo "rows written:"
clickhouse local -q "SELECT count() FROM file('events_large.csv')"
