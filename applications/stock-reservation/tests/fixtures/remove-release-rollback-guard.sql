-- Remove only the failure-injection constraint installed by release-rollback-guard.sql.
ALTER TABLE stock_reservation.reservations
    DROP CONSTRAINT test_reservation_release_rollback;
