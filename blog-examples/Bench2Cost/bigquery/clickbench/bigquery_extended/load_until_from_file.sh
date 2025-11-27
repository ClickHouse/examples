#!/usr/bin/env bash
set -euo pipefail
#
# Usage:
#   ./load_until.sh <dataset.table> [csv_file] [target_rows]
#
# Example:
#   ./load_until.sh test.hits hits.csv 1000000000
#
# Default csv_file: hits.csv
# Default target_rows: 1000000000

TABLE="${1:?Usage: $0 <dataset.table> [csv_file] [target_rows] }"
CSV="${2:-hits.csv}"
TARGET="${3:-1000000000}"

# -------- helpers ---------
need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found in PATH" >&2; exit 1; }; }
need bq; need jq

[[ -f "$CSV" ]] || { echo "ERROR: CSV file not found: $CSV" >&2; exit 1; }

row_count() {
    # Returns current number of rows in the table (0 if table does not exist yet)
    local json
    if ! json="$(bq show --format=json "$TABLE" 2>/dev/null)"; then
        echo 0
        return
    fi
    jq -r '(.numRows // 0) | tonumber' <<<"$json"
}
# --------------------------

echo "Checking current row count for $TABLE ..."
current=$(row_count)
echo "Rows before loading: $current"

iter=0
while (( current < TARGET )); do
    iter=$((iter+1))
    echo "Iteration #$iter: loading $CSV into $TABLE"
    command time -f '   load time: %E' \
      bq load \
        --source_format=CSV \
        --allow_quoted_newlines=1 \
        "$TABLE" \
        "$CSV"
    current=$(row_count)
    echo "Rows now: $current"
done

echo "Target reached (>= $TARGET rows). Final row count: $current"