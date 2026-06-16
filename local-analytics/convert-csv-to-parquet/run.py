#!/usr/bin/env python3
"""chDB equivalent of the CSV -> Parquet conversion shown in the article.
Same ClickHouse SQL, in-process in Python, no server. Run ./generate.sh first.
"""
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# Convert orders.csv -> orders_chdb.parquet, picking zstd compression.
chdb.query("""
SELECT * FROM file('orders.csv')
INTO OUTFILE 'orders_chdb.parquet' TRUNCATE FORMAT Parquet
SETTINGS output_format_parquet_compression_method='zstd'
""")

# Verify: read the Parquet back and check the types carried over.
print(chdb.query("DESCRIBE file('orders_chdb.parquet')", "CSV"))

# The file is queryable directly, columnar and typed.
print(chdb.query("""
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('orders_chdb.parquet')
GROUP BY country ORDER BY revenue DESC
""", "CSV"))
