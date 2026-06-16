#!/usr/bin/env bash
# The exact commands from the article "How to parse a log file with regex in SQL".
# Run ./generate.sh first to create the sample data in ./data/.
set -euo pipefail
cd "$(dirname "$0")/data"

# The regex used throughout: one capture group per column.
RE='^(\S+) - - \[([^\]]+)\] "(\S+) (\S+) [^"]+" (\d+) (\d+) (\S+)'

echo "== 1. A raw log line is unstructured text =="
head -n 3 access.log

echo
echo "== 2. Parse it into typed columns with the Regexp format =="
clickhouse local -q "
SELECT *
FROM file('access.log', Regexp,
  'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64')
LIMIT 5
SETTINGS format_regexp = '$RE', format_regexp_escaping_rule = 'Raw'
FORMAT PrettyCompact"

echo
echo "== 3. Turn the log timestamp into a real DateTime =="
clickhouse local -q "
SELECT
  ip,
  parseDateTime(substring(ts, 1, 20), '%d/%b/%Y:%H:%i:%s') AS event_time,
  method, path, status
FROM file('access.log', Regexp,
  'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64')
ORDER BY event_time
LIMIT 5
SETTINGS format_regexp = '$RE', format_regexp_escaping_rule = 'Raw'
FORMAT PrettyCompact"

echo
echo "== 4. Aggregate: error rate and traffic by path =="
clickhouse local -q "
SELECT
  path,
  count() AS hits,
  countIf(status >= 400) AS errors,
  round(100.0 * countIf(status >= 400) / count(), 1) AS error_pct,
  round(avg(rt), 3) AS avg_rt_s
FROM file('access.log', Regexp,
  'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64')
GROUP BY path
ORDER BY hits DESC
SETTINGS format_regexp = '$RE', format_regexp_escaping_rule = 'Raw'
FORMAT PrettyCompact"

echo
echo "== 5. Read a gzipped log transparently (.log.gz) =="
clickhouse local -q "
SELECT status, count() AS n
FROM file('access.log.gz', Regexp,
  'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64')
GROUP BY status
ORDER BY status
SETTINGS format_regexp = '$RE', format_regexp_escaping_rule = 'Raw'
FORMAT PrettyCompact"

echo
echo "== 6. Perf: parse + aggregate the 2M-line, ~163 MB access_large.log (best-of-3, warm) =="
Q="SELECT status, count() AS n, round(avg(rt),3) AS avg_rt FROM file('access_large.log', Regexp, 'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64') GROUP BY status ORDER BY status SETTINGS format_regexp = '$RE', format_regexp_escaping_rule = 'Raw'"
clickhouse local -q "$Q FORMAT Null"   # warm the OS page cache
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q FORMAT Null" > /dev/null 2> /tmp/_re_time.txt
  echo "run $i: $(grep real /tmp/_re_time.txt)"
done
clickhouse local -q "$Q FORMAT PrettyCompact"
