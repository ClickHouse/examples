#!/usr/bin/env bash
set -euo pipefail
#
# Repeatedly load hits_{0..99}.parquet into ClickHouse Cloud
# until TARGET rows are reached.  If default.hits does not exist,
# it is created from create.sql first.
#
# Environment variables required:
#   export FQDN="your-service-fqdn.clickhouse.cloud"
#   export PASSWORD="your_password"
#
# Usage:
#   ./load_until.sh [target_rows]
# Example:
#   ./load_until.sh 1000000000
#
# Default target_rows: 1,000,000,000
#
# Table is always: default.hits
# ---------------------------------------------

TARGET="${1:-1000000000}"
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

# --- Create table if needed ---
if [[ "$(table_exists)" != "1" ]]; then
  echo "Table $TABLE does not exist — creating from create.sql ..."
  cli < create.sql
fi

echo "Target rows: $TARGET"
before="$(row_count)"
echo "Current rows in $TABLE: $before"

iter=0
while :; do
  current="$(row_count)"
  printf "Rows: %s\r" "$current"
  if [[ "$current" =~ ^[0-9]+$ ]] && (( current >= TARGET )); then
    echo
    echo "Target reached (>= $TARGET). Done."
    break
  fi

  iter=$((iter+1))
  echo
  echo "===== Iteration #$iter: loading rows from 100 parquet files to $TABLE ====="

  # Append the 100 parquet parts. --time prints elapsed at the end.
  cli --time --query "
    INSERT INTO $TABLE
    SELECT *
    FROM url('https://datasets.clickhouse.com/hits_compatible/athena_partitioned/hits_{0..99}.parquet')
  "

  # Optional: small pause if desired
  # sleep 1
done

final="$(row_count)"
echo "Final rows in $TABLE: $final"