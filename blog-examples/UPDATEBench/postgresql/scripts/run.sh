#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Change to the script directory to ensure relative paths work
cd "$SCRIPT_DIR"

# Parse command line arguments
UPDATE_TYPE=""
CACHE_MODE=""
SPECIFIC_QUERY=""

# Function to show usage
show_usage() {
    echo "Usage: $0 <update_type> <cache_mode> [options] [query_index]"
    echo ""
    echo "Arguments:"
    echo "  update_type    point|bulk    Type of updates to run"
    echo "  cache_mode     hot|cold     hot=no cache clearing, cold=clear cache"
    echo ""
    echo "Options:"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 bulk hot                          # Run bulk updates without clearing cache (outputs hot_bulk.json)"
    echo "  $0 point cold                        # Run point updates with cache clearing (outputs cold_point.json)"
    echo "  $0 point cold 3                      # Run only query #3 with cache clearing"
}

# Parse positional arguments first
if [[ $# -lt 2 ]]; then
    echo "Error: Missing required arguments"
    show_usage
    exit 1
fi

UPDATE_TYPE="$1"
CACHE_MODE="$2"
shift 2

# Validate arguments
if [[ "$UPDATE_TYPE" != "point" && "$UPDATE_TYPE" != "bulk" ]]; then
    echo "Error: update_type must be 'point' or 'bulk'"
    show_usage
    exit 1
fi

if [[ "$CACHE_MODE" != "hot" && "$CACHE_MODE" != "cold" ]]; then
    echo "Error: cache_mode must be 'hot' or 'cold'"
    show_usage
    exit 1
fi

# Set cache clearing based on mode
if [[ "$CACHE_MODE" == "hot" ]]; then
    CLEAR_CACHE=false
else
    CLEAR_CACHE=true
fi

# Parse remaining options
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            if [[ -z "$SPECIFIC_QUERY" ]]; then
                SPECIFIC_QUERY="$1"
            else
                echo "Error: Unknown argument: $1"
                show_usage
                exit 1
            fi
            shift
            ;;
    esac
done

# Function to log with timestamp
log_with_timestamp() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Arrays to collect timing data for JSON output
UPDATE_TIMINGS=()
QUERY_TIMINGS=()



# Function to clear page cache if enabled
clear_cache_if_enabled() {
    if [[ "$CLEAR_CACHE" == "true" ]]; then
        log_with_timestamp "Clearing page cache..."
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    else
        log_with_timestamp "Skipping page cache clear (hot mode)"
    fi
}

# Function to run a timed query
run_timed_query() {
    local query="$1"
    local description="$2"
    local timing_array_name="$3"  # Optional: array name to store timing
    local query_index="$4"  # Query index for N-runs
    local run_index="$5"    # Run index for N-runs
    
    log_with_timestamp "Starting: $description"
    
    # Capture start time
    local start=$(date +%s.%N)
    
    # Run query with timing and capture the time output
    local timing_output=$(
        (
            echo '\timing'
            echo "$query"
        ) | sudo -u postgres psql bench -t 2>&1 | grep 'Time:'
    )
    
    # Capture end time and calculate elapsed
    local end=$(date +%s.%N)
    local elapsed=$(echo "$end - $start" | bc)
    
    # Extract PostgreSQL timing from output (convert ms to seconds)
    local psql_timing=""
    if [[ -n "$timing_output" ]]; then
        psql_timing=$(echo "$timing_output" | grep -oP 'Time: \K[0-9]+\.[0-9]+' | head -1)
        if [[ -n "$psql_timing" ]]; then
            psql_timing=$(echo "$psql_timing / 1000" | bc -l)
        fi
    fi
    
    # Store timing in array if specified (use PostgreSQL timing for JSON, wall-clock for display)
    if [[ -n "$timing_array_name" && -n "$psql_timing" ]]; then
        case "$timing_array_name" in
            "UPDATE_TIMINGS")
                UPDATE_TIMINGS+=("$psql_timing")
                ;;
            "QUERY_TIMINGS")
                QUERY_TIMINGS+=("$psql_timing")
                ;;
        esac
    fi
    
    log_with_timestamp "Completed: $description - $timing_output"
    echo "       :stopwatch:  Wall clock time: ${elapsed}s"
    echo "$timing_output"
}

# Function to run a specific analytical query by line number
run_analytical_query_by_index() {
    local index="$1"
    
    log_with_timestamp "=== Running analytical query #$index ==="
    
    # Get the specific analytical query by line number
    local analytical_query=$(sed -n "${index}p" analytical_queries.sql)
    
    # Skip if query is empty
    if [[ -z "$analytical_query" ]]; then
        log_with_timestamp "Warning: No analytical query found at index $index"
        return
    fi
    
    run_timed_query "$analytical_query" "Analytical Query #$index" "QUERY_TIMINGS"
}

# Function to run vacuum
run_vacuum() {
    log_with_timestamp "=== Running VACUUM ==="
    # Run vacuum without timing tracking but with error visibility
    local start=$(date +%s.%N)
    
    # Run vacuum with timeout and error handling
    if timeout 15 sudo -u postgres psql bench -c "VACUUM;" 2>&1; then
        local end=$(date +%s.%N)
        local elapsed=$(echo "$end - $start" | bc)
        log_with_timestamp "VACUUM completed successfully in ${elapsed}s (not tracked in results)"
    else
        local exit_code=$?
        local end=$(date +%s.%N)
        local elapsed=$(echo "$end - $start" | bc)
        if [[ $exit_code -eq 124 ]]; then
            log_with_timestamp "ERROR: VACUUM timed out after 15 seconds"
        else
            log_with_timestamp "ERROR: VACUUM failed with exit code $exit_code after ${elapsed}s"
        fi
        log_with_timestamp "VACUUM failure indicates a serious database issue. Stopping benchmark."
        exit 1
    fi
}

# Determine update file based on type
if [[ "$UPDATE_TYPE" == "point" ]]; then
    UPDATE_FILE="updates-point.sql"
    MODE_DESCRIPTION="Point Update"
else
    UPDATE_FILE="updates-bulk.sql"
    MODE_DESCRIPTION="Bulk Update"
fi

# Check if update file exists
if [[ ! -f "$UPDATE_FILE" ]]; then
    echo "Error: Update file '$UPDATE_FILE' not found"
    exit 1
fi

# Check if analytical queries file exists
if [[ ! -f "analytical_queries.sql" ]]; then
    echo "Error: Analytical queries file 'analytical_queries.sql' not found"
    exit 1
fi

# 
log_with_timestamp "=== Resetting data & cache before benchmark ==="
# Always reset data once at the beginning of the benchmark
./reset_data.sh
# Always clear the cache when a new benchmark run is started
log_with_timestamp "Clearing page cache..."
sync
echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
# If hot mode, prime cache by running query 1
if [[ "$CLEAR_CACHE" == "false" ]]; then
    log_with_timestamp "Priming cache..."
    run_analytical_query_by_index "0"
    run_analytical_query_by_index "4"
fi

# Main benchmark loop
if [[ -n "$SPECIFIC_QUERY" ]]; then
    log_with_timestamp "Starting PostgreSQL $MODE_DESCRIPTION Benchmark ($CACHE_MODE mode) - Query #$SPECIFIC_QUERY Only"
else
    log_with_timestamp "Starting PostgreSQL $MODE_DESCRIPTION Benchmark ($CACHE_MODE mode) - All Queries"
fi
log_with_timestamp "============================================"

# Read both files into arrays for indexed access
mapfile -t update_queries < "$UPDATE_FILE"
mapfile -t analytical_queries < analytical_queries.sql

# Get the maximum number of queries to process
max_queries=${#update_queries[@]}
max_analytical=${#analytical_queries[@]}

log_with_timestamp "Found $max_queries update queries and $max_analytical analytical queries"

# Determine which queries to process
if [[ -n "$SPECIFIC_QUERY" ]]; then
    if [[ $SPECIFIC_QUERY -lt 1 || $SPECIFIC_QUERY -gt $max_queries ]]; then
        log_with_timestamp "Error: Query index $SPECIFIC_QUERY is out of range (1-$max_queries)"
        exit 1
    fi
    start_index=$((SPECIFIC_QUERY-1))
    end_index=$SPECIFIC_QUERY
    log_with_timestamp "Running only query pair #$SPECIFIC_QUERY"
else
    start_index=0
    end_index=$max_queries
    log_with_timestamp "Running all query pairs (1-$max_queries)"
fi

# Process each update query
for ((i=start_index; i<end_index; i++)); do
    query_num=$((i+1))
    update_query="${update_queries[i]}"
    
    # Skip empty lines and comments
    [[ -z "$update_query" || "$update_query" =~ ^[[:space:]]*-- ]] && continue

    # Clear cache pre-update (if cold)
    clear_cache_if_enabled
    
    log_with_timestamp ""
    log_with_timestamp "### Processing Query Pair #$query_num ###"
    log_with_timestamp "Update Query: $update_query"
    
    # Step 1: Run the update query
    log_with_timestamp "=== Running $UPDATE_TYPE update query ==="
    run_timed_query "$update_query" "$MODE_Description Query #$query_num" "UPDATE_TIMINGS"
    
    # Step 2: Run vacuum
    run_vacuum

    # Clear cache pre-query (if cold)
    clear_cache_if_enabled
    
    # Step 3: Run corresponding analytical query
    run_analytical_query_by_index "$query_num"
    
    log_with_timestamp "Completed Query Pair #$query_num"
    log_with_timestamp "----------------------------------------"
done

log_with_timestamp ""
if [[ -n "$SPECIFIC_QUERY" ]]; then
    log_with_timestamp "$MODE_DESCRIPTION benchmark completed successfully!"
    log_with_timestamp "Processed query pair #$SPECIFIC_QUERY"
else
    log_with_timestamp "$MODE_DESCRIPTION benchmark completed successfully!"
    log_with_timestamp "Total query pairs processed: $max_queries"
fi

# Generate JSON output (always enabled)
# Auto-generate filename based on cache mode and update type
RESULTS_DIR="../results"
mkdir -p "$RESULTS_DIR"
OUTPUT_FILE="$RESULTS_DIR/${CACHE_MODE}_${UPDATE_TYPE}.json"
log_with_timestamp "Generating JSON output to: $OUTPUT_FILE"

# Calculate totals with 3 decimal place rounding
update_total=0
query_total=0

for timing in "${UPDATE_TIMINGS[@]}"; do
    update_total=$(echo "$update_total + $timing" | bc -l)
done

for timing in "${QUERY_TIMINGS[@]}"; do
    query_total=$(echo "$query_total + $timing" | bc -l)
done

# Round totals to 3 decimal places
update_total=$(printf "%.3f" "$update_total")
query_total=$(printf "%.3f" "$query_total")
total_duration=$(echo "$update_total + $query_total" | bc -l)
total_duration=$(printf "%.3f" "$total_duration")

# Convert arrays to JSON arrays with 3 decimal place rounding
update_timings_json=$(printf '%s\n' "${UPDATE_TIMINGS[@]}" | jq -R 'tonumber | . * 1000 | round / 1000' | jq -s .)
query_timings_json=$(printf '%s\n' "${QUERY_TIMINGS[@]}" | jq -R 'tonumber | . * 1000 | round / 1000' | jq -s .)

# Create JSON output using jq
jq -n \
    --arg mode "sequential" \
    --arg method "postgresql updates" \
    --arg temperature "$(echo "$CACHE_MODE" | tr '[:lower:]' '[:upper:]')" \
    --arg update_granularity "$(echo "$UPDATE_TYPE" | tr '[:lower:]' '[:upper:]')" \
    --argjson timings_updates "$update_timings_json" \
    --argjson timings_queries "$query_timings_json" \
    --argjson timings_updates_total "$update_total" \
    --argjson timings_queries_total "$query_total" \
    --argjson duration_total "$total_duration" \
    '{
        mode: $mode,
        method: $method,
        temperature: $temperature,
        update_granularity: $update_granularity,
        timings_updates: $timings_updates,
        timings_queries: $timings_queries,
        timings_updates_total: $timings_updates_total,
        timings_queries_total: $timings_queries_total,
        duration_total: $duration_total
    }' > "$OUTPUT_FILE"

log_with_timestamp "JSON results written to: $OUTPUT_FILE"
