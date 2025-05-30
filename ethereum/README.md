# Ethereum

This directory contains examples that demonstrate how store and query Ethereum data in ClickHouse.

Read the accompanying blog post: [Migrating a multi-TB dataset from ClickHouse to Big Query data](https://clickhouse.com/blog/clickhouse-bigquery-migrating-data-for-realtime-queries).

If you just want to play with the data, you can try it live at [crypto.clickhouse.com](https://crypto.clickhouse.com/?query=U0hPVyBUYWJsZXMgZnJvbSBldGhlcmV1bQ&).

## Storing data

ClickHouse supports both batch and streaming workflows.

The [batch](./batch/README.md) directory contains table schemas and examples of loading the Ethereum data set in batches.

The [streaming](./streaming/README.md) directory contains table schemas and examples of loading the Ethereum data set as streams.

## Querying data

The [queries](./queries/README.md) directory contains examples of queries that can be run on the Ethereum dataset.

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
