# Ethereum

Contains queries for the Ethereum block chain dataset available in [sql.clickhouse.com](https://crypto.clickhouse.com/?query=U0hPVyBUYWJsZXMgZnJvbSBldGhlcmV1bQ&).

Read the accompanying blog post on [Migrating a multi-TB dataset from ClickHouse to Big Query data](https://clickhouse.com/blog/clickhouse-bigquery-migrating-data-for-realtime-queries).

These queries were originally provided for BigQuery and have been migrated and optimized for ClickHouse.

## Loading data

Data can be loaded in [batch](./batch/README.md) (once-off or scheduled) or continuously [streamed](./streaming/README.md).
### Batch

#### Schemas
- [Blocks](./batch/schemas/blocks.md) - Blocks are batches of transactions with a hash of the previous block in the chain.
- [Transactions](./batch/schemas/transactions.md) -Transactions are cryptographically signed instructions from accounts. An account will initiate a transaction to update the state of the Ethereum network e.g. transferring ETH from one account to another.
- [Traces](./batch/schemas/traces.md) - Internal transactions that allow querying all Ethereum addresses with their balances.
- [Contracts](./batch/schemas/contracts.md) - A "smart contract" is simply a program that runs on the Ethereum blockchain.

#### Loading with Beam

[Python example of Apache Beam job for data loading](./batch/beam_dataflow/README.md)

#### Loading CSVs from blob storage

[Python example of loading CSVs from blob storage](./batch/inserts/README.md)

### Streaming

#### Schemas
- [Blocks](./streaming/schemas/blocks.md) - Blocks are batches of transactions with a hash of the previous block in the chain.
- [Transactions](./streaming/schemas/transactions.md) -Transactions are cryptographically signed instructions from accounts. An account will initiate a transaction to update the state of the Ethereum network e.g. transferring ETH from one account to another.
- [Traces](./streaming/schemas/traces.md) - Internal transactions that allow querying all Ethereum addresses with their balances.

## Queries

- [Average costs over time](./queries/ether_costs_over_time.sql)
- [Ether supply by day](./queries/ether_supply_by_day.sql)
- [Gas used per week](./queries/gas_used_per_week.sql)
- [10 most popular collectibles (ERC721)](./queries/popular_collectables.sql)
- [10 most popular tokens (ERC20 contracts)](./queries/popular_contracts.sql)
- [Smart contract creation](./queries/smart_contract_creation.sql)
- [Ethereum throughput](./queries/throughput.sql)
- [Ethereum throughput average per day](./queries/throughput_avg_per_day.sql)
- [Top balances](./queries/top_balances.sql)
- [Total market capitalization](./queries/total_market_capitalization.sql)

## References and further reading

We recommend the following resources with respect to Ethereum and querying this dataset.

- [How to replay time series data from Google BigQuery to Pub/Sub](https://medium.com/google-cloud/how-to-replay-time-series-data-from-google-bigquery-to-pub-sub-c0a80095124b)
- [Evgeny Medvedev series on the blockchain analysis](https://evgemedvedev.medium.com/)
- [Ethereum in BigQuery: a Public Dataset for smart contract analytics](https://cloud.google.com/blog/products/data-analytics/ethereum-bigquery-public-dataset-smart-contract-analytics)
- [Awesome BigQuery Views for Crypto](https://github.com/blockchain-etl/awesome-bigquery-views)
- [How to Query Balances for all Ethereum Addresses in BigQuery](https://medium.com/google-cloud/how-to-query-balances-for-all-ethereum-addresses-in-bigquery-fb594e4034a7)
- [Visualizing Average Ether Costs Over Time](https://www.kaggle.com/code/mrisdal/visualizing-average-ether-costs-over-time)
- [Plotting Ethereum Address Growth Chart in BigQuery](https://medium.com/google-cloud/plotting-ethereum-address-growth-chart-55cc0e7207b2)
- [Comparing Transaction Throughputs for 8 blockchains in Google BigQuery with Google Data Studio](https://evgemedvedev.medium.com/comparing-transaction-throughputs-for-8-blockchains-in-google-bigquery-with-google-data-studio-edbabb75b7f1)
- [Introducing six new cryptocurrencies in BigQuery Public Datasets—and how to analyze them](https://cloud.google.com/blog/products/data-analytics/introducing-six-new-cryptocurrencies-in-bigquery-public-datasets-and-how-to-analyze-them)
