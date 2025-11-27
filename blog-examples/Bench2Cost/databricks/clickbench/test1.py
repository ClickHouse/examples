import os
import time
from databricks import sql

HOST = os.environ["DATABRICKS_SERVER_HOSTNAME"]
HTTP_PATH = os.environ["DATABRICKS_HTTP_PATH"]
TOKEN = os.environ["DATABRICKS_TOKEN"]

DB_NAME = "clickbench"
SELECT_QUERY = "SELECT RegionID FROM delta_hits_partitioned GROUP BY RegionID"

def main():
    with sql.connect(
        server_hostname=HOST,
        http_path=HTTP_PATH,
        access_token=TOKEN,
    ) as conn:
        with conn.cursor() as cur:
            # Disable result cache
#             cur.execute("SET use_cached_result=false")
#             cur.fetchall()

            # Select database
            cur.execute(f"USE {DB_NAME}")
            cur.fetchall()

            # Run the actual query
            cur.execute(SELECT_QUERY)
            rows = cur.fetchall()
            print(f"Returned {len(rows)} rows")

            # Grab the statement_id from the cursor
            statement_id = cur.query_id
            print(f"statement_id : {statement_id}")

        # Query metrics
        metrics_sql = f"""
        SELECT
          statement_text,
          total_duration_ms,
          waiting_for_compute_duration_ms,
          from_result_cache,
          read_partitions,
          pruned_files,
          read_files
        FROM system.query.history
        WHERE statement_id = '{statement_id}'
        """

        row = None
        max_wait_sec = 900      # 15 minutes
        poll_interval = 10      # every 10 seconds
        attempts = max_wait_sec // poll_interval

        print(f"\nWaiting for query {statement_id} to appear in system.query.history...")
        for attempt in range(attempts):
            with conn.cursor() as cur:
                cur.execute(metrics_sql)
                row = cur.fetchone()

            if row:
                break
            print(f"  ⏳ Still not visible (checked {attempt + 1}/{attempts})...")
            time.sleep(poll_interval)

        if not row:
            print(f"⚠️ No entry found for {statement_id} after {max_wait_sec}s.")
            return

        (
            stmt_text,
            total_ms,
            wait_ms,
            from_cache,
            read_partitions,
            pruned_files,
            read_files,
        ) = row

        print("\n✅ Found in system.query.history")
        stmt_preview = stmt_text.strip().replace("\n", " ")
        print(f"statement_text                   : {stmt_preview[:200]}{'...' if len(stmt_preview) > 200 else ''}")
        print(f"total_duration_ms                : {total_ms}")
        print(f"waiting_for_compute_duration_ms  : {wait_ms}")
        print(f"from_result_cache                : {from_cache}")
        print(f"read_partitions                  : {read_partitions}")
        print(f"pruned_files                     : {pruned_files}")
        print(f"read_files                       : {read_files}")

if __name__ == "__main__":
    main()