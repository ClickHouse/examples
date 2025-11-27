#!/usr/bin/env bash
set -euo pipefail
#
# Hybrid inflator for BigQuery:
#  - Doubles while the table is small.
#  - Then switches to capped chunk inserts with LIMIT to avoid shuffle limits.
#
# Usage:
#   ./inflate_until_bq_hybrid.sh <dataset.table> [target_rows] [max_batch]
# Example:
#   ./inflate_until_bq_hybrid.sh test.hits 1000000000000 200000000
#
# Defaults:
#   target_rows = 1_000_000_000 (1B)
#   max_batch   = 100_000_000   (100M)
#
# Requires: bq, jq. Table must exist and contain ≥1 row.

TABLE="${1:?Usage: $0 <dataset.table> [target_rows] [max_batch] }"
TARGET="${2:-1000000000}"
MAX_BATCH="${3:-100000000}" # cap per INSERT to avoid shuffle blowups

[[ "$TABLE" == *.* ]] || { echo "ERROR: first arg must be <dataset.table>"; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need '$1' in PATH" >&2; exit 1; }; }
need bq; need jq

row_count() {
  local json
  if ! json="$(bq show --format=json "$TABLE" 2>/dev/null)"; then
    echo 0; return
  fi
  jq -r '(.numRows // 0) | tonumber' <<<"$json"
}

run_insert() {
  local limit="$1"
  local q="
    INSERT INTO \`${TABLE}\`
    SELECT * FROM \`${TABLE}\`
    LIMIT ${limit}
  "
  # Standard SQL, quiet output; let time print elapsed
  command time -f '   insert time: %E' bq query --quiet --nouse_legacy_sql "$q"
}

echo "Target rows: $TARGET"
current="$(row_count)"
echo "Rows before inflate: $current"

(( current > 0 )) || { echo "ERROR: $TABLE is empty. Seed ≥1 row and rerun." >&2; exit 1; }

# ---- 1) Doubling until either we'd exceed TARGET or the next double > MAX_BATCH ----
dbl_iter=0
while (( current < TARGET )); do
  next=$(( current * 2 ))
  need_to_add=$(( TARGET - current ))

  # If a pure double would add more than MAX_BATCH, or exceed target, stop doubling.
  add_if_double=$(( next - current ))
  if (( add_if_double > MAX_BATCH )) || (( next > TARGET )); then
    break
  fi

  dbl_iter=$((dbl_iter+1))
  echo "===== Doubling #$dbl_iter: ${current} → ${next} (target ${TARGET}) ====="
  # Doubling is equivalent to INSERT … SELECT * (no LIMIT needed)
  # but we still guard with MAX_BATCH to be safe:
  run_insert "$add_if_double" || { echo "Doubling failed; switching to chunk mode."; break; }

  current="$(row_count)"
  echo "Rows now: $current"
done

# ---- 2) Chunk mode with LIMIT, capping each insert by MAX_BATCH and backing off on errors ----
iter=0
while (( current < TARGET )); do
  remaining=$(( TARGET - current ))
  batch=$(( remaining < MAX_BATCH ? remaining : MAX_BATCH ))
  iter=$((iter+1))
  echo "===== Chunk #$iter: inserting up to $batch rows into ${TABLE} (remaining $remaining) ====="

  # Simple retry with halving batch on resource errors
  attempt=0
  ok=0
  local_batch="$batch"
  while (( attempt < 6 )); do
    attempt=$((attempt+1))
    if run_insert "$local_batch"; then
      ok=1
      break
    else
      echo "   insert failed (attempt $attempt). Backing batch off …"
      # halve the batch, but not below 1
      local_batch=$(( local_batch / 2 ))
      (( local_batch > 0 )) || { echo "   batch reached 0 — giving up"; exit 1; }
      sleep 2
    fi
  done

  (( ok == 1 )) || { echo "ERROR: unable to insert even tiny batch. Exiting."; exit 1; }

  current="$(row_count)"
  echo "Rows now: $current"
done

echo "Target reached (>= $TARGET). Final row count: $(row_count)"