#!/usr/bin/env bash
# Generate sample files with a CUSTOM field/row delimiter, locally, with
# clickhouse local. Nothing large is committed (data/ is gitignored).
#   data/orders.txt       - small worked example, fields separated by |~| , header row
#   data/orders.txt.gz    - gzipped copy, to show transparent decompression
#   data/orders_pipe.txt  - custom field AND row delimiter, no header
#   data/orders_large.txt - perf file, ~3,000,000 rows, |~| delimited
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-12}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# The custom field delimiter used throughout: |~| (a multi-char separator no
# CSV/TSV tool would split on). Escaping rule CSV so quoted fields are honoured.
DELIM='|~|'

echo "Generating data/orders.txt ($SMALL_ROWS rows, '$DELIM' delimited, with header)..."
clickhouse local -q "
SELECT
  number + 1                                                  AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]           AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]   AS product,
  round(((number % 90) + 5) + (number % 100) / 100.0, 2)      AS revenue,
  (number % 5 + 1)::UInt8                                      AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders.txt' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS format_custom_field_delimiter='$DELIM', format_custom_escaping_rule='CSV'
"

echo "Generating data/orders.txt.gz (gzipped copy)..."
clickhouse local -q "
SELECT
  number + 1                                                  AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]           AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]   AS product,
  round(((number % 90) + 5) + (number % 100) / 100.0, 2)      AS revenue,
  (number % 5 + 1)::UInt8                                      AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders.txt.gz' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS format_custom_field_delimiter='$DELIM', format_custom_escaping_rule='CSV'
"

echo "Generating data/orders_pipe.txt (custom field ' :: ' AND row ' ;;\\n', no header)..."
clickhouse local -q "
SELECT
  number + 1                                                  AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]           AS country,
  round(((number % 90) + 5) + (number % 100) / 100.0, 2)      AS revenue
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders_pipe.txt' TRUNCATE
FORMAT CustomSeparated
SETTINGS format_custom_field_delimiter=' :: ', format_custom_row_after_delimiter=' ;;\n', format_custom_escaping_rule='CSV'
"

echo "Generating data/orders_large.txt ($LARGE_ROWS rows, '$DELIM' delimited)..."
clickhouse local -q "
SELECT
  number + 1                                                                AS order_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]   AS country,
  ['widget','gadget','gizmo','doohickey','sprocket'][(rand(3) % 5) + 1]    AS product,
  round((rand(4) % 50000) / 100.0, 2)                                      AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                  AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/orders_large.txt' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS format_custom_field_delimiter='$DELIM', format_custom_escaping_rule='CSV'
"

echo
echo "Generated files:"
ls -la data
