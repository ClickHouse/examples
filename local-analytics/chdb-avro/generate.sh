#!/usr/bin/env bash
# Generate the sample Avro files used by the read-avro-file-python how-to.
# Everything is created locally with `clickhouse local`, which writes Avro with
# the schema embedded in the file. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-3000000}

mkdir -p data

# 1. Small Avro file with a nested record (user) for the read examples.
#    Avro carries its full schema in the file header, including the nested
#    record type, so chDB infers everything without you declaring a structure.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1]      AS country,
  ['purchase','view'][(number % 2) + 1]   AS event_type,
  round((cityHash64(number, 'a') % 10000) / 100.0, 2) AS amount,
  tuple(number + 100, ['gold','silver','bronze'][(number % 3) + 1])
    ::Tuple(id UInt64, tier String)       AS user
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/events.avro' TRUNCATE FORMAT Avro
SETTINGS output_format_avro_codec = 'deflate'
"

# 2. A larger Avro file (3M rows by default) for the performance contrast.
clickhouse local -q "
SELECT
  number AS event_id,
  ['GB','AU','IN'][(number % 3) + 1]      AS country,
  ['purchase','view'][(number % 2) + 1]   AS event_type,
  round(randUniform(1, 100), 2)           AS amount
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/events_large.avro' TRUNCATE FORMAT Avro
SETTINGS output_format_avro_codec = 'deflate'
"

echo "Generated:"
ls -lh data
