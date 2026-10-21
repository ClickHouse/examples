#!/usr/bin/env python3
"""Prepare a pinned managed binary inside the disposable image, never on the host."""
import hashlib
import json
import os
import platform
from pins import BINARY_SHA256, ENGINE_VERSION
from pathlib import Path
import re
import subprocess

VERSION=ENGINE_VERSION
EXPECTED_SHA256=BINARY_SHA256[platform.machine()]
OUT=Path('/opt/setup')
OUT.mkdir(exist_ok=True)
ENV=dict(os.environ,DO_NOT_TRACK='1')

def command(args,label):
    p=subprocess.run(args,env=ENV,capture_output=True,text=True)
    (OUT/f'{label}.stdout').write_text(p.stdout)
    (OUT/f'{label}.stderr').write_text(p.stderr)
    if label in ['install','which','engine-version']:
        print(json.dumps({'step':label,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}),flush=True)
    if p.returncode:raise RuntimeError(f'{args}: {p.returncode}: {p.stderr}')
    return p.stdout.strip()

def sha(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''):h.update(b)
    return h.hexdigest()

cli=command(['clickhousectl','--version'],'cli-version')
assert cli=='clickhousectl 0.4.2',cli
command(['clickhousectl','local','install','--help'],'install-help')
use_help=command(['clickhousectl','local','use','--help'],'use-help')
assert '--no-global' in use_help
command(['clickhousectl','local','which','--help'],'which-help')
# Supported minor resolution avoids the unavailable exact-version metadata path.
# The already inspected output version and SHA are pinned before measurement.
RESOLVER_INPUT=os.environ.get('CLICKHOUSECTL_RESOLVER_INPUT','26.8')
assert RESOLVER_INPUT=='26.8'
command(['clickhousectl','local','install',RESOLVER_INPUT,'--json'],'install')
which=json.loads(command(['clickhousectl','local','which','--json'],'which'))
# CLI structured output may be an envelope. Resolve by exact documented key.
def resolve(value):
    if isinstance(value,dict):
        if isinstance(value.get('binary_path'),str):return value['binary_path']
        for v in value.values():
            found=resolve(v)
            if found:return found
    return None
binary=resolve(which)
assert binary and Path(binary).is_file(),which
version=command([binary,'local','--version'],'engine-version')
managed=sha(binary)
image=sha('/usr/bin/clickhouse')
record={'cli_version':cli,'engine_version':version,'binary_path':binary,
        'managed_binary_sha256':managed,'original_image_binary_sha256':image,
        'binary_identical_to_original_image':managed==image,'which_response':which,
        'telemetry_env':'DO_NOT_TRACK=1','resolver_input':RESOLVER_INPUT,'required_exact_version':VERSION,
        'required_binary_sha256':EXPECTED_SHA256,'binary_matches_declared_pin':managed==EXPECTED_SHA256,
        'condition_change':f'managed engine {VERSION}; original image 26.8.31.2',
        'default_selection':'first install sets default; no local use command invoked',
        'global_symlink_created':Path('/root/.local/bin/clickhouse').exists()}
(OUT/'managed.json').write_text(json.dumps(record,indent=2))
print(json.dumps(record,indent=2),flush=True)
# Refuse another patch or executable before use or measurements. Do not chase versions.
assert re.search(r'\b'+re.escape(VERSION)+r'\b',version),version
assert record['binary_matches_declared_pin'],record
assert not record['global_symlink_created']
