#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------
# ClickHouse environment / client wrapper
# ---------------------------------------
# Defaults allow localhost dev with no password & no TLS.
CH_HOST="${CH_HOST:-localhost}"
CH_USER="${CH_USER:-default}"
CH_PASSWORD="${CH_PASSWORD-}"          # may be empty / unset
CH_SECURE="${CH_SECURE:-}"             # set to true/1/yes to enable --secure


# Build client command with optional flags
CH_SECURE_FLAG=""
if [[ "${CH_SECURE,,}" =~ ^(1|true|yes)$ ]]; then
  CH_SECURE_FLAG="--secure"
fi

CH_PASSWORD_PART=""
if [[ -n "${CH_PASSWORD}" ]]; then
  CH_PASSWORD_PART="--password ${CH_PASSWORD}"
fi

CH_CLIENT="clickhouse client --host ${CH_HOST} --user ${CH_USER} ${CH_PASSWORD_PART} ${CH_SECURE_FLAG}"

# ---------------------------
# Arguments
# ---------------------------
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <TARGET_ROWS> [MAX_INSERT_THREADS]"
  echo "Examples:"
  echo "  $0 100000000             # 100 million rows, default threads"
  echo "  $0 1000000000000 40      # 1 trillion rows, 40 threads"
  exit 1
fi

TARGET_ROWS="$1"
MAX_INSERT_THREADS="${2:-30}"   # optional, defaults to 30

# ---------------------------------------------------------
# STEP 0: Check if uk_base.uk_price_paid exists, else create + load
# ---------------------------------------------------------
EXISTS=$($CH_CLIENT --query "
    SELECT count()
    FROM system.tables
    WHERE database = 'uk_base' AND name = 'uk_price_paid';
")

if [[ "$EXISTS" -eq 0 ]]; then
  echo "⚙️ Base table uk_base.uk_price_paid not found. Bootstrapping..."

  # Create db
  $CH_CLIENT --query "CREATE DATABASE IF NOT EXISTS uk_base;"

  # Create base table
  $CH_CLIENT --database="uk_base" --query "
  CREATE TABLE uk_price_paid
  (
      price UInt32,
      date Date,
      postcode1 LowCardinality(String),
      postcode2 LowCardinality(String),
      type Enum8('terraced' = 1, 'semi-detached' = 2, 'detached' = 3, 'flat' = 4, 'other' = 0),
      is_new UInt8,
      duration Enum8('freehold' = 1, 'leasehold' = 2, 'unknown' = 0),
      addr1 String,
      addr2 String,
      street LowCardinality(String),
      locality LowCardinality(String),
      town LowCardinality(String),
      district LowCardinality(String),
      county LowCardinality(String)
  )
  ENGINE = MergeTree
  ORDER BY (postcode1, postcode2, addr1, addr2);
  "

  # Load dataset
  echo "⬇️ Loading Land Registry CSV into uk_base.uk_price_paid (this may take a while)..."
  $CH_CLIENT --database="uk_base" --query "
  INSERT INTO uk_price_paid
  SELECT
      toUInt32(price_string) AS price,
      parseDateTimeBestEffortUS(time) AS date,
      splitByChar(' ', postcode)[1] AS postcode1,
      splitByChar(' ', postcode)[2] AS postcode2,
      transform(a, ['T', 'S', 'D', 'F', 'O'], ['terraced', 'semi-detached', 'detached', 'flat', 'other']) AS type,
      b = 'Y' AS is_new,
      transform(c, ['F', 'L', 'U'], ['freehold', 'leasehold', 'unknown']) AS duration,
      addr1,
      addr2,
      street,
      locality,
      town,
      district,
      county
  FROM url(
      'http://prod1.publicdata.landregistry.gov.uk.s3-website-eu-west-1.amazonaws.com/pp-complete.csv',
      'CSV',
      'uuid_string String,
       price_string String,
       time String,
       postcode String,
       a String,
       b String,
       c String,
       addr1 String,
       addr2 String,
       street String,
       locality String,
       town String,
       district String,
       county String,
       d String,
       e String'
  ) SETTINGS max_http_get_redirects=10;
  "

  echo "✅ Base table uk_base.uk_price_paid loaded."
else
  echo "✅ Base table uk_base.uk_price_paid already exists. Skipping bootstrap."
fi

# ---------------------------
# Derive target DB name: uk_m / uk_b / uk_t
# ---------------------------
if (( TARGET_ROWS % 1000000000000 == 0 )); then
  TARGET_DB="uk_t$(( TARGET_ROWS / 1000000000000 ))"
elif (( TARGET_ROWS % 1000000000 == 0 )); then
  TARGET_DB="uk_b$(( TARGET_ROWS / 1000000000 ))"
elif (( TARGET_ROWS % 1000000 == 0 )); then
  TARGET_DB="uk_m$(( TARGET_ROWS / 1000000 ))"
else
  TARGET_DB="uk_raw${TARGET_ROWS}"
fi
TARGET_TABLE="uk_price_paid"

echo "🎯 Target rows: $TARGET_ROWS"
echo "📦 Target database: ${TARGET_DB} (table ${TARGET_TABLE})"
echo "⚙️ max_insert_threads = ${MAX_INSERT_THREADS}"

# ---------------------------
# Create target DB + table
# ---------------------------
$CH_CLIENT --query="CREATE DATABASE IF NOT EXISTS ${TARGET_DB}"

$CH_CLIENT --database="${TARGET_DB}" --query "
CREATE TABLE IF NOT EXISTS ${TARGET_TABLE}
AS uk_base.uk_price_paid
ENGINE = MergeTree
ORDER BY (postcode1, postcode2, addr1, addr2);
"

# ---------------------------
# Base table size
# ---------------------------
BASE_ROWS=$($CH_CLIENT --query "SELECT count() FROM uk_base.uk_price_paid;")
if (( BASE_ROWS == 0 )); then
  echo "❌ Base table uk_base.uk_price_paid is empty; cannot proceed."
  exit 1
fi
echo "📏 Base batch size: $BASE_ROWS rows"

CURRENT=$($CH_CLIENT --query "SELECT count() FROM ${TARGET_DB}.${TARGET_TABLE};")
echo "🔢 Current rows in ${TARGET_DB}.${TARGET_TABLE}: $CURRENT"

if (( CURRENT >= TARGET_ROWS )); then
  echo "✅ Target already met or exceeded. Nothing to do."
  exit 0
fi

REMAINING=$(( TARGET_ROWS - CURRENT ))
FULL_ITERS=$(( REMAINING / BASE_ROWS ))
REMAINDER=$(( REMAINING % BASE_ROWS ))

echo "🧮 Remaining rows: $REMAINING"
echo "🔁 Full inserts needed: $FULL_ITERS"
echo "➕ Remainder for final limited insert: $REMAINDER"

run_full_insert () {
  $CH_CLIENT --query "
    INSERT INTO ${TARGET_DB}.${TARGET_TABLE}
    SELECT * FROM uk_base.uk_price_paid
    SETTINGS max_insert_threads = ${MAX_INSERT_THREADS};
  "
}

run_limited_insert () {
  local LIM="$1"
  $CH_CLIENT --query "
    INSERT INTO ${TARGET_DB}.${TARGET_TABLE}
    SELECT *
    FROM uk_base.uk_price_paid
    ORDER BY tuple()                  -- make LIMIT exact across threads/parts
    LIMIT ${LIM}
    SETTINGS max_insert_threads = ${MAX_INSERT_THREADS};
  "
}

# ---------------------------
# Execute inserts to hit EXACT target
# ---------------------------
for (( i=1; i<=FULL_ITERS; i++ )); do
  before=$($CH_CLIENT --query "SELECT count() FROM ${TARGET_DB}.${TARGET_TABLE};")
  echo "➡️  Full insert $i/$FULL_ITERS (before: $before rows)"
  run_full_insert
  after=$($CH_CLIENT --query "SELECT count() FROM ${TARGET_DB}.${TARGET_TABLE};")
  echo "   ✅ Done (after: $after rows)"
done

# Recompute remainder right before the limited insert
sleep 5   # ⏸️ pause to let merges/replication settle before final LIMIT insert
CURRENT=$($CH_CLIENT --query "SELECT count() FROM ${TARGET_DB}.${TARGET_TABLE};")
REMAINING=$(( TARGET_ROWS - CURRENT ))
if (( REMAINING > 0 )); then
  echo "➡️  Final limited insert to reach target (LIMIT ${REMAINING})"
  run_limited_insert "${REMAINING}"
fi

final=$($CH_CLIENT --query "SELECT count() FROM ${TARGET_DB}.${TARGET_TABLE};")
echo "🏁 Final row count: $final (target: $TARGET_ROWS)"