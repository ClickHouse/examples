# Every Ethereum Balance on Every Day

Originally from [Awesome BigQuery Views](https://github.com/blockchain-etl/awesome-bigquery-views#every-ethereum-balance-on-every-day)

## BigQuery

```sql
WITH double_entry_book AS (
    -- debits
    SELECT to_address AS address, value AS value, block_timestamp
    FROM `bigquery-public-data.crypto_ethereum.traces`
    WHERE to_address IS NOT NULL
    AND status = 1
    AND (call_type NOT IN ('delegatecall', 'callcode', 'staticcall') OR call_type IS NULL)
    UNION ALL
    -- credits
    SELECT from_address AS address, -value AS value, block_timestamp
    FROM `bigquery-public-data.crypto_ethereum.traces`
    WHERE from_address IS NOT NULL
    AND status = 1
    AND (call_type NOT IN ('delegatecall', 'callcode', 'staticcall') OR call_type IS NULL)
    UNION ALL
    -- transaction fees debits
    SELECT 
        miner AS address, 
        SUM(CAST(receipt_gas_used AS numeric) * CAST((receipt_effective_gas_price - COALESCE(base_fee_per_gas, 0)) AS numeric)) AS value,
        block_timestamp
    FROM `bigquery-public-data.crypto_ethereum.transactions` AS transactions
    JOIN `bigquery-public-data.crypto_ethereum.blocks` AS blocks ON blocks.number = transactions.block_number
    GROUP BY blocks.number, blocks.miner, block_timestamp
    UNION ALL
    -- transaction fees credits
    SELECT 
        from_address AS address, 
        -(CAST(receipt_gas_used AS numeric) * CAST(receipt_effective_gas_price AS numeric)) AS value,
        block_timestamp
    FROM `bigquery-public-data.crypto_ethereum.transactions`
),
double_entry_book_grouped_by_date AS (
    SELECT address, SUM(value) AS balance_increment, DATE(block_timestamp) AS date
    FROM double_entry_book
    GROUP BY address, date
),
daily_balances_with_gaps AS (
    SELECT address, date, SUM(balance_increment) OVER (PARTITION BY address ORDER BY date) AS balance,
    LEAD(date, 1, CURRENT_DATE()) OVER (PARTITION BY address ORDER BY date) AS next_date
    FROM double_entry_book_grouped_by_date
),
calendar AS (
    SELECT date FROM UNNEST(GENERATE_DATE_ARRAY('2015-07-30', CURRENT_DATE())) AS date
),
daily_balances AS (
    SELECT address, calendar.date, balance
    FROM daily_balances_with_gaps
    JOIN calendar ON daily_balances_with_gaps.date <= calendar.date AND calendar.date < daily_balances_with_gaps.next_date
)
SELECT address, date, balance
FROM daily_balances
```

## ClickHouse

TODO