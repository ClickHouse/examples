# Project Title
Change Data Capture (CDC) with PostgreSQL and ClickHouse.

## Getting Started
This project sets up a real-time data pipeline utilizing Change Data Capture (CDC) to stream changes from a PostgreSQL database to a ClickHouse database through Apache Kafka. Using Debezium to capture and stream database changes, and Kafka Connect to sink the data into ClickHouse, this pipeline allows for efficient and reliable data synchronization and analytics.

## Prerequisites
* Docker
* Docker Compose
* Git

## Services
The project consists of the following services:

### Required:
* Postgres
* ClickHouse
* Kafka
* Zookeeper
* Kafka-Connect

### Optional:
* Kowl (Apache Kafka UI)
* Adminer (PostgreSQL UI)


## Usage

### 1. Clone repository and start docker containers

```shell
git clone https://github.com/leartbeqiraj1/cdc-postgresql-clickhouse.git
cd cdc-postgresql-clickhouse/
docker-compose up -d
```

### 2. Check if all components are up and running

```shell
docker compose ps
NAME                SERVICE                    STATUS                   PORTS
postgres            postgres                   running             0.0.0.0:5432->5432/tcp, :::5432->5432/tcp
clickhouse-server   clickhouse                 running             9000/tcp, 0.0.0.0:8123->8123/tcp, :::8123->8123/tcp, 9009/tcp
kafka               kafka                      running             0.0.0.0:9092->9092/tcp, :::9092->9092/tcp, 0.0.0.0:9101->9101/tcp, :::9101->9101/tcp
zookeeper           zookeeper                  running             2888/tcp, 0.0.0.0:2181->2181/tcp, :::2181->2181/tcp, 3888/tcp
kafka-connect       kafka-connect              running (healthy)   0.0.0.0:8083->8083/tcp, :::8083->8083/tcp, 9092/tcp
kowl                kowl                       running             0.0.0.0:8080->8080/tcp, :::8080->8080/tcp
adminer             adminer                    running             0.0.0.0:7775->8080/tcp, :::7775->8080/tcp

```
### 3. Verify PostgreSQL data
Login to [Postgres UI](http://localhost:7775/?pgsql=postgres&username=postgres&db=demo_db&ns=public) and verify that there are **demo_table1** and **demo_table2** with 2 rows inserted each. Username and Password are both "**postgres**"

### 4. Verify connection between Debezium Connector and Kafka
Open [Kowl topics](http://localhost:8080/topics) and verify that Debezium Connector has sucessfully published PostgreSQL data to a Kafka topic. There should be a topic named **demo_data** and it should contain 4 messages inside (all 4 rows from PostgreSQL tables).

### 5. Verify connection between ClickHouseSink Connector and Kafka
Navigate to [Consumer Groups](http://localhost:8080/groups) to verify that ClickHouseSink Connector is a stable consumer, and it has successfully subscribed to the **demo_data** topic.

### 6. Verify ClickHouse data
Open [ClickHouse UI](http://localhost:8123/play) and verify that PostgreSQL data are already pushed to ClickHouse from ClickHouseSink Connector by executing below:
```text
SELECT * FROM demo_table1_mv FINAL;
SELECT * FROM demo_table2_mv FINAL;
```

## Testing

### 1. Make new Inserts or Updates in existing PostgreSQL tables
Go to [Postgres UI](http://localhost:7775/?pgsql=postgres&username=postgres&db=demo_db&ns=public&table=demo_table2) and insert or update existing rows.

### 2. Go Back to ClickHouse
Open [ClickHouse UI](http://localhost:8123/play) again and you should see your changes already applied.

## Conclusion 
Inspired by a blog post on ClickHouse's official website [(ClickHouse PostgreSQL Change Data Capture (CDC) - Part 1)](https://clickhouse.com/blog/clickhouse-postgresql-change-data-capture-cdc-part-1), I decided to replicate the setup. Due to the absence of extensive blogs, posts, or documentation on how to set up this particular pipeline locally, I was motivated to create this documentation. Through this effort, I hope to contribute to the community's shared knowledge and facilitate a smoother setup process for this CDC pipeline.

## Contributed by Leart Beqiraj
