#!/usr/bin/env python3
# chDB equivalent of the MsgPack -> CSV conversion. Same SQL, in-process in Python.
# Run ./generate.sh first to create ./data/orders.msgpack.
import os
import chdb

os.chdir(os.path.join(os.path.dirname(__file__), "data"))

# MsgPack read needs an explicit structure, exactly like the CLI.
# Write the result straight to a CSV file with INTO OUTFILE.
chdb.query("""
SELECT * FROM file('orders.msgpack', MsgPack,
  'order_date Date, order_id UInt64, country String, product String, revenue Float64, quantity UInt8')
INTO OUTFILE 'orders_chdb.csv' TRUNCATE FORMAT CSVWithNames
""")

# Confirm the round-trip by reading the CSV back into a DataFrame.
df = chdb.query("""
SELECT country, count() AS orders, round(sum(revenue), 2) AS revenue
FROM file('orders_chdb.csv')
GROUP BY country
ORDER BY revenue DESC
""", "DataFrame")
print(df)
