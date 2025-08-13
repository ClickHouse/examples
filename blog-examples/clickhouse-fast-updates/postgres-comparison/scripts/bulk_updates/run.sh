#!/bin/bash

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Change to the script directory to ensure relative paths work
cd "$SCRIPT_DIR"

# Parse command line arguments
SPECIFIC_QUERY=""
CLEAR_CACHE=true

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-cache-clear)
            CLEAR_CACHE=false
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options] [query_index]"
            echo "Options:"
            echo "  --no-cache-clear    Skip clearing page cache between queries"
            echo "  --help, -h          Show this help message"
            echo "Example: $0 3                    # Run only update query #3"
            echo "Example: $0 --no-cache-clear 3   # Run query #3 without clearing cache"
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
    
    run_timed_query "$analytical_query" "Analytical Query #$index ($phase)"
}

# Function to run vacuum
run_vacuum() {
    log_with_timestamp "=== Running VACUUM ==="
    run_timed_query "VACUUM;" "VACUUM operation"
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
    run_timed_query "$update_query" "Update Query #$query_num"
    
    # Clear caches before analytical query (if enabled)
    clear_cache_if_enabled
    
    # Step 2: Run corresponding analytical query (pre-vacuum)
    run_analytical_query_by_index "$query_num" "pre-vacuum"
    
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