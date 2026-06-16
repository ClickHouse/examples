#!/usr/bin/env bash
# Generate Protobuf demo files locally with clickhouse local.
# Protobuf is schema-first: the .proto (events.proto, message Event) is required
# both to WRITE and to READ the binary. There is no embedded schema.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-20}
LARGE_ROWS=${LARGE_ROWS:-3000000}

SCHEMA="$(pwd)/events.proto:Event"
SMALL="$(pwd)/data/events.bin"
LARGE="$(pwd)/data/events_large.bin"
rm -f "$SMALL" "$LARGE"

gen() {
  local rows="$1" out="$2"
  clickhouse local -q "
  SELECT
      number AS id,
      ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
      ['mobile','desktop','tablet'][(number % 3) + 1] AS device,
      ['view','click','purchase'][(number % 3) + 1] AS event_type,
      round(randUniform(1, 500), 2) AS revenue,
      toUInt32((number % 4) + 1) AS quantity
  FROM numbers($rows)
  INTO OUTFILE '$out'
  FORMAT Protobuf
  SETTINGS format_schema = '$SCHEMA'
  "
}

gen "$SMALL_ROWS" "$SMALL"
gen "$LARGE_ROWS" "$LARGE"

ls -lh "$SMALL" "$LARGE"
