# Traces

## ClickHouse Schema

```sql
CREATE TABLE traces
(
    `transaction_hash` String,
    `transaction_index` UInt16,
    `from_address` String,
    `to_address` String,
    `value` Decimal(38, 0),
    `input` String,
    `output` String,
    `trace_type` Enum8('call' = 1, 'create' = 2, 'suicide' = 3, 'reward' = 4, 'genesis' = 5, 'daofork' = 6),
    `call_type` Enum8('' = 0, 'call' = 1, 'callcode' = 2, 'delegatecall' = 3, 'staticcall' = 4),
    `reward_type` Enum8('' = 0, 'block' = 1, 'uncle' = 2),
    `gas` UInt32 CODEC(Delta(4), ZSTD(1)),
    `gas_used` UInt32,
    `subtraces` UInt32,
    `trace_address` String,
    `error` String,
    `status` Bool,
    `block_timestamp` DateTime CODEC(Delta(4), ZSTD(1)),
    `block_number` UInt32 CODEC(Delta(4), ZSTD(1)),
    `block_hash` String,
    `trace_id` String
)
ENGINE = MergeTree
ORDER BY (trace_type, block_number, block_timestamp)
```

### Load instructions (public bucket - CSV files)

```sql
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
```

## BigQuery Schema

```sql
CREATE TABLE `clickhouse-cloud.crypto_ethereum.traces`
(
  transaction_hash STRING OPTIONS(description="Transaction hash where this trace was in"),
  transaction_index INT64 OPTIONS(description="Integer of the transactions index position in the block"),
  from_address STRING OPTIONS(description="Address of the sender, null when trace_type is genesis or reward"),
  to_address STRING OPTIONS(description="Address of the receiver if trace_type is call, address of new contract or null if trace_type is create, beneficiary address if trace_type is suicide, miner address if trace_type is reward, shareholder address if trace_type is genesis, WithdrawDAO address if trace_type is daofork"),
  value NUMERIC OPTIONS(description="Value transferred in Wei"),
  input STRING OPTIONS(description="The data sent along with the message call"),
  output STRING OPTIONS(description="The output of the message call, bytecode of contract when trace_type is create"),
  trace_type STRING NOT NULL OPTIONS(description="One of call, create, suicide, reward, genesis, daofork"),
  call_type STRING OPTIONS(description="One of call, callcode, delegatecall, staticcall"),
  reward_type STRING OPTIONS(description="One of block, uncle"),
  gas INT64 OPTIONS(description="Gas provided with the message call"),
  gas_used INT64 OPTIONS(description="Gas used by the message call"),
  subtraces INT64 OPTIONS(description="Number of subtraces"),
  trace_address STRING OPTIONS(description="Comma separated list of trace address in call tree"),
  error STRING OPTIONS(description="Error if message call failed. This field doesn't contain top-level trace errors."),
  status INT64 OPTIONS(description="Either 1 (success) or 0 (failure, due to any operation that can cause the call itself or any top-level call to revert)"),
  block_timestamp TIMESTAMP NOT NULL OPTIONS(description="Timestamp of the block where this trace was in"),
  block_number INT64 NOT NULL OPTIONS(description="Block number where this trace was in"),
  block_hash STRING NOT NULL OPTIONS(description="Hash of the block where this trace was in"),
  trace_id STRING OPTIONS(description="Unique string that identifies the trace. For transaction-scoped traces it is {trace_type}_{transaction_hash}_{trace_address}. For block-scoped traces it is {trace_type}_{block_number}_{index_within_block}")
)
PARTITION BY DATE(block_timestamp)
OPTIONS(
  description="Traces exported using Parity trace module https://wiki.parity.io/JSONRPC-trace-module.\nData is exported using https://github.com/medvedev1088/ethereum-etl\n"
);
```

## Redshift Schema

Note the absence of the `input` and `output` columns as they cannot be stored due to their size exceeding [Redshift VARCHAR limits](https://docs.aws.amazon.com/redshift/latest/dg/r_Character_types.html).

```sql
CREATE TABLE traces (
    transaction_hash character(66) ENCODE zstd,
    transaction_index integer ENCODE zstd,
    from_address character(42) ENCODE zstd,
    to_address character(42) ENCODE zstd,
    value numeric(38,0) ENCODE zstd,
    trace_type character varying(7) ENCODE zstd,
    call_type character varying(12) ENCODE raw,
    reward_type character varying(5) ENCODE zstd,
    gas bigint ENCODE zstd,
    gas_used bigint ENCODE zstd,
    subtraces bigint ENCODE zstd,
    trace_address character varying(2500) ENCODE zstd,
    error character varying(50) ENCODE zstd,
    status integer ENCODE zstd,
    block_timestamp timestamp without time zone ENCODE raw,
    block_number bigint ENCODE raw,
    block_hash character(66) ENCODE zstd,
    trace_id character varying(2500) ENCODE zstd
)
DISTSTYLE AUTO
SORTKEY ( trace_type, block_number, block_timestamp );	
```