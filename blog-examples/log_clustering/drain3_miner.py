#!/usr/bin/env python3
import sys, json, argparse
from collections import defaultdict
from io import StringIO
import contextlib
from drain3 import TemplateMiner
from drain3.template_miner_config import TemplateMinerConfig
from drain3.file_persistence import FilePersistence

INI = """
[SNAPSHOT]
snapshot_interval_minutes = 10
compress_state = True

[MASKING]
masking = [
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)(([0-9a-f]{2,}:){3,}([0-9a-f]{2,}))((?=[^A-Za-z0-9])|$)", "mask_with": "ID"},
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)(\\d{1,3}\\.\\d{1,3}\\.\\d{1,3}\\.\\d{1,3})((?=[^A-Za-z0-9])|$)", "mask_with": "IP"},
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)([0-9a-f]{6,} ?){3,}((?=[^A-Za-z0-9])|$)", "mask_with": "SEQ"},
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)([0-9A-F]{4} ?){4,}((?=[^A-Za-z0-9])|$)", "mask_with": "SEQ"},
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)(0x[a-f0-9A-F]+)((?=[^A-Za-z0-9])|$)", "mask_with": "HEX"},
  {"regex_pattern":"((?<=[^A-Za-z0-9])|^)([\\-\\+]?\\d+)((?=[^A-Za-z0-9])|$)", "mask_with": "NUM"},
  {"regex_pattern":"(?i)([a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})","mask_with":"UUID"},
  {"regex_pattern":"\\d{4}-\\d{2}-\\d{2}[ T]\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+\\-]\\d{2}:\\d{2})?","mask_with":"TS"},
  {"regex_pattern":"\\\".*?\\\"","mask_with":"STR"},
  {"regex_pattern":"(?<=executed cmd )(\\".+?\\")", "mask_with": "CMD"}
]
mask_prefix = <:
mask_suffix = :>

[DRAIN]
sim_th = 0.4
depth = 4
max_children = 100
max_clusters = 1024
extra_delimiters = ["_"]

[PROFILING]
enabled = False
report_sec = 30
"""
def build_miner():
    cfg = TemplateMinerConfig()
    with contextlib.redirect_stdout(sys.stderr):
      cfg.load(StringIO(INI))
      cfg.config_file = None
      persistence = None
      return TemplateMiner(persistence, cfg)

def mine_summary(lines):
    miner = build_miner()
    counts = defaultdict(int)
    templates = {}
    total = 0

    for raw in lines:
        if not raw:
            continue
        total += 1
        r = miner.add_log_message(raw)
        cid = r["cluster_id"]
        tmpl = r["template_mined"]
        counts[cid] += 1
        templates[cid] = tmpl

    items = []
    for cid, cnt in counts.items():
        cov = (cnt / total * 100.0) if total else 0.0
        items.append({"template": templates[cid], "count": int(cnt), "coverage": round(cov, 2)})

    items.sort(key=lambda x: (-x["count"], x["template"]))
    return items

def main():
    for line in sys.stdin:
        obj = json.loads(line)
        values = obj.get("values") or []
        strings = [s for s in values if isinstance(s, str)]
        result = mine_summary(strings)
        sys.stdout.write(json.dumps({"result": result}, ensure_ascii=False) + "\n")
        sys.stdout.flush()

if __name__ == "__main__":
    main()
