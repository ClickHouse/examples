-- Remove only the failure-injection constraint installed by rollback-guard.sql.
ALTER TABLE stock_reservation.reservations
    DROP CONSTRAINT test_reservation_insert_rollback;
