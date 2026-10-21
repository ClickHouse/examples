#!/usr/bin/env python3
"""Hard correctness checks; measured mechanism deviations request human review."""
import json
import math
from pathlib import Path
import statistics
import sys

ROOT=Path(__file__).resolve().parent
RUN=Path(sys.argv[1]).resolve()
OUT=RUN/'results'
REF=ROOT/'reference'/'cli-26.8.32.16'
errors=[];reviews=[];checks=[]
def read(path):return json.loads(path.read_text())
def hard(ok,message):
    checks.append({'check':message,'passed':bool(ok)})
    if not ok:errors.append(message)
def review(ok,message):
    if not ok:reviews.append(message)

try:
    manifest=read(OUT/'manifest.json')
    hard(manifest['rows']==500000 and manifest['repeats']==7,'fixed dataset and repetition count')
    hard(manifest['clickhouse_version']=='26.8.32.16','exact engine version')
    hard(manifest['managed_setup']['cli_version']=='clickhousectl 0.4.2','pinned official CLI version')
    hard(manifest['managed_setup']['binary_path']==manifest['base_command'][0],'managed binary actually used by runner')
    baseline_manifest=read(REF/'manifest.json')
    hard(manifest['base_command'][1:]==baseline_manifest['base_command'][1:],'identical query settings and execution mode')
    hard(manifest['export_settings']==baseline_manifest['export_settings'],'identical export and layout settings')
    hard(manifest['platform']['machine']=='aarch64' and manifest['cpu_max']=='200000 100000' and manifest['memory_max']=='3221225472','arm64 architecture and exact resource caps')
    hard(manifest['managed_setup']['managed_binary_sha256']=='0d0719833575d7f930580bba7769069d4bc054a8af037e8b8bc3955f7368f937','exact declared managed binary SHA-256')
    for filename in ['correctness.json','projection-correctness.json']:
        actual=read(OUT/filename);expected=read(REF/filename)
        hard(actual==expected,f'exact reference logical-output invariant: {filename}')
    rowtypes=read(OUT/'row-type-invariants.json')
    for fmt in ['Avro','Parquet']:
        hard(rowtypes[fmt]=={'inferred_types_match':True,'rows':500000,'min_id':0,'max_id':499999,'sum_id':124999750000},f'{fmt} row range/count/sum and inferred types')
    schemas=read(OUT/'schema-resolution.json')
    hard(schemas['sdk_version']=='1.12.2','Apache Avro SDK pin')
    hard(schemas['tests'][0]['result']=={'id':7,'region':'unknown'} and schemas['tests'][1]['exception_type']=='SchemaResolutionException' and schemas['tests'][2]['result']=={'id':7},'schema resolution expected outcomes')
    raw=read(OUT/'raw-measurements.json')
    hard(len(raw)==28,'exactly 28 measured samples')
    expected_cases={(f,s,r) for f in ['Avro','Parquet'] for s in ['two','all'] for r in range(1,8)}
    hard({(r['format'],r['shape'],r['repeat']) for r in raw}==expected_cases,'exact four cases and seven unique repetitions')
    hard([r['sequence'] for r in raw]==list(range(1,29)),'contiguous run sequence')
    ref_queries={(r['format'],r['shape']):r['query'] for r in read(REF/'raw-measurements.json')}
    hard(all(r['query']==ref_queries[(r['format'],r['shape'])] for r in raw),'exact reference projection queries')
    hard(all(r['query'].endswith('FORMAT Null') and 'count(' not in r['query'].lower() for r in raw),'timed projection queries use a local sink without count shortcuts')
    for r in raw:
        for key in ['query_elapsed_seconds','process_wall_seconds','user_cpu_seconds','system_cpu_seconds','peak_rss_kib','clickhouse_peak_tracked_bytes']:
            hard(isinstance(r[key],(int,float)) and math.isfinite(r[key]) and r[key]>=0,f'{r["label"]} finite {key}')
    review(all(r['proc_io']['read_bytes']==0 and r['block_input_ops']==0 for r in raw),'warm guest-block-I/O regime was not reproduced')
    io=read(OUT/'io-counter-control.json')
    review(io['runs'][0]['proc_io']['read_bytes']==16777216 and io['runs'][1]['proc_io']['read_bytes']==0,'positive/warm guest I/O counter control differs')
    traces=read(OUT/'validated-file-reads.json')
    volume_ref=REF
    reference=read(volume_ref/'validated-file-reads.json')
    index={(r['format'],r['shape']):r for r in traces}
    hard(set(index)=={('avro','two'),('avro','all'),('parquet','two'),('parquet','all')},'four validated target-file traces')
    comparisons=[]
    for fmt in ['Avro','Parquet']:
        current=manifest['files'][fmt]['bytes'];baseline=read(volume_ref/'manifest.json')['files'][fmt]['bytes']
        ratio=current/baseline
        # Sizes are observational, not format constants. Allow 1% before requesting review.
        review(abs(ratio-1)<=0.01,f'{fmt} file size differs by more than 1%')
        comparisons.append({'metric':f'{fmt} file bytes','observed':current,'reference':baseline,'ratio':ratio,'review_tolerance':0.01})
    for ref in reference:
        current=index[(ref['format'],ref['shape'])]['returned_bytes'];ratio=current/ref['returned_bytes']
        review(abs(ratio-1)<=0.05,f'{ref["format"]}/{ref["shape"]} traced returned volume differs by more than 5%')
        comparisons.append({'metric':f'{ref["format"]}/{ref["shape"]} traced returned bytes','observed':current,'reference':ref['returned_bytes'],'ratio':ratio,'review_tolerance':0.05})
    av2=index[('avro','two')]['returned_bytes'];avall=index[('avro','all')]['returned_bytes']
    pq2=index[('parquet','two')]['returned_bytes'];pqall=index[('parquet','all')]['returned_bytes']
    review(av2/avall>=0.95,'Avro projection no longer traverses approximately the full compressed stream')
    review(pq2/pqall<0.20,'Parquet narrow projection no longer fetches substantially less than its full projection')
    timing_comparisons=[]
    for reference_dir in [REF]:
        ref_raw=read(reference_dir/'raw-measurements.json')
        for fmt in ['Avro','Parquet']:
            for shape in ['two','all']:
                a=[r for r in raw if r['format']==fmt and r['shape']==shape]
                b=[r for r in ref_raw if r['format']==fmt and r['shape']==shape]
                metrics={'query_seconds':lambda r:r['query_elapsed_seconds'],
                         'process_wall_seconds':lambda r:r['process_wall_seconds'],
                         'process_cpu_seconds':lambda r:r['user_cpu_seconds']+r['system_cpu_seconds'],
                         'peak_rss_kib':lambda r:r['peak_rss_kib'],
                         'clickhouse_peak_tracked_bytes':lambda r:r['clickhouse_peak_tracked_bytes']}
                for metric,get in metrics.items():
                    observed=statistics.median(get(r) for r in a)
                    baseline=statistics.median(get(r) for r in b)
                    timing_comparisons.append({'reference':reference_dir.name,'format':fmt,'shape':shape,'metric':metric,'observed_median':observed,
                        'reference_median':baseline,'delta':observed-baseline,'ratio':observed/baseline if baseline else None,
                        'advisory_only':True})
    status='failed' if errors else 'review_required' if reviews else 'pass'
    report={'status':status,'hard_errors':errors,'review_reasons':reviews,'checks':checks,
            'volume_reference':volume_ref.name,'comparisons':comparisons,'advisory_resource_comparisons':timing_comparisons,
            'timing_policy':'Advisory only; no exact expected timings, speed ratios, CPU or memory pass thresholds. Do not tune to force a winner.'}
except Exception as e:
    errors.append(f'{type(e).__name__}: {e}')
    report={'status':'failed','hard_errors':errors,'review_reasons':reviews,'checks':checks}
(RUN/'validation.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
sys.exit(1 if report['status']=='failed' else 2 if report['status']=='review_required' else 0)
