#!/usr/bin/env python3
"""Cheap synthetic-evidence control tests; no benchmark or Docker access."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parent
ART=ROOT/'artifacts'
ART.mkdir(exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='validator-fixture-',dir=ART) as temp:
    run=Path(temp);out=run/'results';out.mkdir()
    for name in ['manifest.json','correctness.json','projection-correctness.json','raw-measurements.json','validated-file-reads.json','schema-resolution.json','io-counter-control.json','row-type-invariants.json']:
        shutil.copyfile(ROOT/'reference'/'cli-26.8.32.16'/name,out/name)
    # Copy recorded current evidence, then mutate it to exercise validator failure states.
    # These fixtures are not evidence of a new benchmark run.
    def check(label,status,reason=None):
        p=subprocess.run([sys.executable,str(ROOT/'validate.py'),str(run)],capture_output=True,text=True)
        value=json.loads((run/'validation.json').read_text())
        assert value['status']==status,(label,value)
        if reason:
            assert any(reason in s for s in value['hard_errors']+value['review_reasons']),(label,value)
        results.append({'test':label,'expected':status,'observed':value['status'],'exit_code':p.returncode,'passed':True})
    check('synthetic complete evidence','pass')
    raw_path=out/'raw-measurements.json';raw=raw_path.read_text()
    x=json.loads(raw);x.pop();raw_path.write_text(json.dumps(x))
    check('missing measured sample','failed','exactly 28 measured samples')
    raw_path.write_text(raw)
    corr_path=out/'correctness.json';corr=corr_path.read_text();x=json.loads(corr)
    x['files']['Avro']['ordered_rowbinary_sha256']='corrupted';corr_path.write_text(json.dumps(x))
    check('corrupted complete-output hash','failed','exact reference logical-output invariant')
    corr_path.write_text(corr)
    x=json.loads(raw);x[0]['proc_io']['read_bytes']=4096;raw_path.write_text(json.dumps(x))
    check('changed warm I/O regime','review_required','warm guest-block-I/O regime')
report={'status':'pass','scope':'Synthetic validator fixtures only; no CLI-managed measurement claimed','tests':results}
(ART/'validator-self-test.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
