-- Destructive: inspect and run explicitly as the service administrator.
DROP SCHEMA webhook CASCADE;
DROP ROLE webhook_receiver;
DROP ROLE webhook_worker;
DROP ROLE webhook_migrator;
DROP ROLE webhook_owner;
