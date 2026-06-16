# Parse a log file with regex in SQL using clickhouse-local

Runnable companion to
[How to parse a log file with regex in SQL](https://clickhouse.com/resources/engineering/parse-log-with-regex-sql).

Turn unstructured access-log lines into typed columns with the `Regexp` input
format: one capture group per column, mapped onto an explicit schema.

```bash
./generate.sh   # writes access.log (20 lines), access.log.gz, access_large.log (~163 MB)
./run.sh        # runs every command from the article; compare with expected_output.txt
```

The one-liner:

```bash
clickhouse local -q "
SELECT * FROM file('access.log', Regexp,
  'ip String, ts String, method String, path String, status UInt16, size UInt32, rt Float64')
SETTINGS format_regexp = '^(\S+) - - \[([^\]]+)\] \"(\S+) (\S+) [^\"]+\" (\d+) (\d+) (\S+)',
         format_regexp_escaping_rule = 'Raw'"
```

Covered in `run.sh`: the `Regexp` format with capture-group-to-column mapping,
parsing the log timestamp into a real `DateTime`, an error-rate-by-path
aggregation, transparent `.log.gz` reads, and a best-of-3 perf number on the
2M-line file.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.
