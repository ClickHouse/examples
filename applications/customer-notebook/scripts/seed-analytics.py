"""Explicit administrator-only synthetic seed, using Python's native TLS client.

Repeat replaces the four-event fixture, not production activity. Runtime has no
analytical write path. Load CH_HOST/PORT/ADMIN_PASSWORD/REPORT_PASSWORD privately.
"""
import json
import os
import re
import ssl
import urllib.request


def query(statement):
    request = urllib.request.Request(
        f"https://{os.environ['CH_HOST']}:{os.environ['CH_PORT']}/?max_execution_time=10",
        data=statement.encode(), headers={"X-ClickHouse-User": "default",
                                          "X-ClickHouse-Key": os.environ["CH_ADMIN_PASSWORD"]})
    with urllib.request.urlopen(request, context=ssl.create_default_context(), timeout=15) as response:
        return response.read().decode()


password = os.environ["CH_REPORT_PASSWORD"]
# Setup generates a64-character ASCII password; reject unsupported literal text.
assert re.fullmatch(r"[A-Za-z0-9!]{32,128}", password)
query("CREATE DATABASE IF NOT EXISTS notebook_analytics")
query("""CREATE TABLE IF NOT EXISTS notebook_analytics.activity (
  customer_id UUID COMMENT 'Synthetic seeded customer',
  activity_day Date COMMENT 'UTC activity date',
  event_id UInt32 COMMENT 'Fixture event identity'
) ENGINE=MergeTree ORDER BY(customer_id,activity_day,event_id)""")
query("TRUNCATE TABLE notebook_analytics.activity")
rows = [(1, "2026-09-28", 1), (1, "2026-09-28", 2), (1, "2026-09-30", 3), (2, "2026-09-29", 4)]
query("INSERT INTO notebook_analytics.activity SETTINGS async_insert=0,deduplicate_insert='disable' FORMAT JSONEachRow\n" + "\n".join(
    json.dumps({"customer_id": f"00000000-0000-0000-0000-{customer:012d}",
                "activity_day": day, "event_id": event}) for customer, day, event in rows))
query(f"""CREATE USER IF NOT EXISTS notebook_report IDENTIFIED WITH sha256_password BY '{password}'
SETTINGS readonly=2,max_execution_time=10,max_rows_to_read=20000,max_result_rows=31,
         max_result_bytes=65536,result_overflow_mode='throw'""")
query("GRANT SELECT ON notebook_analytics.activity TO notebook_report")
count = json.loads(query("SELECT count() AS events FROM notebook_analytics.activity LIMIT 1 FORMAT JSONEachRow"))["events"]
assert int(count) == 4
print("Synthetic analytical fixture contains exactly four events; reporting grant is SELECT only.")
