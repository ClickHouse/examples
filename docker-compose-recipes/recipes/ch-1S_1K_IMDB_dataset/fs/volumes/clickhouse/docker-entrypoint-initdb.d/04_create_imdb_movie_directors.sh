#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.movie_directors (director_id UInt32,movie_id UInt64) ENGINE = MergeTree ORDER BY (director_id, movie_id)
EOSQL
