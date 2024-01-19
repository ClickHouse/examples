#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
CREATE TABLE imdb.roles (actor_id UInt32, movie_id UInt32, role String, created_at DateTime DEFAULT now()) ENGINE = MergeTree ORDER BY (actor_id, movie_id);
EOSQL
