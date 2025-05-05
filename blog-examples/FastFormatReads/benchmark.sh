#!/bin/bash
set -euo pipefail

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


# =========================================
# Usage / Arguments
# =========================================
if [[ $# -lt 6 ]]; then
    echo "Usage: $0 DATA_DIRECTORY FORMAT LOG_COMMENT RESULT_FILE_RUNTIMES RESULT_FILE_MEMORY LOG_FILE [QUERIES_FILE]"
    echo "Example: $0 /path/to/output/zstd TabSeparated runtimes.json memory.json queries.sql"
    exit 1
fi

DATA_DIR="$1"                          # e.g. /home/.../unsorted/zstd
FORMAT="$2"                            # e.g. TabSeparated
LOG_COMMENT="$3"
RESULT_FILE_RUNTIMES="$4"             # e.g. runtimes.json
RESULT_FILE_MEMORY="$5"               # e.g. memory.json
LOG_FILE="$6"
QUERIES_FILE="${7:-queries.sql}"       # defaults to queries.sql if omitted

# derive a log for the raw output
QUERY_LOG_FILE="_query_log_${FORMAT}.txt"

log "Running queries in '$QUERIES_FILE' against files under '$DATA_DIR' using format '$FORMAT'"
log "  → logging raw output to '$QUERY_LOG_FILE'"

# invoke the new runner
./run_queries.sh "$DATA_DIR" "$FORMAT" "$LOG_COMMENT" "$LOG_FILE" "$QUERIES_FILE" 2>&1 | tee "$QUERY_LOG_FILE"

# -----------------------------------------
# parse out timings (odd lines) into JSON arrays
# -----------------------------------------
RUNTIME_RESULTS=$(
  grep -E '^[0-9]' "$QUERY_LOG_FILE" \
    | awk 'NR % 2 == 1' \
    | awk -v tries=3 '{
        if ((NR-1) % tries == 0) { printf "["; }
        printf $1;
        if ((NR) % tries == 0) { print "]"; }
        else              { printf ", "; }
      }'
)

# -----------------------------------------
# parse out memory (even lines) into JSON arrays
# -----------------------------------------
MEMORY_RESULTS=$(
  grep -E '^[0-9]' "$QUERY_LOG_FILE" \
    | awk 'NR % 2 == 0' \
    | awk -v tries=3 '{
        # start a new [ ] block every `tries` values,
        # exactly like we do for runtimes
        if ((NR-1) % tries == 0) { printf "["; }
        printf $1;
        if ((NR) % tries == 0)   { print "]"; }
        else                     { printf ", "; }
      }'
)

# write out results
echo "$RUNTIME_RESULTS" > "$RESULT_FILE_RUNTIMES"
log "✓ Runtimes written to $RESULT_FILE_RUNTIMES"

echo "$MEMORY_RESULTS" > "$RESULT_FILE_MEMORY"
log "✓ Memory usage written to $RESULT_FILE_MEMORY"