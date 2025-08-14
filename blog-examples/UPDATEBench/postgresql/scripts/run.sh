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
NUM_RUNS=1

# Function to show usage
show_usage() {
    echo "Usage: $0 <update_type> <cache_mode> [options] [query_index]"
    echo ""
    echo "Arguments:"
    echo "  update_type    point|bulk    Type of updates to run"
    echo "  cache_mode     hot|cold     hot=no cache clearing, cold=clear cache"
    echo ""
    echo "Options:"
    echo "  --runs N, -n N           Number of runs to perform and average (default: 1)"
    echo "  --help, -h               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 bulk hot                          # Run bulk updates without clearing cache (outputs hot_bulk.json)"
    echo "  $0 point cold                        # Run point updates with cache clearing (outputs cold_point.json)"
    echo "  $0 point cold --runs 3               # Run with 3 iterations and average results"
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
        --runs|-n)
            if [[ -z "$2" ]] || ! [[ "$2" =~ ^[0-9]+$ ]] || [[ "$2" -lt 1 ]]; then
                echo "Error: --runs requires a positive integer"
                show_usage
                exit 1
            fi
            NUM_RUNS="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            if [[ -z "$SPECIFIC_QUERY" ]]; then
                SPECIFIC_QUERY="$1"
                if ! [[ "$SPECIFIC_QUERY" =~ ^[0-9]+$ ]]; then
                    echo "Error: Query index must be a positive integer"
                    show_usage
                    exit 1
                fi
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
# For N>1, these will be 2D arrays: [query_index][run_index]
declare -A UPDATE_TIMINGS_ALL
declare -A QUERY_TIMINGS_ALL
declare -A VACUUM_TIMINGS_ALL

# Final averaged arrays for JSON output
UPDATE_TIMINGS=()
QUERY_TIMINGS=()
VACUUM_TIMINGS=()

# Function to calculate averages from multiple runs
calculate_averages() {
    if [[ "$NUM_RUNS" -eq 1 ]]; then
        return  # No averaging needed for single runs
    fi
    
    log_with_timestamp "Calculating averages from $NUM_RUNS runs..."
    
    # Calculate averages for each query index
    for ((q=start_index; q<end_index; q++)); do
        query_num=$((q+1))
        
        # Skip empty queries
        update_query="${update_queries[q]}"
        [[ -z "$update_query" || "$update_query" =~ ^[[:space:]]*-- ]] && continue
        
        # Average UPDATE_TIMINGS for this query
        local update_sum=0
        local update_count=0
        for ((run=0; run<NUM_RUNS; run++)); do
            local key="${query_num}_${run}"
            if [[ -n "${UPDATE_TIMINGS_ALL[$key]}" ]]; then
                update_sum=$(echo "$update_sum + ${UPDATE_TIMINGS_ALL[$key]}" | bc -l)
                update_count=$((update_count + 1))
            fi
        done
        if [[ $update_count -gt 0 ]]; then
            local update_avg=$(echo "scale=9; $update_sum / $update_count" | bc -l)
            UPDATE_TIMINGS+=("$update_avg")
        fi
        
        # Average QUERY_TIMINGS for this query
        local query_sum=0
        local query_count=0
        for ((run=0; run<NUM_RUNS; run++)); do
            local key="${query_num}_${run}"
            if [[ -n "${QUERY_TIMINGS_ALL[$key]}" ]]; then
                query_sum=$(echo "$query_sum + ${QUERY_TIMINGS_ALL[$key]}" | bc -l)
                query_count=$((query_count + 1))
            fi
        done
        if [[ $query_count -gt 0 ]]; then
            local query_avg=$(echo "scale=9; $query_sum / $query_count" | bc -l)
            QUERY_TIMINGS+=("$query_avg")
        fi
        
        # VACUUM_TIMINGS - only one vacuum per query, so just copy
        local vacuum_key="${query_num}_0"
        if [[ -n "${VACUUM_TIMINGS_ALL[$vacuum_key]}" ]]; then
            VACUUM_TIMINGS+=("${VACUUM_TIMINGS_ALL[$vacuum_key]}")
        fi
    done
    
    log_with_timestamp "Averaging completed. Final arrays contain ${#UPDATE_TIMINGS[@]} update timings, ${#QUERY_TIMINGS[@]} query timings."
}

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
        if [[ "$NUM_RUNS" -gt 1 ]]; then
            # Store in 2D array for multiple runs
            local key="${query_index}_${run_index}"
            case "$timing_array_name" in
                "UPDATE_TIMINGS")
                    UPDATE_TIMINGS_ALL["$key"]="$psql_timing"
                    ;;
                "QUERY_TIMINGS")
                    QUERY_TIMINGS_ALL["$key"]="$psql_timing"
                    ;;
                "VACUUM_TIMINGS")
                    VACUUM_TIMINGS_ALL["$key"]="$psql_timing"
                    ;;
            esac
        else
            # Single run - store directly in final arrays
            case "$timing_array_name" in
                "UPDATE_TIMINGS")
                    UPDATE_TIMINGS+=("$psql_timing")
                    ;;
                "QUERY_TIMINGS")
                    QUERY_TIMINGS+=("$psql_timing")
                    ;;
                "VACUUM_TIMINGS")
                    VACUUM_TIMINGS+=("$psql_timing")
                    ;;
            esac
        fi
    fi
    
    log_with_timestamp "Completed: $description - $timing_output"
    echo "       :stopwatch:  Wall clock time: ${elapsed}s"
    echo "$timing_output"
}

# Function to run a specific analytical query by line number
run_analytical_query_by_index() {
    local index="$1"
    local run_index="$2"
    
    log_with_timestamp "=== Running analytical query #$index ==="
    
    # Get the specific analytical query by line number
    local analytical_query=$(sed -n "${index}p" analytical_queries.sql)
    
    # Skip if query is empty
    if [[ -z "$analytical_query" ]]; then
        log_with_timestamp "Warning: No analytical query found at index $index"
        return
    fi
    
    run_timed_query "$analytical_query" "Analytical Query #$index" "QUERY_TIMINGS" "$index" "$run_index"
}

# Function to run vacuum
run_vacuum() {
    local query_index="$1"
    local run_index="$2"
    log_with_timestamp "=== Running VACUUM ==="
    run_timed_query "VACUUM;" "VACUUM operation" "VACUUM_TIMINGS" "$query_index" "$run_index"
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

# Process each update query with N-runs support
for ((i=start_index; i<end_index; i++)); do
    query_num=$((i+1))
    update_query="${update_queries[i]}"
    
    # Skip empty lines and comments
    [[ -z "$update_query" || "$update_query" =~ ^[[:space:]]*-- ]] && continue
    
    log_with_timestamp ""
    log_with_timestamp "### Processing Query Pair #$query_num (N=$NUM_RUNS runs) ###"
    log_with_timestamp "Update Query: $update_query"
    
    # Run N iterations for this query pair
    for ((run=0; run<NUM_RUNS; run++)); do
        run_num=$((run+1))
        log_with_timestamp ""
        log_with_timestamp "--- Run $run_num/$NUM_RUNS for Query Pair #$query_num ---"
        
        # Clear caches before each test (if enabled)
        clear_cache_if_enabled
        
        # Step 1: Run the update query
        log_with_timestamp "=== Running $UPDATE_TYPE update query ==="
        run_timed_query "$update_query" "$MODE_Description Query #$query_num (Run $run_num)" "UPDATE_TIMINGS" "$query_num" "$run"
        
        # Step 2: Reset data after update (before vacuum)
        log_with_timestamp "=== Resetting data after update ==="
        ./reset_data.sh
        
        # Clear caches before next update run (if enabled and not last run)
        if [[ $run -lt $((NUM_RUNS-1)) ]]; then
            clear_cache_if_enabled
        fi
    done
    
    # After all update runs, run vacuum once
    log_with_timestamp ""
    log_with_timestamp "=== Running VACUUM after all update runs ==="
    run_vacuum "$query_num" "0"
    
    # Run analytical query N times
    for ((run=0; run<NUM_RUNS; run++)); do
        run_num=$((run+1))
        log_with_timestamp ""
        log_with_timestamp "--- Analytical Query Run $run_num/$NUM_RUNS for Query #$query_num ---"
        
        # Clear caches before analytical query (if enabled)
        clear_cache_if_enabled
        
        # Step 3: Run corresponding analytical query
        run_analytical_query_by_index "$query_num" "$run"
    done
    
    # Final reset after all runs for this query
    log_with_timestamp "=== Final reset after Query Pair #$query_num ==="
    ./reset_data.sh
    
    log_with_timestamp "Completed Query Pair #$query_num (all $NUM_RUNS runs)"
    log_with_timestamp "----------------------------------------"
done

# Calculate averages if multiple runs were performed
calculate_averages

log_with_timestamp ""
if [[ -n "$SPECIFIC_QUERY" ]]; then
    log_with_timestamp "$MODE_DESCRIPTION benchmark completed successfully!"
    log_with_timestamp "Processed query pair #$SPECIFIC_QUERY with $NUM_RUNS runs each"
else
    log_with_timestamp "$MODE_DESCRIPTION benchmark completed successfully!"
    log_with_timestamp "Total query pairs processed: $max_queries with $NUM_RUNS runs each"
fi

# Generate JSON output (always enabled)
# Auto-generate filename based on cache mode and update type
OUTPUT_FILE="${CACHE_MODE}_${UPDATE_TYPE}.json"
log_with_timestamp "Generating JSON output to: $OUTPUT_FILE"
    # Calculate totals
    update_total=0
    query_total=0
    vacuum_total=0
    
    for timing in "${UPDATE_TIMINGS[@]}"; do
        update_total=$(echo "$update_total + $timing" | bc)
    done
    
    for timing in "${QUERY_TIMINGS[@]}"; do
        query_total=$(echo "$query_total + $timing" | bc)
    done
    
    for timing in "${VACUUM_TIMINGS[@]}"; do
        vacuum_total=$(echo "$vacuum_total + $timing" | bc)
    done
    
    total_duration=$(echo "$update_total + $query_total + $vacuum_total" | bc)
    
    # Create JSON output
    json_output="{"
    json_output+='"mode": "sequential",'
    json_output+='"method": "postgresql updates",'
    json_output+='"temperature": "'$(echo "$CACHE_MODE" | tr '[:lower:]' '[:upper:]')'",'
    json_output+='"update_granularity": "'$(echo "$UPDATE_TYPE" | tr '[:lower:]' '[:upper:]')'",'
    json_output+='"N": '$NUM_RUNS','
    
    # Add timing arrays
    json_output+='"timings_updates": ['
    for i in "${!UPDATE_TIMINGS[@]}"; do
        json_output+="${UPDATE_TIMINGS[i]}"
        if [[ $i -lt $((${#UPDATE_TIMINGS[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    json_output+='"timings_queries": ['
    for i in "${!QUERY_TIMINGS[@]}"; do
        json_output+="${QUERY_TIMINGS[i]}"
        if [[ $i -lt $((${#QUERY_TIMINGS[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    # Add totals
    json_output+='"timings_updates_total": '$update_total','
    json_output+='"timings_queries_total": '$query_total','
    json_output+='"duration_total": '$total_duration
    json_output+='}'
    
    # Format JSON with jq and output to file
    echo "$json_output" | jq '.' > "$OUTPUT_FILE"
    log_with_timestamp "JSON results written to: $OUTPUT_FILE"
