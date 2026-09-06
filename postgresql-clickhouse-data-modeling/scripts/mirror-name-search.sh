#!/bin/sh
set -eu
attempt=0
while [ "$attempt" -lt 30 ]; do
  attempt=$((attempt + 1))
  if temporal --command-timeout 5s operator search-attribute list > /tmp/search-attributes; then
    if ! grep -q 'MirrorName' /tmp/search-attributes; then
      temporal --command-timeout 5s operator search-attribute create --name MirrorName --type Text --namespace default
    fi
    echo 'Temporal namespace and MirrorName search attribute ready'
    exit 0
  fi
  sleep 2
done
echo 'Temporal setup failed after 30 attempts' >&2
exit 1
