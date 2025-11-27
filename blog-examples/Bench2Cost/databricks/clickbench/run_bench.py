#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# run_bench.py — Stage 1: Execute benchmark queries and collect statement_ids
#
# This script runs each ClickBench query (optionally multiple times) against
# Databricks SQL, records its statement_id, and writes the results to
# runs_<machine>.json.
#
# Why this is a separate stage:
# - system.query.history entries can take 4–10 minutes to appear after a query
#   finishes, depending on Databricks' telemetry refresh cycle.
# - If we immediately tried to fetch metrics after each query, we’d spend most
#   of the time idling on polling and API waits.
# - Instead, we first record all statement_ids as soon as queries complete,
#   then resolve them later in bulk (in collect_metrics.py).
#
# This two-phase approach:
#   ✅ avoids idle time between queries
#   ✅ allows deferred metric collection
#   ✅ makes re-running metric collection possible without re-running queries
#
# Output: runs_<machine>.json — one record per (query_index, run_index)
# -----------------------------------------------------------------------------

import os
import json
import argparse
from databricks import sql


def load_queries(path: str):
    queries = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            q = line.strip()
            if not q or q.startswith("--"):
                continue
            if q.endswith(";"):
                q = q[:-1]
            queries.append(q)
    return queries


def main():
    parser = argparse.ArgumentParser(
        description="Execute ClickBench queries and collect Databricks statement_ids"
    )
    parser.add_argument(
        "--machine",
        required=True,
        help='Machine name (e.g. "2X-Small", "2X-Large", etc.)',
    )
    parser.add_argument(
        "--input",
        default="queries.sql",
        help="Path to SQL file with one query per line (default: queries.sql)",
    )
    parser.add_argument(
    "--catalog",
    help='Optional catalog name (e.g. "hive_metastore", "main", "samples"). '
         'If omitted, Databricks default catalog "workspace" is used.',
    )
    parser.add_argument(
        "--db-name",
        default="clickbench",
        help="Database to USE (default: clickbench)",
    )
    parser.add_argument(
        "--table-name",
        default="delta_hits_partitioned",
        help='Table name to replace "FROM hits" with (default: delta_hits_partitioned)',
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="Number of runs per query (default: 3)",
    )

    args = parser.parse_args()
    MACHINE = args.machine
    INPUT_FILE = args.input
    DB_NAME = args.db_name
    CATALOG = args.catalog
    TABLE_NAME = args.table_name
    NUM_RUNS = args.runs
    OUTPUT_FILE = f"runs_{MACHINE}.json"

    HOST = os.environ["DATABRICKS_SERVER_HOSTNAME"]
    HTTP_PATH = os.environ["DATABRICKS_HTTP_PATH"]
    TOKEN = os.environ["DATABRICKS_TOKEN"]

    queries = load_queries(INPUT_FILE)
    print(f"Loaded {len(queries)} queries from {INPUT_FILE}")
    print(f"Machine: {MACHINE}")
    print(f"DB: {DB_NAME}, table: {TABLE_NAME}, runs/query: {NUM_RUNS}")
    print(f"Output file: {OUTPUT_FILE}")

    runs = []  # one record per (query_index, run_index)

    with sql.connect(
        server_hostname=HOST,
        http_path=HTTP_PATH,
        access_token=TOKEN,
    ) as conn:
        with conn.cursor() as cur:
            # disable cached results for this session
            cur.execute("SET use_cached_result=false")
            cur.fetchall()

            # If user supplied a catalog, activate it
            if CATALOG:
                print(f"Using catalog: {CATALOG}")
                cur.execute(f"USE CATALOG {CATALOG}")

            # choose database
            cur.execute(f"USE {DB_NAME}")
            cur.fetchall()

            for q_idx, q in enumerate(queries, start=1):
                rewritten = q.replace("FROM hits", f"FROM {TABLE_NAME}")

                for run_idx in range(1, NUM_RUNS + 1):
                    print(f"\n[Q{q_idx} run {run_idx}/{NUM_RUNS}]")
                    print(f"  {rewritten}")

                    cur.execute(rewritten)
                    cur.fetchall()

                    statement_id = cur.query_id
                    print(f"  statement_id: {statement_id}")

                    runs.append(
                        {
                            "query_index": q_idx,
                            "run_index": run_idx,
                            "original_query": q,
                            "rewritten_query": rewritten,
                            "statement_id": statement_id,
                            "table_name": TABLE_NAME,
                            "machine": MACHINE,
                        }
                    )

    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        json.dump(runs, f, indent=2)

    print(
        f"\nSaved {len(runs)} runs to {OUTPUT_FILE} "
        f"({len(queries)} queries × {NUM_RUNS} runs)."
    )


if __name__ == "__main__":
    main()