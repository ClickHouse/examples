#!/bin/sh
set -eu
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if timeout 15 mc alias set stage http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; then
    timeout 15 mc mb --ignore-existing stage/peerdbbucket
    timeout 15 mc stat stage/peerdbbucket
    echo 'PeerDB staging bucket ready'
    exit 0
  fi
  sleep 2
done
echo 'MinIO bucket setup failed after 30 attempts' >&2
exit 1
