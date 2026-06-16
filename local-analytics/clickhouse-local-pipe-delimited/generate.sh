#!/usr/bin/env bash
# Generate sample pipe-delimited (|) files locally with clickhouse local, so
# nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/orders.psv        - 20 rows, header row + "|" field delimiter (worked example)
#   data/orders_nohdr.psv  - same data, NO header row (shows the headerless variant)
#   data/orders_large.psv  - 3,000,000 rows, ~126 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# CustomSeparatedWithNames writes a header row + "|" between fields.
PIPE_SETTINGS="format_custom_field_delimiter='|', format_custom_escaping_rule='CSV'"

echo "Generating data/orders.psv ($SMALL_ROWS rows, with header)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                          AS order_date,
  number + 1                                                    AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]             AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]     AS product,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)       AS revenue,
  (number % 5 + 1)::UInt8                                       AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders.psv' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS $PIPE_SETTINGS
"

echo "Generating data/orders_nohdr.psv ($SMALL_ROWS rows, no header)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                          AS order_date,
  number + 1                                                    AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]             AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]     AS product,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)       AS revenue,
  (number % 5 + 1)::UInt8                                       AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders_nohdr.psv' TRUNCATE
FORMAT CustomSeparated
SETTINGS $PIPE_SETTINGS
"

echo "Generating data/orders_large.psv ($LARGE_ROWS rows, ~126 MB at 3M)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                   AS order_date,
  number + 1                                                               AS order_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]  AS country,
  ['widget','gadget','gizmo','doohickey','sprocket'][(rand(3) % 5) + 1]    AS product,
  round((rand(4) % 50000) / 100.0, 2)                                      AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                  AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/orders_large.psv' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS $PIPE_SETTINGS
"

echo
echo "Generated files:"
ls -la data
echo
echo "First 3 lines of data/orders.psv:"
head -n 3 data/orders.psv
