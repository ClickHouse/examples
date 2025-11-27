#!/bin/bash

set -e

TRIES=3
QUERY_COUNT=$(grep -c '^[^#]' queries.sql)
TOTAL_QUERIES=$((QUERY_COUNT * TRIES))

# Create results directory if it doesn't exist
mkdir -p results

# Get start and end times in UTC
START_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")
# End time will be set after all queries complete

echo "Running benchmark with $QUERY_COUNT queries, $TRIES times each (total: $TOTAL_QUERIES)"

# Run all queries
cat queries.sql | while read -r query; do
    if [ -z "$query" ] || [[ "$query" == "--"* ]]; then
        continue  # Skip empty lines and comments
    fi
    
    echo "Running query: $query";
    for i in $(seq 1 $TRIES); do
        psql -h "${FQDN}" -U dev -d dev -p 5439 -t -c 'SET enable_result_cache_for_session = off' -c '\timing' -c "$query" | grep 'Time'
    done;
done;

# Get end time in UTC and run final metrics
END_TIME=$(date -u +"%Y-%m-%d %H:%M:%S")

# START_TIME="2025-09-05 11:47:00"
# END_TIME="2025-09-05 11:54:00"

# Get metrics for the benchmark run
echo "\nCollecting metrics for benchmark run..."
./get_metrics.sh "$START_TIME" "$END_TIME" "$QUERY_COUNT" "$TRIES"

