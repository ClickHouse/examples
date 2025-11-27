#!/usr/bin/env python3
import os
import time
import json
import argparse
from databricks import sql

HOST = os.environ["DATABRICKS_SERVER_HOSTNAME"]
HTTP_PATH = os.environ["DATABRICKS_HTTP_PATH"]
TOKEN = os.environ["DATABRICKS_TOKEN"]


def escape_literal(s: str) -> str:
    """Escape single quotes for safe inclusion in an IN (...) list."""
    return s.replace("'", "''")


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
        help="Max seconds to wait for history entries (default: 900 = 15min)",
    )
    parser.add_argument(
        "--poll-interval-sec",
        type=int,
        default=10,
        help="Polling interval in seconds (default: 10)",
    )

    args = parser.parse_args()
    machine = args.machine

    input_path = args.input or f"runs_{machine}.json"
    output_path = args.output or f"metrics_{machine}.json"
    max_wait = args.max_wait_sec
    interval = args.poll_interval_sec

    print(f"Machine           : {machine}")
    print(f"Input (runs)      : {input_path}")
    print(f"Output (metrics)  : {output_path}")
    print(f"Max wait (sec)    : {max_wait}")
    print(f"Poll interval (s) : {interval}")

    with open(input_path, "r", encoding="utf-8") as f:
        items = json.load(f)

    print(f"Loaded {len(items)} run records from {input_path}")

    # Map statement_id -> list of items (in case of collisions)
    by_stmt = {}
    for item in items:
        sid = item["statement_id"]
        by_stmt.setdefault(sid, []).append(item)

    pending_ids = set(by_stmt.keys())
    found_metrics = {}  # statement_id -> list of rows (should normally be 1)

    start_ts = time.time()
    attempts = 0

    with sql.connect(
        server_hostname=HOST,
        http_path=HTTP_PATH,
        access_token=TOKEN,
    ) as conn:
        while pending_ids and (time.time() - start_ts) < max_wait:
            attempts += 1
            print(
                f"\nPolling attempt {attempts} "
                f"(pending {len(pending_ids)} statement_ids)..."
            )

            batch_ids = list(pending_ids)
            # Databricks can handle pretty large IN lists, but be safe:
            chunk_size = 200
            new_found = 0

            for i in range(0, len(batch_ids), chunk_size):
                chunk = batch_ids[i : i + chunk_size]
                in_list = ",".join(
                    f"'{escape_literal(s)}'" for s in chunk
                )

                metrics_sql = f"""
                SELECT
                    statement_id,
                    total_duration_ms,
                    waiting_for_compute_duration_ms,
                    from_result_cache,
                    read_partitions,
                    pruned_files,
                    read_files,
                    execution_status,
                    error_message,
                    statement_text
                FROM system.query.history
                WHERE statement_id IN ({in_list})
                """

                with conn.cursor() as cur:
                    cur.execute(metrics_sql)
                    rows = cur.fetchall()

                for row in rows:
                    (
                        stmt_id,
                        total_ms,
                        wait_ms,
                        from_cache,
                        read_partitions,
                        pruned_files,
                        read_files,
                        exec_status,
                        err_msg,
                        stmt_text,
                    ) = row

                    # accumulate metrics (normally 1 row per statement_id)
                    found_metrics.setdefault(stmt_id, []).append(
                        {
                            "total_duration_ms": total_ms,
                            "waiting_for_compute_duration_ms": wait_ms,
                            "from_result_cache": from_cache,
                            "read_partitions": read_partitions,
                            "pruned_files": pruned_files,
                            "read_files": read_files,
                            "execution_status": exec_status,
                            "error_message": err_msg,
                            "statement_text": stmt_text,
                        }
                    )

                new_found += len(rows)

            if new_found:
                print(f"  → Found {new_found} new history rows.")
                # remove any IDs that now have metrics
                pending_ids -= set(found_metrics.keys())
            else:
                print("  → No new rows yet.")

            if pending_ids:
                elapsed = int(time.time() - start_ts)
                print(
                    f"  Still waiting on {len(pending_ids)} ids "
                    f"(elapsed {elapsed}s, sleeping {interval}s)..."
                )
                time.sleep(interval)

        # after polling loop
        if pending_ids:
            elapsed = int(time.time() - start_ts)
            print(
                f"\n⚠️  Timeout after {elapsed}s, "
                f"{len(pending_ids)} statement_ids still missing."
            )
        else:
            elapsed = int(time.time() - start_ts)
            print(f"\n✅ All statement_ids resolved in {elapsed}s.")

    # Build final per-run records, keeping your exact schema
    records = []
    for item in items:
        q_idx = item["query_index"]
        r_idx = item["run_index"]
        statement_id = item["statement_id"]

        # there may be multiple metrics rows; take the first
        metric_rows = found_metrics.get(statement_id)

        if not metric_rows:
            # mirror old behavior: write a record with None fields
            print(
                f"⚠️  No history entry for statement_id={statement_id}, "
                "writing empty metrics."
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
                "execution_status": None,
                "error_message": None,
            }
            records.append(record)
            continue

        m = metric_rows[0]
        stmt_text = m["statement_text"] or ""
        stmt_preview = stmt_text.strip().replace("\n", " ")

        record = {
            "query_index": q_idx,
            "run_index": r_idx,
            "statement_id": statement_id,
            "original_query": item["original_query"],
            "rewritten_query": item["rewritten_query"],
            "table_name": item["table_name"],
            "machine": item["machine"],
            "total_duration_ms": m["total_duration_ms"],
            "waiting_for_compute_duration_ms": m[
                "waiting_for_compute_duration_ms"
            ],
            "from_result_cache": m["from_result_cache"],
            "read_partitions": m["read_partitions"],
            "pruned_files": m["pruned_files"],
            "read_files": m["read_files"],
            "statement_text": stmt_preview,
            "execution_status": m["execution_status"],
            "error_message": m["error_message"],
        }
        records.append(record)

    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(records, f, indent=2)

    print(f"\nWrote {len(records)} records to {output_path}")


if __name__ == "__main__":
    main()