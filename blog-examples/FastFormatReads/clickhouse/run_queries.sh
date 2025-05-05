#!/bin/bash
set -euo pipefail


log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


# =========================================
# Usage / Arguments
# =========================================
if [[ $# -lt 4 ]]; then
    echo "Usage: $0 DB EXTRA_SETTINGS LOG_COMMENT LOG_FILE [QUERIES_FILE]"
    exit 1
fi

DB="$1"
EXTRA_SETTINGS="$2"
LOG_COMMENT="$3"
LOG_FILE="$4"
QUERIES_FILE="${5:-queries.sql}"      # defaults to queries.sql if not passed
TRIES=3

# =========================================
# Process each query
# =========================================
while IFS= read -r query || [[ -n "$query" ]]; do


    # clear OS cache
    log "Clearing file system cache..."
    sync
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null
    log "File system cache cleared."

    log "Running query: $query"

    # Append extra settings if provided
    adapted_query="$query"
    if [ -n "$EXTRA_SETTINGS" ]; then
        adapted_query=$(echo "$query" | sed "s/;[[:space:]]*$/ SETTINGS $EXTRA_SETTINGS;/")
    fi

    # execute TRIES times, feeding SQL via stdin
    for run in $(seq 1 $TRIES); do
        clickhouse-client \
          --database="${DB}" \
          --time \
          --memory-usage \
          --progress 0 \
          --log_comment="${LOG_COMMENT}" \
          --format=Null <<EOF
$adapted_query;
EOF
    done

done < "$QUERIES_FILE"