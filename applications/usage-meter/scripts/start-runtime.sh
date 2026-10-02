#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
umask 077
mkdir -p .deployment
port=${PORT:-3000}
# Whitelist runtime values; no Cloud API, migration, replication or admin credentials.
nohup env -i PATH="$PATH" PGHOST="$PGHOST" PGPORT="${PGPORT:-5432}" \
  PGDATABASE="$PGDATABASE" PGUSER="$PGUSER" PGPASSWORD="$PGPASSWORD" \
  PGSSLROOTCERT="$PGSSLROOTCERT" ACCOUNT_TOKENS="$ACCOUNT_TOKENS" \
  CLICKHOUSE_URL="$CLICKHOUSE_URL" CLICKHOUSE_USER="$CLICKHOUSE_USER" \
  CLICKHOUSE_PASSWORD="$CLICKHOUSE_PASSWORD" PORT="$port" \
  build/install/usage-meter/bin/usage-meter > ".deployment/server-$port.log" 2>&1 < /dev/null &
pid=$!
printf '%s\n' "$pid" > ".deployment/server-$port.pid"
export API_URL="http://127.0.0.1:$port"
python3 - <<'PY'
import json,os,time,urllib.request,urllib.error
url=os.environ['API_URL']+'/quota'
token=next(iter(json.loads(os.environ['ACCOUNT_TOKENS']).values()))
deadline=time.monotonic()+90
while time.monotonic()<deadline:
    try:
        req=urllib.request.Request(url,headers={'Authorization':'Bearer '+token})
        with urllib.request.urlopen(req,timeout=10) as response:
            if response.status==200:break
    except (urllib.error.URLError,TimeoutError):pass
    time.sleep(1)
else:raise RuntimeError('Runtime readiness deadline90s exceeded; inspect private server log')
print('Runtime API ready with authenticated PostgreSQL quota response')
PY
