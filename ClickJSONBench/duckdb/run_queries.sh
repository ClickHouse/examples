#!/bin/bash

# Check if the required arguments are provided
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <DB_NAME>"
    exit 1
fi

# Arguments
DB_NAME="$1"

DUCKDB_CMD="duckdb $DB_NAME"

TRIES=3

LOG_FILE="query_results.log"
> "$LOG_FILE"

cat queries.sql | while read -r query; do
    # Clear filesystem cache between queries.
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null

    echo "Running query: $query"
    for i in $(seq 1 $TRIES); do
        start=`date +%s`
        # Run query with timer enabled and extract the real time.
        OUTPUT=$($DUCKDB_CMD <<EOF >> "$LOG_FILE"
.timer on
$query
EOF
)
        end=`date +%s.%N`
        runtime=$( echo "$end - $start" | bc -l )
        runtime_formatted=$(printf "%.3f" "$runtime")
        REAL_TIME=$(tac "$LOG_FILE" | grep -m 1 -oP 'real\s+\K[\d.]+')
        echo "Real time: $runtime_formatted seconds"
    done
done