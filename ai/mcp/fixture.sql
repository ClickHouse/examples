CREATE DATABASE IF NOT EXISTS mcp_demo;

CREATE TABLE IF NOT EXISTS mcp_demo.sales
(
    sale_id UInt8,
    sold_on Date,
    region LowCardinality(String),
    revenue UInt32
)
ENGINE = MergeTree
ORDER BY sale_id;

-- Load once; rerunning the walkthrough does not duplicate the fixture.
INSERT INTO mcp_demo.sales
SELECT *
FROM values(
    'sale_id UInt8, sold_on Date, region String, revenue UInt32',
    (1, '2026-09-01', 'North', 100),
    (2, '2026-09-02', 'North', 150),
    (3, '2026-09-01', 'South', 200),
    (4, '2026-09-02', 'South', 300)
)
WHERE (SELECT count() FROM mcp_demo.sales) = 0;
