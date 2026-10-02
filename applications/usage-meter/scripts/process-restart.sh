#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PORT=${RESTART_PORT:-3302}
export API_URL="http://127.0.0.1:$PORT"
trap '[[ -f ".deployment/server-$PORT.pid" ]] && kill "$(cat ".deployment/server-$PORT.pid")" 2>/dev/null || true' EXIT
bash scripts/start-runtime.sh
first=$(cat ".deployment/server-$PORT.pid")
python3 - <<'PY'
import runpy,json
c=runpy.run_path('scripts/cloud-core.py')
result=c['http'](c['B'],'/events/snapshot-b')
assert result[0]==200
quota=c['http'](c['B'],'/quota')[1]
open('.deployment/restart-before.json','w').write(json.dumps({'event':result[1],'quota':quota}))
PY
kill "$first"
for attempt in $(seq 1 50); do kill -0 "$first" 2>/dev/null || break; sleep 0.1; done
bash scripts/start-runtime.sh
second=$(cat ".deployment/server-$PORT.pid")
[[ "$first" != "$second" ]]
python3 - <<'PY'
import runpy,json
c=runpy.run_path('scripts/cloud-core.py')
before=json.load(open('.deployment/restart-before.json'))
status,event=c['http'](c['B'],'/usage',{'requestId':'snapshot-b','feature':'api','units':4})
assert status==200 and event==before['event']
assert c['http'](c['B'],'/quota')[1]==before['quota']
assert c['http'](c['B'],'/reports')[0]==200
print('PASS: matching persisted retry200, unchanged quota and report after new OS process')
PY
printf 'External runtime-only process restart: %s -> %s\n' "$first" "$second"
