#!/usr/bin/env bash
# Builds pg_lake images (PG17) from the repo-provided Dockerfile.
# Deviations (see README): NCORES=8 for the DuckDB compile (Docker VM has ~11.7 GiB; upstream recommends 16 GB+)
# and the dev_base stage slimmed to build only PostgreSQL 17 (upstream builds 16, 17, 18 and 19).
set -euo pipefail
LAB=$(cd "$(dirname "$0")/.." && pwd)
CTX=$LAB/vendor/pg_lake/docker
mkdir -p $LAB/results/build
DF=$LAB/docker/pg_lake.Dockerfile
docker build --target pgduck_server --build-arg PG_MAJOR=17 --build-arg BUILD_NCORES=${BUILD_NCORES:-8} -t pgduck-server:lab-pg17 -f $DF --progress=plain $CTX > $LAB/results/build/pgduck_server_build.log 2>&1 &
P1=$!
sleep 30
docker build --target pg_lake_postgres --build-arg PG_MAJOR=17 -t pg_lake:lab-pg17 -f $DF --progress=plain $CTX > $LAB/results/build/pg_lake_build.log 2>&1 &
P2=$!
wait $P1; echo "pgduck_server build rc=$?"
wait $P2; echo "pg_lake build rc=$?"
