# Log collection with the Open Telemetry Collector and Vector

Collect logs and store in ClickHouse using the Open Telemetry Collector as an agent and Vector as an aggregator.

Installs Vector as a deployment (for an aggregator) and an Open Telemetry collector as a deamonset to collect logs from each node.


## Install helm charts

```bash
helm repo add vector https://helm.vector.dev
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
```

## Create the database and table

```sql
CREATE database vector

CREATE TABLE vector.otel_vector_logs
(
    `message` String,
    `dropped_attributes_count` Int32,
    `timestamp` DateTime64(9),
    `source_type` LowCardinality(String),
    `resources` Map(LowCardinality(String), String) CODEC(ZSTD(1)),
    `attributes` Map(LowCardinality(String), String) CODEC(ZSTD(1))
)
ENGINE = MergeTree
ORDER BY (timestamp)
```

Remember to adapt you [ORDER BY key](https://clickhouse.com/docs/en/guides/improving-query-performance/sparse-primary-indexes/sparse-primary-indexes-intro) to suit your access patterns.

## Download files

Download the agent and aggregator value files for the helm chart.

```
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/otel_to_vector/agent.yml
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/otel_to_vector/aggregator.yml
```

## Aggregator Configuration

The [aggregator.yml](./aggregator.yml) provides a full sample Vector aggregator configuration, requiring only minor changes for most cases.

Key configuration is the use of the otel source to recieve logs from the OTEL agent i.e.

```yaml
  sources:
    otel:
      type: opentelemetry
      acknowledgements:
        enabled: false
      grpc:
        address: "0.0.0.0:4317"
      http:
        address: "0.0.0.0:4318"
```

**Important**

Ensure you configure your the [ClickHouse host and access credentials](./aggregator.yaml#L313-L324) and adapt [resources](./aggregator.yaml#L173) as required.

## Install the aggregator

Installs the vector as a deployment.

```bash
helm install vector-aggregator-otel vector/vector \
  --namespace otel-vector \
  --create-namespace \
  --values aggregator.yaml

kubectl get pods -n=otel-vector
NAME                  READY   STATUS    RESTARTS   AGE
vector-aggregator-otel-0   1/1     Running   0          39s
```

## Agent Configuration

The [agent.yml](./agent.yml) provides a full sample OTEL agent configuration for log location, requiring only minor changes for most cases.

We set the mode to `daemonset` and enable the logs' collection and enrichment with k8s metadata.

```yaml
mode: "daemonset"
presets:
 logsCollection:
   enabled: true
   includeCollectorLogs: false
   storeCheckpoints: true
 kubernetesAttributes:
   enabled: true
```

Our pipeline, in this instance, is configured to utilize an oltp exporter to send logs to the aggregator. Again we use the batch processor to ensure large bulk sizes and modify the `k8sattributes` processor to enrich our logs.

```yaml
config:
 exporters:
   OTLP:
     endpoint: vector-aggregator-otel:4317
     tls:
       insecure: true
     sending_queue:
       num_consumers: 4
       queue_size: 100
     retry_on_failure:
       enabled: true
```

## Install the Agent

Installs the OTEL collector as a daemonset:

```bash
helm install otel-agent-vector open-telemetry/opentelemetry-collector --values agent.yml --namespace otel-vector
```

## Confirm logs are arriving

```sql
SELECT count()
FROM vector.otel_vector_logs

┌─count()─┐
│ 5695341 │
└─────────┘
```
