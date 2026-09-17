-- Apply once as stock_reservation_migrator. Later changes belong in new numbered files.
BEGIN;
SET LOCAL ROLE stock_reservation_owner;

CREATE TABLE stock_reservation.inventory (
  sku text PRIMARY KEY CHECK (sku ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'),
  name text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
  available integer NOT NULL CHECK (available >= 0)
);

CREATE TABLE stock_reservation.reservations (
  id uuid PRIMARY KEY,
  client_id text NOT NULL CHECK (client_id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'),
  sku text NOT NULL REFERENCES stock_reservation.inventory (sku),
  quantity integer NOT NULL CHECK (quantity BETWEEN 1 AND 1000),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'released')),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  released_at timestamptz,
  CONSTRAINT reservation_release_state CHECK (
    (status = 'active' AND released_at IS NULL) OR
    (status = 'released' AND released_at IS NOT NULL)
  )
);

CREATE TABLE stock_reservation.idempotency_keys (
  client_id text NOT NULL CHECK (client_id ~ '^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$'),
  key text NOT NULL CHECK (key ~ '^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$'),
  request_sku text NOT NULL,
  request_quantity integer NOT NULL CHECK (request_quantity BETWEEN 1 AND 1000),
  reservation_id uuid NOT NULL,
  response_status integer NOT NULL CHECK (response_status = 201),
  response_body jsonb NOT NULL CHECK (jsonb_typeof(response_body) = 'object'),
  created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (client_id, key),
  -- The key is claimed before stock is decremented and the reservation is inserted.
  -- Deferred validation allows that order, but an incomplete transaction cannot commit.
  CONSTRAINT idempotency_reservation_fk FOREIGN KEY (reservation_id)
    REFERENCES stock_reservation.reservations (id) DEFERRABLE INITIALLY DEFERRED
);

COMMENT ON TABLE stock_reservation.idempotency_keys IS
  'Successful reservation responses, retained indefinitely. Failed transactions leave no key. Do not delete while a client may retry.';

COMMIT;
