#!/usr/bin/env bash
set -euo pipefail
#
# Run Snowflake benchmark and emit a JSON doc with runtimes.
# Usage:
#   ./run.sh <schema> <db> <warehouse> <machine> <cluster_size> [outfile]
# Example:
#   ./run.sh PUBLIC HITS TEST "XS" 1 results/snowflake.json
#
# Requires:
#   - Env: SNOWSQL_ACCOUNT, SNOWSQL_USER, SNOWSQL_PWD
#   - File: queries.sql (SQL statements end with ';')
#
# Notes:
#   - Region is intentionally NOT passed to snowsql.
#   - Times are extracted from "Time Elapsed: <secs>s".
#   - Writes JSON to stdout and saves to results/… (and /results if available).
# ---------------------------------------------------------------------------

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <schema> <db> <warehouse> <machine> <cluster_size> [outfile]" >&2
  exit 1
fi

SCHEMA="$1"
DBNAME="$2"
WAREHOUSE="$3"
MACHINE="$4"
CLUSTER_SIZE="$5"         # must be an integer
OUTFILE="${6:-}"

# --- Required env ---
: "${SNOWSQL_ACCOUNT:?Set SNOWSQL_ACCOUNT}"
: "${SNOWSQL_USER:?Set SNOWSQL_USER}"
: "${SNOWSQL_PWD:?Set SNOWSQL_PWD}"

TRIES=3

# JSON metadata
SYSTEM="Snowflake"
PROPRIETARY="yes"
TUNED="no"
TAGS='["managed","column-oriented"]'
LOAD_TIME=0
DATA_SIZE=0
COMMENT=""

# Common snowsql args (no --region here, by design)
ARGS=(--dbname "$DBNAME" --schemaname "$SCHEMA" --warehouse "$WAREHOUSE"
      -o timing=true -o exit_on_error=true -o quiet=false)

command -v snowsql >/dev/null 2>&1 || { echo "snowsql not found in PATH" >&2; exit 1; }
[[ -f queries.sql ]] || { echo "queries.sql not found" >&2; exit 1; }

echo "→ Checking connection ..." >&2
snowsql "${ARGS[@]}" --query "SELECT 1" >/dev/null

echo "→ Disabling result cache for user ${SNOWSQL_USER}..." >&2
snowsql "${ARGS[@]}" --query "ALTER USER ${SNOWSQL_USER} SET USE_CACHED_RESULT = false;" >/dev/null

# --- Parse queries.sql by semicolons ---
mapfile -t QUERIES < <(
  awk 'BEGIN { RS=";"; ORS="" } { q=$0; gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", q); if (length(q)) print q "\n" }' queries.sql
)
TOTAL=${#QUERIES[@]}
echo "→ Found ${TOTAL} queries" >&2
(( TOTAL > 0 )) || { echo "No queries found" >&2; exit 1; }

mkdir -p results /results 2>/dev/null || true

# --- Run benchmark ---
RESULT_RAW="$(
QUERY_NUM=1
for query in "${QUERIES[@]}"; do
  echo "→ Running query #$QUERY_NUM..." >&2
  echo -n "["
  ARR=()
  for i in $(seq 1 "$TRIES"); do
    out="$(snowsql "${ARGS[@]}" --query "$query" 2>&1 || true)"
    val="$(printf "%s\n" "$out" | grep -Eo 'Time Elapsed:[[:space:]]*[0-9.]+s' | sed -E 's/.* ([0-9.]+)s/\1/' | tail -n1)"
    [[ -z "$val" ]] && val="null"
    ARR+=("$val")
    echo -n "$val"
    [[ "$i" != "$TRIES" ]] && echo -n ","
  done
  echo "],"
  echo "   -> [${ARR[*]}]" >&2
  QUERY_NUM=$((QUERY_NUM + 1))
done
)"

# Clean trailing comma
RESULT_CLEAN="$(printf "%s\n" "$RESULT_RAW" | sed '$ s/,\s*$//')"
DATE_ISO="$(date -u +%F)"

JSON_DOC="$(cat <<JSON
{
  "system": "$SYSTEM",
  "date": "$DATE_ISO",
  "machine": "$MACHINE",
  "cluster_size": $CLUSTER_SIZE,
  "comment": "$COMMENT",
  "proprietary": "$PROPRIETARY",
  "tuned": "$TUNED",
  "tags": $TAGS,
  "load_time": $LOAD_TIME,
  "data_size": $DATA_SIZE,
  "result": [
$RESULT_CLEAN
  ]
}
JSON
)"

# Emit JSON to stdout
printf "%s\n" "$JSON_DOC"

# Save JSON
if [[ -n "$OUTFILE" ]]; then
  printf "%s\n" "$JSON_DOC" > "$OUTFILE"
  echo "→ Wrote JSON: $OUTFILE" >&2
else
  OUTNAME="results/snowflake_${DATE_ISO}_${MACHINE// /_}.json"
  printf "%s\n" "$JSON_DOC" > "$OUTNAME"
  echo "→ Wrote JSON: $OUTNAME" >&2
fi
