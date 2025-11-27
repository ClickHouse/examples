WITH
    sel AS
    (
            -- 01: ClickHouse Enterprise
        SELECT '01' AS id, 'CH Ent 2×236GiB' AS bar_label, 'ClickHouse%' AS system_pat,
            'Enterprise' AS tier, 'default' AS compute_model,
            'aws' AS provider, 'us-east-1' AS region, '236GiB' AS machine, '2' AS cluster_size

        UNION ALL
        -- 02: BigQuery Enterprise Plus (Capacity)
        SELECT '02' AS id, 'BQ Ent+' AS bar_label, 'Bigquery' AS system_pat,
               'Enterprise Plus' AS tier, 'capacity' AS compute_model,
               'gcp' AS provider, 'us-east-1' AS region, 'serverless' AS machine, 'serverless' AS cluster_size

        UNION ALL
        -- 03: BigQuery On-demand (Bytes)
        SELECT '03' AS id, 'BQ On-demand' AS bar_label, 'Bigquery' AS system_pat,
               'OnDemand' AS tier, 'on_demand' AS compute_model,
               'gcp' AS provider, 'us-east-1' AS region, 'serverless' AS machine, 'serverless' AS cluster_size

        UNION ALL
        -- 04: Redshift Serverless (AWS)
        SELECT '04' AS id, 'RS Serverless' AS bar_label, 'Redshift%' AS system_pat,
               'Standard' AS tier, 'capacity' AS compute_model,
               'aws' AS provider, 'us-east-1' AS region, 'serverless' AS machine, 'serverless' AS cluster_size
        UNION ALL
        -- 05: Databricks SQL Serverless (2X-Small)
        SELECT '05' AS id, 'DBR SQL 2X-Small' AS bar_label, 'Databricks%' AS system_pat,
            'premium' AS tier, NULL AS compute_model, 'aws' AS provider, 'us-east-1' AS region, 'serverless' AS machine, '2X-Small' AS cluster_size
        UNION ALL
        -- 06: Databricks SQL Serverless (Large)
        SELECT '06' AS id, 'DBR SQL Large' AS bar_label, 'Databricks%' AS system_pat,
            'premium' AS tier, NULL AS compute_model, 'aws' AS provider, 'us-east-1' AS region, 'serverless' AS machine, 'Large' AS cluster_size
        UNION ALL
        -- 07: Databricks SQL Serverless (4X-Large)
        SELECT '07' AS id, 'DBR SQL 4X-Large' AS bar_label, 'Databricks%' AS system_pat,
            'premium' AS tier, NULL AS compute_model, 'aws' AS provider, 'us-east-1' AS region, 'serverless' AS machine, '4X-Large' AS cluster_size
        UNION ALL
        -- 08: Snowflake Standard 4X-Large (128 credits/h)
        SELECT '08' AS id, 'SF Std 4X-L' AS bar_label, 'Snowflake%' AS system_pat,
               'standard' AS tier, NULL AS compute_model,
               'aws' AS provider, 'us-east-1' AS region,
               '4X-Large' AS machine, '128' AS cluster_size
        UNION ALL
        -- 09: Snowflake Enterprise 4X-Large (128 credits/h)
        SELECT '09' AS id, 'SF Ent 4X-L' AS bar_label, 'Snowflake%' AS system_pat,
               'enterprise' AS tier, NULL AS compute_model,
               'aws' AS provider, 'us-east-1' AS region,
               '4X-Large' AS machine, '128' AS cluster_size
        UNION ALL
        -- 10: Snowflake Business Critical 4X-Large (128 credits/h)
        SELECT '10' AS id, 'SF BC 4X-L' AS bar_label, 'Snowflake%' AS system_pat,
               'business_critical' AS tier, NULL AS compute_model,
               'aws' AS provider, 'us-east-1' AS region,
               '4X-Large' AS machine, '128' AS cluster_size
    ),

    rows AS
    (
        SELECT
            s.id,
            s.bar_label,
            replaceRegexpOne(
                replaceRegexpOne(
                    replaceRegexpOne(c.system, '^Redshift.*$', 'Redshift'),
                    '^ClickHouse.*$', 'ClickHouse'
                ),
                '^Databricks.*$', 'Databricks'
            ) AS sys,
            c.tier          AS tier,
            c.compute_model AS cmodel,
            c.provider      AS prov,
            c.region        AS reg,
            c.machine       AS mach,
            c.cluster_size  AS csize,
            c.data_size     AS data_sz,
            c.storage_cost  AS stor_cost,
            c.compute_costs AS comp_arr,
            c.result        AS res_arr
        FROM sel AS s
        INNER JOIN
        (
            SELECT
                system,
                tier,
                compute_model,
                provider,
                region,
                machine,
                cluster_size,
                data_size,
                storage_cost,
                compute_costs,
                result
            FROM bench2cost.costs
        ) AS c
            ON  lowerUTF8(c.system) LIKE lowerUTF8(s.system_pat)
            AND ifNull(c.tier, '') = s.tier
            -- normalize compute_model on both sides: NULL == 'default'
            AND ifNull(c.compute_model, 'default') = ifNull(s.compute_model, 'default')
            AND lowerUTF8(ifNull(c.provider, '')) = lowerUTF8(s.provider)
            AND replaceAll(lowerUTF8(ifNull(c.region, '')), '-', '') =
                replaceAll(lowerUTF8(s.region), '-', '')
            AND c.machine LIKE concat('%', s.machine)
            -- critical fix: treat literal 'null' as NULL, then normalize
            AND ifNull(nullIf(c.cluster_size, 'null'), 'serverless')
                = ifNull(s.cluster_size, 'serverless')
    ),

    per_idx AS
    (
        SELECT
            id,
            bar_label,
            sys,
            tier,
            cmodel,
            prov,
            reg,
            mach,
            csize,
            data_sz,
            stor_cost,
            idx,
            tup,
            ((tup.1) IS NULL) AND ((tup.2) IS NULL) AND ((tup.3) IS NULL) AS all_null,
            arrayMin(arrayFilter(x -> (x IS NOT NULL), [tup.1, tup.2, tup.3])) AS hot_cost,
            res_arr[idx] AS rt,
            arrayMin(arrayFilter(x -> (x IS NOT NULL), [rt.1, rt.2, rt.3])) AS hot_rt
        FROM rows
        ARRAY JOIN
            arrayEnumerate(comp_arr) AS idx,
            comp_arr AS tup
    ),

    mask AS
    (
        SELECT
            idx,
            min(toUInt8(NOT all_null)) AS keep_idx
        FROM per_idx
        GROUP BY idx
    )

SELECT
    id,
    sys AS system,
    tier,
    cmodel AS compute_model,
    bar_label,
    prov AS provider,
    reg AS region,
    mach AS machine,
    csize AS cluster,
    formatReadableSize(any(data_sz)) AS data_sz,
    round(sumIf(hot_rt,  keep_idx = 1 AND hot_rt  IS NOT NULL), 3) AS rt_hot,
    round(any(stor_cost),                                     5) AS cost_data,
    round(sumIf(hot_cost, keep_idx = 1 AND hot_cost IS NOT NULL), 5) AS cost_hot,
    sumIf(1, keep_idx = 1) AS nq
FROM per_idx
INNER JOIN mask USING (idx)
GROUP BY
    id,
    sys,
    tier,
    cmodel,
    bar_label,
    prov,
    reg,
    mach,
    csize
ORDER BY id ASC
-- FORMAT JSONEachRow
;