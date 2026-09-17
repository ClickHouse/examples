-- Integration tests only. Reject the reservation status UPDATE after release
-- has incremented inventory, proving that both changes roll back together.
-- Existing active fixtures remain valid; unrelated application SKUs are ignored.
ALTER TABLE stock_reservation.reservations
    ADD CONSTRAINT test_reservation_release_rollback
    CHECK (sku NOT LIKE 'test-release-rollback-%' OR status <> 'released') NOT VALID;
