#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE ROLE IF NOT EXISTS Admins;
GRANT ALL ON *.* TO Admins;
CREATE ROLE IF NOT EXISTS Sales;
GRANT ALL ON sales_db.* TO Sales;
CREATE ROLE IF NOT EXISTS Development;
GRANT ALL ON development_db.* TO Development;
CREATE ROLE IF NOT EXISTS AllUsers;
GRANT SELECT ON *.* TO AllUsers;
EOSQL
