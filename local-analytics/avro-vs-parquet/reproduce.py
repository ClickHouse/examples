#!/usr/bin/env python3
"""Orchestrate the complete local-only lifecycle; Python standard library only."""
import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT=Path(__file__).resolve().parent
IMAGE='avro-parquet-clickhousectl:26.8.32.16'
CONTEXT='orbstack'
OWNER='clickhouse.avro-parquet-example'

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('action',choices=['all','setup','run','validate','cleanup','status'])
    ap.add_argument('--id',required=True,help='Unique lowercase run ID; never overwrite an earlier run')
    ap.add_argument('--resolver-input',choices=['26.8'],default='26.8')
    args=ap.parse_args()
    if not re.fullmatch('[a-z0-9][a-z0-9-]{0,63}',args.id):ap.error('Invalid run ID')
    run=ROOT/'artifacts'/args.id
    state_path=run/'state.json'
    docker=['docker','--context',CONTEXT]
    name=f'avro-parquet-{args.id}'
    env=dict(os.environ,DO_NOT_TRACK='1')
    def command(parts,label,*,capture=False):
        with (run/f'{label}.stdout').open('wb') as out,(run/f'{label}.stderr').open('wb') as err:
            p=subprocess.run(parts,cwd=ROOT,env=env,stdout=out,stderr=err)
        if p.returncode:raise RuntimeError(f'{label} exited {p.returncode}; inspect {run}/{label}.stderr')
        return (run/f'{label}.stdout').read_text().strip() if capture else None
    def save(state):state_path.write_text(json.dumps(state,indent=2)+'\n')
    def load():
        if not state_path.is_file():raise RuntimeError('Run not set up; use setup or all first')
        return json.loads(state_path.read_text())
    def owned():
        label=command(docker+['inspect',name,'--format','{{index .Config.Labels "clickhouse.avro-parquet-example"}}'],'ownership',capture=True)
        if label!=args.id:raise RuntimeError('Container ownership label does not match; no lifecycle mutation performed')
    def setup():
        run.mkdir(parents=True,exist_ok=False)
        selected=command(['docker','context','show'],'context',capture=True)
        # Explicit context avoids a remote or paid service selected in the user's default context.
        inspected=json.loads(command(['docker','context','inspect',CONTEXT],'context-inspect',capture=True))
        endpoint=inspected[0]['Endpoints']['docker']['Host']
        if not endpoint.startswith('unix://'):raise RuntimeError('Only the local OrbStack Unix socket is allowed')
        command(docker+['build','--build-arg',f'CLICKHOUSECTL_RESOLVER_INPUT={args.resolver_input}','-t',IMAGE,'.'],'build')
        command(docker+['run','-d','--name',name,'--label',f'{OWNER}={args.id}',
           '--cpus=2','--memory=3g','--memory-swap=3g','--pids-limit=256',
           '--network=none','--cap-drop=ALL','--security-opt=no-new-privileges',
           '-e','DO_NOT_TRACK=1',IMAGE],'container-create')
        save({'run_id':args.id,'container':name,'image':IMAGE,'context':CONTEXT,
              'resolver_input':args.resolver_input,'stage':'created','created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()})
        for filename in ['run.py']:
            command(docker+['cp',str(ROOT/filename),f'{name}:/work/{filename}'],f'copy-{filename}')
        command(docker+['cp',f'{name}:/opt/setup',str(run/'setup')],'copy-setup')
        command(docker+['inspect',name],'container-inspect')
        command(docker+['image','inspect',IMAGE],'image-inspect')
        state=load();state['stage']='ready';save(state)
    def execute():
        state=load()
        if state['stage']!='ready':raise RuntimeError('A measured run must start from ready; choose a new ID to rerun')
        owned()
        try:
            command(docker+['exec',name,'python3','/work/run.py'],'measured-run')
        finally:
            # Preserve partial correctness/measurement evidence even if the runner fails.
            command(docker+['cp',f'{name}:/work/results',str(run/'results')],'copy-results')
        state['stage']='measured';save(state)
    def validate():
        state=load()
        if state['stage'] not in ['measured','validated']:raise RuntimeError('No completed measured run available')
        command([sys.executable,str(ROOT/'analyze.py'),str(run)],'analysis')
        p=subprocess.run([sys.executable,str(ROOT/'validate.py'),str(run)],cwd=ROOT,env=env,capture_output=True,text=True)
        (run/'validation.stdout').write_text(p.stdout)
        (run/'validation.stderr').write_text(p.stderr)
        if p.returncode not in [0,2]:raise RuntimeError(f'Correctness validation failed; inspect {run}/validation.json')
        state['stage']='validated';state['validation_status']=json.loads((run/'validation.json').read_text())['status'];save(state)
        return p.returncode
    def cleanup():
        state=load();owned()
        command(docker+['stop',name],'container-stop')
        state['container_state']='stopped';save(state)
    result=0
    try:
        if args.action=='all':
            try:
                setup();execute();result=validate()
            finally:
                if state_path.exists():cleanup()
        elif args.action=='setup':setup()
        elif args.action=='run':execute()
        elif args.action=='validate':result=validate()
        elif args.action=='cleanup':cleanup()
        elif args.action=='status':load()
        print(json.dumps({'status':'completed' if result==0 else 'review_required','run_directory':str(run),'state':load()},indent=2))
    except Exception as e:
        print(json.dumps({'status':'failed','run_directory':str(run),'error':str(e)},indent=2))
        result=1
    return result

if __name__=='__main__':sys.exit(main())
