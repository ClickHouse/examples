#!/usr/bin/env bash
# Generate the sample semicolon-separated files locally with clickhouse local,
# so nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/orders.csv        - 20 rows, header + ';' delimiter, dot decimals (the worked example)
#   data/orders_eu.csv     - 5 rows, ';' delimiter with EUROPEAN decimal commas (the gotcha)
#   data/orders_large.csv  - 3,000,000 rows, ~110 MB, ';' delimiter (the perf number)
# Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

# ';' delimited, unquoted, with a header row (CustomSeparatedWithNames + CSV escaping)
SEMI="format_custom_field_delimiter = ';', format_custom_escaping_rule = 'CSV', format_custom_row_after_delimiter = '\n'"

echo "Generating data/orders.csv ($SMALL_ROWS rows, ';' delimited)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (number % 31)                          AS order_date,
  number + 1                                                    AS order_id,
  ['GB','US','DE','FR','IN','AU'][(number % 6) + 1]             AS country,
  ['widget','gadget','gizmo','doohickey'][(number % 4) + 1]     AS product,
  round(((number % 500) + 5) + (number % 100) / 100.0, 2)       AS revenue,
  (number % 5 + 1)::UInt8                                       AS quantity
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/orders.csv' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS $SEMI
"
# clickhouse local writes CSV-escaped strings quoted; strip the surrounding quotes
# to mimic a typical plain export from a European spreadsheet (unquoted text).
sed -i '' 's/"//g' data/orders.csv

echo "Generating data/orders_eu.csv (5 rows, ';' delimited, EUROPEAN decimal commas)..."
cat > data/orders_eu.csv <<'EOF'
order_date;order_id;country;product;revenue;quantity
2026-01-01;1;DE;widget;1234,50;1
2026-01-02;2;FR;gadget;6,01;2
2026-01-03;3;NL;gizmo;7,02;3
2026-01-04;4;DE;doohickey;89,99;4
2026-01-05;5;FR;widget;1000,00;5
EOF

echo "Generating data/orders_large.csv ($LARGE_ROWS rows, ~110 MB, ';' delimited)..."
clickhouse local -q "
SELECT
  toDate('2026-01-01') + (rand(1) % 365)                                   AS order_date,
  number + 1                                                               AS order_id,
  ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1]  AS country,
  ['widget','gadget','gizmo','doohickey','sprocket'][(rand(3) % 5) + 1]    AS product,
  round((rand(4) % 50000) / 100.0, 2)                                      AS revenue,
  (rand(5) % 5 + 1)::UInt8                                                  AS quantity
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/orders_large.csv' TRUNCATE
FORMAT CustomSeparatedWithNames
SETTINGS $SEMI
"
sed -i '' 's/"//g' data/orders_large.csv

echo
echo "Generated files:"
ls -la data
