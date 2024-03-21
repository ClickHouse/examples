# Window Functions - Aggregate

Video: https://youtu.be/Yku9mmBYm_4

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

Max salary

```sql
SELECT
    player, team, position AS pos,
    salary,
    MAX(salary) OVER (PARTITION BY position) AS max,
    salary - max AS diff
FROM salaries
ORDER BY diff
LIMIT 10;
```

Average salaries

```sql
SELECT
    player, team, salary,
    round(avg(salary) OVER (PARTITION BY team), 0) AS avg,
    round(salary - avg, 2) AS avgDiff,
    round(median(salary) OVER (PARTITION BY team), 0) AS med,
    round(salary - med, 2) AS medDiff
FROM salaries
ORDER BY avgDiff
LIMIT 10;
```

Window clause

```sql
SELECT
    player, team, salary,
    round(avg(salary) OVER teamPartition, 0) AS avg,
    round(salary - avg, 2) AS avgDiff,
    round(median(salary) OVER teamPartition, 0) AS med,
    round(salary - med, 2) AS medDiff
FROM salaries
WINDOW teamPartition AS (PARTITION BY team)
ORDER BY avgDiff
LIMIT 10;
```

Salaries by team/position

```sql
WITH salaryDist AS(
    SELECT
        player, team, position, salary,
        groupArray(salary) OVER (PARTITION BY team, position) AS distribution
    FROM salaries
    ORDER BY team, position, salary DESC
)
FROM salaryDist
SELECT * EXCEPT(team) REPLACE(arraySort(distribution) AS distribution)
WHERE team = 'Arsenal' AND position = 'M'
FORMAT Vertical;
```