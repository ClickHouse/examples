INSERT INTO traces
SELECT
    transaction_hash,
    transaction_index,
    from_address,
    to_address,
    value,
    input,
    output,
    trace_type,
    call_type,
    reward_type,
    gas,
    gas_used,
    subtraces,
    trace_address,
    error,
    status,
    toInt64(block_timestamp) AS block_timestamp,
    block_number,
    block_hash,
    trace_id
FROM s3Cluster('default', 'https://storage.googleapis.com/clickhouse_public_datasets/ethereum/traces/*.csv.gz', 'CSVWithNames', 'transaction_hash String,transaction_index Int64,from_address String,to_address String,value Decimal(38, 0),input String,output String,trace_type Enum8(\'\'=0,\'call\'=1, \'create\' = 2, \'suicide\' = 3, \'reward\' = 4, \'genesis\' = 5, \'daofork\' = 6) ,call_type Enum8(\'call\' = 1, \'callcode\' = 2, \'delegatecall\' = 3, \'staticcall\' = 4),reward_type Enum8(\'\'=0,\'block\' = 1, \'uncle\' = 2), gas Int64, gas_used Int64, subtraces Int64, trace_address String, error String, status Bool, block_timestamp DateTime, block_number Int64, block_hash String, trace_id String')