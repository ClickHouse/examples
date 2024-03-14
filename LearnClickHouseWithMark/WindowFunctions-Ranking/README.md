# Window Functions - Ranking

Video: https://www.youtube.com/watch?v=nnvtLLFy8fc

Install ClickHouse

```bash
curl https://clickhouse.com/ | sh
```

Launch ClickHouse

```bash
./clickhouse -m
```

Import settings

```sql
SET schema_inference_make_columns_nullable=0,
    describe_compact_output=1;
```

Ingest salaries

```sql
CREATE OR REPLACE VIEW salaries AS 
FROM file('data/salaries.csv')
SELECT * EXCEPT (weeklySalary), weeklySalary AS salary;
```

Row numbers

```sql
FROM salaries
SELECT *,
       row_number() OVER () AS rowNum
LIMIT 10;
```


Row number/Rank/Dense Rank

```sql
FROM salaries
SELECT *,
       row_number() OVER () AS rowNum,
       rank() OVER (ORDER BY salary DESC) AS rank,
       dense_rank() OVER (ORDER BY salary DESC) AS denseRank
LIMIT 10;
```

Rank on different partitions

```sql
FROM salaries
SELECT *,
       rank() OVER (ORDER BY salary DESC) AS rank,
       rank() OVER (PARTITION BY team ORDER BY salary DESC) AS teamRank,
       rank() OVER (PARTITION BY position ORDER BY salary DESC) AS posRank
ORDER BY salary DESC
LIMIT 10;
```

Filter rankings

```sql
WITH windowedSalaries AS
    (
        SELECT
            *,
            rank() OVER (ORDER BY salary DESC) AS rank,
            rank() OVER (PARTITION BY team ORDER BY salary DESC) AS teamRank,
            rank() OVER (PARTITION BY position ORDER BY salary DESC) AS posRank
        FROM salaries
        ORDER BY salary DESC
    )
SELECT
    player,
    position,
    salary,
    bar(salary, 0, (
        SELECT max(salary)
        FROM windowedSalaries
        LIMIT 1
    ), 10) AS plot,
    teamRank,
    posRank,
    rank
FROM windowedSalaries
WHERE team LIKE '%Claireberg Vikings%'
LIMIT 15;
```