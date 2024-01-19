#!/bin/bash
set -e 
clickhouse client -n <<-EOSQL
INSERT INTO imdb.actors SELECT * FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_actors.tsv.gz', 'TSVWithNames');
INSERT INTO imdb.directors SELECT * FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_directors.tsv.gz', 'TSVWithNames');
INSERT INTO imdb.genres SELECT * FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_movies_genres.tsv.gz', 'TSVWithNames');
INSERT INTO imdb.movies SELECT * FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_movies.tsv.gz', 'TSVWithNames');
INSERT INTO imdb.roles (actor_id, movie_id, role) SELECT actor_id,movie_id,role FROM s3('https://datasets-documentation.s3.eu-west-3.amazonaws.com/imdb/imdb_ijs_roles.tsv.gz', 'TSVWithNames');
EOSQL
