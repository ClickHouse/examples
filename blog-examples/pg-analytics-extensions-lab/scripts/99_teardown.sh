#!/usr/bin/env bash
# Remove all lab containers, volumes and the network. Keeps scripts, SQL and results.
set -uo pipefail
for c in lab-client lab-ch lab-pgduck lab-pgch lab-pglake lab-pgduck-server lab-s3; do docker rm -f $c >/dev/null 2>&1; done
for v in lab-ch-data lab-pgduck-data lab-pgch-data lab-pglake-data lab-pglake-sock lab-pglake-tmp lab-pglake-cache lab-s3-data; do docker volume rm $v >/dev/null 2>&1; done
docker network rm pglab >/dev/null 2>&1
echo "torn down (images kept: remove pg_lake:lab-pg17 / pgduck-server:lab-pg17 manually if wanted)"
