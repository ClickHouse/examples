#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# collect_metrics.py — Stage 2: Resolve metrics from system.query.history
#
# This script reads the statement_ids produced by run_bench.py (runs_<machine>.json),
# polls system.query.history for each one, and collects detailed per-run metrics
# such as total_duration_ms, from_result_cache, and read_files.
#
# Why this is a separate stage:
# - Query history updates asynchronously in Databricks, often lagging 4–10 minutes
#   behind execution.
# - Decoupling execution (run_bench.py) from metric collection allows us to:
#     • start polling only after all queries have finished
#     • batch-resolve metrics efficiently in one pass
#     • retry metric collection without re-running queries
#
# Output: metrics_<machine>.json — one record per query run with Databricks metrics.
# -----------------------------------------------------------------------------

import os
import time
import json
import argparse
from databricks import sql


def main():
    parser = argparse.ArgumentParser(
        description="Collect Databricks metrics for benchmark runs"
    )
    parser.add_argument(
        "--machine",
        required=True,
        help='Machine name (e.g. "2X-Small", "2X-Large", etc.)',
    )
    parser.add_argument(
        "--input",
        help="Path to runs JSON (default: runs_<machine>.json)",
    )
    parser.add_argument(
        "--output",
        help="Path to metrics JSON (default: metrics_<machine>.json)",
    )
    parser.add_argument(
        "--max-wait-sec",
        type=int,
        default=900,
        help="Max seconds to wait per query in history (default: 900 = 15min)",
    )
    parser.add_argument(
        "--poll-interval-sec",
        type=int,
        default=10,
        help="Polling interval in seconds (default: 10)",
    )

    args = parser.parse_args()
    MACHINE = args.machine
    INPUT_FILE = args.input or f"runs_{MACHINE}.json"
    OUTPUT_JSON = args.output or f"metrics_{MACHINE}.json"
    MAX_WAIT_SEC = args.max_wait_sec
    POLL_INTERVAL_SEC = args.poll_interval_sec

    HOST = os.environ["DATABRICKS_SERVER_HOSTNAME"]
    HTTP_PATH = os.environ["DATABRICKS_HTTP_PATH"]
    TOKEN = os.environ["DATABRICKS_TOKEN"]

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        runs = json.load(f)

    print(f"Loaded {len(runs)} runs from {INPUT_FILE}")
    print(f"Machine: {MACHINE}")
    print(f"Metrics output: {OUTPUT_JSON}")

    results = []

    with sql.connect(
        server_hostname=HOST,
        http_path=HTTP_PATH,
        access_token=TOKEN,
    ) as conn:
        for item in runs:
            q_idx = item["query_index"]
            r_idx = item["run_index"]
            statement_id = item["statement_id"]

            print(f"\n[Q{q_idx} run {r_idx}] Collecting metrics for {statement_id}")

            metrics_sql = f"""
            SELECT
              total_duration_ms,
              waiting_for_compute_duration_ms,
              from_result_cache,
              read_partitions,
              pruned_files,
              read_files,
              statement_text,
              execution_status,
              error_message
            FROM system.query.history
            WHERE statement_id = '{statement_id}'
            """

            row = None
            attempts = MAX_WAIT_SEC // POLL_INTERVAL_SEC

            for attempt in range(attempts):
                with conn.cursor() as cur:
                    cur.execute(metrics_sql)
                    row = cur.fetchone()

                if row:
                    break

                print(
                    f"  ⏳ not visible yet (checked {attempt + 1}/{attempts}), "
                    f"waiting {POLL_INTERVAL_SEC}s..."
                )
                time.sleep(POLL_INTERVAL_SEC)

            if not row:
                print(
                    f"  ⚠️ no entry in system.query.history for {statement_id} "
                    f"after {MAX_WAIT_SEC}s – writing NOT_FOUND record."
                )
                record = {
                    "query_index": q_idx,
                    "run_index": r_idx,
                    "statement_id": statement_id,
                    "original_query": item["original_query"],
                    "rewritten_query": item["rewritten_query"],
                    "table_name": item["table_name"],
                    "machine": item["machine"],
                    "total_duration_ms": None,
                    "waiting_for_compute_duration_ms": None,
                    "from_result_cache": None,
                    "read_partitions": None,
                    "pruned_files": None,
                    "read_files": None,
                    "statement_text": None,
                    "execution_status": "NOT_FOUND",
                    "error_message": None,
                }
                results.append(record)
                continue

            (
                total_ms,
                wait_ms,
                from_cache,
                read_partitions,
                pruned_files,
                read_files,
                stmt_text,
                exec_status,
                err_msg,
            ) = row

            stmt_preview = stmt_text.strip().replace("\n", " ") if stmt_text else ""

            record = {
                "query_index": q_idx,
                "run_index": r_idx,
                "statement_id": statement_id,
                "original_query": item["original_query"],
                "rewritten_query": item["rewritten_query"],
                "table_name": item["table_name"],
                "machine": item["machine"],
                "total_duration_ms": total_ms,
                "waiting_for_compute_duration_ms": wait_ms,
                "from_result_cache": from_cache,
                "read_partitions": read_partitions,
                "pruned_files": pruned_files,
                "read_files": read_files,
                "statement_text": stmt_preview,
                "execution_status": exec_status,
                "error_message": err_msg,
            }

            results.append(record)

            print(
                f"  ✅ status={exec_status}, total_ms={total_ms}, wait_ms={wait_ms}, "
                f"cache={from_cache}, read_files={read_files}"
            )

    with open(OUTPUT_JSON, "w", encoding="utf-8") as jf:
        json.dump(results, jf, indent=2)

    print(f"\nMetrics written to {OUTPUT_JSON}")


if __name__ == "__main__":
    main()