# Log collection with the Vector

Collect logs and store in ClickHouse using Vector.


Installs an Vector agent as a deployment (for an aggregator) and as a deamonset to collect logs from each node.

## Install helm chart

```bash
helm repo add vector https://helm.vector.dev
```

## Create the database and table

```bash
CREATE database vector

CREATE TABLE vector.vector_logs
(
   `file` String,
   `timestamp` DateTime64(3),
   `kubernetes_container_id` LowCardinality(String),
   `kubernetes_container_image` LowCardinality(String),
   `kubernetes_namespace_labels` Map(LowCardinality(String), String),
   `kubernetes_node_labels` Map(LowCardinality(String), String),
   `kubernetes_container_name` LowCardinality(String),
   `kubernetes_pod_annotations`  Map(LowCardinality(String), String),
   `kubernetes_pod_ip` IPv4,
   `kubernetes_pod_ips` Array(IPv4),
   `kubernetes_pod_labels` Map(LowCardinality(String), String),
   `kubernetes_pod_name` LowCardinality(String),
   `kubernetes_pod_namespace` LowCardinality(String),
   `kubernetes_pod_node_name` LowCardinality(String),
   `kubernetes_pod_owner` LowCardinality(String),
   `kubernetes_pod_uid` LowCardinality(String),
   `message` String,
   `source_type` LowCardinality(String),
   `stream` Enum('stdout', 'stderr')
)
ENGINE = MergeTree
ORDER BY (`kubernetes_container_name`, timestamp)
```

## Download files

Download the agent and aggregator value files for the helm chart.

```
wget https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml
wget https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/agent.yaml
```

## Install the aggregator

Installs the collector as a deployment. Ensure you modify the [target ClickHouse cluster](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml#L314-L324) and [resources](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml#L167-L173) to fit your environment.


```bash
helm install vector-aggregator vector/vector \
  --namespace vector \
  --create-namespace \
  --values aggregator.yaml
```


## Install the Agent

Installs the collector as a daemonset. Ensure you modify the [resources]() to fit your environment.


```bash
helm install vector-agent vector/vector \
  --namespace vector \
  --create-namespace \
  --values agent.yaml
```
