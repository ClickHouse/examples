\set ON_ERROR_STOP on
-- Run as the Cloud administrator after migrations. Never publish tokens/counters.
SELECT current_setting('wal_level') = 'logical' AS logical \gset
\if :logical
CREATE PUBLICATION usage_events_clickpipe FOR TABLE usage.events;
\else
\echo 'Logical replication must be enabled before creating the ClickPipe'
\quit 1
\endif
