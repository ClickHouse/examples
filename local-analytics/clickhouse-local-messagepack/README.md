# Read a MessagePack file with clickhouse-local

Runnable companion to
[How to read a MessagePack file](https://clickhouse.com/resources/engineering/read-messagepack-file).

MsgPack carries no embedded schema, so reads require an explicit structure.

```bash
./generate.sh   # writes events.msgpack (20 rows), events.msgpack.gz, events_large.msgpack (3M rows)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (note the format + schema as the 2nd and 3rd args to `file()`):

```bash
clickhouse local -q "SELECT * FROM file('events.msgpack', MsgPack,
  'id UInt64, country String, event_type String, revenue Float64, quantity UInt8') LIMIT 5"
```

Covered in `run.sh`: why a bare read fails, supplying the explicit structure,
group-by on the file, transparent `.msgpack.gz` reads, and a best-of-3 perf
number on the 3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-read-messagepack`.
