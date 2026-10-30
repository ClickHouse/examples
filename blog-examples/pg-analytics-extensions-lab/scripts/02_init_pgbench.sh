#!/usr/bin/env bash
# Usage: 02_init_pgbench.sh <container>  -- create a scale-50 pgbench database in the same instance as the events data
set -euo pipefail
source "$(dirname "$0")/env.sh"
H=$1
psql_c $H -c "DROP DATABASE IF EXISTS pgbench" -c "CREATE DATABASE pgbench"
docker exec lab-client pgbench -i -s 50 -q -h $H -U postgres pgbench 2>&1 | tail -3
