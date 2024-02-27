# Converting JSON to Parquet

Video: https://www.youtube.com/watch?v=ueDyFl4eAgg

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse local -m
```

Compact describe output

```sql
SET describe_compact_output=1;
```

```sql
DESCRIBE 'movies.json';
```

Export to Parquet

```sql
FROM 'movies.json' 
SELECT *
INTO OUTFILE 'data/movies.parquet' 
FORMAT Parquet;
```

Export to partitioned Parquet files


```sql
INSERT INTO FUNCTION 
file('data/movies_lang_{_partition_id}.parquet', 'Parquet') 
PARTITION BY original_language
select *
from file('movies.json');
```

```sql
INSERT INTO FUNCTION 
file('data/movies_vote_{_partition_id}.parquet', 'Parquet') 
PARTITION BY multiIf(
    vote_average = 10,
    '9-10',
    vote_average = floor(vote_average),
    toString(vote_average) || '-' || toString(vote_average +1),
    toString(floor(vote_average)) || '-' || toString(ceil(vote_average))
)
select *
from file('movies.json');
```

Query Parquet files

```sql
FROM 'data/movies_vote_*.parquet'
SELECT _file, count(*), 
       min(vote_average) AS min, 
       max(vote_average) AS max, 
       round(avg(vote_average), 2) AS avg
GROUP BY ALL 
ORDER BY count(*) DESC
```