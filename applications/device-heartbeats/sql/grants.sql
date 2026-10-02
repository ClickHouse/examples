\set ON_ERROR_STOP on
GRANT USAGE ON SCHEMA heartbeats TO heartbeats_app;
GRANT SELECT ON heartbeats.devices,heartbeats.samples TO heartbeats_app;
GRANT INSERT ON heartbeats.samples TO heartbeats_app;
GRANT UPDATE(latest_sequence,sample_count) ON heartbeats.devices TO heartbeats_app;
GRANT USAGE ON SEQUENCE heartbeats.samples_id_seq TO heartbeats_app;
