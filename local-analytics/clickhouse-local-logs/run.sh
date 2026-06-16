#!/usr/bin/env bash
# The exact commands from the article:
#   https://clickhouse.com/resources/engineering/analyze-log-files-with-sql
# Run ./generate.sh first.
set -euo pipefail
cd "$(dirname "$0")"

# A reusable extraction CTE. extractGroups() pulls the nginx combined fields out
# of each raw line; parseDateTime() turns the nginx timestamp into a real DateTime.
EXTRACT="WITH extractGroups(line, '^(\\\\S+) - - \\\\[([^\\\\]]+)\\\\] \"(\\\\S+) (\\\\S+) [^\"]*\" (\\\\d+) (\\\\d+) \"[^\"]*\" \"[^\"]*\" (\\\\S+)') AS g"

echo "== 1. read raw lines =="
clickhouse local -q "SELECT * FROM file('access.log', LineAsString) LIMIT 5"

echo; echo "== 2. extract fields =="
clickhouse local -q "
${EXTRACT}
SELECT
  g[1] AS ip,
  parseDateTime(g[2], '%d/%b/%Y:%H:%i:%S %z', 'UTC') AS ts,
  g[3] AS method,
  g[4] AS path,
  toUInt16(g[5]) AS status,
  toFloat64(g[7]) AS request_time
FROM file('access.log', LineAsString)
LIMIT 5"

echo; echo "== 3. status-code counts =="
clickhouse local -q "
${EXTRACT}
SELECT toUInt16(g[5]) AS status, count() AS requests
FROM file('access.log', LineAsString)
GROUP BY status ORDER BY requests DESC"

echo; echo "== 4. p95 / p99 latency =="
clickhouse local -q "
${EXTRACT}
SELECT
  round(quantile(0.95)(toFloat64(g[7])), 3) AS p95_s,
  round(quantile(0.99)(toFloat64(g[7])), 3) AS p99_s,
  round(max(toFloat64(g[7])), 3)            AS max_s
FROM file('access.log', LineAsString)"

echo; echo "== 5. top URLs =="
clickhouse local -q "
${EXTRACT}
SELECT g[4] AS path, count() AS hits
FROM file('access.log', LineAsString)
GROUP BY path ORDER BY hits DESC LIMIT 5"

echo; echo "== 6. top IPs by 5xx errors =="
clickhouse local -q "
${EXTRACT}
SELECT g[1] AS ip, count() AS errors
FROM file('access.log', LineAsString)
WHERE toUInt16(g[5]) >= 500
GROUP BY ip ORDER BY errors DESC LIMIT 5"

echo; echo "== 7. requests per minute =="
clickhouse local -q "
${EXTRACT}
SELECT
  toStartOfMinute(parseDateTime(g[2], '%d/%b/%Y:%H:%i:%S %z', 'UTC')) AS minute,
  count() AS requests
FROM file('access.log', LineAsString)
GROUP BY minute ORDER BY minute LIMIT 5"

echo; echo "== 8. glob over rotated, gzipped logs (read transparently) =="
clickhouse local -q "
${EXTRACT}
SELECT toUInt16(g[5]) AS status, count() AS requests
FROM file('logs/*.log.gz', LineAsString)
GROUP BY status ORDER BY requests DESC"

if [[ -f big_access.log ]]; then
  echo; echo "== 9. perf: parse + aggregate 20M lines / 2.4 GB =="
  clickhouse local --time -q "
  ${EXTRACT}
  SELECT toUInt16(g[5]) AS status, count() AS requests,
         round(quantile(0.95)(toFloat64(g[7])), 3) AS p95
  FROM file('big_access.log', LineAsString)
  GROUP BY status ORDER BY requests DESC"
fi
