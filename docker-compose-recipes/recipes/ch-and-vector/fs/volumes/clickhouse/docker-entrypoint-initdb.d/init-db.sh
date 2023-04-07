#!/bin/bash
set -e
clickhouse client -n <<-EOSQL
CREATE OR REPLACE TABLE syslog_raw_data ( appname String, facility String, hostname String, message String, msgid String, procid Int64, severity String, source_type String, timestamp String, version Int32) ENGINE = MergeTree ORDER BY (appname,  hostname,  severity);
CREATE OR REPLACE TABLE apache_raw_data (datetime String, host String, method String, protocol String, referer String, request String, status String, bytes Int64, \`user-identifier\` String) ENGINE = MergeTree ORDER BY (host,  method,  protocol,  status);
EOSQL
