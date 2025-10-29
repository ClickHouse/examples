-- Create table for nginx logs
CREATE TABLE logs_nginx
(
    `remote_addr` IPv4,
    `remote_user` LowCardinality(String),
    `time_local` DateTime CODEC(Delta(4), ZSTD(1)),
    `request_type` LowCardinality(String),
    `request_path` String CODEC(ZSTD(6)),
    `request_protocol` LowCardinality(String),
    `status` UInt16,
    `size` UInt32,
    `referer` String CODEC(ZSTD(6)),
    `user_agent` LowCardinality(String),
     Body ALIAS format('{0} - {1} [{2}] "{3} {4} {5}" {6} {7} "{8}" "{9}"',remote_addr, remote_user, time_local, request_type, request_path, request_protocol, status, size, referer, user_agent)
)
ORDER BY (user_agent, remote_user, referer, request_path)


-- Create table for recommendation service logs
CREATE TABLE logs_service_recommendation
(
    TemplateNumber UInt8,
    `date` String,
    `time` String,
    `service_name` Nullable(UUID),
    `trace_sampled` Nullable(UUID),
    `prod_1` LowCardinality(String),
    `prod_2` LowCardinality(String),
    `prod_3` LowCardinality(String),
    `prod_4` LowCardinality(String),
    `prod_5` LowCardinality(String),
    Body ALIAS multiIf(TemplateNumber=1, format('{0} {1} INFO [main] [recommendation_server.py:47] resource.service.name={2} trace_sampled={3}] - Receive ListRecommendations for product {4} {5} {6} {7} {8}',date,time,service_name,trace_sampled,prod_1,prod_2,prod_3,prod_4,prod_5), TemplateNumber=2, format('Receive ListRecommendations for product {0} {1} {2} {3} {4}',prod_1,prod_2,prod_3,prod_4,prod_5),''))
ORDER BY (date, prod_1, prod_2, prod_3, prod_4, prod_5)

-- Create table for cart service logs
CREATE TABLE logs_service_cart
(
    TemplateNumber UInt8,
    `user_id` Nullable(UUID),
    `product_id` String,
    `quantity` String,
    Body ALIAS multiIf(
        TemplateNumber=1, format('GetCartAsync called with userId={0}',user_id),
        TemplateNumber=2, 'info: cart.cartstore.ValkeyCartStore[0]',
        TemplateNumber=3, format('AddItemAsync called with userId={0}, productId={1}, quantity={2}', user_id, product_id, quantity),
        TemplateNumber=4, format('EmptyCartAsync called with userId={0}',user_id),
        '')
)
ORDER BY (TemplateNumber, product_id, quantity)

-- Create materialized view for nginx logs
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_logs_nginx
TO logs_service_nginx
AS
SELECT
    remote_address,
    remote_user,
    time_local,
    request_type,
    request_path,
    request_protocol,
    status,
    size,
    referer,
    user_agent
FROM
(
    WITH
        '^(\S+) - (\S+) \[([^\]]+)\] "([A-Z]+)?\s*(.*?)\s*(HTTP\S+)?" (\d{3}) (\d+) "([^"]*)" "([^"]*)"$' AS pattern
    SELECT
        *,
        match(Body, pattern) AS m1,
        extractAllGroups(Body, pattern) AS g,
        arrayElement(arrayElement(g, 1), 1) AS remote_address,
        arrayElement(arrayElement(g, 1), 2) AS remote_user,
        parseDateTimeBestEffort(arrayElement(arrayElement(g, 1), 3)) AS time_local,
        arrayElement(arrayElement(g, 1), 4) AS request_type,
        arrayElement(arrayElement(g, 1), 5) AS request_path,
        arrayElement(arrayElement(g, 1), 6) AS request_protocol,
        arrayElement(arrayElement(g, 1), 7) AS status,
        arrayElement(arrayElement(g, 1), 8) AS size,
        arrayElement(arrayElement(g, 1), 9) AS referer,
        arrayElement(arrayElement(g, 1), 10) AS user_agent
    FROM raw_logs where ServiceName='nginx'
) WHERE m1;

-- Create materialized view for recommendation service logs
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_logs_recommendation
TO logs_service_recommendation
AS
SELECT
   CASE WHEN m1 THEN 1 WHEN m2 THEN 2 ELSE 0 END AS TemplateNumber,
   CASE when m1 THEN g1_1 ELSE NULL END AS date,
   CASE when m1 THEN g1_2 ELSE NULL END AS time,
   CASE when m1 THEN g1_3 ELSE NULL END AS service_name,
   CASE when m1 THEN g1_4 ELSE NULL END AS trace_sampled,
   CASE when m1 THEN g1_5 ELSE g2_1 END AS prod_1,
   CASE when m1 THEN g1_6 ELSE g2_2 END AS prod_2,
   CASE when m1 THEN g1_7 ELSE g2_3 END AS prod_3,
   CASE when m1 THEN g1_8 ELSE g2_4 END AS prod_4,
   CASE when m1 THEN g1_9 ELSE g2_5 END AS prod_5

FROM
(
    WITH
        '^([^\\s]+) ([^\\s]+) INFO \[main\] \[recommendation_server.py:47\] \[trace_id=([^\\s]+) span_id=([^\\s]+) resource\.service\.name=recommendation trace_sampled=True\] - Receive ListRecommendations for product ids:\[([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+)\]$' AS pattern1,
        '^Receive ListRecommendations for product ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+) ([^\\s]+)$' AS pattern2
    SELECT
        *,
        match(Body, pattern1) AS m1,
        match(Body, pattern2) AS m2,
        extractAllGroups(Body, pattern1) AS g1,
        extractAllGroups(Body, pattern2) AS g2,

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
        arrayElement(arrayElement(g2, 1), 5) AS g2_5
    FROM raw_logs where ServiceName='recommendation'
);

-- Create materialized view for cart service logs
CREATE MATERIALIZED VIEW IF NOT EXISTS mv_logs_cart
TO logs_service_cart
AS
SELECT
   multiIf(m1, 1, m2, 2, m3, 3, 0) AS TemplateNumber,
   multiIf(m1, g1_1, m2, Null, m3, g3_1, m4, g4_1, Null) AS user_id,
   multiIf(m1, '', m2, '', m3, g3_2, '') AS product_id,
   multiIf(m1, '', m2, '', m3, g3_3, '') AS quantity

FROM
(
    WITH
        '^[\\s]*GetCartAsync called with userId=([^\\s]*)$' AS pattern1,
        '^info\: cart.cartstore.ValkeyCartStore\[0\]$' AS pattern2,
        '^[\\s]*AddItemAsync called with userId=([^\\s]+), productId=([^\\s]+), quantity=([^\\s]+)$' AS pattern3,
        '^[\\s]*EmptyCartAsync called with userId=([^\\s]*)$' AS pattern4
    SELECT
        *,
        match(Body, pattern1) AS m1,
        match(Body, pattern2) AS m2,
        match(Body, pattern3) AS m3,
        match(Body, pattern4) AS m4,
        extractAllGroups(Body, pattern1) AS g1,
        extractAllGroups(Body, pattern2) AS g2,
        extractAllGroups(Body, pattern3) AS g3,
        extractAllGroups(Body, pattern4) AS g4,

        arrayElement(arrayElement(g1, 1), 1) AS g1_1,
        arrayElement(arrayElement(g3, 1), 1) AS g3_1,
        arrayElement(arrayElement(g3, 1), 2) AS g3_2,
        arrayElement(arrayElement(g3, 1), 3) AS g3_3,
        arrayElement(arrayElement(g4, 1), 1) AS g4_1
    FROM raw_logs where ServiceName='cart'
);
