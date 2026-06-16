#!/usr/bin/env bash
# Generates synthetic nginx "combined" access logs locally with `clickhouse local`.
# Nothing large is committed to git; everything is reproducible from this script.
#
#   access.log            50,000 lines  (~6 MB)   -- the worked example
#   logs/access-{1,2,3}.log.gz  3 x 5,000 lines   -- rotated + gzip-compressed
#   big_access.log        20,000,000 lines (~2.4 GB) -- the perf file (opt-in)
#
# Pass --big to also generate the 2.4 GB perf file (off by default; it is large).
set -euo pipefail
cd "$(dirname "$0")"

# nginx combined log format:
#   IP - - [dd/Mon/yyyy:HH:MM:SS +0000] "METHOD PATH HTTP/1.1" STATUS BYTES "ref" "ua" REQUEST_TIME
gen() {  # gen <rows> <rows_per_second> <base_datetime> <seed> <outfile>
  local rows="$1" rps="$2" base="$3" seed="$4" out="$5"
  clickhouse local -q "
    WITH
      ['GET','GET','GET','GET','POST','PUT','DELETE'] AS methods,
      ['/','/index.html','/api/users','/api/orders','/login','/static/app.js','/static/style.css','/images/logo.png','/api/products','/checkout'] AS paths,
      [200,200,200,200,200,301,304,404,500,503] AS statuses
    SELECT
      '198.51.100.' || toString(cityHash64(number, ${seed}) % 254 + 1)
      || ' - - [' || formatDateTime(toDateTime('${base}') + intDiv(number, ${rps}), '%d/%b/%Y:%H:%i:%S +0000')
      || '] \"' || methods[(cityHash64(number, 1) % 7) + 1] || ' ' || paths[(cityHash64(number, 2) % 10) + 1] || ' HTTP/1.1\" '
      || toString(statuses[(cityHash64(number, 3) % 10) + 1]) || ' '
      || toString(cityHash64(number, 4) % 50000 + 200)
      || ' \"-\" \"Mozilla/5.0 (compatible)\" '
      || toString(round((cityHash64(number, 5) % 2000000) / 1000000.0, 3)) AS line
    FROM numbers(${rows})
    INTO OUTFILE '${out}' TRUNCATE FORMAT TSVRaw
  "
}

echo "generating access.log (50,000 lines) ..."
gen 50000 5 '2026-06-01 00:00:00' 0 'access.log'

echo "generating rotated + gzipped logs/access-{1,2,3}.log.gz ..."
mkdir -p logs
gen 5000 5 '2026-05-21 00:00:00' 1 'logs/access-1.log.gz'
gen 5000 5 '2026-05-22 00:00:00' 2 'logs/access-2.log.gz'
gen 5000 5 '2026-05-23 00:00:00' 3 'logs/access-3.log.gz'

if [[ "${1:-}" == "--big" ]]; then
  echo "generating big_access.log (20,000,000 lines, ~2.4 GB) ..."
  gen 20000000 50 '2026-06-01 00:00:00' 0 'big_access.log'
fi

echo "done."
ls -lh access.log logs/ ${1:+big_access.log} 2>/dev/null || true
