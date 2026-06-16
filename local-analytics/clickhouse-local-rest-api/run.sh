#!/usr/bin/env bash
# The exact commands from the article "How to query a REST API with SQL".
# Run ./generate.sh first to create the sample data in ./data/.
#
# To prove url() against a real HTTP endpoint with ZERO external dependency, we
# serve ./data with `python3 -m http.server` on a fixed port, point url() at
# http://127.0.0.1:PORT/feed.json, then shut the server down at the end.
set -euo pipefail
cd "$(dirname "$0")/data"

PORT=${PORT:-8731}
BASE="http://127.0.0.1:$PORT"

# Start a throwaway HTTP server that stands in for a live REST API.
lsof -ti tcp:"$PORT" 2>/dev/null | xargs kill 2>/dev/null || true
python3 -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
SRV=$!
trap 'kill $SRV 2>/dev/null || true' EXIT
for i in $(seq 1 25); do
  curl -s -o /dev/null "$BASE/feed.json" && break
  sleep 0.2
done
echo "Serving ./data at $BASE (pid $SRV) -- stands in for a live REST API"
echo

echo "== 1. Fetch a JSON endpoint and read the first rows, no download step =="
clickhouse local -q "SELECT * FROM url('$BASE/feed.json', JSONEachRow) ORDER BY id LIMIT 5 FORMAT PrettyCompact"

echo
echo "== 2. Inspect the response schema (inferred from the JSON) =="
clickhouse local -q "DESCRIBE url('$BASE/feed.json', JSONEachRow) FORMAT PrettyCompact"

echo
echo "== 3. Aggregate the response in the same statement =="
clickhouse local -q "
SELECT country, count() AS events, round(sum(amount), 2) AS total
FROM url('$BASE/feed.json', JSONEachRow)
GROUP BY country
ORDER BY total DESC
FORMAT PrettyCompact"

echo
echo "== 4. Join the live response to a local lookup file =="
clickhouse local -q "
SELECT t.1 AS country, t.2 AS region
FROM (SELECT arrayJoin([('GB','EMEA'),('DE','EMEA'),('FR','EMEA'),('NL','EMEA'),
                        ('US','AMER'),('BR','AMER'),('IN','APAC'),('JP','APAC')]) AS t)
INTO OUTFILE 'regions.csv' TRUNCATE FORMAT CSVWithNames"
clickhouse local -q "
SELECT r.region AS region, count() AS events, round(sum(f.amount), 2) AS total
FROM url('$BASE/feed.json', JSONEachRow) AS f
JOIN file('regions.csv', CSVWithNames) AS r ON f.country = r.country
GROUP BY region
ORDER BY total DESC
FORMAT PrettyCompact"

echo
echo "== 5. Pass an Authorization header with the headers() clause =="
# Tiny echo server that reflects the Authorization header back as JSON, to prove
# headers() actually reaches the endpoint. Runs on PORT+1, then shuts down.
HDR_PORT=$((PORT + 1))
lsof -ti tcp:"$HDR_PORT" 2>/dev/null | xargs kill 2>/dev/null || true
cat > /tmp/_hdr_echo_server.py <<'PY'
import sys, json, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = json.dumps({"seen_auth": self.headers.get("Authorization", "none")}) + "\n"
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
        self.wfile.write(body.encode())
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
python3 /tmp/_hdr_echo_server.py "$HDR_PORT" >/dev/null 2>&1 &
HDR_SRV=$!
for i in $(seq 1 25); do curl -s -o /dev/null "http://127.0.0.1:$HDR_PORT/x" && break; sleep 0.2; done
clickhouse local -q "
SELECT seen_auth
FROM url('http://127.0.0.1:$HDR_PORT/whoami', JSONEachRow, 'seen_auth String',
         headers('Authorization'='Bearer YOUR_TOKEN'))
FORMAT PrettyCompact"
kill "$HDR_SRV" >/dev/null 2>&1 || true
wait "$HDR_SRV" 2>/dev/null || true

echo
echo "== 6. Perf: aggregate a 1.5M-row JSON response over HTTP (best-of-3, warm) =="
Q="SELECT country, count() AS events, round(sum(amount),2) AS total FROM url('$BASE/feed_large.json', JSONEachRow) GROUP BY country ORDER BY total DESC"
clickhouse local -q "$Q" > /dev/null   # warm caches
for i in 1 2 3; do
  /usr/bin/time -p clickhouse local -q "$Q" > /dev/null 2> /tmp/_api_time.txt
  echo "run $i: $(grep real /tmp/_api_time.txt)"
done
clickhouse local -q "$Q LIMIT 5 FORMAT PrettyCompact"

echo
echo "Stopping HTTP server."
