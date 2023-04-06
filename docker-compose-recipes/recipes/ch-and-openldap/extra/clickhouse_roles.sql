CREATE ROLE clickhouse_administrators;
GRANT SELECT ON *.* TO clickhouse_administrators;
CREATE ROLE clickhouse_sales;
GRANT SELECT ON sales_db.* TO clickhouse_sales;
CREATE ROLE clickhouse_marketing;
GRANT SELECT ON marketing_db.* TO clickhouse_marketing;
