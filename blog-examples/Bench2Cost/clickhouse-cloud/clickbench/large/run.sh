#!/usr/bin/env bash
set -euo pipefail
#
# Run ClickHouse queries 3x each and emit a JSON doc with results.
# - Parses queries.sql by semicolons (not lines) to guarantee all queries run.
# - Keeps the original timing/grep pipeline intact.
# - Prints progress (stderr) and JSON (stdout).
#
# Usage:
#   ./run.sh <system> <machine_desc> <cluster_size> <base_comment> <parallel_replicas_flag>
# Example:
#   ./run.sh "ClickHouse Cloud (AWS)" "236GiB" 3 "1B rows" 0
# ---------------------------------------------------------------------------

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <system> <machine_desc> <cluster_size> <base_comment> <parallel_replicas_flag>" >&2
  exit 1
fi

SYSTEM="$1"
MACHINE="$2"
CLUSTER_SIZE="$3"
BASE_COMMENT="$4"
PARALLEL_FLAG="$5"  # 0 or 1

COMMENT="${BASE_COMMENT} (enable_parallel_replicas=${PARALLEL_FLAG})"
PROPRIETARY="yes"
TUNED="no"
TAGS='["C++","column-oriented","ClickHouse derivative","managed","aws"]'
LOAD_TIME=0
DATA_SIZE=0

# Client env
FQDN="${FQDN:=localhost}"
PASSWORD="${PASSWORD:=}"
EXTRA_SETTINGS="--enable_parallel_replicas=${PARALLEL_FLAG}"

TRIES=3

# --- Parse queries.sql by semicolons (trimmed, non-empty) ---
mapfile -t QUERIES < <(
  awk '
    BEGIN { RS=";"; ORS="" }
    {
      q=$0
      gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", q)  # trim leading/trailing whitespace
      if (length(q) > 0) print q "\n"
    }
  ' queries.sql
)

TOTAL=${#QUERIES[@]}
echo "Parsed queries: ${TOTAL}" >&2
if (( TOTAL == 0 )); then
  echo "ERROR: No queries found in queries.sql" >&2
  exit 1
fi

# --- Collect results using your ORIGINAL timing/grep pipeline ---
RESULT_RAW="$(
QUERY_NUM=1
for query in "${QUERIES[@]}"; do
    echo "Running query #$QUERY_NUM..." >&2
    echo -n "["
    ARRAY_VALUES=()
    for i in $(seq 1 $TRIES); do
        val=$(
          (clickhouse-client --host "${FQDN:=localhost}" --password "${PASSWORD:=}" ${PASSWORD:+--secure} \
            --time --format=Null --query="$query" --progress 0 ${EXTRA_SETTINGS} 2>&1 |
            grep -o -P '^\d+\.\d+$' || echo -n "null") | tr -d '\n'
        )
        ARRAY_VALUES+=("$val")
        echo -n "$val"
        [[ "$i" != $TRIES ]] && echo -n ", "
    done
    echo "],"
    echo "→ [${ARRAY_VALUES[*]}]" >&2
    QUERY_NUM=$((QUERY_NUM + 1))
done
)"

# Make valid JSON arrays (drop trailing comma)
RESULT_CLEAN="$(printf "%s\n" "$RESULT_RAW" | sed '$ s/,\s*$//')"

DATE_ISO="$(date -u +%F)"

cat <<JSON
{
    "system": "$SYSTEM",
    "date": "$DATE_ISO",
    "machine": "$MACHINE",
    "cluster_size": $CLUSTER_SIZE,
    "proprietary": "$PROPRIETARY",
    "tuned": "$TUNED",
    "comment": "$COMMENT",

    "tags": $TAGS,

    "load_time": $LOAD_TIME,
    "data_size": $DATA_SIZE,

    "result": [
$RESULT_CLEAN
    ]
}
JSON