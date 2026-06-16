# Convert MsgPack to JSON with clickhouse-local

Runnable companion to
[How to convert MsgPack to JSON](https://clickhouse.com/resources/engineering/convert-messagepack-to-json).

Convert a MessagePack file to JSON with one command — no server, no upload.

```bash
./generate.sh   # writes events.msgpack (20 rows) and events_large.msgpack (~93 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner (MsgPack has no embedded schema, so the read needs an explicit structure):

```bash
clickhouse local -q "SELECT * FROM file('events.msgpack', MsgPack,
  'event_id UInt64, ts DateTime, event_type String, country String, amount Float64')
  INTO OUTFILE 'events.jsonl' TRUNCATE FORMAT JSONEachRow"
```

Covered in `run.sh`: why a structureless read fails, MsgPack -> NDJSON, MsgPack ->
single-array JSON, filtering during conversion, and a best-of-3 perf number on the
3M-row file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? `run.py` and `run.ipynb` do the same conversion with chDB
(`pip install chdb`).
