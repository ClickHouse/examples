#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
SET allow_experimental_database_materialized_postgresql=1;
CREATE DATABASE postgres_db ENGINE = MaterializedPostgreSQL('postgres:5432', 'clickhouse_pg_db', 'admin', 'password');
EOSQL
