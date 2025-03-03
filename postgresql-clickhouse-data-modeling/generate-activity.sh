#!/bin/sh 

VENV_DIR="venv"
. $VENV_DIR/bin/activate

python python/generate_activity.py clickhouse_pg_db admin password localhost 5432 
