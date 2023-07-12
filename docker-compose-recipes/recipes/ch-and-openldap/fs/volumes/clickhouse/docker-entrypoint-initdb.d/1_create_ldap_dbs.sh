#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE DATABASE IF NOT EXISTS sales_db;
CREATE DATABASE IF NOT EXISTS development_db;
CREATE DATABASE IF NOT EXISTS other_data_db;
EOSQL
