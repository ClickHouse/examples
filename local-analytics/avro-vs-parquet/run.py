#!/usr/bin/env python3
"""Deterministic local-file experiment. Run inside the isolated Docker image."""
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import resource
import re
import statistics
import subprocess
import sys
import time

ROOT = Path('/work')
OUT = ROOT / 'results'
DATA = ROOT / 'data'
OUT.mkdir(exist_ok=True)
DATA.mkdir(exist_ok=True)
N = 500000
REPEATS = 7
SETUP = json.loads(Path('/opt/setup/managed.json').read_text())
CLICKHOUSE_BINARY = SETUP['binary_path']
FIELDS = [
    ('event_id','Int64'), ('event_time','DateTime64(3, \'UTC\')'),
    ('tenant_id','Int32'), ('user_id','Int64'), ('event_type','String'),
    ('country','String'), ('status','Int32'), ('latency_ms','Float64'),
    ('bytes_sent','Int64'), ('cpu_ms','Float64'), ('path','String'),
    ('host','String'), ('user_agent','String'), ('campaign','String'),
    ('email','String'), ('request_id','String'), ('payload','String'),
    ('region','String'), ('service','String'), ('retry_count','Int32')]
NAMES = [x[0] for x in FIELDS]
STRUCT = ', '.join(f'{n} {t}' for n,t in FIELDS)
BASE = [CLICKHOUSE_BINARY,'local','--max_threads=1','--max_memory_usage=1500000000',
        '--max_execution_time=30','--max_rows_to_read=600000',
        '--max_bytes_to_read=1500000000','--max_result_rows=600000',
        '--input_format_parallel_parsing=0','--input_format_parquet_preserve_order=1',
        '--storage_file_read_method=pread',
        '--use_query_cache=0','--use_parquet_metadata_cache=0',
        '--input_format_parquet_memory_high_watermark=536870912']
GEN = f"""SELECT
 toInt64(number) AS event_id,
 toDateTime64('2026-01-01 00:00:00',3,'UTC') + toIntervalMillisecond(number * 137) AS event_time,
 toInt32(number % 100) AS tenant_id,
 toInt64(cityHash64(number) % 100000) AS user_id,
 ['view','click','purchase','login'][1 + number % 4] AS event_type,
 ['US','GB','DE','IN','JP'][1 + number % 5] AS country,
 toInt32(if(number % 37 = 0, 500, 200)) AS status,
 toFloat64(1 + cityHash64(number,1) % 10000) / 10 AS latency_ms,
 toInt64(cityHash64(number,2) % 100000) AS bytes_sent,
 toFloat64(cityHash64(number,3) % 10000) / 100 AS cpu_ms,
 concat('/api/products/',toString(number % 10000)) AS path,
 concat('edge-',toString(number % 50),'.example.test') AS host,
 ['Chrome-test','Firefox-test','SDK-test'][1 + number % 3] AS user_agent,
 concat('campaign-',toString(number % 30)) AS campaign,
 concat('user',toString(number % 100000),'@example.test') AS email,
 hex(sipHash128(number)) AS request_id,
 concat('{{\"product\":',toString(number % 10000),',\"trace\":\"',
 hex(sipHash128(number,11)),hex(sipHash128(number,12)),
 hex(sipHash128(number,13)),hex(sipHash128(number,14)),'\"}}') AS payload,
 ['us-east','eu-west','ap-south'][1 + number % 3] AS region,
 ['checkout','catalog','identity','search'][1 + number % 4] AS service,
 toInt32(number % 3) AS retry_count
FROM numbers({N})"""

def call(query, *, stdout=subprocess.PIPE, profile=False, extra=None):
    args = BASE + (extra or []) + (['--time','--print-profile-events'] if profile else []) + ['--query',query]
    p = subprocess.run(args, stdout=stdout, stderr=subprocess.PIPE, check=False)
    if p.returncode:
        raise RuntimeError(p.stderr.decode())
    return p

def file_expr(fmt):
    return f"file('/work/data/events.{fmt.lower()}', '{fmt}', '{STRUCT.replace(chr(39), chr(92)+chr(39))}')"

def measured(query, label, *, trace=False):
    stderr = OUT / f'{label}.stderr'
    args = BASE + ['--time','--print-profile-events','--query',query]
    if trace:
        args = ['strace','-f','-yy','-e','trace=read,pread64,lseek','-o',str(OUT/f'{label}.strace')] + args
    start = time.perf_counter()
    with open(stderr,'wb') as err, open(os.devnull,'wb') as devnull:
        p = subprocess.Popen(args, stdout=devnull, stderr=err)
        os.waitid(os.P_PID, p.pid, os.WEXITED | os.WNOWAIT)
        elapsed = time.perf_counter() - start
        proc_io = dict(line.split(': ',1) for line in Path(f'/proc/{p.pid}/io').read_text().splitlines())
        pid, status, usage = os.wait4(p.pid,0)
        p.returncode = os.waitstatus_to_exitcode(status)
    if p.returncode:
        raise RuntimeError(stderr.read_text())
    lines=stderr.read_text().splitlines()
    query_seconds=[float(x) for x in lines if re.fullmatch(r'\d+\.\d+',x)]
    peaks=[int(m.group(1)) for x in lines if (m:=re.search(r'MemoryTrackerPeakUsage: (\d+)',x))]
    return {'label':label,'query_elapsed_seconds':query_seconds[-1] if query_seconds else None,
            'clickhouse_peak_tracked_bytes':max(peaks) if peaks else None,
            'process_wall_seconds':elapsed,'user_cpu_seconds':usage.ru_utime,
            'system_cpu_seconds':usage.ru_stime,'peak_rss_kib':usage.ru_maxrss,
            'block_input_ops':usage.ru_inblock,'block_output_ops':usage.ru_oublock,
            'proc_io':{k:int(v) for k,v in proc_io.items()},'query':query}

def hash_query(q):
    h=hashlib.sha256()
    p=subprocess.Popen(BASE+['--query',q+' FORMAT RowBinary'],stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    while True:
        b=p.stdout.read(1024*1024)
        if not b:break
        h.update(b)
    err=p.stderr.read()
    if p.wait():raise RuntimeError(err.decode())
    return h.hexdigest()

def schema_resolution():
    import avro, avro.schema, avro.io
    writer=avro.schema.parse(json.dumps({'type':'record','name':'Event','fields':[
        {'name':'id','type':'long'},{'name':'obsolete','type':'string'}]}))
    b=io.BytesIO()
    avro.io.DatumWriter(writer).write({'id':7,'obsolete':'old'},avro.io.BinaryEncoder(b))
    rows=[]
    for name,fields in [
      ('add_with_default',[{'name':'id','type':'long'},{'name':'region','type':'string','default':'unknown'}]),
      ('add_without_default',[{'name':'id','type':'long'},{'name':'region','type':'string'}]),
      ('omit_writer_field',[{'name':'id','type':'long'}])]:
        reader=avro.schema.parse(json.dumps({'type':'record','name':'Event','fields':fields}))
        try:
            result=avro.io.DatumReader(writer,reader).read(avro.io.BinaryDecoder(io.BytesIO(b.getvalue())))
            rows.append({'test':name,'outcome':'success','result':result})
        except Exception as e:
            rows.append({'test':name,'outcome':'error','exception_type':type(e).__name__,'message':str(e)})
    assert rows[0]['result']=={'id':7,'region':'unknown'}
    assert rows[1]['outcome']=='error' and rows[1]['exception_type']=='SchemaResolutionException'
    assert rows[2]['result']=={'id':7}
    (OUT/'schema-resolution.json').write_text(json.dumps({'sdk_version':avro.__version__,'tests':rows},indent=2))

def io_control():
    """Validate Linux guest block-I/O accounting with only an owned scratch file."""
    pth=DATA/'io-control.bin'
    size=16*1024*1024
    with pth.open('wb') as f:
        for i in range(size//65536):f.write(hashlib.sha256(str(i).encode()).digest()*2048)
        f.flush();os.fsync(f.fileno())
    with pth.open('rb') as f:os.posix_fadvise(f.fileno(),0,0,os.POSIX_FADV_DONTNEED)
    code="with open('/work/data/io-control.bin','rb') as f:\n while f.read(65536):pass"
    rows=[]
    for label in ['owned-file-eviction-advice','warm-repeat']:
        p=subprocess.Popen(['python3','-c',code])
        os.waitid(os.P_PID,p.pid,os.WEXITED|os.WNOWAIT)
        counters={k:int(v) for k,v in [x.split(': ',1) for x in Path(f'/proc/{p.pid}/io').read_text().splitlines()]}
        _,status,r=os.wait4(p.pid,0);p.returncode=os.waitstatus_to_exitcode(status)
        rows.append({'label':label,'proc_io':counters,'block_input_ops':r.ru_inblock})
    (OUT/'io-counter-control.json').write_text(json.dumps({'file_bytes':size,'note':'Linux guest block I/O, not laptop SSD physical reads; targeted POSIX_FADV_DONTNEED only, no host/global drop_caches','runs':rows},indent=2))

def main():
    (OUT/'generator.sql').write_text(GEN+';\n')
    (OUT/'settings.jsonl').write_bytes(call("SELECT name,value,description FROM system.settings WHERE name LIKE '%parquet%' OR name LIKE '%avro%' OR name IN ('max_threads','max_memory_usage','max_execution_time','max_rows_to_read','max_bytes_to_read','input_format_parallel_parsing','use_query_cache') FORMAT JSONEachRow").stdout)
    manifest={'rows':N,'repeats':REPEATS,'fields':FIELDS,'base_command':BASE,
              'clickhouse_version':call('SELECT version()').stdout.decode().strip(),
              'platform':platform.uname()._asdict(),'python':sys.version,
              'cpu_max':Path('/sys/fs/cgroup/cpu.max').read_text().strip(),
              'memory_max':Path('/sys/fs/cgroup/memory.max').read_text().strip(),
              'cache_regime':'warm OS page cache; fresh ClickHouse process per invocation; no cache drop claimed',
              'managed_setup':SETUP,'start_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}
    (OUT/'packages.txt').write_bytes(subprocess.check_output(['dpkg-query','-W']))
    schema_resolution()
    io_control()
    exports={
      'Avro':['--output_format_avro_codec=zstd','--output_format_avro_sync_interval=65536','--output_format_avro_string_column_pattern=.*'],
      'Parquet':['--output_format_parquet_compression_method=zstd','--output_format_parquet_row_group_size=100000',
                 '--output_format_parquet_row_group_size_bytes=134217728','--output_format_parquet_data_page_size=1048576',
                 '--output_format_parquet_parallel_encoding=0','--output_format_parquet_write_page_index=1']}
    manifest['export_settings']=exports
    for fmt,extra in exports.items():
        path=DATA/f'events.{fmt.lower()}'
        with path.open('wb') as out:call(GEN+f' FORMAT {fmt}',stdout=out,extra=extra)
        manifest.setdefault('files',{})[fmt]={'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()}
    from avro.datafile import DataFileReader
    from avro.io import DatumReader
    with DataFileReader(open(DATA/'events.avro','rb'),DatumReader()) as header:
        (OUT/'avro-metadata.json').write_text(json.dumps({k:v.decode() for k,v in header.meta.items()},indent=2))
    (OUT/'parquet-metadata.jsonl').write_bytes(call("SELECT * FROM file('/work/data/events.parquet', ParquetMetadata) LIMIT 1 FORMAT JSONEachRow").stdout)
    baseline=hash_query(GEN)
    correct={'generator_ordered_rowbinary_sha256':baseline,'files':{}}
    for fmt in exports:
        digest=hash_query(f"SELECT {', '.join(NAMES)} FROM {file_expr(fmt)}")
        assert digest==baseline,(fmt,digest,baseline)
        sample=call(f"SELECT {', '.join(NAMES)} FROM {file_expr(fmt)} LIMIT 3 FORMAT JSONEachRow").stdout.decode()
        (OUT/f'{fmt.lower()}-sample.jsonl').write_text(sample)
        correct['files'][fmt]={'ordered_rowbinary_sha256':digest,'matches_generator':True}
        desc=call(f'DESCRIBE TABLE {file_expr(fmt)} FORMAT JSONEachRow').stdout
        (OUT/f'{fmt.lower()}-schema.jsonl').write_bytes(desc)
    projected=hash_query(f'SELECT event_time, latency_ms FROM ({GEN})')
    projection={'generator_two_column_ordered_rowbinary_sha256':projected,'files':{}}
    invariants={}
    for fmt in exports:
        actual=hash_query(f'SELECT event_time, latency_ms FROM {file_expr(fmt)}')
        assert actual==projected
        projection['files'][fmt]={'two_column_ordered_rowbinary_sha256':actual,'matches_generator':True}
        path=f"/work/data/events.{fmt.lower()}"
        inferred=[json.loads(x) for x in call(f"DESCRIBE TABLE file('{path}', '{fmt}') FORMAT JSONEachRow").stdout.decode().splitlines()]
        (OUT/f'{fmt.lower()}-inferred-schema.json').write_text(json.dumps(inferred,indent=2))
        normalize=lambda t:''.join(t.split()).replace(',\'UTC\'','')
        assert [x['name'] for x in inferred]==NAMES
        assert [normalize(x['type']) for x in inferred]==[normalize(t) for _,t in FIELDS]
        stats=json.loads(call(f"SELECT count() AS rows, min(event_id) AS min_id, max(event_id) AS max_id, sum(event_id) AS sum_id FROM {file_expr(fmt)} FORMAT JSONEachRow").stdout)
        stats={k:int(v) for k,v in stats.items()}
        assert stats=={'rows':N,'min_id':0,'max_id':N-1,'sum_id':N*(N-1)//2}
        invariants[fmt]={'inferred_types_match':True,**stats}
    (OUT/'projection-correctness.json').write_text(json.dumps(projection,indent=2))
    (OUT/'row-type-invariants.json').write_text(json.dumps(invariants,indent=2))
    (OUT/'correctness.json').write_text(json.dumps(correct,indent=2))
    # Warm the complete data files before measurements. Fresh processes do not clear the OS page cache.
    for fmt in exports:call(f"SELECT {', '.join(NAMES)} FROM {file_expr(fmt)} FORMAT Null",stdout=subprocess.DEVNULL)
    variants=[('Avro','two',['event_time','latency_ms']),('Parquet','two',['event_time','latency_ms']),
              ('Avro','all',NAMES),('Parquet','all',NAMES)]
    records=[]
    for rep in range(REPEATS):
        order=variants if rep%2==0 else list(reversed(variants))
        for fmt,shape,cols in order:
            q=f"SELECT {', '.join(cols)} FROM {file_expr(fmt)} FORMAT Null"
            rec=measured(q,f'run-{rep+1:02}-{fmt.lower()}-{shape}')
            rec.update(format=fmt,shape=shape,repeat=rep+1,sequence=len(records)+1)
            records.append(rec)
            (OUT/'raw-measurements.json').write_text(json.dumps(records,indent=2))
    # Untimed tracing validates logical file read calls separately from process physical-block counters.
    for fmt,shape,cols in variants:
        q=f"SELECT {', '.join(cols)} FROM {file_expr(fmt)} FORMAT Null"
        measured(q,f'trace-{fmt.lower()}-{shape}',trace=True)
        (OUT/f'explain-{fmt.lower()}-{shape}.txt').write_bytes(call('EXPLAIN PIPELINE '+q.removesuffix(' FORMAT Null')).stdout)
    summary=[]
    for fmt,shape,_ in variants:
        group=[r for r in records if r['format']==fmt and r['shape']==shape]
        row={'format':fmt,'shape':shape,'n':len(group)}
        for key in ['query_elapsed_seconds','clickhouse_peak_tracked_bytes','process_wall_seconds','user_cpu_seconds','system_cpu_seconds','peak_rss_kib','block_input_ops']:
            row[key]={'median':statistics.median(r[key] for r in group),'min':min(r[key] for r in group),'max':max(r[key] for r in group)}
        row['proc_read_bytes']=[r['proc_io']['read_bytes'] for r in group]
        summary.append(row)
    manifest['end_utc']=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2))
    (OUT/'summary.json').write_text(json.dumps(summary,indent=2))
    print(json.dumps({'manifest':manifest,'summary':summary},indent=2),flush=True)

if __name__=='__main__':main()
