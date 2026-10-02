-- Destructive: review and run explicitly as the service administrator.
DROP SCHEMA catalogue CASCADE;
DROP ROLE catalogue_reader;
DROP ROLE catalogue_migrator;
DROP ROLE catalogue_owner;
