# Log collection with the Fluent Bit and Vector

Collect logs and store in ClickHouse using the Fluent Bit as an agent and Vector as an aggregator.

Installs Vector as a StatefulSet (for an aggregator) and an Fluent Bit as a deamonset to collect logs from each node.

## Install helm charts

```bash
helm repo add vector https://helm.vector.dev
helm repo add fluent https://fluent.github.io/helm-charts
```

## Create the database and table

```sql
CREATE TABLE default.fluent_vector_logs
(
    `log` String,
    `host` IPv4,
    `tag` String,
    `timestamp` DateTime64(9),
    `source_type` LowCardinality(String),
    `stream` LowCardinality(String),
    `kubernetes` Tuple(annotations Map(LowCardinality(String), String), container_hash String, container_image LowCardinality(String), container_name LowCardinality(String), docker_id LowCardinality(String), host LowCardinality(String), labels Map(LowCardinality(String), String), namespace_name LowCardinality(String), pod_id LowCardinality(String), pod_name LowCardinality(String))
)
ENGINE = MergeTree
ORDER BY (timestamp)
```

An alternative simpler schema is to move all fields of the `kubernetes` column to the root using VTL. This requires a remap transform. See the example and associated schema in the [Vector to Vector](../vector_to_vector/) case.

Remember to adapt you [ORDER BY key](https://clickhouse.com/docs/en/guides/improving-query-performance/sparse-primary-indexes/sparse-primary-indexes-intro) to suit your access patterns.


## Download files

Download the agent and aggregator value files for the helm chart.

```
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/fluentbit_to_vector/agent.yaml
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/fluentbit_to_vector/aggregator.yaml
```

## Aggregator Configuration

The [aggregator.yaml](./aggregator.yaml) provides a full sample Vector aggregator configuration, requiring only minor changes for most cases.

Key configuration is the use of the fluent source to receive logs from the Fluent Bit agent i.e.

```yaml
sources:
  fluent:
    address: 0.0.0.0:24244
    type: fluent
```

**Important**

Ensure you configure your [ClickHouse host and access credentials](./aggregator.yaml#L298-L304) and adapt [resources](./aggregator.yaml#L167) as required.

## Install the aggregator

Installs the vector as a StatefulSet.

```bash
helm install vector-aggregator-fluent vector/vector \
  --namespace fluent-vector \
  --create-namespace \
  --values aggregator.yaml
```

## Agent Configuration

The [agent.yaml](./agent.yaml) provides a full sample Fluent Bit configuration for log location, requiring only minor changes for most cases.

The principal configuration changes is the specification of a `forward` output to communicate with the aggregator:

```yaml
outputs: |
    [OUTPUT]
        Name forward
        Match *
        Host vector-aggregator-fluent
        Port 24244
```

## Install the Agent

Installs the OTEL collector as a daemonset:

```bash
helm install fluent-bit fluent/fluent-bit --values agent.yaml --namespace fluent-vector
```

## Confirm logs are arriving

```sql
SELECT count()
FROM vector.fluent_vector_logs

┌─count()─┐
│ 1195341 │
└─────────┘
```
