#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE OR REPLACE TABLE syslog_raw_data ( appname String, facility String, hostname String, message String, msgid String, procid Int64, severity String, source_type String, timestamp String, version Int32) ENGINE = MergeTree ORDER BY (appname,  hostname,  severity);
EOSQL
