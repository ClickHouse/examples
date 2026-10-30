#!/usr/bin/env bash
# Usage: 02_gen_events.sh <container>  -- deterministic 50M-row events + 5M users heap tables
set -euo pipefail
source "$(dirname "$0")/env.sh"
H=$1; mkdir -p $LAB/results/load
( time psql_c $H -v rows=$ROWS -f /lab/sql/01_gen_events.sql ) > $LAB/results/load/${H#lab-}_gen_events.log 2>&1
tail -6 $LAB/results/load/${H#lab-}_gen_events.log
