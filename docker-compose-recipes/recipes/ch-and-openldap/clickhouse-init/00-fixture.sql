CREATE DATABASE sales_db;
CREATE DATABASE development_db;
CREATE DATABASE other_data_db;
CREATE TABLE sales_db.sample (id UInt32, message String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE development_db.sample (id UInt32, message String) ENGINE = MergeTree ORDER BY id;
CREATE TABLE other_data_db.sample (id UInt32, message String) ENGINE = MergeTree ORDER BY id;
INSERT INTO sales_db.sample VALUES (1, 'sales row');
INSERT INTO development_db.sample VALUES (1, 'development row');
INSERT INTO other_data_db.sample VALUES (1, 'shared row');

-- LDAP groups map onto these existing ClickHouse roles after prefix removal.
CREATE ROLE Admins;
GRANT SELECT, INSERT, CREATE TABLE, ALTER TABLE, DROP TABLE ON sales_db.* TO Admins;
GRANT SELECT, INSERT, CREATE TABLE, ALTER TABLE, DROP TABLE ON development_db.* TO Admins;
GRANT SELECT, INSERT, CREATE TABLE, ALTER TABLE, DROP TABLE ON other_data_db.* TO Admins;
CREATE ROLE Sales;
GRANT SELECT ON sales_db.* TO Sales;
CREATE ROLE Development;
GRANT SELECT ON development_db.* TO Development;
CREATE ROLE AllUsers;
GRANT SELECT ON other_data_db.* TO AllUsers;
