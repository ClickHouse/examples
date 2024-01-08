#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE TABLE default.odbc_customer (customer_id UInt64, firstname String, lastname String, email String, created_date DateTime ) ENGINE = ODBC('DSN=ch_mssql;port=1433;Uid=sa;Pwd=Mssql_Password123;Database=master', 'dbo', 'Customer');
EOSQL
