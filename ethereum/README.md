# Ethereum

Contains queries for the Ethereum block chain dataset available in [sql.clickhouse.com](https://sql.clickhouse.com/play?user=play#U0hPVyBUQUJMRVMgSU4gZXRoZXJldW0=).

Read the accompanying blog post on [Migrating a multi-TB dataset from ClickHouse to Big Query data]().

These queries were originally provided for BigQuery and have been migrated and optimized for ClickHouse syntax. For each, we provide the original BigQuery syntax and ClickHouse equivalent. We welcome contributions and improvements.

## Dataset

The dataset consists of the following tables (schemas and loading instructions are linked):

- [Blocks](./schemas/blocks.md) - Blocks are batches of transactions with a hash of the previous block in the chain.
- [Transactions](./schemas/transactions.md) -Transactions are cryptographically signed instructions from accounts. An account will initiate a transaction to update the state of the Ethereum network e.g. transferring ETH from one account to another.
- [Traces](./schemas/traces.md) - Internal transactions that llow querying all Ethereum addresses with their balances.
- [Contracts](./schemas/contracts.md) - A "smart contract" is simply a program that runs on the Ethereum blockchain.

## Queries

Note some of the following are pending ClickHouse implementations. Contributions welcome.

- [Top Ethereum Balances](./queries/top_balances.md)
- [Number of addresses with non-zero balance over time](./queries/non_zero_balance.md)
- [Every Ethereum Balance on Every Day](./queries/every_balance_every_day.md)
- [Ethereum Throughput](./queries/throughput.md)
- [Average Ether Costs over Time](./queries/ether_costs_over_time.md)
- [Ethereum Address Growth](./queries/address_growth.md)
- [Ether supply by day](./queries/ether_supply_by_day.md)
- [Unique Addresses by Day](./queries/unique_addresses_by_day.md)
- [10 most popular Ethereum collectibles (ERC721)](./queries/popular_collectables.md)
- [10 most popular Ethereum tokens (ERC20 contracts)](./queries/popular_contracts.md)
- [Shortest Path via Traces]()
- [Total Ether transferred and average transaction cost, aggregated by day]() - pending.

## References and further reading

We recommend the following resources with respect to Ethereum and querying this dataset.

[How to replay time series data from Google BigQuery to Pub/Sub](https://medium.com/google-cloud/how-to-replay-time-series-data-from-google-bigquery-to-pub-sub-c0a80095124b)

[Evgeny Medvedev series on the blockchain analysis](https://evgemedvedev.medium.com/)

[Ethereum in BigQuery: a Public Dataset for smart contract analytics](https://cloud.google.com/blog/products/data-analytics/ethereum-bigquery-public-dataset-smart-contract-analytics)

[Awesome BigQuery Views for Crypto](https://github.com/blockchain-etl/awesome-bigquery-views)

[How to Query Balances for all Ethereum Addresses in BigQuery](https://medium.com/google-cloud/how-to-query-balances-for-all-ethereum-addresses-in-bigquery-fb594e4034a7)

[Visualizing Average Ether Costs Over Time](https://www.kaggle.com/code/mrisdal/visualizing-average-ether-costs-over-time)

[Plotting Ethereum Address Growth Chart in BigQuery](https://medium.com/google-cloud/plotting-ethereum-address-growth-chart-55cc0e7207b2)

[Comparing Transaction Throughputs for 8 blockchains in Google BigQuery with Google Data Studio](https://evgemedvedev.medium.com/comparing-transaction-throughputs-for-8-blockchains-in-google-bigquery-with-google-data-studio-edbabb75b7f1)

[Introducing six new cryptocurrencies in BigQuery Public Datasets—and how to analyze them](https://cloud.google.com/blog/products/data-analytics/introducing-six-new-cryptocurrencies-in-bigquery-public-datasets-and-how-to-analyze-them)
