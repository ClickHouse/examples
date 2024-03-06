#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.genres (movie_id UInt32,genre String) ENGINE = MergeTree ORDER BY (movie_id, genre);
EOSQL
