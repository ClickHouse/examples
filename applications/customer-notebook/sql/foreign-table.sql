\set ON_ERROR_STOP on
-- Administrator only. CH_HOST and CH_REPORT_PASSWORD come from private setup.
BEGIN;
CREATE SCHEMA IF NOT EXISTS notebook_fdw;
CREATE EXTENSION IF NOT EXISTS pg_clickhouse WITH SCHEMA notebook_fdw;
CREATE SERVER notebook_activity FOREIGN DATA WRAPPER clickhouse_fdw
OPTIONS(driver 'binary',host :'ch_host',port '9440',dbname 'notebook_analytics',
        secure 'on',min_tls_version 'TLSv1.2');
CREATE USER MAPPING FOR notebook_report SERVER notebook_activity
OPTIONS(user 'notebook_report',password :'ch_password');
CREATE FOREIGN TABLE notebook_fdw.activity (
  customer_id uuid NOT NULL,
  activity_day date NOT NULL,
  event_id bigint NOT NULL
) SERVER notebook_activity OPTIONS(database 'notebook_analytics',table_name 'activity');
REVOKE ALL ON SCHEMA notebook_fdw FROM PUBLIC;
GRANT USAGE ON SCHEMA notebook_fdw TO notebook_report;
GRANT USAGE ON FOREIGN SERVER notebook_activity TO notebook_report;
GRANT SELECT ON notebook_fdw.activity TO notebook_report;
ALTER ROLE notebook_report SET pg_clickhouse.session_settings=
'join_use_nulls 1,group_by_use_nulls 1,final 1,transform_null_in 0,max_execution_time 10,max_rows_to_read 20000,max_result_rows 31,max_result_bytes 65536,result_overflow_mode throw,connect_timeout 5,receive_timeout 10,send_timeout 10';
COMMIT;
