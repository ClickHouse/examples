CREATE TABLE default.upclick_metrics (
    `target` String,
    `status_code` UInt8,
    `latency` UInt16,
    `continent_code` String,
    `country_iso_code` String,
    `country_name_en` String,
    `city_name_en` String,
    `latitude` Float64,
    `longitude` Float64,
    `receive_timestamp` DateTime MATERIALIZED now()
) ENGINE = ReplicatedMergeTree
ORDER BY (
        target,
        status_code,
        continent_code,
        country_iso_code,
        country_name_en,
        city_name_en
    ) SETTINGS index_granularity = 8192;
