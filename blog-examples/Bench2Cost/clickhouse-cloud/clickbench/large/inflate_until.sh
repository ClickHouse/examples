#!/usr/bin/env bash
set -euo pipefail
#
# Exponentially inflate a ClickHouse table by self-inserting:
#   1) While rows*2 <= TARGET:  INSERT INTO t SELECT * FROM t;
#   2) Final top-off:           INSERT INTO t SELECT * FROM t LIMIT remaining;
#
# Env:
#   export FQDN="your-service-fqdn.clickhouse.cloud"
#   export PASSWORD="your_password"
#
# Usage:
#   ./inflate_until_exp.sh [target_rows]
# Example:
#   ./inflate_until_exp.sh 1000000000000
#
# Table is hard-coded: default.hits
# ------------------------------------------------------------

TARGET="${1:-1000000000}"      # default: 1 billion rows
TABLE="default.hits"

: "${FQDN:?ERROR: please export FQDN}"
: "${PASSWORD:?ERROR: please export PASSWORD}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: need '$1' in PATH" >&2; exit 1; }; }
need clickhouse-client

cli() {
  clickhouse-client \
    --host "$FQDN" \
    --secure \
    --password "$PASSWORD" \
    "$@"
}

table_exists() {
  cli --query "EXISTS TABLE $TABLE" --format=TSV | tr -d '[:space:]'
}

row_count() {
  cli --query "SELECT toUInt64(count()) FROM $TABLE" --format=TSV | tr -d '[:space:]'
}

# --- Ensure table exists ---
if [[ "$(table_exists)" != "1" ]]; then
  echo "Table $TABLE does not exist — creating from create.sql ..."
  cli < create.sql
fi

current="$(row_count)"
if (( current == 0 )); then
  echo "ERROR: $TABLE is empty. Seed it with at least 1 row, then rerun." >&2
  exit 1
fi

echo "Target rows: $TARGET"
echo "Starting rows in $TABLE: $current"

# 1) Doubling phase
dbl_iter=0
while (( current * 2 <= TARGET )); do
  dbl_iter=$((dbl_iter+1))
  echo "===== Doubling #$dbl_iter: ${current} → $((current*2)) (target ${TARGET}) ====="
  cli --time --query "
    INSERT INTO $TABLE
    SELECT * FROM $TABLE
  "
  current="$(row_count)"
  echo "Rows now: $current"
done

# 2) Final precise top-off
if (( current < TARGET )); then
  remaining=$(( TARGET - current ))
  echo "===== Final top-off: inserting exactly ${remaining} rows into ${TABLE} ====="
  cli --time --query "
    INSERT INTO $TABLE
    SELECT * FROM $TABLE
    LIMIT $remaining
  "
  current="$(row_count)"
fi

echo "✅ Target reached (>= $TARGET). Final row count: $current"