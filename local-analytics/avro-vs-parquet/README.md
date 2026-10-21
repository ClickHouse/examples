# Avro vs Parquet locally

Compare reading two columns with reading all 20 from the same 500,000 events, stored as Avro and Parquet. This example shows how Parquet can skip unneeded columns while Avro reads through the records. It also checks that both formats return the same data.

Runnable companion to [Avro vs Parquet](https://clickhouse.com/resources/engineering/avro-vs-parquet).

## Install what you need

Install [Python 3](https://www.python.org/downloads/) and [Docker](https://docs.docker.com/get-started/get-docker/), then start Docker on your laptop or VM. You need Linux containers, cgroup v2, at least 2 CPUs and 3 GiB of memory available to Docker, and a [ClickHouse-compatible amd64 or arm64 CPU](https://clickhouse.com/docs/get-started/setup/self-managed/docker#compatibility).

The first build needs internet access. The container installs `clickhousectl` and the pinned ClickHouse version for you.

## Run it

Use Bash or a similar shell.

1. From the root of this repository, open the example folder.

   ```sh
   cd local-analytics/avro-vs-parquet
   ```

2. Create a fresh run ID and run the example.

   ```sh
   RUN_ID="laptop-$(date -u +%Y%m%d%H%M%S)"
   python3 reproduce.py all --id "$RUN_ID"
   ```

   It uses your current local Docker engine. Add `--context NAME` to choose another local context. Remote TCP and SSH endpoints are refused.

   The script sets up ClickHouse through `clickhousectl`, runs the comparison, validates the results, and stops its container. It keeps the output and stopped container for inspection. Use a new ID each time.

3. Read the verdict and comparison table.

   ```sh
   cat "artifacts/$RUN_ID/validation.json"
   cat "artifacts/$RUN_ID/results/summary-table.md"
   ```

## What to expect

The terminal ends with a JSON status of `completed` when checks pass, and `validation.json` reports `"status": "pass"`. A `review_required` result (exit code 2) needs inspection; `failed` (exit code 1) means the run could not complete.

The table has four rows covering both formats with two or all columns. It reports elapsed time, memory use, and file bytes read. Results and logs stay in `artifacts/<run-id>/`.

This is a small local illustration, and timings vary by machine. The [recorded run](reference/cli-26.8.32.16/README.md) includes a ready-made comparison and its reference environment details.

## Prompt for your agent

```text
Run local-analytics/avro-vs-parquet using its README and reproduce.py all with a new run ID. Use this machine's local Docker engine and the existing clickhousectl setup. Check validation.json and results/summary-table.md, then summarize the verdict and the two-column versus all-column results for each format. Report any failures or review_required reasons without changing the benchmark or reference results.
```
