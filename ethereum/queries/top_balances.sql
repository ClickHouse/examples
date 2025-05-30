
-- Originally from https://github.com/blockchain-etl/awesome-bigquery-views#top-ethereum-balances and https://medium.com/google-cloud/how-to-query-balances-for-all-ethereum-addresses-in-bigquery-fb594e4034a7

SELECT
    address,
    sum(sub) AS balance
FROM
(
    SELECT
        arrayJoin([to_address, from_address]) AS address,
        sum(value * multiIf(to_address = from_address, 0, address = to_address, 1, -1)) AS sub
    FROM ethereum.traces
    WHERE (address IS NOT NULL) AND (status = 1) AND ((call_type NOT IN ('delegatecall', 'callcode', 'staticcall')) OR (call_type IS NULL))
    GROUP BY address
    UNION ALL
    SELECT
        miner AS address,
        SUM(receipt_gas_used * (receipt_effective_gas_price - base_fee_per_gas)) AS sub
    FROM ethereum.transactions AS transactions
    INNER JOIN ethereum.blocks AS blocks ON blocks.number = transactions.block_number
    GROUP BY
        blocks.number,
        blocks.miner
    UNION ALL
    SELECT
        from_address AS address,
        sum((-1 * receipt_gas_used) * receipt_effective_gas_price) AS sub
    FROM ethereum.transactions
    GROUP BY from_address
)
GROUP BY address
ORDER BY balance DESC
LIMIT 10