# Kubernetes Logs in ClickHouse

Examples of how to collect and analyze Kubernetes logs in ClickHouse.

## Collection

Currently this consists of example configuration for different agent configurations. Agents can assume the role of either an [aggregator or agent](https://clickhouse.com/blog/storing-log-data-in-clickhouse-fluent-bit-vector-open-telemetry#architectures). These agents can be combined in different combinations e.g. FluentBit agent, Vector aggregator. We provide working examples for the following combinations. We use the naming convention `<agent> to <aggregator>`. 

- [Fluent Bit to Fluent Bit](./fluentbit_to_fluentbit)
- [Vector to Vector](./vector_to_vector)
- [OTEL Collector to OTEL Collector](./otel_to_otel)
- [Fluent Bit to Vector](./fluentbit_to_vector)
- [OTEL Collector to Vector](./otel_to_vector)

Note: these examples can be adapted for agent only examples. This is appropriate in smaller architectures of test scenarios.

Further detail can be found in this [blog post](https://clickhouse.com/blog/storing-log-data-in-clickhouse-fluent-bit-vector-open-telemetry).