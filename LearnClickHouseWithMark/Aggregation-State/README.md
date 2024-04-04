# Aggregation States

Video: https://youtu.be/pryhI4F_zqQ

Tools: [rpk](https://docs.redpanda.com/current/reference/rpk/), [kcat](https://github.com/edenhill/kcat)

Launch Redpanda

```bash
docker compose up
```

Create topic

```bash
rpk topic create wiki_events -p5
```

Ingest Wiki changes data into Redpanda

```bash
curl -N https://stream.wikimedia.org/v2/stream/recentchange  |
awk '/^data: /{gsub(/^data: /, ""); print}' |
jq -cr --arg sep ø '[.meta.id, tostring] | join($sep)' |
kcat -P -b localhost:9092 -t wiki_events -Kø
```

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse -m --path wiki.chdb
```

Create a Kafka table engine

```sql
CREATE TABLE wikiQueue(
    id UInt32,
    type String,
    title String,
    title_url String,
    comment String,
    timestamp UInt64,
    user String,
    bot Boolean,
    server_url String,
    server_name String,
    wiki String,
    meta Tuple(uri String, id String, stream String, topic String, domain String)
)
ENGINE = Kafka('localhost:9092', 'wiki_events', 'consumer-group-wiki', 'JSONEachRow');
```

Create table

```sql
CREATE TABLE byMinute
(
    dateTime DateTime64 NOT NULL,
    users AggregateFunction(uniq, String),
    pages AggregateFunction(uniq, String)
)
ENGINE = AggregatingMergeTree() 
ORDER BY dateTime;
```

Create MV

```sql
CREATE MATERIALIZED VIEW byMinute_mv TO byMinute AS 
SELECT toStartOfMinute(toDateTime(timestamp)) AS dateTime,
       uniqState(user) as users,
       uniqState(title_url) as pages
FROM wikiQueue
WHERE title_url <> ''
GROUP BY dateTime;
```

Query table

```sql
select dateTime, uniqMerge(users)
FROM byMinute
GROUP BY dateTime
ORDER BY dateTime;
```

```sql
select toStartOfTenMinutes(dateTime) AS dateTime, uniqMerge(users)
FROM byMinute
GROUP BY dateTime
ORDER BY dateTime;
```
