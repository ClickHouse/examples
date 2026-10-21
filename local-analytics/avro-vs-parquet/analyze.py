#!/usr/bin/env python3
"""Recompute trace accounting and compact summaries from retained raw evidence."""
import json
from pathlib import Path
import re
import statistics
import sys
ROOT=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parent
OUT=ROOT/'results'
records=json.loads((OUT/'raw-measurements.json').read_text())
traces=[]
for fmt in ['avro','parquet']:
 for shape in ['two','all']:
  path=OUT/f'trace-{fmt}-{shape}.strace'
  pending={};reads=[]
  for line in path.read_text().splitlines():
   m=re.match(r'\s*(\d+)\s+(.*)',line)
   if not m:continue
   pid,call=m.groups()
   if '<unfinished ...>' in call:
    pending[pid]=call.replace('<unfinished ...>','');continue
   if call.startswith('<... '):
    if pid not in pending:continue
    call=pending.pop(pid)+re.sub(r'^<\.\.\. \w+ resumed>', '',call)
   if f'</work/data/events.{fmt}>' not in call:continue
   m=re.match(r'pread64\(.*?,\s*(\d+),\s*(\d+)\)\s*=\s*(-?\d+)',call)
   if not m:raise ValueError(f'Unparsed target read: {call}')
   requested,offset,returned=map(int,m.groups())
   if returned<0:raise ValueError(f'Failed target read: {call}')
   reads.append({'offset':offset,'requested_bytes':requested,'returned_bytes':returned})
  intervals=sorted((r['offset'],r['offset']+r['returned_bytes']) for r in reads if r['returned_bytes'])
  merged=[]
  for lo,hi in intervals:
   if merged and lo<=merged[-1][1]:merged[-1][1]=max(hi,merged[-1][1])
   else:merged.append([lo,hi])
  traces.append({'format':fmt,'shape':shape,'read_calls':len(reads),
    'requested_bytes':sum(r['requested_bytes'] for r in reads),
    'returned_bytes':sum(r['returned_bytes'] for r in reads),
    'unique_file_range_bytes':sum(hi-lo for lo,hi in merged),
    'file_ranges':merged,'reads':reads})
(OUT/'validated-file-reads.json').write_text(json.dumps(traces,indent=2))
lines=['| Format | Columns | Query elapsed ms, median (range) | Process wall ms | Process CPU ms | Peak RSS MiB | CH tracked peak MiB | File read bytes, separate trace |',
       '|---|---|---|---:|---:|---:|---:|---:|']
for fmt in ['Avro','Parquet']:
 for shape in ['two','all']:
  group=[r for r in records if r['format']==fmt and r['shape']==shape]
  q=[r['query_elapsed_seconds']*1000 for r in group]
  cpu=[(r['user_cpu_seconds']+r['system_cpu_seconds'])*1000 for r in group]
  med=lambda key:statistics.median(r[key] for r in group)
  traced=next(t for t in traces if t['format']==fmt.lower() and t['shape']==shape)
  lines.append(f'| {fmt} | {shape} | {statistics.median(q):.0f} ({min(q):.0f}–{max(q):.0f}) | {med("process_wall_seconds")*1000:.1f} | {statistics.median(cpu):.1f} | {med("peak_rss_kib")/1024:.1f} | {med("clickhouse_peak_tracked_bytes")/1048576:.1f} | {traced["returned_bytes"]:,} |')
(OUT/'summary-table.md').write_text('\n'.join(lines)+'\n')
print('\n'.join(lines))
