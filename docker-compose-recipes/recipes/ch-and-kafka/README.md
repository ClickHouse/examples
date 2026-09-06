# Legacy Confluent Kafka stack

This unmaintained Compose stack contains a multi-broker Confluent/ZooKeeper
configuration without a verified produce-to-query walkthrough. It is awaiting
replacement with a small Kafka-compatible Redpanda example; use the other
[indexed recipes](../../README.md) for verified local lessons.

For production streaming ingestion, use [ClickPipes](https://clickhouse.com/cloud/clickpipes)
to connect Kafka or Redpanda to ClickHouse Cloud.
