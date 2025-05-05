#!/bin/bash

LOG_FILE="logs/main_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


set -euo pipefail





# General information variables
MACHINE="m6i.8xlarge, 10000gib gp3"
SYSTEM="clickhouse"
VERSION="25.4.1.2389"
OS="Ubuntu 24.04"
DATE_TODAY=$(date +"%Y-%m-%d")
# TOTAL_NUM_ROWS=10000000
TOTAL_NUM_ROWS=100000000



# ==============================
# Parameters
# ==============================

settings_variants=(
    "optimize_move_to_prewhere = true, query_plan_optimize_lazy_materialization = true"
    "optimize_move_to_prewhere = true, query_plan_optimize_lazy_materialization = false"
    "optimize_move_to_prewhere = false, query_plan_optimize_lazy_materialization = true"
    "optimize_move_to_prewhere = false, query_plan_optimize_lazy_materialization = false"
)



run_benchmark() {

    local db="$1"
    local dirname="$2"
    local settings="$3"

    log "🏁 Running benchmark with:"
    log "   db:       $db"
    log "   settings: $settings"

    # ensure output dir exists
    mkdir -p "$dirname"

    local runtimes_file="$dirname/runtimes_clickhouse-mergetree.json"
    local memory_file="$dirname/memory_clickhouse-mergetree.json"


     # Create log comment string with current timestamp
    local timestamp=$(date +%s)
    local log_comment="${db}_${timestamp}"


    log "  → Benchmarking clickhouse-mergetree"
    ./benchmark.sh "$db" "$settings" "$log_comment" "$runtimes_file" "$memory_file" "$LOG_FILE" "queries.sql"

    sleep 10

    # Run metrics.sql with substituted log_comment
    METRICS_SQL_TMP="metrics_tmp.sql"
    sed "s/{LOG_COMMENT}/$log_comment/g" metrics.sql > "$METRICS_SQL_TMP"

    METRICS_FILE="$dirname/metrics_${db}.txt"
    clickhouse-client --query="$(cat "$METRICS_SQL_TMP")" > "$METRICS_FILE"

    log "✓ Metrics written to $METRICS_FILE"

    # Parse grouped metrics from metrics file
    read_rows=$(grep "read_rows:" "$METRICS_FILE" | sed 's/^.*read_rows:[[:space:]]*//')
    read_bytes=$(grep "read_bytes:" "$METRICS_FILE" | sed 's/^.*read_bytes:[[:space:]]*//')
    threads_participating=$(grep "threads_participating:" "$METRICS_FILE" | sed 's/^.*threads_participating:[[:space:]]*//')
    threads_simultaneous_peak=$(grep "threads_simultaneous_peak:" "$METRICS_FILE" | sed 's/^.*threads_simultaneous_peak:[[:space:]]*//')
    concurrency_control_slots_acquired=$(grep "concurrency_control_slots_acquired:" "$METRICS_FILE" | sed 's/^.*concurrency_control_slots_acquired:[[:space:]]*//')
    disk_read_elapsed=$(grep "disk_read_elapsed:" "$METRICS_FILE" | sed 's/^.*disk_read_elapsed:[[:space:]]*//')


    # Calculate total size of all files in data_dir
    total_size_bytes=$(clickhouse-client --query "SELECT sum(data_compressed_bytes) FROM system.parts WHERE database = '$db' AND table = 'hits' AND active")

    local settings_escaped
    settings_escaped=$(echo "$settings" | sed 's/"/\\"/g')

    # Prepare JSON output
    local timestamp=$(date +%s)
    local results_file="results/clickhouse_mergetree_${TOTAL_NUM_ROWS}_${timestamp}.json"
    mkdir -p results


    # Read runtimes and memory arrays as JSON-compatible lists
    local runtimes_json memory_json
    runtimes_json=$(awk 'BEGIN { ORS=""; print "[" } { gsub(/^[ \t]+|[ \t]+$/, ""); print $0; if (NR != 0) print "," } END { print "]" }' "$runtimes_file" | sed 's/,\]$/]/')
    memory_json=$(awk 'BEGIN { ORS=""; print "[" } { gsub(/^[ \t]+|[ \t]+$/, ""); print $0; if (NR != 0) print "," } END { print "]" }' "$memory_file" | sed 's/,\]$/]/')

    # Write JSON results
    echo -e "{\n  \"system\": \"$SYSTEM\",\n  \"version\": \"$VERSION\",\n  \"os\": \"$OS\",\n  \"date\": \"$DATE_TODAY\",\n  \"machine\": \"$MACHINE\",\n  \"total_num_rows\": $TOTAL_NUM_ROWS,\n  \"data_size\": $total_size_bytes,\n  \"format\": \"MergeTree\",\n  \"compressor\": \"zstd\",\n  \"settings\": \"$settings_escaped\",\n  \"runtime_result\": $runtimes_json,\n  \"memory_result\": $memory_json,\n  \"read_rows\": $read_rows,\n  \"read_bytes\": $read_bytes,\n  \"threads_participating\": $threads_participating,\n  \"threads_simultaneous_peak\": $threads_simultaneous_peak,\n  \"concurrency_control_slots_acquired\": $concurrency_control_slots_acquired,\n  \"disk_read_elapsed\": $disk_read_elapsed\n}" > "$results_file"

    log "JSON benchmark results saved to $results_file"

}



# ==============================
# Main
# ==============================

TSV_FILE="./downloads/hits-${TOTAL_NUM_ROWS}-shuf.tsv"

log "🔧 Starting ClickHouse server..."
sudo clickhouse start

log "⏳ Waiting for ClickHouse to be ready..."
while true; do
    clickhouse-client --query "SELECT 1" && break
    sleep 1
done
log "✅ ClickHouse is ready."

log "📁 Ensuring database exists: hits_${TOTAL_NUM_ROWS}"
clickhouse-client --query "CREATE DATABASE IF NOT EXISTS hits_${TOTAL_NUM_ROWS}"

# log "📥 Loading schema from ddl.sql..."
clickhouse-client --database=hits_${TOTAL_NUM_ROWS} < ddl.sql
log "✅ Schema loaded."

log "📦 Inserting data from TSV file: $TSV_FILE"
clickhouse-client --query "INSERT INTO hits_${TOTAL_NUM_ROWS}.hits FORMAT TSV" < "$TSV_FILE"
log "✅ Data inserted into hits_${TOTAL_NUM_ROWS}.hits"

log "🚀 Running benchmark..."

for settings in "${settings_variants[@]}"; do

    run_benchmark "hits_${TOTAL_NUM_ROWS}" "./result_snippets" "$settings"

done


log "✅ Benchmark complete."

