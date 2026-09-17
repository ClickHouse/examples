-- Integration tests only. Deliberately reject a reservation INSERT after its
-- transaction has claimed an idempotency key and decremented inventory.
-- NOT VALID avoids scanning existing data. The constraint still applies to new
-- rows, and the reserved prefix affects only this test's generated fixtures.
ALTER TABLE stock_reservation.reservations
    ADD CONSTRAINT test_reservation_insert_rollback
    CHECK (sku NOT LIKE 'test-rollback-%') NOT VALID;
