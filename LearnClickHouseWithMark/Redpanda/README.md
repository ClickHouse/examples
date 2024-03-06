# Ingesting data from Redpanda into ClickHouse

Video: https://www.youtube.com/watch?v=1O27sis1nLE

Tools: [rpk](https://docs.redpanda.com/current/reference/rpk/), [kcat](https://github.com/edenhill/kcat)

Launch Redpanda

```bash
docker compose up
```

Create topic

```bash
rpk topic describe wiki_events -p
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
./clickhouse local -m --path wiki.chdb
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
CREATE TABLE wiki (
    dateTime DateTime64(3, 'UTC'),
    type String,
    title String,
    title_url String,
    id String,
    stream String,
    topic String,
    user String,
    bot Boolean, 
    server_name String,
    wiki String
) 
ENGINE = MergeTree 
ORDER BY dateTime;
```

Create MV

```sql
CREATE MATERIALIZED VIEW wiki_mv TO wiki AS 
SELECT toDateTime(timestamp) AS dateTime,
       type, title, title_url, 
       tupleElement(meta, 'id') AS id, 
       tupleElement(meta, 'stream') AS stream, 
       tupleElement(meta, 'topic') AS topic, 
       user, bot, server_name, wiki
FROM wikiQueue;
```

Query table

```sql
FROM wiki
SELECT user, bot, COUNT(*) AS updates
GROUP BY user, bot
ORDER BY updates DESC
LIMIT 10;
```

```sql
WITH users AS (
    SELECT user, COUNT(*) AS updates
    FROM wiki
    GROUP BY user
    ORDER BY updates DESC
)
SELECT
    user,
    updates,
    bar(updates, 0, (SELECT max(updates) FROM users), 30) AS plot
FROM users
LIMIT 10;
```