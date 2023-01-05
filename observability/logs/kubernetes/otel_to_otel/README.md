# Log collection with the Open Telemetry Collector

Collect logs and store in ClickHouse using the Open Telemetry Collector.

Installs an Open Telemetry collector as a deployment (for an aggregator/gateway) and as a deamonset to collect logs from each node.

## Install helm chart

```bash
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
```

## Download files

```
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/otel_to_otel/agent.yml
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/otel_to_otel/gateway.yml
```

## Install the aggregator

Installs the collector as a deployment. Ensure you modify the [target ClickHouse cluster](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/otel_to_otel/gateway.yml#L78) and [resources](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/otel_to_otel/gateway.yml#L223-L226) to fit your environment.

```bash
helm install otel-collector open-telemetry/opentelemetry-collector --values gateway.yml --create-namespace --namespace otel
```

This will create a table `otel_logs` in the `otel` database of the following schema:

```sql
CREATE TABLE otel.otel_logs
(
    `Timestamp` DateTime64(9) CODEC(Delta(8), ZSTD(1)),
    `TraceId` String CODEC(ZSTD(1)),
    `SpanId` String CODEC(ZSTD(1)),
    `TraceFlags` UInt32 CODEC(ZSTD(1)),
    `SeverityText` LowCardinality(String) CODEC(ZSTD(1)),
    `SeverityNumber` Int32 CODEC(ZSTD(1)),
    `ServiceName` LowCardinality(String) CODEC(ZSTD(1)),
    `Body` String CODEC(ZSTD(1)),
    `ResourceAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `LogAttributes` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    INDEX idx_trace_id TraceId TYPE bloom_filter(0.001) GRANULARITY 1,
    INDEX idx_res_attr_key mapKeys(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_res_attr_value mapValues(ResourceAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_key mapKeys(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_log_attr_value mapValues(LogAttributes) TYPE bloom_filter(0.01) GRANULARITY 1,
    INDEX idx_body Body TYPE tokenbf_v1(32768, 3, 0) GRANULARITY 1
)
ENGINE = MergeTRee
PARTITION BY toDate(Timestamp)
ORDER BY (ServiceName, SeverityText, toUnixTimestamp(Timestamp), TraceId)
SETTINGS index_granularity = 8192, ttl_only_drop_parts = 1
```

## Install the Agent

Installs the collector as a daemonset. Ensure you modify the [resources]() to fit your environment.

```bash
helm install otel-agent open-telemetry/opentelemetry-collector --values agent.yml --create-namespace --namespace otel
```

## Confirm logs are arriving


```sql
SELECT count()
FROM otel.otel_logs

┌─count()─┐
│ 4695341 │
└─────────┘
```
