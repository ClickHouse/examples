#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
# EXPERIMENTAL materialized postgres database https://clickhouse.com/docs/en/integrations/postgresql#using-the-materializedpostgresql-database-engine
SET allow_experimental_database_materialized_postgresql=1;
CREATE DATABASE postgres_materialized_db ENGINE = MaterializedPostgreSQL('postgres:5432', 'clickhouse_pg_db', 'admin', 'password');

# materialized postgres table (hacker_news) https://clickhouse.com/docs/en/engines/table-engines/integrations/materialized-postgresql
CREATE TABLE default.postgresql_hacker_news_materialised ( id Int64, deleted Int64, type String,  by String, time DateTime, text String, dead Int64, parent Int64, poll Int64, kids Array(String), url String, score Int64, title String, parts Array(String), descendants Int64) ENGINE = MaterializedPostgreSQL('postgres:5432', 'clickhouse_pg_db', 'hacker_news', 'admin', 'password') ORDER BY (type,id);

# postgres table (hacker_news) https://clickhouse.com/docs/en/engines/table-engines/integrations/postgresql
CREATE TABLE default.postgresql_hacker_news_subset ( id Int64, text String, by String ) ENGINE = PostgreSQL('postgres:5432', 'clickhouse_pg_db', 'hacker_news', 'admin', 'password');
EOSQL
