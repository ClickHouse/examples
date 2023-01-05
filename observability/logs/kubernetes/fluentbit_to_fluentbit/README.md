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


## Install the aggregator

Installs the collector as a deployment. Ensure you modify the [target ClickHouse cluster]() and [resources]() to fit your environment.

```bash
helm install fluent-aggregator fluent/fluent-bit --values aggregator.yaml --namespace fluent --create-namespace
```

## Install the Agent

Installs the collector as a daemonset. Ensure you modify the [resources]() to fit your environment.

```bash
helm install fluent-agent fluent/fluent-bit --values agent.yaml --namespace fluent
```
