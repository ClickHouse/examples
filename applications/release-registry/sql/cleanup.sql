-- Destructive: inspect and run explicitly as the service administrator.
DROP SCHEMA registry CASCADE;
DROP ROLE registry_app;
DROP ROLE registry_migrator;
DROP ROLE registry_owner;
