# Continuous data transformation example

We use the [UK property prices dataset](https://clickhouse.com/docs/en/getting-started/example-datasets/uk-price-paid) where we want to pre-aggregate the average property price per city.

## Elasticsearch transforms

The following diagram shows how three documents are inserted (e.g. via [bulk api](https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html)) into an initially empty index for storing the raw data. This index is configured to be the source index for continuous transforms into a destination index storing the pre-calculated average price per city:
![](es_01.png)
① The initial transform checkpoint occurred while the source index was empty. ② A bulk insert with three documents ③ creates a corresponding source index segment. ④ After the check interval time has elapsed, a new checkpoint is created, ⑤ changes in the source index are detected, ⑥ aggregate values are calculated, and ⑦ a corresponding destination index segment is created.

The following diagram visualizes an additional bulk insert into the source index:
![](es_02.png)
① A bulk insert with two documents ② creates a new source index segment. ③ After the check interval time has elapsed, a checkpoint is created, ④ changes in the source index are detected, ⑤ aggregate values are re-calculated (from scratch), ⑥ the previous aggregate values for the changed bucket are marked as deleted, and ⑦ a corresponding destination index segment is created.

For completeness, we also sketch background segment merges:
![](es_03.png)

## ClickHouse materialized views
![](ch_01.png)
① A bulk insert with three rows ② creates a corresponding source table data part. ③ In parallel, the block of newly inserted rows is transformed into partial aggregation states (e.g., a `sum` and a `count` for `avg()`) by the materialized view’s [transformation query](https://www.youtube.com/watch?v=QDAJTKZT8y4), and ④ a corresponding ⑤ data part is inserted into the materialized view’s target table. Finally, ⑥ the insert into the source table is acknowledged.

We visualize another bulk insert into the source table:
![](ch_02.png)
① A bulk insert with two rows ② creates a source table data part. ③ In parallel, the block of newly inserted rows is transformed into partial `avg` aggregation states,  ④ a corresponding ⑤ data part is inserted into the materialized view’s target table, and ⑥ the insert into the source table is acknowledged.

Background part merges continue the incremental data transformation:
![](ch_03.png)
The diagram above shows how the partial aggregation states for `avg` are combined during a background part merge.

Users can consolidate the partial aggregation states in the materialized view’s target table using `avg()` with the -[Merge](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/combinators#-merge) extension to obtain the final result.

Note that all [over 90 aggregate functions](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference), including their combination with aggregate function [combinators](https://www.youtube.com/watch?v=7ApwD0cfAFI), support partial aggregation states. To give one additional example, the partial state for [uniqExact](https://clickhouse.com/docs/en/sql-reference/aggregate-functions/reference/uniqexact) is a hashtable containing unique value hashes.