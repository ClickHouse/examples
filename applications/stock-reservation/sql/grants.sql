-- Run as stock_reservation_migrator after the migration. Reapplying is safe.
BEGIN;
SET LOCAL ROLE stock_reservation_owner;

GRANT USAGE ON SCHEMA stock_reservation TO stock_reservation_app;
REVOKE ALL ON ALL TABLES IN SCHEMA stock_reservation FROM PUBLIC, stock_reservation_app;

GRANT SELECT ON stock_reservation.inventory TO stock_reservation_app;
GRANT UPDATE (available) ON stock_reservation.inventory TO stock_reservation_app;

GRANT SELECT ON stock_reservation.reservations TO stock_reservation_app;
GRANT INSERT (id, client_id, sku, quantity, status, created_at)
  ON stock_reservation.reservations TO stock_reservation_app;
GRANT UPDATE (status, released_at) ON stock_reservation.reservations TO stock_reservation_app;

GRANT SELECT ON stock_reservation.idempotency_keys TO stock_reservation_app;
GRANT INSERT (client_id, key, request_sku, request_quantity, reservation_id, response_status, response_body)
  ON stock_reservation.idempotency_keys TO stock_reservation_app;

-- No DELETE, TRUNCATE, schema CREATE, role membership, or blanket future-table grants.
COMMIT;
