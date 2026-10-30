#!/bin/bash
# Copy of vendor/pg_lake/docker/scripts/entrypoint-postgres.sh with the lab postgresql.conf tuning appended.

set -euo pipefail

trap "echo 'Caught termination signal. Exiting...'; exit 0" SIGINT SIGTERM

# Ensure PGBASEDIR and PG_MAJOR are set
PGBASEDIR=${PGBASEDIR:-/home/postgres}
PG_MAJOR=${PG_MAJOR:-18}

# Create and fix permissions for temporary directory BEFORE starting PostgreSQL
# Docker volumes are created with root ownership, but postgres user needs write access
mkdir -p ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp
sudo chown -R postgres:postgres ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp
sudo chmod 700 ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/base/pgsql_tmp

# Update pg_hba.conf
echo "local all all trust" | tee ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/pg_hba.conf
echo "host all all 127.0.0.1/32 trust" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/pg_hba.conf
echo "host all all ::1/128 trust" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/pg_hba.conf
echo "host all all 0.0.0.0/0 trust" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/pg_hba.conf

# Update postgresql.conf
# !!IMPORTANT!!: NOT RECOMMENDED FOR PRODUCTION
# ALLOW ACCESS FROM ANY IP ADDRESS typically used for development to access the database from outside the container
echo "listen_addresses = '*'" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf
echo "port = 5432" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf
echo "shared_preload_libraries = 'pg_extension_base'" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf
echo "pg_lake_iceberg.default_location_prefix = 's3://testbucket/pg_lake/'" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf
echo "pg_lake_engine.host = 'host=${PGBASEDIR}/pgduck_socket_dir port=5332'" | tee -a ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf

# --- lab additions (identical tuning to the other Postgres instances) ---
if ! grep -q "lab tuning" ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf; then
  cat >> ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/postgresql.conf <<'CONF'
# lab tuning
shared_buffers = 1GB
work_mem = 64MB
max_parallel_workers_per_gather = 4
max_wal_size = 4GB
maintenance_work_mem = 512MB
max_connections = 100
CONF
fi
# Start PostgreSQL server using explicit path
${PGBASEDIR}/pgsql-${PG_MAJOR}/bin/pg_ctl -D ${PGBASEDIR}/pgsql-${PG_MAJOR}/data start -l ${PGBASEDIR}/pgsql-${PG_MAJOR}/data/logfile

# Run initialization script (idempotent-ish; errors on restart are ignored)
${PGBASEDIR}/pgsql-${PG_MAJOR}/bin/psql -U postgres -f /init-postgres.sql || true

sleep infinity
