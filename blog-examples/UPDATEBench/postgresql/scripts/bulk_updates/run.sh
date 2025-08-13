#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Change to the script directory to ensure relative paths work
cd "$SCRIPT_DIR"

# Parse command line arguments
SPECIFIC_QUERY=""
CLEAR_CACHE=true
JSON_OUTPUT=false
OUTPUT_FILE=""
ONLY_POST_VACUUM=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache-clear)
            CLEAR_CACHE=false
            shift
            ;;
        --json-output)
            JSON_OUTPUT=true
            if [[ -n "$2" && ! "$2" =~ ^-- ]]; then
                OUTPUT_FILE="$2"
                shift
            fi
            shift
            ;;
        --only-post-vacuum)
            ONLY_POST_VACUUM=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] [query_index]"
            echo "Options:"
            echo "  --no-cache-clear         Skip clearing page cache between queries"
            echo "  --json-output [file]     Generate JSON output (optionally to specified file)"
            echo "  --only-post-vacuum       Skip pre-vacuum analytical queries, only run post-vacuum"
            echo "  --help, -h               Show this help message"
            echo "Example: $0 3                         # Run only update query #3"
            echo "Example: $0 --no-cache-clear 3        # Run query #3 without clearing cache"
            echo "Example: $0 --json-output results.json # Generate JSON output to results.json"
            echo "Example: $0 --only-post-vacuum        # Skip pre-vacuum queries"
            exit 0
            ;;
        *)
            if [[ -z "$SPECIFIC_QUERY" ]]; then
                SPECIFIC_QUERY="$1"
                if ! [[ "$SPECIFIC_QUERY" =~ ^[0-9]+$ ]]; then
                    echo "Error: Argument must be a positive integer (query index)"
                    echo "Usage: $0 [options] [query_index]"
                    echo "Use --help for more information"
                    exit 1
                fi
            else
                echo "Error: Unknown argument: $1"
                echo "Use --help for usage information"
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
QUERY_TIMINGS_PRE=()
QUERY_TIMINGS_POST=()
VACUUM_TIMINGS=()

# Function to clear page cache if enabled
clear_cache_if_enabled() {
    if [[ "$CLEAR_CACHE" == "true" ]]; then
        log_with_timestamp "Clearing page cache..."
        sync
        echo 3 | sudo tee /proc/sys/vm/drop_caches > /dev/null
    else
        log_with_timestamp "Skipping page cache clear (--no-cache-clear flag set)"
    fi
}

# Function to run a single query and capture timing
run_timed_query() {
    local query="$1"
    local description="$2"
    local timing_array_name="$3"  # Optional: array name to store timing
    
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
            "QUERY_TIMINGS_PRE")
                QUERY_TIMINGS_PRE+=("$psql_timing")
                ;;
            "QUERY_TIMINGS_POST")
                QUERY_TIMINGS_POST+=("$psql_timing")
                ;;
            "VACUUM_TIMINGS")
                VACUUM_TIMINGS+=("$psql_timing")
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
    local phase="$2"  # "pre-vacuum" or "post-vacuum"
    
    log_with_timestamp "=== Running analytical query #$index ($phase) ==="
    
    # Get the specific analytical query by line number
    local analytical_query=$(sed -n "${index}p" analytical_queries.sql)
    
    # Skip if query is empty
    if [[ -z "$analytical_query" ]]; then
        log_with_timestamp "Warning: No analytical query found at index $index"
        return
    fi
    
    # Determine which timing array to use
    local timing_array=""
    if [[ "$phase" == "pre-vacuum" ]]; then
        timing_array="QUERY_TIMINGS_PRE"
    elif [[ "$phase" == "post-vacuum" ]]; then
        timing_array="QUERY_TIMINGS_POST"
    fi
    
    run_timed_query "$analytical_query" "Analytical Query #$index ($phase)" "$timing_array"
}

# Function to run vacuum
run_vacuum() {
    log_with_timestamp "=== Running VACUUM ==="
    run_timed_query "VACUUM;" "VACUUM operation" "VACUUM_TIMINGS"
}

# Main benchmark loop
if [[ -n "$SPECIFIC_QUERY" ]]; then
    log_with_timestamp "Starting PostgreSQL Update Benchmark (Paired Query Mode) - Query #$SPECIFIC_QUERY Only"
else
    log_with_timestamp "Starting PostgreSQL Update Benchmark (Paired Query Mode) - All Queries"
fi
log_with_timestamp "============================================"

# Read both files into arrays for indexed access
mapfile -t update_queries < update_queries.sql
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

# Process each pair of queries
for ((i=start_index; i<end_index; i++)); do
    query_num=$((i+1))
    update_query="${update_queries[i]}"
    
    # Skip empty lines and comments
    [[ -z "$update_query" || "$update_query" =~ ^[[:space:]]*-- ]] && continue
    
    log_with_timestamp ""
    log_with_timestamp "### Processing Query Pair #$query_num ###"
    log_with_timestamp "Update Query: $update_query"
    
    # Clear caches before each test (if enabled)
    clear_cache_if_enabled
    
    # Step 1: Run the update query
    log_with_timestamp "=== Running update query ==="
    run_timed_query "$update_query" "Update Query #$query_num" "UPDATE_TIMINGS"
    
    # Clear caches before analytical query (if enabled)
    clear_cache_if_enabled
    
    # Step 2: Run corresponding analytical query (pre-vacuum) - skip if only-post-vacuum is set
    if [[ "$ONLY_POST_VACUUM" != "true" ]]; then
        run_analytical_query_by_index "$query_num" "pre-vacuum"
    else
        log_with_timestamp "Skipping pre-vacuum analytical query (--only-post-vacuum flag set)"
    fi
    
    # Step 3: Run vacuum
    run_vacuum
    
    # Clear caches before post-vacuum analytical query (if enabled)
    clear_cache_if_enabled
    
    # Step 4: Run corresponding analytical query (post-vacuum)
    run_analytical_query_by_index "$query_num" "post-vacuum"
    
    # Step 5: Reset data
    log_with_timestamp "=== Resetting data ==="
    ../reset_data.sh
    
    log_with_timestamp "Completed Query Pair #$query_num"
    log_with_timestamp "----------------------------------------"
done

log_with_timestamp ""
if [[ -n "$SPECIFIC_QUERY" ]]; then
    log_with_timestamp "Single query benchmark completed successfully!"
    log_with_timestamp "Processed query pair #$SPECIFIC_QUERY"
else
    log_with_timestamp "Benchmark completed successfully!"
    log_with_timestamp "Total query pairs processed: $max_queries"
fi

# Generate JSON output if requested
if [[ "$JSON_OUTPUT" == "true" ]]; then
    # Calculate totals
    update_total=0
    query_pre_total=0
    query_post_total=0
    vacuum_total=0
    
    for timing in "${UPDATE_TIMINGS[@]}"; do
        update_total=$(echo "$update_total + $timing" | bc)
    done
    
    for timing in "${QUERY_TIMINGS_PRE[@]}"; do
        query_pre_total=$(echo "$query_pre_total + $timing" | bc)
    done
    
    for timing in "${QUERY_TIMINGS_POST[@]}"; do
        query_post_total=$(echo "$query_post_total + $timing" | bc)
    done
    
    for timing in "${VACUUM_TIMINGS[@]}"; do
        vacuum_total=$(echo "$vacuum_total + $timing" | bc)
    done
    
    total_duration=$(echo "$update_total + $query_pre_total + $query_post_total + $vacuum_total" | bc)
    
    # Create JSON output
    json_output="{"
    json_output+='"mode": "bulk",'
    json_output+='"method": "postgresql updates",'
    json_output+='"cache_clearing": '$(if [[ "$CLEAR_CACHE" == "true" ]]; then echo 'true'; else echo 'false'; fi)','
    json_output+='"only_post_vacuum": '$(if [[ "$ONLY_POST_VACUUM" == "true" ]]; then echo 'true'; else echo 'false'; fi)','
    
    # Add timing arrays
    json_output+='"timings_updates": ['
    for i in "${!UPDATE_TIMINGS[@]}"; do
        json_output+="${UPDATE_TIMINGS[i]}"
        if [[ $i -lt $((${#UPDATE_TIMINGS[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    json_output+='"timings_queries_pre_vacuum": ['
    for i in "${!QUERY_TIMINGS_PRE[@]}"; do
        json_output+="${QUERY_TIMINGS_PRE[i]}"
        if [[ $i -lt $((${#QUERY_TIMINGS_PRE[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    json_output+='"timings_queries_post_vacuum": ['
    for i in "${!QUERY_TIMINGS_POST[@]}"; do
        json_output+="${QUERY_TIMINGS_POST[i]}"
        if [[ $i -lt $((${#QUERY_TIMINGS_POST[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    json_output+='"timings_vacuum": ['
    for i in "${!VACUUM_TIMINGS[@]}"; do
        json_output+="${VACUUM_TIMINGS[i]}"
        if [[ $i -lt $((${#VACUUM_TIMINGS[@]} - 1)) ]]; then
            json_output+=','
        fi
    done
    json_output+='],'
    
    # Add totals
    json_output+='"timings_updates_total": '$update_total','
    json_output+='"timings_queries_pre_vacuum_total": '$query_pre_total','
    json_output+='"timings_queries_post_vacuum_total": '$query_post_total','
    json_output+='"timings_vacuum_total": '$vacuum_total','
    json_output+='"duration_total": '$total_duration
    json_output+='}'
    
    # Format JSON with jq and output
    if [[ -n "$OUTPUT_FILE" ]]; then
        echo "$json_output" | jq '.' > "$OUTPUT_FILE"
        log_with_timestamp "JSON results written to: $OUTPUT_FILE"
    else
        echo "$json_output" | jq '.'
    fi
fi