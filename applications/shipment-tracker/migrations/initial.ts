import type { MigrationInterface, QueryRunner } from 'typeorm';

export class Initial1700000000000 implements MigrationInterface {
  async up(runner: QueryRunner): Promise<void> {
    await runner.query(`
      CREATE TABLE shipments.accounts (
        account_id UUID PRIMARY KEY,
        name TEXT NOT NULL UNIQUE
      );
      CREATE TABLE shipments.shipments (
        shipment_id UUID PRIMARY KEY,
        account_id UUID NOT NULL REFERENCES shipments.accounts(account_id),
        service_level TEXT NOT NULL CHECK (service_level IN ('standard', 'express')),
        status TEXT NOT NULL DEFAULT 'created'
          CHECK (status IN ('created', 'dispatched', 'delivered', 'cancelled')),
        revision INTEGER NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 10000),
        dispatched_at TIMESTAMPTZ(3),
        created_at TIMESTAMPTZ(3) NOT NULL,
        updated_at TIMESTAMPTZ(3) NOT NULL,
        UNIQUE (account_id, shipment_id),
        CHECK ((status = 'created' AND dispatched_at IS NULL) OR
               (status IN ('dispatched', 'delivered') AND dispatched_at IS NOT NULL) OR
               status = 'cancelled')
      );
      CREATE TABLE shipments.events (
        event_id UUID PRIMARY KEY,
        account_id UUID NOT NULL,
        shipment_id UUID NOT NULL,
        request_id TEXT NOT NULL CHECK (length(request_id) BETWEEN 1 AND 64 AND request_id !~ '[^A-Za-z0-9._-]'),
        expected_revision INTEGER NOT NULL CHECK (expected_revision BETWEEN 0 AND 9999),
        revision INTEGER NOT NULL CHECK (revision = expected_revision + 1),
        from_status TEXT NOT NULL,
        to_status TEXT NOT NULL,
        service_level TEXT NOT NULL CHECK (service_level IN ('standard', 'express')),
        event_at TIMESTAMPTZ(3) NOT NULL,
        event_day DATE NOT NULL CHECK (event_day = (event_at AT TIME ZONE 'UTC')::DATE),
        dispatched_at TIMESTAMPTZ(3),
        duration_ms BIGINT NOT NULL DEFAULT 0 CHECK (duration_ms >= 0),
        FOREIGN KEY (account_id, shipment_id)
          REFERENCES shipments.shipments(account_id, shipment_id),
        UNIQUE (account_id, request_id),
        UNIQUE (shipment_id, revision),
        CHECK ((from_status = 'created' AND to_status IN ('dispatched', 'cancelled')) OR
               (from_status = 'dispatched' AND to_status IN ('delivered', 'cancelled'))),
        CHECK ((to_status = 'delivered' AND dispatched_at IS NOT NULL AND
                event_at >= dispatched_at AND
                duration_ms = extract(epoch FROM event_at - dispatched_at) * 1000) OR
               (to_status <> 'delivered' AND duration_ms = 0)),
        CHECK (to_status <> 'dispatched' OR
               (dispatched_at IS NOT NULL AND dispatched_at = event_at)),
        CHECK (from_status <> 'dispatched' OR dispatched_at IS NOT NULL)
      );
      CREATE UNIQUE INDEX events_replica_identity
        ON shipments.events(account_id, event_day, event_id);
      ALTER TABLE shipments.events REPLICA IDENTITY USING INDEX events_replica_identity;
      GRANT SELECT ON shipments.accounts, shipments.shipments, shipments.events TO shipments_app;
      GRANT UPDATE (account_id) ON shipments.accounts TO shipments_app;
      GRANT UPDATE (status, revision, dispatched_at, updated_at) ON shipments.shipments TO shipments_app;
      GRANT INSERT ON shipments.events TO shipments_app;
      GRANT SELECT ON shipments.events TO shipments_cdc;
    `);
  }
  async down(runner: QueryRunner): Promise<void> {
    await runner.query('DROP TABLE shipments.events, shipments.shipments, shipments.accounts');
  }
}
