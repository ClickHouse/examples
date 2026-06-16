# Read Avro (and Confluent-framed Avro) with clickhouse-local

Runnable companion to
[Read Avro from a schema registry with clickhouse-local](https://clickhouse.com/resources/engineering/read-avro-confluent).

Read a plain `.avro` file with one command, and see the exact `AvroConfluent`
command form for messages produced against a Confluent Schema Registry.

```bash
./generate.sh   # writes events.avro (8 rows) + events_large.avro (~62 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "SELECT * FROM file('events.avro')"
```

Covered in `run.sh`: schema-embedded read, `DESCRIBE`, group-by on the Avro
file, the plain-Avro vs Confluent-wire-format magic-byte difference, the
`AvroConfluent` + `format_avro_schema_registry_url` command form, and a
best-of-3 perf number on the 3M-row file.

Scope note: `clickhouse local` writes/reads plain Avro (the `.avro` Object
Container File) locally. The Confluent wire format is a registry-bound framing
emitted by Kafka producers; reading it end to end needs a **running** Schema
Registry, so step 6 shows the command form rather than faking registry output.
Step 5 proves the two framings are not interchangeable.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

Prefer Python? See the chDB version: `../chdb-read-avro`.
