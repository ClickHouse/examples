#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# summarize_results.py — Stage 3: Build final ClickBench-style result JSON
#
# Produces a minimal ClickBench-compatible result file:
# {
#   "system": "Databricks Serverless SQL warehouse",
#   "date": "YYYY-MM-DD",
#   "machine": "<machine>",
#   "proprietary": "yes",
#   "tuned": "no",
#   "tags": ["Databricks", "Photon", "Serverless"],
#   "load_time": 0,
#   "data_size": 0,
#   "result": [[run1, run2, run3], ...]
# }
# -----------------------------------------------------------------------------

import json
import argparse
from datetime import date


def main():
    parser = argparse.ArgumentParser(
        description="Summarize Databricks benchmark results into minimal ClickBench JSON"
    )
    parser.add_argument(
        "--machine",
        required=True,
        help='Machine name (e.g. "2X-Small", "2X-Large", etc.)',
    )
    parser.add_argument(
        "--input",
        help="Path to metrics JSON (default: metrics_<machine>.json)",
    )
    parser.add_argument(
        "--output",
        help="Output file name (default: clickbench_<machine>.json)",
    )

    args = parser.parse_args()
    MACHINE = args.machine
    input_path = args.input or f"metrics_{MACHINE}.json"
    output_path = args.output or f"clickbench_{MACHINE}.json"

    print(f"Loading metrics from {input_path}")
    print(f"Generating ClickBench result for machine: {MACHINE}")
    print(f"Output file will be: {output_path}")

    with open(input_path, "r", encoding="utf-8") as f:
        runs = json.load(f)

    # group by query_index → list of runs (sorted by run_index)
    by_query = {}
    for r in runs:
        q_idx = r["query_index"]
        by_query.setdefault(q_idx, []).append(r)

    # build result: list[query] -> [run1_sec, run2_sec, run3_sec]
    result = []
    max_q = max(by_query.keys())

    for q_idx in range(1, max_q + 1):
        q_runs = sorted(by_query.get(q_idx, []), key=lambda x: x["run_index"])
        run_times = []
        for r in q_runs:
            if (
                r["total_duration_ms"] is None
                or r.get("execution_status") != "FINISHED"
            ):
                run_times.append(None)
            else:
                run_times.append(round(r["total_duration_ms"] / 1000.0, 3))
        result.append(run_times)

    output = {
        "system": "Databricks Serverless SQL warehouse",
        "date": str(date.today()),
        "machine": "serverless",
        "cluster_size": MACHINE,
        "proprietary": "yes",
        "tuned": "no",
        "tags": ["Databricks", "Photon", "Serverless"],
        "load_time": 0,
        "data_size": 0,
        "result": result,
    }

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2)

    print(f"\n✅ Wrote ClickBench-compatible result to {output_path}")


if __name__ == "__main__":
    main()