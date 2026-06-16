#!/usr/bin/env bash
# Generate the sample API responses used by the query-rest-api-with-sql-python how-to.
# Everything is created locally with `clickhouse local` so we can serve it over a
# plain http.server and prove url() works against a real HTTP endpoint -- no
# external API or network needed. Idempotent: re-running overwrites the files.
set -euo pipefail
cd "$(dirname "$0")"

SMALL_ROWS=${SMALL_ROWS:-5}
LARGE_ROWS=${LARGE_ROWS:-2000000}

mkdir -p data

# 1. A small "GET /orders" response: a JSON array of objects with a nested object.
#    This is the shape most REST APIs return.
clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(number % 5) + 1]              AS country,
  ['open','closed','pending'][(number % 3) + 1]            AS status,
  round((number * 137 + 1099) % 100000 / 100.0, 2)         AS amount,
  map('tier',   ['gold','silver','bronze'][(number % 3) + 1],
      'region', ['emea','apac','amer'][(number % 3) + 1])  AS labels
FROM numbers(${SMALL_ROWS})
INTO OUTFILE 'data/orders.json' TRUNCATE FORMAT JSONEachRow
"

# 2. Two 'pages' of the same endpoint, to show querying many URLs at once.
clickhouse local -q "
SELECT number AS id, ['GB','AU','IN'][(number % 3) + 1] AS country,
       round((number * 91 % 100000) / 100.0, 2) AS amount
FROM numbers(3)
INTO OUTFILE 'data/orders_page1.json' TRUNCATE FORMAT JSONEachRow
"
clickhouse local -q "
SELECT number + 1000 AS id, ['US','DE'][(number % 2) + 1] AS country,
       round((number * 53 % 100000) / 100.0, 2) AS amount
FROM numbers(3)
INTO OUTFILE 'data/orders_page2.json' TRUNCATE FORMAT JSONEachRow
"

# 3. A larger response (default 2M rows, ~120 MB) for the perf contrast vs requests+json.
clickhouse local -q "
SELECT
  number AS id,
  ['GB','AU','IN','US','DE'][(cityHash64(number) % 5) + 1] AS country,
  ['open','closed','pending'][(cityHash64(number,'s') % 3) + 1] AS status,
  round((cityHash64(number,'a') % 100000) / 100.0, 2) AS amount
FROM numbers(${LARGE_ROWS})
INTO OUTFILE 'data/orders_large.json' TRUNCATE FORMAT JSONEachRow
"

echo "Generated:"
ls -lh data
