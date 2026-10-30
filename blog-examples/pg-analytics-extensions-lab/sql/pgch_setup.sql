CREATE EXTENSION IF NOT EXISTS pg_clickhouse;
DROP SERVER IF EXISTS ch_srv CASCADE;
CREATE SERVER ch_srv FOREIGN DATA WRAPPER clickhouse_fdw OPTIONS (driver 'binary', host 'lab-ch', port '9000', dbname 'lab');
CREATE USER MAPPING FOR CURRENT_USER SERVER ch_srv OPTIONS (user 'default', password 'lab');
DROP SCHEMA IF EXISTS ch CASCADE;
CREATE SCHEMA ch;
IMPORT FOREIGN SCHEMA lab FROM SERVER ch_srv INTO ch;
\d ch.events
\d ch.users
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_clickhouse';
