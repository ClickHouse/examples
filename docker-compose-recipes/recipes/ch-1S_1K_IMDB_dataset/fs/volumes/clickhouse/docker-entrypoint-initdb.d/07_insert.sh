#!/bin/bash
set -euo pipefail
# Tiny synthetic fixture using the IMDb schema; no startup downloads.
clickhouse client -n <<'EOSQL'
INSERT INTO imdb.actors VALUES (1, 'Alex', 'Example', 'X'), (2, 'Sam', 'Sample', 'X');
INSERT INTO imdb.directors VALUES (1, 'Casey', 'Example');
INSERT INTO imdb.genres VALUES (1, 'Drama'), (2, 'Comedy');
INSERT INTO imdb.movies VALUES (1, 'Example Movie', 2024, 7.5), (2, 'Another Example', 2025, 8.0);
INSERT INTO imdb.movie_directors VALUES (1, 1), (1, 2);
INSERT INTO imdb.roles (actor_id, movie_id, role) VALUES (1, 1, 'Lead'), (2, 2, 'Lead');
EOSQL
