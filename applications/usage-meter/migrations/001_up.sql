CREATE TABLE usage.accounts (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  daily_quota INTEGER NOT NULL CHECK (daily_quota BETWEEN 1 AND 1000000)
);
CREATE TABLE usage.daily_counters (
  account_id UUID NOT NULL REFERENCES usage.accounts(id),
  usage_day DATE NOT NULL,
  used_units INTEGER NOT NULL CHECK (used_units BETWEEN 0 AND 1000000),
  PRIMARY KEY (account_id, usage_day)
);
CREATE TABLE usage.events (
  event_id UUID PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES usage.accounts(id),
  request_id TEXT NOT NULL CHECK (request_id ~ '^[A-Za-z0-9._-]{1,64}$'),
  usage_day DATE NOT NULL,
  feature TEXT NOT NULL CHECK (feature IN ('api', 'export', 'storage')),
  units SMALLINT NOT NULL CHECK (units BETWEEN 1 AND 1000),
  remaining_units INTEGER NOT NULL CHECK (remaining_units BETWEEN 0 AND 1000000),
  created_at TIMESTAMPTZ NOT NULL,
  UNIQUE (account_id, request_id)
);
-- Every custom ClickHouse ordering column is carried by DELETE tombstones.
CREATE UNIQUE INDEX events_replica_identity ON usage.events(account_id, usage_day, event_id);
ALTER TABLE usage.events REPLICA IDENTITY USING INDEX events_replica_identity;
GRANT SELECT ON usage.accounts, usage.daily_counters, usage.events TO usage_app;
-- SELECT FOR UPDATE needs UPDATE privilege; only the ID column is grantable.
-- The API never changes it. Operators with this shared role remain trusted.
GRANT UPDATE (id) ON usage.accounts TO usage_app;
GRANT INSERT ON usage.daily_counters TO usage_app;
GRANT UPDATE (used_units) ON usage.daily_counters TO usage_app;
GRANT INSERT ON usage.events TO usage_app;
GRANT SELECT ON usage.events TO usage_cdc;
