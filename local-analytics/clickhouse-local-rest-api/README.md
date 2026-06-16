# Query a REST API with SQL using clickhouse-local

Runnable companion to
[How to query a REST API with SQL](https://clickhouse.com/resources/engineering/query-rest-api-with-sql).

`url()` is callable inside a `SELECT`, so you fetch a JSON (or CSV) HTTP endpoint
and filter, aggregate and join the response in one statement — no download step.

```bash
./generate.sh   # writes data/feed.json (200 rows) + data/feed_large.json (~133 MB)
./run.sh        # serves ./data locally, runs every command from the article, then stops the server
```

The one-liner (against any JSON endpoint):

```bash
clickhouse local -q "SELECT * FROM url('https://api.example.com/events', JSONEachRow) LIMIT 5"
```

`run.sh` proves it with zero external dependency: it starts `python3 -m http.server`
on `127.0.0.1:8731`, points `url()` at `http://127.0.0.1:8731/feed.json`, captures
the real output, and shuts the server down. Override the port with `PORT=...`.

Covered in `run.sh`: fetch + `LIMIT`, `DESCRIBE` on the response, group-by on the
response, joining the live response to a local lookup file, and a best-of-3 perf
number on a 1.5M-row JSON response over HTTP.

Requirements: `clickhouse` (install with `clickhousectl`: `curl https://clickhouse.com/cli | sh`
then `clickhousectl local use latest`), invoked as `clickhouse local`; `python3` and `curl`
(for the throwaway local server in `run.sh`).
