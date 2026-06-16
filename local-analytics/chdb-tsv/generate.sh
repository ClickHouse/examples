#!/usr/bin/env bash
# Generate the sample TSV files used by the read-tsv-file-python how-to.
# Everything is created locally with `clickhouse local` so nothing large is
# committed to git. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-6}
LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data

# 1. Small TSV WITH a header row (TSVWithNames). Note the product name in row 2
#    contains a comma — harmless in TSV because the delimiter is a tab.
cat > data/events.tsv <<'TSV'
event_id	country	event_type	revenue	product
1	GB	purchase	49.99	Widget, Deluxe
2	AU	view	0	Gadget
3	GB	purchase	19.50	Widget
4	IN	purchase	5.00	Bolt
5	AU	purchase	99.00	Gizmo
6	IN	view	0	Bolt
TSV

# 2. The same data WITHOUT a header (plain TSV) to show the structure argument.
clickhouse local -q "
SELECT event_id, country, event_type, revenue, product
FROM file('data/events.tsv', TSVWithNames,
          'event_id UInt32, country String, event_type String, revenue Float64, product String')
INTO OUTFILE 'data/events_noheader.tsv' TRUNCATE FORMAT TSV
"

# 3. A larger TSV (default 3M rows, ~70 MB) for the performance contrast.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1] AS country,
  ['purchase','view'][(number % 2) + 1] AS event_type,
  round(randUniform(1, 100), 2) AS revenue,
  ['Widget','Gadget','Bolt','Gizmo'][(number % 4) + 1] AS product
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events_large.tsv' TRUNCATE FORMAT TSVWithNames
"

echo "Generated:"
ls -lh data
