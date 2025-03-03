#!/bin/sh 

DOCKER="docker"

$DOCKER compose pull
$DOCKER compose -f docker-compose.yaml up --no-attach catalog --no-attach temporal --no-attach temporal-ui --no-attach temporal-admin-tools -d


# Create and activate a Python virtual environment
VENV_DIR="venv"
python3 -m venv $VENV_DIR
. $VENV_DIR/bin/activate

# Install dependencies
pip install -r python/requirements.txt

# Run the Python script
python python/import_parquet.py clickhouse_pg_db admin password localhost 5432 100000

./scripts/init-cdc.sh


