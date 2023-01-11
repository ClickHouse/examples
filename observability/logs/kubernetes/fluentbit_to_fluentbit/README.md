# Log collection with the FluentBit

Collect logs and store in ClickHouse using FluentBit.

Installs an FluentBit agent as a deployment (for an aggregator) and as a deamonset to collect logs from each node.


## Install helm chart

```bash
helm repo add fluent https://fluent.github.io/helm-charts
```

## Create the database and table

```sql
CREATE database fluent

CREATE TABLE fluent.fluent_logs
(
    `timestamp` DateTime64(9),
    `log` String,
    `kubernetes` Map(LowCardinality(String), String),
    `host` LowCardinality(String),
    `pod_name` LowCardinality(String),
    `stream` LowCardinality(String),
    `labels` Map(LowCardinality(String), String),
    `annotations` Map(LowCardinality(String), String)
)
ENGINE = MergeTree
ORDER BY (host, pod_name, timestamp)
```

## Download files

Download the agent and aggregator value files for the helm chart.

```
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/fluentbit_to_fluentbit/agent.yaml
wget https://raw.githubusercontent.com/ClickHouse/examples/main/observability/logs/kubernetes/fluentbit_to_fluentbit/aggregator.yaml
```

## Aggegator Configuration

The [aggregator.yml](./aggregator.yml) provides a full sample aggregator configuration, requiring only minor changes for most cases.


**Important Note on asynchronous inserts**

We recommend the use of asynchronous inserts with ClickHouse and Fluent Bit to address the lack of batching in the ClickHouse output. This avoids [common problems with too many small writes](https://clickhouse.com/blog/common-getting-started-issues-with-clickhouse) and is the [recommended approach](https://clickhouse.com/docs/en/optimize/asynchronous-inserts/) for the write profile produced by Fluent Bit.

Note the following:

- For the aggregator, the property `kind` is set to `Deployment` 
    ```yaml
    kind: Deployment
    ```
- We utilize a different [Lua script](./aggregator.yaml#L291-L309) to move certain fields to the root out of the Kubernetes key, allowing these to be used in the primary key. We also move annotations and labels to the root. This allows them to be declared as a Map type and excluded from [Compression](#compression) statistics later as they are very sparse. Furthermore, this means our `kubernetes` column has only a single later of nesting and can be declared as a Map also.
- An aggregator output specifies the use of [async_inserts](https://clickhouse.com/docs/en/cloud/bestpractices/asynchronous-inserts/) in the `URI`. We combine this with a [flush interval of 5 seconds](./aggregator.yaml#L264). In our example, we do not specify `wait_for_async_insert=1` but this can be appended as required.
- The aggregator and agent instances communicate over the [`forward`](https://docs.fluentbit.io/manual/pipeline/outputs/forward) protocol. This requires the aggregator to have a `forward` input as shown below:

    ```yaml
    inputs: |
        [INPUT]
            Name              forward
            Listen            0.0.0.0
            Port              24224
            Buffer_Chunk_Size 10M
            Buffer_Max_Size   500M
    ```

- The above requires the aggregator to also have ports explicitly exposed, so a Kubernetes service is created.
    ```yaml
    extraPorts:
    - port: 24224
    containerPort: 24224
    protocol: TCP
    name: tcp
    ```

**Important**

Ensure you modify the [target ClickHouse cluster](./aggregator.yaml#L346-L353) and [resources](./aggregator.yaml#L161-L167) to fit your environment.


## Install the aggregator


```bash
helm install fluent-aggregator fluent/fluent-bit --values aggregator.yaml --namespace fluent --create-namespace

kubectl get pods -n=fluent
NAME                                            READY   STATUS    RESTARTS   AGE
fluent-aggregator-fluent-bit-5d89dd49dd-hsc5d   1/1     Running   0          16m
```

## Agent Configuration


    ```yaml
    outputs: |
        [OUTPUT]
            Name forward
            Match *
            Host fluent-aggregator-fluent-bit
            Port 24224
    ```

## Install the Agent

Installs the collector as a daemonset. Ensure you modify the [resources]() to fit your environment.

```bash
helm install fluent-agent fluent/fluent-bit --values agent.yaml --namespace fluent

kubectl get pods -n=fluent
NAME                                            READY   STATUS    RESTARTS   AGE
fluent-agent-fluent-bit-4dp7j                   1/1     Running   0          87s
fluent-agent-fluent-bit-68zg4                   1/1     Running   0          86s
...
fluent-aggregator-fluent-bit-5d89dd49dd-hsc5d   1/1     Running   0          16m
```

## Confirm logs are arriving


```sql
SELECT count()
FROM fluent.fluent_logs

┌─count()─┐
│ 4695341 │
└─────────┘
```