#!/usr/bin/env bash
set -euo pipefail

# --------- config ----------
QUERY_FILE="${1:-queries.sql}"   # pass a different file as arg1 if needed
SYSTEM_NAME="BigQuery"
MACHINE_DESC="serverless"
CLUSTER_DESC="serverless"
PROPRIETARY="yes"
TUNED="no"
COMMENT=""
LOAD_TIME_SEC=0
DATA_SIZE_BYTES=0
TAGS='["serverless","column-oriented","gcp","managed"]'
VERBOSE="${VERBOSE:-0}"          # set VERBOSE=1 to see extra debug
# --------------------------

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found." >&2; exit 1; }; }
need bq; need jq; need uuidgen; need awk; need sed

[[ -f "$QUERY_FILE" ]] || { echo "ERROR: Query file not found: $QUERY_FILE" >&2; exit 1; }

# Read queries from file, split by semicolon, trim whitespace, ignore empties.
mapfile -t QUERIES < <(awk '
  BEGIN{RS=";"; ORS=""}
  { q=$0; gsub(/^[ \t\r\n]+|[ \t\r\n]+$/,"",q); if (length(q)>0) print q "\n" }
' "$QUERY_FILE")

(( ${#QUERIES[@]} > 0 )) || { echo "ERROR: No queries found in $QUERY_FILE" >&2; exit 1; }

RESULT_ROWS=()
SLOTS_ROWS=()
BYTES_ROWS=()

run_one() {
  local query="$1"
  local JOB_ID="job_$(uuidgen | tr "A-Z" "a-z" | tr -d "-")"

  # Human-facing banner → STDERR
  {
    echo
    echo "============================================================"
    echo "Query (job: $JOB_ID):"
    echo "$query;"
    echo "============================================================"
  } >&2

  # Force pretty table output and also route it → STDERR so you see it live,
  # while stdout remains clean for the metrics line we capture.
  if bq query \
        --nouse_legacy_sql \
        --use_cache=false \
        --format=pretty \
        --max_rows=100000 \
        --job_id="$JOB_ID" \
        "$query;" 1>&2; then

    # Pull metrics for exactly this job
    local METRICS_JSON
    METRICS_JSON="$(bq show -j --format=json "$JOB_ID")" || true

    local RUNTIME_S BILLED_SLOT_S BILLED_BYTES
    RUNTIME_S="$(jq -r '(.statistics.finalExecutionDurationMs // null) as $m | if $m==null then null else ($m|tonumber/1000) end' <<< "$METRICS_JSON")"
    BILLED_SLOT_S="$(jq -r '(.statistics.totalSlotMs // null) as $s | if $s==null then null else ($s|tonumber/1000) end' <<< "$METRICS_JSON")"
    BILLED_BYTES="$(jq -r '( .statistics.query.totalBytesBilled // .statistics.totalBytesBilled // null )' <<< "$METRICS_JSON")"
    if [[ "$BILLED_BYTES" != "null" ]]; then
      BILLED_BYTES="$(jq -r 'tonumber' <<<"$BILLED_BYTES")" || BILLED_BYTES="null"
    fi

    # Human-facing metrics line → STDERR
    echo "" >&2
    echo "METRICS → jobId=$JOB_ID  runtime_sec=${RUNTIME_S:-null}  billed_slot_sec=${BILLED_SLOT_S:-null}  billed_bytes=${BILLED_BYTES:-null}" >&2
    echo "" >&2

    # Machine-captured triplet → STDOUT (this is what $(run_one) grabs)
    echo "${RUNTIME_S:-null}|${BILLED_SLOT_S:-null}|${BILLED_BYTES:-null}"
  else
    echo "Query failed. Recording null metrics." >&2
    echo "null|null|null"
  fi
}

for ((qi=0; qi<${#QUERIES[@]}; qi++)); do
  Q="${QUERIES[$qi]}"

  RUNTIMES=()
  SLOTS=()
  BYTES=()

  for rep in 1 2 3; do
    echo ">>> Run $rep/3 for query #$((qi+1))"
    triplet="$(run_one "$Q")"  # "runtime|slot|bytes"
    runtime="${triplet%%|*}"; rest="${triplet#*|}"
    slot="${rest%%|*}"; bytes="${rest#*|}"

    RUNTIMES+=("${runtime}")
    SLOTS+=("${slot}")
    BYTES+=("${bytes}")
  done

  row_result="$(printf '[%s,%s,%s]' "${RUNTIMES[0]}" "${RUNTIMES[1]}" "${RUNTIMES[2]}")"
  row_slots="$(printf  '[%s,%s,%s]' "${SLOTS[0]}"    "${SLOTS[1]}"    "${SLOTS[2]}")"
  row_bytes="$(printf  '[%s,%s,%s]' "${BYTES[0]}"    "${BYTES[1]}"    "${BYTES[2]}")"

  RESULT_ROWS+=("$row_result")
  SLOTS_ROWS+=("$row_slots")
  BYTES_ROWS+=("$row_bytes")
done

join_by_comma() { local IFS=,; echo "$*"; }

RESULT_JSON="$(join_by_comma "${RESULT_ROWS[@]}")"
SLOTS_JSON="$(join_by_comma "${SLOTS_ROWS[@]}")"
BYTES_JSON="$(join_by_comma "${BYTES_ROWS[@]}")"

DATE_ISO="$(date -u +%F)"
cat <<JSON
{
  "system": "$SYSTEM_NAME",
  "date": "$DATE_ISO",
  "machine": "$MACHINE_DESC",
  "cluster_size": "$CLUSTER_DESC",
  "proprietary": "$PROPRIETARY",
  "tuned": "$TUNED",
  "comment": "$COMMENT",
  "tags": $TAGS,
  "load_time": $LOAD_TIME_SEC,
  "data_size": $DATA_SIZE_BYTES,

  "result": [
    $RESULT_JSON
  ],
  "billed_slot_sec": [
    $SLOTS_JSON
  ],
  "billed_bytes": [
    $BYTES_JSON
  ]
}
JSON