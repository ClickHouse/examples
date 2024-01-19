#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.directors (id UInt32,first_name String,last_name  String) ENGINE = MergeTree ORDER BY (id, first_name, last_name);
EOSQL
