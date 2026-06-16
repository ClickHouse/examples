#!/usr/bin/env bash
# Generate small demo TSV files locally with clickhouse local.
# Writes a tab-separated file with a header (TSVWithNames) and, for contrast,
# a CSV holding a field that needs quoting (a comma + a quote) so the
# delimiter/quoting difference vs TSV is visible.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

ROWS=${ROWS:-12}

TSV="$(pwd)/data/events.tsv"
CSV="$(pwd)/data/events.csv"
rm -f "$TSV" "$CSV"

# Tab-separated values, with a header row (TSVWithNames).
clickhouse local -q "
SELECT
    number AS id,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    ['view','click','purchase'][(number % 3) + 1] AS event_type,
    round(randUniform(1, 500), 2) AS revenue
FROM numbers($ROWS)
INTO OUTFILE '$TSV'
FORMAT TSVWithNames
"

# Same rows as CSV, but with a label column that contains a comma and a quote,
# so CSV has to quote/escape it. TSV would not need quoting for commas.
clickhouse local -q "
SELECT
    number AS id,
    ['GB','AU','IN','US','DE'][(number % 5) + 1] AS country,
    concat('VIP, \"gold\" tier #', toString(number)) AS label
FROM numbers($ROWS)
INTO OUTFILE '$CSV'
FORMAT CSVWithNames
"

ls -lh "$TSV" "$CSV"
