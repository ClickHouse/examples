#!/bin/bash
set -euo pipefail

METHOD="${1:-}"
INPUT_DIR="${2:-}"
PART_NUM="${3:-}"

if [[ "$METHOD" != "mutation" && "$METHOD" != "mutations_on_fly" && "$METHOD" != "lightweight" ]]; then
    echo "Usage: $0 [mutation|mutations_on_fly|lightweight] [SMALL|LARGE][1|2|20]"
    exit 1
fi

if [[ "$INPUT_DIR" != "SMALL" && "$INPUT_DIR" != "LARGE" ]]; then
    echo "INPUT_DIR must be either 'SMALL' or 'LARGE'"
    exit 1
fi

if [[ "$PART_NUM" != "1" && "$PART_NUM" != "2" && "$PART_NUM" != "20" ]]; then
    echo "PART_NUM must be 1 or 2 or 20"
    exit 1
fi

MODE="parallel"
TABLE_NAME="lineitem"
BASE_TABLE="lineitem_base_tbl_${PART_NUM}part"
CLICKHOUSE_CLIENT="clickhouse-client"
QUERY_DIR="./${INPUT_DIR}"
RESULT_DIR="results"
mkdir -p "$RESULT_DIR"
JSON_FILE="${RESULT_DIR}/update_timings_${MODE}_${METHOD}_${INPUT_DIR}_${PART_NUM}part.json"

# Method-specific setup
if [[ "$METHOD" == "mutation" ]]; then
    SQL_FILE="${QUERY_DIR}/mutation_updates.sql"
    CLIENT_FLAGS="--mutations_sync=0"
    METHOD_NAME="mutation updates"
elif [[ "$METHOD" == "mutations_on_fly" ]]; then
    SQL_FILE="${QUERY_DIR}/mutation_updates.sql"
    CLIENT_FLAGS="--apply_mutations_on_fly=1 --mutations_sync=0"
    METHOD_NAME="mutations on the fly"
elif [[ "$METHOD" == "lightweight" ]]; then
    SQL_FILE="${QUERY_DIR}/lightweight_updates.sql"
    CLIENT_FLAGS="--allow_experimental_lightweight_update=1"
    METHOD_NAME="lightweight updates"
fi

echo "🔄 Preparing table: ${TABLE_NAME}"
$CLICKHOUSE_CLIENT --query="DROP TABLE IF EXISTS ${TABLE_NAME};"
$CLICKHOUSE_CLIENT --query="CREATE TABLE ${TABLE_NAME} CLONE AS ${BASE_TABLE};"

# Extra prep for lightweight and mutations_on_fly
if [[ "$METHOD" == "lightweight" ]]; then
    echo "🛠️  Enabling internal columns for lightweight updates..."
    $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING enable_block_number_column = 1, enable_block_offset_column = 1;"
fi

if [[ "$METHOD" == "lightweight" || "$METHOD" == "mutations_on_fly" ]]; then
    echo "⚙️  Lowering merge threshold..."
    $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1;"
fi

echo "🚀 Launching updates in parallel from $SQL_FILE..."
mapfile -t updates < <(cat "$SQL_FILE"; echo)

start=$(date +%s.%N)

pids=()
for update in "${updates[@]}"; do
    $CLICKHOUSE_CLIENT $CLIENT_FLAGS --query="$update" &
    pids+=($!)
done

# Wait for all background updates (lightweight and on-the-fly)
for pid in "${pids[@]}"; do
    wait "$pid"
done

# Wait for classic mutations to finish via system.mutations
if [[ "$METHOD" == "mutation" ]]; then
    prev_count=1
    while true; do
        count=$($CLICKHOUSE_CLIENT --query="SELECT count() FROM system.mutations WHERE table = '$TABLE_NAME' AND NOT is_done")
        echo "⏳ Mutations still running: $count"
        if [[ "$count" -eq 0 && "$prev_count" -eq 0 ]]; then
            break
        fi
        prev_count=$count
        echo "🛌 Sleeping for 1s..."
        sleep 1
    done
fi

end=$(date +%s.%N)
mutation_duration=$(echo "$end - $start" | bc)


if [[ "$METHOD" == "mutations_on_fly" ]]; then
        echo "🛌 Sleeping for 100s..."
        sleep 100
fi


echo "📊 Running analytical queries..."
ANALYTICAL_SQL_FILE="${QUERY_DIR}/analytical_queries.sql"
mapfile -t queries < <(cat "$ANALYTICAL_SQL_FILE"; echo)
timings_queries=()

for ((i = 0; i < ${#queries[@]}; i++)); do
    query="${queries[i]}"
    echo "🔍 Query $((i + 1))..."
    start_q=$(date +%s.%N)

    $CLICKHOUSE_CLIENT $CLIENT_FLAGS --query="$query"

    end_q=$(date +%s.%N)
    elapsed_q=$(echo "$end_q - $start_q" | bc)
    timings_queries+=("$elapsed_q")
done

# Write results to JSON

# Compute totals
timings_queries_total=$(printf "%s\n" "${timings_queries[@]}" | paste -sd+ - | bc)
duration_total=$(echo "$mutation_duration + $timings_queries_total" | bc)

# Write JSON
{
  echo "{"
  echo "  \"mode\": \"${MODE}\","
  echo "  \"method\": \"${METHOD_NAME}\","
  echo "  \"part_num\": ${PART_NUM},"
  echo "  \"update_duration\": ${mutation_duration},"
  echo "  \"timings_queries_total\": ${timings_queries_total},"
  echo "  \"duration_total\": ${duration_total},"
  echo "  \"timings_queries\": ["
  for ((j = 0; j < ${#timings_queries[@]}; j++)); do
    sep=$([[ $j -lt $((${#timings_queries[@]} - 1)) ]] && echo "," || echo "")
    printf "    %.9f%s\n" "${timings_queries[j]}" "$sep"
  done
  echo "  ]"
  echo "}"
} > "$JSON_FILE"

echo "✅ Done. Results written to $JSON_FILE"