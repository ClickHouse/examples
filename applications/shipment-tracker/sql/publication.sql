\set ON_ERROR_STOP on
DO $$ BEGIN
  IF current_setting('wal_level') <> 'logical' THEN
    RAISE EXCEPTION 'Logical replication required';
  END IF;
END $$;
CREATE PUBLICATION shipments_events_clickpipe FOR TABLE shipments.events;
