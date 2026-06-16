#!/usr/bin/env bash
# Generate sample mysqldump (.sql) files locally with clickhouse local, so nothing
# large is committed to git. Writes into ./data/ (gitignored):
#   data/shop.sql        - small two-table dump (customers + orders), the worked example
#   data/events_large.sql - single-table dump, LARGE_ROWS rows (the perf number)
#
# These look exactly like real `mysqldump` output: header comments, DROP TABLE,
# CREATE TABLE, LOCK TABLES, multi-row INSERT ... VALUES, UNLOCK TABLES.
# We synthesise the INSERT VALUES tuples with clickhouse local, then wrap them in
# the surrounding DDL with a heredoc. No MySQL server is involved at any point.
# Idempotent: files are overwritten on re-run.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p data

SMALL_ROWS=${SMALL_ROWS:-3}
LARGE_ROWS=${LARGE_ROWS:-2000000}

# ---- small two-table dump: data/shop.sql -------------------------------------
echo "Generating data/shop.sql (customers + orders)..."

customers_values=$(clickhouse local -q "
SELECT '(' || toString(number + 1) || ','''
  || ['GB','US','DE'][(number % 3) + 1] || ''','''
  || toString(toDate('2026-01-01') + number) || ''')'
FROM numbers($SMALL_ROWS)
FORMAT TSVRaw" | paste -sd, -)

orders_values=$(clickhouse local -q "
SELECT '(' || toString(number + 1) || ','
  || toString((number % $SMALL_ROWS) + 1) || ','''
  || ['widget','gadget','gizmo'][(number % 3) + 1] || ''','
  || toString(round(((number % 40) + 5) + (number % 100) / 100.0, 2)) || ','
  || toString((number % 5) + 1) || ')'
FROM numbers(4)
FORMAT TSVRaw" | paste -sd, -)

cat > data/shop.sql <<EOF
-- MySQL dump 10.13  Distrib 8.0.36, for Linux (x86_64)
--
-- Host: localhost    Database: shop
-- ------------------------------------------------------
-- Server version	8.0.36

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
SET NAMES utf8mb4;

--
-- Table structure for table \`customers\`
--

DROP TABLE IF EXISTS \`customers\`;
CREATE TABLE \`customers\` (
  \`id\` int NOT NULL,
  \`country\` varchar(2) DEFAULT NULL,
  \`signup_date\` date DEFAULT NULL,
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table \`customers\`
--

LOCK TABLES \`customers\` WRITE;
INSERT INTO \`customers\` VALUES $customers_values;
UNLOCK TABLES;

--
-- Table structure for table \`orders\`
--

DROP TABLE IF EXISTS \`orders\`;
CREATE TABLE \`orders\` (
  \`id\` int NOT NULL,
  \`customer_id\` int DEFAULT NULL,
  \`product\` varchar(32) DEFAULT NULL,
  \`revenue\` decimal(10,2) DEFAULT NULL,
  \`quantity\` int DEFAULT NULL,
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

--
-- Dumping data for table \`orders\`
--

LOCK TABLES \`orders\` WRITE;
INSERT INTO \`orders\` VALUES $orders_values;
UNLOCK TABLES;
EOF

# ---- large single-table dump for the perf number: data/events_large.sql ------
echo "Generating data/events_large.sql ($LARGE_ROWS rows)..."

# Header + DDL first, then stream one big extended INSERT of all rows.
cat > data/events_large.sql <<EOF
-- MySQL dump 10.13  Distrib 8.0.36, for Linux (x86_64)
--
-- Host: localhost    Database: shop
-- Server version	8.0.36

DROP TABLE IF EXISTS \`events\`;
CREATE TABLE \`events\` (
  \`id\` int NOT NULL,
  \`country\` varchar(2) DEFAULT NULL,
  \`event_type\` varchar(16) DEFAULT NULL,
  \`revenue\` decimal(10,2) DEFAULT NULL,
  \`quantity\` int DEFAULT NULL,
  PRIMARY KEY (\`id\`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

LOCK TABLES \`events\` WRITE;
EOF

# One extended INSERT: "INSERT INTO `events` VALUES " followed by N comma-joined tuples.
{
  printf 'INSERT INTO `events` VALUES '
  clickhouse local -q "
  SELECT '(' || toString(number + 1) || ','''
    || ['GB','US','DE','FR','IN','AU','BR','JP','CA','NL'][(rand(2) % 10) + 1] || ''','''
    || ['click','view','purchase','refund'][(rand(3) % 4) + 1] || ''','
    || toString(round((rand(4) % 50000) / 100.0, 2)) || ','
    || toString((rand(5) % 5) + 1) || ')'
  FROM numbers($LARGE_ROWS)
  FORMAT TSVRaw" | paste -sd, -
  printf ';\nUNLOCK TABLES;\n'
} >> data/events_large.sql

echo
echo "Generated files:"
ls -la data
