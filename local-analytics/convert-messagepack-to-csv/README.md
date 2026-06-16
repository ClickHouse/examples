# Convert MessagePack to CSV with clickhouse-local

Runnable companion to
[How to convert MessagePack to CSV](https://clickhouse.com/resources/engineering/convert-messagepack-to-csv).

No server, no upload. One binary reads a `.msgpack` file and writes `.csv`, streaming files larger than RAM.

```bash
./generate.sh   # writes data/orders.msgpack (20 rows), data/orders_large.msgpack (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (MsgPack carries no schema, so you supply the structure):

```bash
clickhouse local -q "
SELECT * FROM file('orders.msgpack', MsgPack,
  'order_date Date, order_id UInt64, country String, product String, revenue Float64, quantity UInt8')
INTO OUTFILE 'orders.csv' TRUNCATE FORMAT CSVWithNames"
```

Covered in `run.sh`: the explicit-structure gotcha, the one-line conversion,
a round-trip query against the CSV, and a best-of-3 conversion throughput
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` / `run.ipynb` do the same conversion in-process with chDB (`pip install chdb`).
