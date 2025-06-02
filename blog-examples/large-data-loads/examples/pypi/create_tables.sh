#!/bin/bash

CLICKHOUSE_HOST=${CLICKHOUSE_HOST:-localhost}
CLICKHOUSE_PASSWORD=${CLICKHOUSE_PASSWORD:-}

echo "creating database"
clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query 'DROP DATABASE pypi'
clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query 'CREATE DATABASE IF NOT EXISTS pypi'



echo "creating base table"
clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE OR REPLACE TABLE pypi.pypi
(
    `date` Date,
    `country_code` LowCardinality(String),
    `project` String,
    `type` LowCardinality(String),
    `installer` LowCardinality(String),
    `python_minor` LowCardinality(String),
    `system` LowCardinality(String),
    `version` String
)
ENGINE = MergeTree
ORDER BY (project, date, version, country_code, python_minor, system)
'

echo "creating pypi_downloads view"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads
(
    `project` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY project
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_mv TO pypi.pypi_downloads
(
    `project` String,
    `count` Int64

) AS SELECT project, count() AS count
FROM pypi.pypi
GROUP BY project
'

echo "creating pypi_downloads_by_version view"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_by_version
(
    `project` String,
    `version` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_by_version_mv TO pypi.pypi_downloads_by_version
(
    `project` String,
    `version` String,
    `count` Int64

) AS
SELECT
    project,
    version,
    count() AS count
FROM pypi.pypi
GROUP BY
    project,
    version
'

echo "creating pypi_downloads_per_day view"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day
(
    `date` Date,
    `project` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, date)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_mv TO pypi.pypi_downloads_per_day
(
    `date` Date,
    `project` String,
    `count` Int64

) AS
SELECT
    date,
    project,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project
'

echo "creating pypi_downloads_per_day_by_version view"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version
(
    `date` Date,
    `project` String,
    `version` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_mv TO pypi.pypi_downloads_per_day_by_version
(
    `date` Date,
    `project` String,
    `version` String,
    `count` Int64
) AS
SELECT
    date,
    project,
    version,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project,
    version
'


echo "creating pypi_downloads_per_day_by_version_by_country"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `country_code` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, country_code)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_country_mv TO pypi.pypi_downloads_per_day_by_version_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `country_code` String,
    `count` Int64
) AS
SELECT
    date,
    project,
    version,
    country_code,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project,
    version,
    country_code
'


echo "creating pypi_downloads_per_day_by_version_by_file_type"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_file_type
(
    `date` Date,
    `project` String,
    `version` String,
    `type` LowCardinality(String),
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, type)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_file_type_mv TO pypi.pypi_downloads_per_day_by_version_by_file_type
(
    `date` Date,
    `project` String,
    `version` String,
    `type` LowCardinality(String),
    `count` Int64
) AS
SELECT
    date,
    project,
    version,
    type,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project,
    version,
    type
'

echo "creating pypi_downloads_per_day_by_version_by_python"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_python
(
    `date` Date,
    `project` String,
    `version` String,
    `python_minor` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, python_minor)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_python_mv TO pypi.pypi_downloads_per_day_by_version_by_python
(
    `date` Date,
    `project` String,
    `version` String,
    `python_minor` String,
    `count` Int64
) AS
SELECT
    date,
    project,
    version,
    python_minor,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project,
    version,
    python_minor
'

echo "creating pypi_downloads_per_day_by_version_by_installer_by_type"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE OR REPLACE TABLE pypi.pypi_downloads_per_day_by_version_by_installer_by_type
(
    `project` String,
    `version` String,
    `date` Date,
    `installer` String,
    `type` LowCardinality(String),
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, installer)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_installer_by_type_mv TO pypi.pypi_downloads_per_day_by_version_by_installer_by_type
(
    `project` String,
    `version` String,
    `date` Date,
    `installer` String,
    `type` LowCardinality(String),
    `count` Int64
) AS
SELECT
    project,
    version,
    date,
    installer,
    type,
    count() AS count
FROM pypi.pypi
GROUP BY
    project,
    version,
    date,
    installer,
    type
'


echo "creating pypi_downloads_per_day_by_version_by_system"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_system
(
    `date` Date,
    `project` String,
    `version` String,
    `system` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, system)
'


clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_system_mv TO pypi.pypi_downloads_per_day_by_version_by_system
(
    `date` Date,
    `project` String,
    `version` String,
    `system` String,
    `count` Int64
) AS
SELECT
    date,
    project,
    version,
    system,
    count() AS count
FROM pypi.pypi
GROUP BY
    date,
    project,
    version,
    system
'

echo "creating pypi_downloads_per_day_by_version_by_installer_by_type_by_country"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_installer_by_type_by_country
(
    `project` String,
    `version` String,
    `date` Date,
    `installer` String,
    `type` LowCardinality(String),
    `country_code` LowCardinality(String),
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, country_code, installer, type)
'

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_installer_by_type_by_country_mv TO pypi.pypi_downloads_per_day_by_version_by_installer_by_type_by_country
(
    `project` String,
    `version` String,
    `date` Date,
    `installer` String,
    `type` LowCardinality(String),
    `country_code` LowCardinality(String),
    `count` Int64
) AS
SELECT project, version, date, installer, type, country_code, count() as count
FROM pypi.pypi
GROUP BY project, version, date, installer, type, country_code
'

echo "creating pypi_downloads_per_day_by_version_by_python_by_country"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_python_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `python_minor` String,
    `country_code` LowCardinality(String),
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, country_code, python_minor)
'


clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_python_by_country_mv TO pypi.pypi_downloads_per_day_by_version_by_python_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `python_minor` String,
    `country_code` LowCardinality(String),
    `count` Int64
) AS
SELECT date, project, version,  python_minor, country_code, count() as count FROM pypi.pypi GROUP BY date, project, version, python_minor, country_code
'


echo "creating pypi_downloads_per_day_by_version_by_system_by_country"

clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE TABLE pypi.pypi_downloads_per_day_by_version_by_system_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `system` String,
    `country_code` String,
    `count` Int64
)
ENGINE = SummingMergeTree
ORDER BY (project, version, date, country_code, system)
'


clickhouse client --host ${CLICKHOUSE_HOST} --secure --password ${CLICKHOUSE_PASSWORD} --query '
CREATE MATERIALIZED VIEW pypi.pypi_downloads_per_day_by_version_by_system_by_country_mv TO pypi.pypi_downloads_per_day_by_version_by_system_by_country
(
    `date` Date,
    `project` String,
    `version` String,
    `system` String,
    `country_code` String,
    `count` Int64
) AS
SELECT date, project, version,  system, country_code, count() as count FROM pypi.pypi GROUP BY date, project, version, system, country_code
'