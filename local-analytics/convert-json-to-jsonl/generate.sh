#!/usr/bin/env bash
# Generate sample JSON (top-level array) files locally with clickhouse local, so
# nothing large is committed to git. Writes into ./data/ (gitignored):
#   data/events.json        - small array, nested object + nested array (worked example)
#   data/events_large.json  - large array (the perf number)
#
# clickhouse local's FORMAT JSONEachRow emits one object per line (JSONL), not a
# top-level array. To synthesise a genuine "[ {...}, {...} ]" input file we first
# write the rows as JSONEachRow, then fold those lines into one array. The folding
# is done in modest chunks so the large file never holds every row in memory.
# Idempotent: re-running overwrites.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-8}
LARGE_ROWS=${LARGE_ROWS:-2000000}

emit_rows() {  # $1 = row count, $2 = seeded? (1) or sequential (0)
  local n="$1" seeded="$2"
  if [[ "$seeded" == "1" ]]; then
    clickhouse local -q "
    SELECT
      number + 1                                                            AS id,
      ['login','purchase','view','logout'][(rand(1) % 4) + 1]               AS event,
      ['GB','US','DE','FR','IN','AU','BR','JP'][(rand(2) % 8) + 1]          AS country,
      round((rand(3) % 50000) / 100.0, 2)                                  AS amount,
      map('name', ['Ada','Linus','Grace','Dennis'][(rand(4) % 4) + 1],
          'tier', ['free','pro','enterprise'][(rand(5) % 3) + 1])           AS user,
      range(toUInt64(rand(6) % 3) + 1)                                      AS items
    FROM numbers($n) FORMAT JSONEachRow"
  else
    clickhouse local -q "
    SELECT
      number + 1                                                            AS id,
      ['login','purchase','view','logout'][(number % 4) + 1]                AS event,
      ['GB','US','DE','FR'][(number % 4) + 1]                               AS country,
      round(((number % 50) + 1) + (number % 100) / 100.0, 2)               AS amount,
      map('name', ['Ada','Linus','Grace','Dennis'][(number % 4) + 1],
          'tier', ['free','pro','free','enterprise'][(number % 4) + 1])     AS user,
      range(toUInt64(number % 3) + 1)                                       AS items
    FROM numbers($n) FORMAT JSONEachRow"
  fi
}

# Wrap a stream of JSONEachRow lines into a single top-level JSON array on stdout.
# sed adds a leading two-space indent and a trailing comma to every line; the last
# comma is stripped, then the whole thing is bracketed. Streams line-by-line, so
# memory stays flat regardless of row count.
fold_to_array() {
  printf '[\n'
  sed 's/^/  /; s/$/,/' | sed '$ s/,$//'
  printf ']\n'
}

echo "Generating data/events.json ($SMALL_ROWS rows, top-level array)..."
emit_rows "$SMALL_ROWS" 0 | fold_to_array > data/events.json

echo "Generating data/events_large.json ($LARGE_ROWS rows, top-level array)..."
emit_rows "$LARGE_ROWS" 1 | fold_to_array > data/events_large.json

echo
echo "Generated files:"
ls -la data
echo
echo "Preview data/events.json:"
head -c 400 data/events.json; echo
