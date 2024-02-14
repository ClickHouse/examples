#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.actors (id UInt32, first_name String, last_name  String,gender FixedString(1)) ENGINE = MergeTree ORDER BY (id, first_name, last_name, gender);
EOSQL
