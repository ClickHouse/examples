\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA transfers TO transfers_app;
GRANT SELECT ON transfers.balances, transfers.transfers TO transfers_app;
GRANT UPDATE (quantity) ON transfers.balances TO transfers_app;
GRANT INSERT ON transfers.transfers TO transfers_app;
GRANT USAGE ON SEQUENCE transfers.transfers_id_seq TO transfers_app;
