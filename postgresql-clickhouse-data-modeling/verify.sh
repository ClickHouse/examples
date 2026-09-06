#!/bin/sh
set -eu
cd "$(dirname "$0")"
case "${1:-initial}" in
  initial) expected="[(1,'Alice Example'),(2,'Bob Example')]|2|1|1" ;;
  changed) expected="[(1,'Updated User'),(3,'New User')]|2|1|1" ;;
  *) echo "Usage: $0 [initial|changed]" >&2; exit 1 ;;
esac
q() {
  docker compose exec -T clickhouse clickhouse-client --user demo --password local-example-password \
    --connect_timeout 3 --receive_timeout 10 --max_execution_time 10 --query "$1"
}
q 'SELECT version()'
# FINAL resolves versions at query time; filtering removes the latest tombstones.
sql=$(cat fixtures/current-state.sql)
deadline=$(( $(date +%s) + 180 ))
while [ "$(date +%s)" -lt "$deadline" ]; do
  if actual=$(q "$sql FORMAT TSVRaw" 2>/dev/null) && [ "$actual" = "$expected" ]; then
    q 'SELECT id, displayname FROM stackoverflow.users FINAL WHERE _peerdb_is_deleted = 0 ORDER BY id'
    echo "OK: ${1:-initial} logical state; 2 users, 2 posts, 1 vote, 1 comment"
    exit 0
  fi
  sleep 2
done
echo "CDC timed out; expected $expected; last state: ${actual:-unavailable}" >&2
exit 1
