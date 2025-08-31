#!/bin/bash
set -euo pipefail

# Usage: ./run_updates.sh [1|2|20] [COLD|HOT] [BULK|POINT]
PART_NUM="${1:-}"
TEMP="${2:-HOT}"
GRANULARITY="${3:-POINT}"   # BULK or POINT

if [[ "$PART_NUM" != "1" && "$PART_NUM" != "2" && "$PART_NUM" != "20" ]]; then
  echo "Usage: $0 [1|2|20] [COLD|HOT] [BULK|POINT]"
  echo "PART_NUM must be 1, 2, or 20"
  exit 1
fi

shopt -s nocasematch
case "$TEMP" in
  COLD|cold) CLEAR_CACHES=true;  TEMP_CANON="COLD" ;;
  HOT|hot)   CLEAR_CACHES=false; TEMP_CANON="HOT"  ;;
  *) echo "Second parameter must be COLD or HOT"; exit 1 ;;
esac

case "$GRANULARITY" in
  BULK|bulk)   SQL_UPDATES_FILE="updates-bulk.sql";  GRAN_CANON="BULK"  ;;
  POINT|point) SQL_UPDATES_FILE="updates-point.sql"; GRAN_CANON="POINT" ;;
  *) echo "Third parameter must be BULK or POINT"; exit 1 ;;
esac
shopt -u nocasematch

# Defaults
# N=${N:-3}                        # repetitions per step
N=${N:-1}                        # repetitions per step
MODE="sequential"
METHOD_NAME="lightweight updates"
TABLE_NAME="lineitem"
BASE_TABLE="lineitem_base_tbl_${PART_NUM}part"
CLICKHOUSE_CLIENT="clickhouse-client"
CLIENT_FLAGS="--allow_experimental_lightweight_update=1"

# Paths
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
RESULT_DIR="${SCRIPT_DIR}/../results"   # sibling of the current folder
mkdir -p "$RESULT_DIR"
JSON_FILE="${RESULT_DIR}/update_timings_${MODE}_lightweight_p${PART_NUM}_${TEMP_CANON}_${GRAN_CANON}.json"

ANALYTICAL_SQL_FILE="analytical_queries.sql"

# --- Helpers ---
clear_caches_if_cold() {
  if $CLEAR_CACHES; then
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
  fi
}

run_with_time() {
  local sql="$1"
  local out rc elapsed
  # Capture BOTH streams; don't print results to console
  out=$($CLICKHOUSE_CLIENT $CLIENT_FLAGS --time --progress 0 --query="$sql" 2>&1)
  rc=$?

  # Prefer labeled format: "Elapsed: 0.123 sec."
  elapsed=$(printf '%s\n' "$out" \
    | sed -n 's/.*Elapsed: \([0-9][0-9]*\(\.[0-9]\+\)\?\) sec.*/\1/p' \
    | tail -n 1)

  # Fallback: bare float on its own line (e.g. "0.036")
  if [[ -z "$elapsed" ]]; then
    elapsed=$(printf '%s\n' "$out" \
      | grep -E '^[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*$' \
      | awk '{print $1}' \
      | tail -n 1)
  fi

  if [[ $rc -ne 0 || -z "$elapsed" ]]; then
    echo "❌ clickhouse-client failed or no timing found for SQL:" >&2
    echo "---- client output (tail) ----" >&2
    printf '%s\n' "$out" | tail -n 20 >&2
    echo "------------------------------" >&2
    return 1
  fi
  echo "$elapsed"
}

# --- Load SQLs ---
[[ -f "$SQL_UPDATES_FILE" ]] || { echo "Missing $SQL_UPDATES_FILE"; exit 1; }
[[ -f "$ANALYTICAL_SQL_FILE" ]] || { echo "Missing $ANALYTICAL_SQL_FILE"; exit 1; }

# Each statement should be on its own line
mapfile -t updates < <(cat "$SQL_UPDATES_FILE"; echo)
mapfile -t queries < <(cat "$ANALYTICAL_SQL_FILE"; echo)

if [[ ${#updates[@]} -ne ${#queries[@]} ]]; then
  echo "Mismatch between number of updates (${#updates[@]}) and queries (${#queries[@]})"
  exit 1
fi

echo "Running ${METHOD_NAME} (${GRAN_CANON}, ${TEMP_CANON}) on PART_NUM=${PART_NUM}..."


echo "Preparing table: ${TABLE_NAME}"
$CLICKHOUSE_CLIENT --query="DROP TABLE IF EXISTS ${TABLE_NAME};"
$CLICKHOUSE_CLIENT --query="CREATE TABLE ${TABLE_NAME} CLONE AS ${BASE_TABLE};"
$CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING enable_block_number_column = 1, enable_block_offset_column = 1;"
$CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1;"


timings_updates=()
timings_queries=()

for ((i = 0; i < ${#updates[@]}; i++)); do
  update="${updates[$i]}"
  query="${queries[$i]}"
  echo "⚙️  Step $((i + 1))"

  # Avg update time over N runs (reset table before each)
  total_update_time=0
  for run in $(seq 1 $N); do

    clear_caches_if_cold

    echo "    ▶️  Update run #$run"
    elapsed_update=$(run_with_time "$update")
    echo "       ⏱️  ${elapsed_update}s"
    total_update_time=$(echo "$total_update_time + $elapsed_update" | bc)
  done
  avg_update_time=$(echo "scale=9; $total_update_time / $N" | bc)
  echo "    📊 Avg update time: ${avg_update_time}s"
  timings_updates+=("$avg_update_time")

  # Avg query time over N runs (using run_with_time)
  total_query_time=0
  for run in $(seq 1 $N); do
    clear_caches_if_cold
    echo "    ▶️  Query run #$run"
    elapsed_query=$(run_with_time "$query")
    echo "       ⏱️  ${elapsed_query}s"
    total_query_time=$(echo "$total_query_time + $elapsed_query" | bc)
  done
  avg_query_time=$(echo "scale=9; $total_query_time / $N" | bc)
  echo "    📊 Avg query time: ${avg_query_time}s"
  timings_queries+=("$avg_query_time")
done

# Totals
timings_updates_total=$(printf "%s\n" "${timings_updates[@]}" | paste -sd+ - | bc)
timings_queries_total=$(printf "%s\n" "${timings_queries[@]}" | paste -sd+ - | bc)
duration_total=$(echo "$timings_updates_total + $timings_queries_total" | bc)

# JSON output
{
  echo "{"
  echo "  \"mode\": \"${MODE}\","
  echo "  \"method\": \"${METHOD_NAME}\","
  echo "  \"part_num\": ${PART_NUM},"
  echo "  \"temperature\": \"${TEMP_CANON}\","
  echo "  \"update_granularity\": \"${GRAN_CANON}\","
  echo "  \"N\": ${N},"
  echo "  \"timings_updates\": ["
  for ((j = 0; j < ${#timings_updates[@]}; j++)); do
    sep=$([[ $j -lt $((${#timings_updates[@]} - 1)) ]] && echo "," || echo "")
    printf "    %.9f%s\n" "${timings_updates[j]}" "$sep"
  done
  echo "  ],"
  echo "  \"timings_queries\": ["
  for ((j = 0; j < ${#timings_queries[@]}; j++)); do
    sep=$([[ $j -lt $((${#timings_queries[@]} - 1)) ]] && echo "," || echo "")
    printf "    %.9f%s\n" "${timings_queries[j]}" "$sep"
  done
  echo "  ],"
  printf "  \"timings_updates_total\": %.9f,\n" "$timings_updates_total"
  printf "  \"timings_queries_total\": %.9f,\n" "$timings_queries_total"
  printf "  \"duration_total\": %.9f\n" "$duration_total"
  echo "}"
} > "$JSON_FILE"

echo "✅ Done. Timings saved to $JSON_FILE"