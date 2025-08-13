# PostgreSQL update benchmarks

This directory contains scripts to run the update benchmarks for PostgreSQL.

## Purpose 

Postgres is the most popular OLTP database in the world. It's fair to assume that its UPDATE performance constitutes an acceptable baseline for what developers expect from a database. Thus, we want to know how ClickHouse's UPDATE performance compares to Postgres.

There are several reasons why this is not a perfect benchmark/comparison, such as Postgres having full transactions for every update, which ClickHouse does not.

The goal of the comparison is simply to find out, "Is ClickHouse UPDATE performance competitive with Postgres?"

## Setup

The benchmark was originally run on an AWS m6i.8xlarge EC2 instance (32 cores, 128 GB RAM) with a gp3 EBS volume (16k IOPS, 1000 MiB/s max throughput) running Ubuntu 24.04 LTS. The default version of Postgres at this time was 17.5.

The `benchmark.sh` script will perform all necessary steps:
1. Install Postgres
2, Configure some best practise optimisations
3. Download and extract the test dataset (100M lineitem table)
4. Create the database and load the data
5. Create a reusable snapshot of the data
6. Run the single row update benchmark
7. Run the bulk update benchmark

Results are exported into `single_row_results.txt` and `bulk_results.txt`.


# Results

## Single-row updates

### Update Performance
| Query | Update Time (ms) |
|-------|------------------|
| 1     | 64.442          |
| 2     | 59.599          |
| 3     | 59.225          |
| 4     | 53.678          |
| 5     | 61.190          |
| 6     | 60.926          |
| 7     | 63.289          |
| 8     | 60.338          |
| 9     | 61.748          |
| 10    | 63.754          |

### Analytical Query Performance
| Query | Pre-Vacuum (ms) | Post-Vacuum (ms) |
|-------|-----------------|------------------|
| 1     | 97,135.221      | 97,150.972      |
| 2     | 87,112.859      | 87,089.960      |
| 3     | 87,105.641      | 87,070.256      |
| 4     | 87,061.198      | 87,042.769      |
| 5     | 86,458.939      | 86,442.421      |
| 6     | 87,072.981      | 87,056.657      |
| 7     | 87,157.190      | 87,128.116      |
| 8     | 87,107.230      | 87,090.760      |
| 9     | 96,318.914      | 95,555.374      |
| 10    | 89,681.496      | 89,679.810      |

## Bulk updates

### Update Performance
| Query | Update Time (ms) | Rows Affected |
|-------|------------------|---------------|
| 1     | 391,691.590     | 4,902         |
| 2     | 390,967.884     | 5,019         |
| 3     | 381,330.548     | 2,487         |
| 4     | 387,405.100     | 262           |
| 5     | 643.928         | 6             |
| 6     | 391,792.495     | 5,111         |
| 7     | 392,522.278     | 4,840         |
| 8     | 397,804.831     | 215,148       |
| 9     | 382,364.561     | 119           |
| 10    | 390,966.980     | 4,925         |

### Analytical Query Performance
| Query | Pre-Vacuum (ms) | Post-Vacuum (ms) |
|-------|-----------------|------------------|
| 1     | 97,847.851      | 97,736.590      |
| 2     | 87,138.937      | 87,105.590      |
| 3     | 87,091.495      | 87,020.673      |
| 4     | 87,060.508      | 87,045.084      |
| 5     | 86,460.661      | 86,444.674      |
| 6     | 87,099.302      | 87,069.617      |
| 7     | 87,188.945      | 87,145.000      |
| 8     | 87,091.680      | 87,073.270      |
| 9     | 95,204.458      | 95,809.857      |
| 10    | 89,839.039      | 89,759.975      |
