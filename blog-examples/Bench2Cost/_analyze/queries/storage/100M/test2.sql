
WITH
sel AS
(
    -- 01: ClickHouse Enterprise on GCP
    SELECT '01' AS id, 'CH Ent'   AS bar_label, 'ClickHouse%' AS system_pat,
           'Enterprise' AS tier, 'default' AS compute_model,
           'aws' AS provider, 'us-east-1' AS region, '236GiB' AS machine, '2' AS cluster_size

    UNION ALL
    -- 02: BigQuery Enterprise Plus
    SELECT '02', 'BQ Ent+'  AS bar_label, 'Bigquery'   AS system_pat,
           'Enterprise Plus' AS tier, 'capacity' AS compute_model,
           'gcp' AS provider, 'us-east-1' AS region, 'serverless' AS machine, 'serverless' AS cluster_size

    UNION ALL
    -- 03: Redshift Serverless (AWS)
    SELECT '03', 'RS Serverless', 'Redshift%',   -- <— wildcard
           'Standard', 'capacity',
           'aws', 'us-east-1', 'serverless', 'serverless'
),

rows AS (
  SELECT
      s.id,
      s.bar_label,
      -- keep raw system for ON; normalize after
      replaceRegexpOne(
        replaceRegexpOne(c.system, '^Redshift.*$', 'Redshift'),
        '^ClickHouse.*$', 'ClickHouse'
      ) AS sys,
      c.tier        AS tier,
      c.compute_model AS cmodel,
      c.provider    AS prov,
      c.region      AS reg,
      c.machine     AS mach,
      c.cluster_size AS csize,
      c.data_size   AS data_sz,
      c.storage_cost AS stor_cost,
      c.compute_costs AS comp_arr,
      c.result        AS res_arr
  FROM sel s
  INNER JOIN
  (
      -- ensure columns referenced in ON exist on the right side
      SELECT
          system, tier, compute_model, provider, region, machine, cluster_size,
          data_size, storage_cost, compute_costs, result
      FROM bench2cost.costs
  ) c
  ON  lowerUTF8(c.system) LIKE lowerUTF8(s.system_pat)
  AND ifNull(c.tier, '') = s.tier
  AND ifNull(c.compute_model, 'default') = s.compute_model
  AND lowerUTF8(ifNull(c.provider, '')) = lowerUTF8(s.provider)
  AND replaceAll(lowerUTF8(ifNull(c.region, '')), '-', '') =
      replaceAll(lowerUTF8(s.region), '-', '')
  AND c.machine = s.machine
  AND c.cluster_size = s.cluster_size
),

per_idx AS
(
    SELECT
        id, bar_label, sys, tier, cmodel, prov, reg, mach, csize, data_sz, stor_cost,
        idx, tup,
        (isNull(tup.1) AND isNull(tup.2) AND isNull(tup.3)) AS all_null,
        arrayMin(arrayFilter(x -> isNotNull(x), [tup.1, tup.2, tup.3])) AS hot_cost,
        arrayElement(res_arr, idx) AS rt,
        arrayMin(arrayFilter(x -> isNotNull(x), [rt.1, rt.2, rt.3])) AS hot_rt
    FROM rows
    ARRAY JOIN arrayEnumerate(comp_arr) AS idx, comp_arr AS tup
),

mask AS
(
    SELECT idx, min(toUInt8(NOT all_null)) AS keep_idx
    FROM per_idx GROUP BY idx
)

SELECT
    id,
    sys AS system,
    tier,
    cmodel AS compute_model,
    bar_label,   -- for chart labeling
    prov AS provider,
    reg AS region,
    mach AS machine,
    csize AS cluster,
    formatReadableSize(any(data_sz)) AS data_sz,
    round(sumIf(hot_rt,   keep_idx=1 AND isNotNull(hot_rt)),   3) AS rt_hot,
    round(any(stor_cost), 5) AS cost_data,
    round(sumIf(hot_cost, keep_idx=1 AND isNotNull(hot_cost)), 5) AS cost_hot,
    sumIf(1, keep_idx=1) AS nq
FROM per_idx
INNER JOIN mask USING (idx)
GROUP BY id, sys, tier, cmodel, bar_label, prov, reg, mach, csize
ORDER BY id
FORMAT JSONEachRow
;