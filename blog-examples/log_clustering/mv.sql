CREATE MATERIALIZED VIEW IF NOT EXISTS mv_logs_structured
TO logs_structured
AS
SELECT
    ServiceName,
    /* which template matched */
    multiIf(m1, 1, m2, 2, m3, 3, m4, 4, m5, 5, m6, 6, 7) AS TemplateNumber,
    /* extracted fields as Map(LowCardinality(String), String) */
    CAST(
    multiIf(
      m1,
      map(
        'date',           g1_1,
        'time',           g1_2,
        'service_name',   g1_3,
        'trace_sampled',  g1_4,
        'prod_1',         g1_5,
        'prod_2',         g1_6,
        'prod_3',         g1_7,
        'prod_4',         g1_8,
        'prod_5',         g1_9
      ),
      m2,
      map(
        'prod_1', g2_1,
        'prod_2', g2_2,
        'prod_3', g2_3,
        'prod_4', g2_4,
        'prod_5', g2_5
      ),
      m3,
      map('cart_1', g3_1),
      m4,
      map(),                 -- pattern4 has no captures; nothing to extract
      m5,
      map(
        'cart_1', g5_1,
        'cart_2', g5_2,
        'cart_3', g5_3
      ),
      m6,
      map(
        'remote_addr', g6_1,
        'remote_user', g6_2,
        'time_local', g6_3,
        'request_type', g6_4,
        'request_path', g6_5,
        'request_protocol', g6_6,
        'status', g6_7,
        'size', g6_8,
        'referer', g6_9,
        'user_agent', g6_10
      ),
      map()                   -- else: empty map
    ),
    'Map(LowCardinality(String), String)'
  ) AS Extracted
FROM
(
    /* compute once per row */
    WITH
        '^([^\\s]+) ([^\\s]+) INFO \[main\] \[recommendation_server.py:47\] \[trace_id=([^\\s]+) span_id=([^\\s]+) resource\.service\.name=recommendation trace_sampled=True\] - Receive ListRecommendations for product ids:\[([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+)\]$' AS pattern1,
        '^Receive ListRecommendations for product ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+)$' AS pattern2,
        '^[\\s]*GetCartAsync called with userId=([^\\s]+)$' AS pattern3,
        '^info\: cart.cartstore.ValkeyCartStore\[0\]$' AS pattern4,
        '^[\\s]*AddItemAsync called with userId=([^\\s]+), productId=([^\\s]+), quantity=([^\\s]+)$' AS pattern5,
        '^(\S+) - (\S+) \[([^\]]+)\] "([A-Z]+)?\s*(.*?)\s*(HTTP\S+)?" (\d{3}) (\d+) "([^"]*)" "([^"]*)"$' AS pattern6

    SELECT
        *,
        match(Body, pattern1) AS m1,
        match(Body, pattern2) AS m2,
        match(Body, pattern3) AS m3,
        match(Body, pattern4) AS m4,
        match(Body, pattern5) AS m5,
         match(Body, pattern6) AS m6,
        extractAllGroups(Body, pattern1) AS g1,
        extractAllGroups(Body, pattern2) AS g2,
        extractAllGroups(Body, pattern3) AS g3,
        extractAllGroups(Body, pattern4) AS g4,
        extractAllGroups(Body, pattern5) AS g5,
        extractAllGroups(Body, pattern6) AS g6,

        /* pick first (and only) match’s capture groups */
        arrayElement(arrayElement(g1, 1), 1) AS g1_1,
        arrayElement(arrayElement(g1, 1), 2) AS g1_2,
        arrayElement(arrayElement(g1, 1), 3) AS g1_3,
        arrayElement(arrayElement(g1, 1), 4) AS g1_4,
        arrayElement(arrayElement(g1, 1), 5) AS g1_5,
        arrayElement(arrayElement(g1, 1), 6) AS g1_6,
        arrayElement(arrayElement(g1, 1), 7) AS g1_7,
        arrayElement(arrayElement(g1, 1), 7) AS g1_8,
        arrayElement(arrayElement(g1, 1), 7) AS g1_9,

        arrayElement(arrayElement(g2, 1), 1) AS g2_1,
        arrayElement(arrayElement(g2, 1), 2) AS g2_2,
        arrayElement(arrayElement(g2, 1), 3) AS g2_3,
        arrayElement(arrayElement(g2, 1), 4) AS g2_4,
        arrayElement(arrayElement(g2, 1), 5) AS g2_5,

        arrayElement(arrayElement(g3, 1), 1) AS g3_1,
        arrayElement(arrayElement(g5, 1), 1) AS g5_1,
        arrayElement(arrayElement(g5, 1), 2) AS g5_2,
        arrayElement(arrayElement(g5, 1), 3) AS g5_3,

        arrayElement(arrayElement(g6, 1), 1) AS g6_1,
        arrayElement(arrayElement(g6, 1), 2) AS g6_2,
        arrayElement(arrayElement(g6, 1), 3) AS g6_3,
        arrayElement(arrayElement(g6, 1), 4) AS g6_4,
        arrayElement(arrayElement(g6, 1), 1) AS g6_5,
        arrayElement(arrayElement(g6, 1), 2) AS g6_6,
        arrayElement(arrayElement(g6, 1), 3) AS g6_7,
        arrayElement(arrayElement(g6, 1), 4) AS g6_8,
        arrayElement(arrayElement(g6, 1), 4) AS g6_9,
        arrayElement(arrayElement(g6, 1), 4) AS g6_10
    FROM logs_raw
);
