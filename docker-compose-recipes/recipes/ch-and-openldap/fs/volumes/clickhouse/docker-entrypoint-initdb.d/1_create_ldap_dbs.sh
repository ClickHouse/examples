#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE DATABASE sales;
CREATE DATABASE development;
CREATE DATABASE other_data;
EOSQL
