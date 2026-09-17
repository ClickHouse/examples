-- Run as stock_reservation_migrator. Existing stock is never reset by seeding.
BEGIN;
SET LOCAL ROLE stock_reservation_owner;

INSERT INTO stock_reservation.inventory (sku, name, available) VALUES
  ('FIELD-NOTES', 'Field Notes notebook', 25),
  ('CAMP-MUG', 'Enamel camp mug', 10),
  ('TRAIL-PACK', 'Lightweight trail pack', 5)
ON CONFLICT (sku) DO NOTHING;

COMMIT;
