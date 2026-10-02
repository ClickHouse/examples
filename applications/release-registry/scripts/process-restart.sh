#!/usr/bin/env bash
# Run after loading app.env on a disposable Cloud service. Changes production.
set -euo pipefail
umask 077
export PORT="${RESTART_PORT:-3043}"
ROOT="http://127.0.0.1:$PORT"
RESULTS=.deployment/restart-results
mkdir -p "$RESULTS"
API_TOKEN="$(printf '%s' "$PROJECT_TOKENS" | jq -er '.["00000000-0000-4000-8000-000000000001"]')"
VERSION="restart-$(date +%s)-$$"
pid=''
trap 'if [[ -n "$pid" ]]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi' EXIT

start() {
  env -i PGHOST="$PGHOST" PGPORT="${PGPORT:-5432}" PGDATABASE="$PGDATABASE" \
    PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" PGSSLROOTCERT="$PGSSLROOTCERT" \
    PROJECT_TOKENS="$PROJECT_TOKENS" PORT="$PORT" \
    target/debug/release-registry serve > "$RESULTS/server-$1.txt" 2>&1 &
  pid=$!
  for attempt in {1..30}; do
    if curl --silent --fail "$ROOT/health" >/dev/null; then return; fi
    sleep 1
  done
  printf 'Server did not become ready\n' >&2
  exit 1
}

start before
first=$pid
curl --silent --fail -H "Authorization: Bearer $API_TOKEN" \
  "$ROOT/channels/production" > "$RESULTS/channel-initial.json"
revision="$(jq -er .revision "$RESULTS/channel-initial.json")"
jq -n --arg version "$VERSION" \
  '{version:$version,digest:("sha256:"+("a"*64)),metadata:{commit:"restart-proof"}}' \
  > "$RESULTS/register.json"
status="$(curl --silent -o "$RESULTS/release-before.json" -w '%{http_code}' \
  -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @"$RESULTS/register.json" "$ROOT/releases")"
[[ "$status" == 201 ]]
id="$(jq -er .id "$RESULTS/release-before.json")"
jq -n --arg id "$id" --argjson revision "$revision" \
  '{release_id:$id,expected_revision:$revision}' > "$RESULTS/promotion.json"
status="$(curl --silent -o "$RESULTS/channel-before.json" -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @"$RESULTS/promotion.json" "$ROOT/channels/production")"
[[ "$status" == 200 ]]
kill -TERM "$pid"
wait "$pid"
pid=''

start after
second=$pid
[[ "$first" != "$second" ]]
curl --silent --fail -H "Authorization: Bearer $API_TOKEN" \
  "$ROOT/releases/$VERSION" > "$RESULTS/release-after.json"
curl --silent --fail -H "Authorization: Bearer $API_TOKEN" \
  "$ROOT/channels/production" > "$RESULTS/channel-after.json"
[[ "$(jq -r .id "$RESULTS/release-after.json")" == "$id" ]]
[[ "$(jq -r .release_id "$RESULTS/channel-after.json")" == "$id" ]]
[[ "$(jq -r .revision "$RESULTS/channel-after.json")" == "$((revision+1))" ]]
status="$(curl --silent -o "$RESULTS/stale.json" -w '%{http_code}' -X PUT \
  -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @"$RESULTS/promotion.json" "$ROOT/channels/production")"
[[ "$status" == 409 ]]
status="$(curl --silent -o "$RESULTS/replay.json" -w '%{http_code}' \
  -H "Authorization: Bearer $API_TOKEN" -H 'Content-Type: application/json' \
  --data-binary @"$RESULTS/register.json" "$ROOT/releases")"
[[ "$status" == 200 ]]
[[ "$(jq -r .id "$RESULTS/replay.json")" == "$id" ]]
printf 'External HTTP process restart: PASS\nBefore PID: %s\nAfter PID: %s\nRelease and channel survived at revision %s.\nStale promotion returned 409; registration replay returned 200 with original ID.\n' \
  "$first" "$second" "$((revision+1))" | tee "$RESULTS/result.txt"
