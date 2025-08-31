#!/bin/bash
set -euo pipefail

METHOD="${1:-}"
INPUT_DIR="${2:-}"

if [[ "$METHOD" != "lightweight" && "$METHOD" != "mutation" && "$METHOD" != "mutations_on_fly" && "$METHOD" != "replacing_insert" ]]; then
    echo "Usage: $0 [lightweight|mutation|mutations_on_fly|replacing_insert] [10x1|10x100]"
    exit 1
fi

if [[ "$INPUT_DIR" != "10x1" && "$INPUT_DIR" != "10x100" ]]; then
    echo "INPUT_DIR must be either '10x1' or '10x100'"
    exit 1
fi



MODE="parallel"
TABLE_NAME="lineitem"
BASE_TABLE="lineitem_base_tbl"
CLICKHOUSE_CLIENT="clickhouse-client"
QUERY_DIR="./${INPUT_DIR}"
RESULT_DIR="results"
mkdir -p "$RESULT_DIR"
JSON_FILE="${RESULT_DIR}/update_timings_${MODE}_${METHOD}_${INPUT_DIR}.json"

if [[ "$METHOD" == "lightweight" ]]; then
    FILE_PREFIX="lightweight_update"
    CLIENT_FLAGS="--allow_experimental_lightweight_update=1"
    METHOD_NAME="lightweight updates"
elif [[ "$METHOD" == "mutation" ]]; then
    FILE_PREFIX="mutation_update"
    CLIENT_FLAGS="--mutations_sync=0"
    METHOD_NAME="mutation updates"
elif [[ "$METHOD" == "mutations_on_fly" ]]; then
    FILE_PREFIX="mutation_update"
    CLIENT_FLAGS="--apply_mutations_on_fly=1 --mutations_sync=0"
    METHOD_NAME="mutations on the fly"
else
    FILE_PREFIX="replacing_insert"
    CLIENT_FLAGS=""
    METHOD_NAME="replacing inserts"
fi

echo "🔄 Preparing table: ${TABLE_NAME}"
$CLICKHOUSE_CLIENT --query="DROP TABLE IF EXISTS ${TABLE_NAME};"

if [[ "$METHOD" == "replacing_insert" ]]; then
    $CLICKHOUSE_CLIENT --query="CREATE TABLE ${TABLE_NAME} CLONE AS ${BASE_TABLE} ENGINE = ReplacingMergeTree"
else
    $CLICKHOUSE_CLIENT --query="CREATE TABLE ${TABLE_NAME} CLONE AS ${BASE_TABLE}"
fi

if [[ "$METHOD" == "lightweight" ]]; then
    $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING enable_block_number_column = 1, enable_block_offset_column = 1;"
fi

if [[ "$METHOD" == "replacing_insert" ||  "$METHOD" == "lightweight" || "$METHOD" == "mutations_on_fly" ]]; then
    $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1;"
fi

echo "🚀 Launching updates in parallel..."

start=$(date +%s.%N)

pids=()
for i in $(seq -w 1 10); do
    SQL_FILE="${QUERY_DIR}/${FILE_PREFIX}_${i}.sql"
    if [[ ! -f "$SQL_FILE" ]]; then
        echo "File not found: $SQL_FILE"
        exit 1
    fi

    $CLICKHOUSE_CLIENT $CLIENT_FLAGS < "$SQL_FILE" &
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
mapfile -t ANALYTICAL_QUERIES < "${QUERY_DIR}/analytical_queries.sql"
timings_queries=()

for ((i = 0; i < ${#ANALYTICAL_QUERIES[@]}; i++)); do
    query="${ANALYTICAL_QUERIES[i]}"
    echo "🔍 Query $((i + 1))..."
    start_q=$(date +%s.%N)
    [[ "$METHOD" == "replacing_insert" ]] && query="${query//FROM lineitem/FROM lineitem FINAL}"
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