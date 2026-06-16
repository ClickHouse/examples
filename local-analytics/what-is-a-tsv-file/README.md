# What is a TSV file?

Runnable companion to the article
[What is a TSV file?](https://clickhouse.com/resources/engineering/what-is-a-tsv-file).

Generates a small tab-separated file (with a header) plus a CSV that needs quoting,
then uses `clickhouse local` to infer the TSV schema, query it in place, and show
why the tab delimiter avoids the quoting/escaping that CSV needs.

## Run it

```bash
./generate.sh   # writes data/events.tsv (TSVWithNames) + data/events.csv
./run.sh        # describes, queries, and contrasts TSV vs CSV
```

Override the row count: `ROWS=100 ./generate.sh`.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh` then `clickhousectl local use latest`), invoked as `clickhouse local`.

## What's in the files

- `data/events.tsv` — `id`, `country`, `event_type`, `revenue`, tab-separated, with a header row (`TSVWithNames`).
- `data/events.csv` — same shape but with a `label` column that contains a comma and a quote, so CSV has to wrap the field in quotes and double the inner quote. The tab delimiter never appears in the TSV data, so the TSV needs no quoting.

## Notes on reproducibility

Structure (columns, types, the CSV quoting) is deterministic. The `revenue` column
uses `randUniform`, so the `sum(revenue)` figures vary slightly run-to-run;
`expected_output.txt` is a real capture from one run.
