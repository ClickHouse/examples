#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.movies (id UInt32 ,name String , year UInt32, rank Float32 DEFAULT 0) ENGINE = MergeTree ORDER BY (id, name, year);
EOSQL
