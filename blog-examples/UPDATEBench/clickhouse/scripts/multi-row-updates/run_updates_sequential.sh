#!/bin/bash
set -euo pipefail

METHOD="${1:-}"
INPUT_DIR="${2:-}"
PART_NUM="${3:-}"


if [[ "$METHOD" != "lightweight" && "$METHOD" != "lightweight_join_mode" && "$METHOD" != "mutation" && "$METHOD" != "mutations_on_fly" ]]; then
    echo "Usage: $0 [lightweight|lightweight_join_mode|mutation|mutations_on_fly] [SMALL|LARGE] [1|2|20]"
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


# Default to 3 repetitions if N not set
N=${N:-3}

MODE="sequential"
TABLE_NAME="lineitem"
BASE_TABLE="lineitem_base_tbl_${PART_NUM}part"
CLICKHOUSE_CLIENT="clickhouse-client"
QUERY_DIR="./${INPUT_DIR}"
RESULT_DIR="results"
mkdir -p "$RESULT_DIR"
JSON_FILE="${RESULT_DIR}/update_timings_${MODE}_${METHOD}_${INPUT_DIR}_${PART_NUM}part.json"

if [[ "$METHOD" == "lightweight" ]]; then
    SQL_FILE="${QUERY_DIR}/lightweight_updates.sql"
    CLIENT_FLAGS="--allow_experimental_lightweight_update=1"
    METHOD_NAME="lightweight updates"
elif [[ "$METHOD" == "lightweight_join_mode" ]]; then
    SQL_FILE="${QUERY_DIR}/lightweight_updates.sql"
    CLIENT_FLAGS="--allow_experimental_lightweight_update=1"
    METHOD_NAME="lightweight updates - join mode"
elif [[ "$METHOD" == "mutation" ]]; then
    SQL_FILE="${QUERY_DIR}/mutation_updates.sql"
    CLIENT_FLAGS="--mutations_sync=1"
    METHOD_NAME="mutation updates"
else
    SQL_FILE="${QUERY_DIR}/mutation_updates.sql"
    CLIENT_FLAGS="--apply_mutations_on_fly=1 --mutations_sync=0"
    METHOD_NAME="mutations on the fly"
fi



ANALYTICAL_SQL_FILE="${QUERY_DIR}/analytical_queries.sql"

# Load update and query SQLs into arrays
mapfile -t updates < <(cat "$SQL_FILE"; echo)
mapfile -t queries < <(cat "$ANALYTICAL_SQL_FILE"; echo)

if [[ ${#updates[@]} -ne ${#queries[@]} ]]; then
    echo "Mismatch between number of updates (${#updates[@]}) and queries (${#queries[@]})"
    exit 1
fi

run_with_time() {
  local update="$1"
  local out rc elapsed

  # Capture BOTH streams (some builds print timing on stdout, others on stderr)
  out=$($CLICKHOUSE_CLIENT $CLIENT_FLAGS --time --progress 0 --query="$update" 2>&1)
  rc=$?

  # 1) Prefer the labeled format: "Elapsed: 0.123 sec."
  elapsed=$(printf '%s\n' "$out" \
    | sed -n 's/.*Elapsed: \([0-9][0-9]*\(\.[0-9]\+\)\?\) sec.*/\1/p' \
    | tail -n 1)

  # 2) Fallback: last bare floating-point number on its own line (e.g. "0.036")
  if [[ -z "$elapsed" ]]; then
    elapsed=$(printf '%s\n' "$out" \
      | grep -E '^[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*$' \
      | awk '{print $1}' \
      | tail -n 1)
  fi

  if [[ $rc -ne 0 || -z "$elapsed" ]]; then
    echo "❌ clickhouse-client failed or no timing found for update: $update"
    echo "---- client output (tail) ----" >&2
    printf '%s\n' "$out" | tail -n 20 >&2
    echo "------------------------------" >&2
    return 1
  fi

  echo "$elapsed"
}

echo "Running ${METHOD_NAME}..."
timings_updates=()
timings_queries=()
memory_usages_queries=()

for ((i = 0; i < ${#updates[@]}; i++)); do
    update="${updates[$i]}"
    query="${queries[$i]}"
    echo "⚙️  Running update $((i + 1))..."


    total_time=0

    for run in $(seq 1 $N); do

        echo "Preparing table: ${TABLE_NAME}"
        $CLICKHOUSE_CLIENT --query="DROP TABLE IF EXISTS ${TABLE_NAME};"
        $CLICKHOUSE_CLIENT --query="CREATE TABLE ${TABLE_NAME} CLONE AS ${BASE_TABLE};"

        if [[ "$METHOD" == "lightweight" || "$METHOD" == "lightweight_join_mode" ]]; then
            $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING enable_block_number_column = 1, enable_block_offset_column = 1;"
        fi

        if [[ "$METHOD" == "lightweight" || "$METHOD" == "lightweight_join_mode" || "$METHOD" == "mutations_on_fly" ]]; then
            $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 1;"
        fi

        # Clear caches before each test
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

        echo "    ▶️  Update run #$run"
        elapsed_update=$(run_with_time "$update")
        echo "       ⏱️  Run took: ${elapsed_update}s"
        total_time=$(echo "$total_time + $elapsed_update" | bc)


    done


    avg_time=$(echo "scale=9; $total_time / $N" | bc)
    echo "    📊 Avg update time over $N runs: ${avg_time}s"
    timings_updates+=("$avg_time")




    if [[ "$METHOD" == "mutations_on_fly" ]]; then
        echo "🛌 Sleeping for 30s..."
        sleep 30
    fi


    if [[ "$METHOD" == "lightweight_join_mode" ]]; then
        echo "Applying table settings for lightweight join mode..."
        $CLICKHOUSE_CLIENT --query="ALTER TABLE ${TABLE_NAME} MODIFY SETTING max_bytes_to_merge_at_max_space_in_pool = 0, apply_patches_on_merge = 0;"

        echo "Starting OPTIMIZE FINAL on ${TABLE_NAME}..."
        start_time=$(date +%s)

        $CLICKHOUSE_CLIENT --mutations_sync=1 --query="OPTIMIZE TABLE ${TABLE_NAME} FINAL;"

        end_time=$(date +%s)
        duration=$((end_time - start_time))
        echo "OPTIMIZE FINAL completed in ${duration} seconds."

        # Count active parts after optimize
        part_count=$($CLICKHOUSE_CLIENT --query="SELECT count() FROM system.parts WHERE active AND database = 'default' AND table = '${TABLE_NAME}'")
        echo "Active parts after optimize: ${part_count}"
    fi


    total_query_time=0
    total_query_memory=0

    for run in $(seq 1 $N); do

        # Clear caches before each test
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null

        echo "    ▶️  Query run #$run"
        ts_start=$(date +%s.%N)

        # Capture query output including memory usage (last line)
        if output=$($CLICKHOUSE_CLIENT $CLIENT_FLAGS --use_query_condition_cache=0 --memory-usage --query="$query" 2>&1); then
            ts_end=$(date +%s.%N)
            elapsed_query=$(echo "$ts_end - $ts_start" | bc)

            # Extract last line as memory usage (in bytes)
            memory_usage=$(echo "$output" | tail -n 1)

            # Remove the last line for actual query output if needed
            query_result=$(echo "$output" | head -n -1)

            echo "${query_result}"
            echo "       ⏱️  Query run took: ${elapsed_query}s"
            echo "       💾 Memory used: ${memory_usage} bytes"
        else
            ts_end=$(date +%s.%N)
            elapsed_query=0
            memory_usage=0
            echo "       ❌ Query run failed, using 0 for time and memory"
            echo "       Error: $output"
        fi

        total_query_time=$(echo "$total_query_time + $elapsed_query" | bc)
        total_query_memory=$(echo "$total_query_memory + $memory_usage" | bc)
    done

    avg_query_time=$(echo "scale=9; $total_query_time / $N" | bc)
    avg_query_memory=$(echo "scale=0; $total_query_memory / $N" | bc)

    echo "    📊 Avg query time over $N runs: ${avg_query_time}s"
    echo "    📊 Avg memory usage: ${avg_query_memory} bytes"

    timings_queries+=("$avg_query_time")
    memory_usages_queries+=("$avg_query_memory")



done

# Write results as pretty JSON

# Compute totals
timings_updates_total=$(printf "%s\n" "${timings_updates[@]}" | paste -sd+ - | bc)
timings_queries_total=$(printf "%s\n" "${timings_queries[@]}" | paste -sd+ - | bc)
duration_total=$(echo "$timings_updates_total + $timings_queries_total" | bc)

# Write JSON
{
  echo "{"
  echo "  \"mode\": \"${MODE}\","
  echo "  \"method\": \"${METHOD_NAME}\","
  echo "  \"part_num\": ${PART_NUM},"
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
  echo "  \"memory_usages_queries\": ["
  for ((j = 0; j < ${#memory_usages_queries[@]}; j++)); do
    sep=$([[ $j -lt $((${#memory_usages_queries[@]} - 1)) ]] && echo "," || echo "")
    printf "    %d%s\n" "${memory_usages_queries[j]}" "$sep"
  done
  echo "  ],"
  printf "  \"timings_updates_total\": %.9f,\n" "$timings_updates_total"
  printf "  \"timings_queries_total\": %.9f,\n" "$timings_queries_total"
  printf "  \"duration_total\": %.9f\n" "$duration_total"
  echo "}"
} > "$JSON_FILE"

echo "✅ Done. Timings saved to $JSON_FILE"