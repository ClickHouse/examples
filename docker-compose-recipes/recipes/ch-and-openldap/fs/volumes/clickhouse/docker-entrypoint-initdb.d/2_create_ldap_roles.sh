#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE ROLE Admins;
GRANT ALL ON *.* TO Admins;
CREATE ROLE Sales;
GRANT ALL ON sales_db.* TO Sales;
CREATE ROLE Development;
GRANT ALL ON development_db.* TO Development;
CREATE ROLE AllUsers;
GRANT SELECT ON *.* TO AllUsers;
EOSQL
