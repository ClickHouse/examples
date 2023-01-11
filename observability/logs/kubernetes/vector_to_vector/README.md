# Log collection with the Vector

Collect logs and store in ClickHouse using Vector.


Installs an Vector agent as a deployment (for an aggregator) and as a deamonset to collect logs from each node.

## Install helm chart

```bash
helm repo add vector https://helm.vector.dev
```

## Create the database and table

```sql
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

```bash
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/vector_to_vector/agent.yaml
```

## Aggegator Configuration

The [aggregator.yml](./aggregator.yml) provides a full sample gateway configuration, requiring only minor changes for most cases.

To deploy an aggregator, we make a few key configuration changes to the charts `values.yaml`:
  - Set the `role` to “Aggregator”
    ```yaml
    role: "Aggregator"
    ```
  - Tune our resource limits to fit our throughput
  - Modify the `customConfig` key to use [vector as our source](https://vector.dev/docs/reference/configuration/sources/vector/). This vector-specific protocol allows agent instances to forward logs to the aggregator over port 6000. Note also our [remap](https://vector.dev/docs/reference/configuration/transforms/remap/) transform, which uses [VRL](https://vector.dev/docs/reference/vrl/) to ensure columns use `_` as delimiter and not `.`.
    ```yaml
    customConfig:
      data_dir: /vector-data-dir
        api:
          enabled: true
          address: 127.0.0.1:8686
          playground: false
        sources:
          vector:
            address: 0.0.0.0:6000
            type: vector
            version: "2"
        transforms:
          dots_to_underscores:
            type: remap
            inputs: [vector]
            source: |
              .kubernetes_namespace_labels = .kubernetes.namespace_labels
              .kubernetes_node_labels = .kubernetes.node_labels
              .kubernetes_pod_annotations = .kubernetes.pod_annotations
              .kubernetes_pod_labels = .kubernetes.pod_labels
              .kubernetes_container_image = .kubernetes.container_image
              .kubernetes_container_name = .kubernetes.container_name
              .kubernetes_pod_ip = .kubernetes.pod_ip
              .kubernetes_pod_ips = .kubernetes.pod_ips
              .kubernetes_pod_name = .kubernetes.pod_name
              .kubernetes_pod_namespace = .kubernetes.pod_namespace
              .kubernetes_pod_node_name = .kubernetes.pod_node_name
              .kubernetes_pod_owner = .kubernetes.pod_owner
              .kubernetes_pod_uid = .kubernetes.pod_uid
              del(.kubernetes)
    ```
  - Under the same `customConfig` key, configure the ClickHouse sink. Note the need to specify a protocol prefix in the endpoint and settings to encourage [larger batch sizes](https://vector.dev/docs/reference/configuration/sinks/clickhouse/#batch).
    ```yaml
    customConfig:
      sinks:
        clickhouse:
          type: clickhouse
          inputs: [dots_to_underscores]
          database: vector
          endpoint: "https://<host>:8443"
          table: vector_logs
          compression: gzip
          auth:
            password: <password>
            strategy: basic
            user: <username>
          batch:
            timeout_secs: 10
            max_events: 10000
            max_bytes: 10485760
          skip_unknown_fields: true
    ```

## Install the aggregator

Installs the collector as a deployment. Ensure you modify the [target ClickHouse cluster](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml#L314-L324) and [resources](https://github.com/ClickHouse/examples/blob/main/observability/logs/kubernetes/vector_to_vector/aggregator.yaml#L167-L173) to fit your environment.


```bash
helm install vector-aggregator vector/vector \
  --namespace vector \
  --create-namespace \
  --values aggregator.yaml

kubectl get pods -n=vector
NAME                  READY   STATUS    RESTARTS   AGE
vector-aggregator-0   1/1     Running   0          39s
```

## Agent Configuration

The [agent.yml](./agent.yml) provides a full sample agent configuration.

Vector agents communicate over the [Vector sink](https://vector.dev/docs/reference/configuration/sinks/vector/) to the aggregator instance using an equivalent [source](https://vector.dev/docs/reference/configuration/sources/vector/). Our key configuration:

  - Set the role to be "Agent"
    ```yaml
    role: "Agent"
    ```
  - Use the `customConfig` key to configure the [Kubernetes logs input](https://vector.dev/docs/reference/configuration/sources/kubernetes_logs/) and vector sink. This represents the actual Vector configuration file.
    ```yaml
    customConfig:
      data_dir: /vector-data-dir
      api:
        enabled: true
        address: 127.0.0.1:8686
        playground: false
      sources:
        kubernetes_logs:
          type: kubernetes_logs
      sinks:
        vector:
          type: vector
          inputs: [kubernetes_logs]
          address: vector-aggregator:6000   
    ```

## Install the Agent

Installs the collector as a daemonset. Ensure you modify the [resources]() to fit your environment.


```bash
helm install vector-agent vector/vector \
  --namespace vector \
  --create-namespace \
  --values agent.yaml

kubectl get pods -n=vector
NAME                  READY   STATUS    RESTARTS   AGE
vector-agent-2nxgv    1/1     Running   0          75s
vector-agent-4m2vj    1/1     Running   0          75s
vector-agent-6jdg4    1/1     Running   0          75s
vector-agent-74cbd    1/1     Running   0          75s
```
