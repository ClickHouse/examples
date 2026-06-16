#!/usr/bin/env bash
# Generate a sample NGINX/Apache-style access log locally with clickhouse local,
# so nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/access.log        - 20 lines, the worked example
#   data/access.log.gz     - gzipped copy, to show transparent .log.gz reads
#   data/access_large.log  - 2,000,000 lines, ~163 MB (the perf number)
# Idempotent: TRUNCATE overwrites on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-2000000}

# Build one combined-log line per row. We synthesise typed fields, then format()
# them into the exact text layout a real web server emits, and write the single
# resulting string column out as raw lines (TSVRaw, one column = no escaping).
LINE_SQL='
format(
  '\''{} - - [{}] "{} {} HTTP/1.1" {} {} {}'\'',
  ['\''192.168.1.10'\'','\''10.0.0.5'\'','\''172.16.0.9'\'','\''203.0.113.7'\'','\''198.51.100.2'\''][(rand(1) % 5) + 1],
  formatDateTime(toDateTime('\''2026-06-06 10:00:00'\'') + (rand(2) % 86400), '\''%d/%b/%Y:%H:%i:%s'\'') || '\'' +0000'\'',
  ['\''GET'\'','\''GET'\'','\''GET'\'','\''POST'\'','\''PUT'\'','\''DELETE'\''][(rand(3) % 6) + 1],
  ['\''/index.html'\'','\''/api/login'\'','\''/api/orders'\'','\''/static/app.js'\'','\''/health'\'','\''/cart'\''][(rand(4) % 6) + 1],
  ([200,200,200,200,301,404,401,500][(rand(5) % 8) + 1])::String,
  ((rand(6) % 9000) + 100)::String,
  toString(round((rand(7) % 2000) / 1000.0, 3))
)'

echo "Generating data/access.log ($SMALL_ROWS lines)..."
clickhouse local -q "
SELECT $LINE_SQL AS line
FROM numbers($SMALL_ROWS)
INTO OUTFILE 'data/access.log' TRUNCATE FORMAT TSVRaw
"

echo "Generating data/access_large.log ($LARGE_ROWS lines, ~163 MB)..."
clickhouse local -q "
SELECT $LINE_SQL AS line
FROM numbers($LARGE_ROWS)
INTO OUTFILE 'data/access_large.log' TRUNCATE FORMAT TSVRaw
"

echo "Generating data/access.log.gz..."
clickhouse local -q "SELECT line FROM file('data/access.log', LineAsString) INTO OUTFILE 'data/access.log.gz' TRUNCATE FORMAT TSVRaw"

echo
echo "Generated files:"
ls -la data
echo
echo "First 3 lines of data/access.log:"
head -n 3 data/access.log
