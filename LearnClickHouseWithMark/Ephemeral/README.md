# The Ephemeral Modifier

Video: https://www.youtube.com/watch?v=vaY5LQ7a_Dk

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Describe log file:

```sql
DESCRIBE file('small_logs.log')
SETTINGS describe_compact_output=1,
         schema_inference_make_columns_nullable=0;
```

Show one row:

```sql
SELECT *
FROM file('small_logs.log')
LIMIT 1
FORMAT Vertical
SETTINGS schema_inference_make_columns_nullable=0;
```

Parse log line function:

```sql
CREATE OR REPLACE FUNCTION parseLogLine AS (line) -> (
   extractAllGroups(line,
    '(\\d+\\.\\d+\\.\\d+\\.\\d+)' ||
    ' - - ' ||
    '\\[(\\d+/\\w+/\\d+):(\\d+:\\d+:\\d+ [+-]\\d+)\\] ' ||
    '"(\\w+) (.*?) HTTP/\\d\\.\\d" ' ||
    '(\\d+) (\\d+) "(.*?)" "(.*?)"'
  )[1]
);
```

Use the function:

```sql
SELECT *, parseLogLine(c1) AS parts
FROM file('logs.log')
LIMIT 1
FORMAT Vertical
SETTINGS schema_inference_make_columns_nullable=0;
```

Create logs table:

```sql
CREATE TABLE logs (
    line String EPHEMERAL,
    parts Array(String) EPHEMERAL parseLogLine(line),
    ip String MATERIALIZED parts[1],
    method LowCardinality(String) MATERIALIZED parts[4],
    url String MATERIALIZED parts[5],
    browser String MATERIALIZED parts[-1],
    statusCode UInt16 MATERIALIZED toUInt16OrDefault(parts[6]),
    date DateTime MATERIALIZED assumeNotNull(parseDateTimeBestEffortOrNull(
        replaceRegexpAll(parts[2], '/', ' ') || ' ' || parts[3]
    ))
)
ORDER BY url;
```

Import data:

```sql
INSERT INTO logs (line)
SELECT * 
FROM file('small_logs.log');
```

Query the data:

```sql
SELECT statusCode, count()
FROM logs
GROUP BY ALL
ORDER BY count() DESC
LIMIT 10;   
```