-- DESTRUCTIVE: removes all Stock Reservation example data and its three roles.
-- Stop the API first. Run as the same service administrator used for bootstrap.
-- This does not delete the ClickHouse Cloud service or affect other schemas.
BEGIN;

DROP SCHEMA stock_reservation CASCADE;
REVOKE CONNECT ON DATABASE :"DBNAME" FROM stock_reservation_app, stock_reservation_migrator;
REVOKE stock_reservation_owner FROM stock_reservation_migrator;
REVOKE stock_reservation_owner FROM CURRENT_USER;
DROP ROLE stock_reservation_app;
DROP ROLE stock_reservation_migrator;
DROP ROLE stock_reservation_owner;

COMMIT;
