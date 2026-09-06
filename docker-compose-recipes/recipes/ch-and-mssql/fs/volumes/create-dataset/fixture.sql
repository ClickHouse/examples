SET NOCOUNT ON;
IF DB_ID('ClickHouseDemo') IS NULL CREATE DATABASE ClickHouseDemo;
GO
USE ClickHouseDemo;
GO
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DROP TABLE IF EXISTS dbo.Customer;
CREATE TABLE dbo.Customer (
    customer_id INT NOT NULL PRIMARY KEY,
    firstname VARCHAR(25) NOT NULL,
    lastname VARCHAR(25) NOT NULL,
    email VARCHAR(25) NOT NULL,
    created_date DATETIME NOT NULL
);
INSERT INTO dbo.Customer VALUES
    (1, 'Jonah', 'Hook', 'jonah@clickhouse.db', '20210901'),
    (2, 'Mary', 'Brown', 'mary@clickhouse.db', '20121201'),
    (3, 'Russell', 'White', 'rwhite@clickhouse.db', '20180701'),
    (4, 'Dan', 'Red', 'dan@clickhouse.db', '20110901'),
    (5, 'Alice', 'Black', 'alice@clickhouse.db', '20110901');
COMMIT TRANSACTION;
SELECT COUNT(*) AS fixture_rows FROM dbo.Customer;
GO
