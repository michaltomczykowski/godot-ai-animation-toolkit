"""Offline historical audit only: preserve tested source/context and raw bundles."""
import argparse
import hashlib
import json
from pathlib import Path
from collections import Counter
from operation_motion_sequence_native_checks import verify_event

def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda:f.read(1048576),b''):h.update(block)
    return h.hexdigest()

def audit(bundle,output):
    original_path=bundle/'operation-case-results.json'
    original=json.loads(original_path.read_text(encoding='utf-8'))
    context=json.loads((bundle/'operation-context.json').read_text(encoding='utf-8'))
    artifacts=[]
    for a in original['raw_artifacts']:
        path=(bundle/a['path']).resolve()
        if not path.is_relative_to(bundle.resolve()) or sha(path)!=a['sha256']:raise ValueError('raw artifact identity mismatch: '+str(path))
        artifacts.append(dict(path=a['path'],sha256=a['sha256']))
    files=sorted((bundle/'public-calls').glob('*.jsonl'))
    begins=[];support=[]
    for path in files:
        for line in path.open(encoding='utf-8'):
            e=json.loads(line)
            if e.get('kind')=='public_test_run_begin':begins.append(e)
            elif e.get('kind')=='public_support_call' or (e.get('kind')=='native_saved_output' and 'res://tools/check_motion_sequence_history.gd' in e.get('command',[])):support.append(e)
    byid={r['raw_event_id']:r for r in original['cases'] if r.get('raw_event_id')}
    changed=[];seen=set()
    for path in files:
        for line in path.open(encoding='utf-8'):
            if 'motion_sequence_history_v1' not in line:continue
            e=json.loads(line)
            if e.get('validator')!='motion_sequence_history_v1':continue
            if e['id'] in seen:raise ValueError('duplicate raw case event')
            seen.add(e['id']);proof=verify_event(e,context,begins,support)
            old=byid[e['id']];new=proof['checks']
            changed.append(dict(raw_event_id=e['id'],case_id=e['row']['case_id'],operation=e['operation'],before=old['checks'],after=new))
            old['checks']=new;old['limits']=proof['limits']
    if len(seen)!=273:raise ValueError('expected exact273 raw history cases')
    def failures(cases):return Counter(k for c in cases for k,v in c['checks'].items() if k!='mcp_invocation' and v=='fail')
    auditor={p.name:sha(p) for p in (Path(__file__),Path(__file__).with_name('operation_motion_sequence_history_checks.py'),Path(__file__).with_name('operation_motion_sequence_native_checks.py'))}
    result=dict(kind='historical_operation_recollection',original_tested_source=context['tested_source'],original_report_sha256=sha(original_path),original_context_sha256=sha(bundle/'operation-context.json'),auditor_file_sha256=auditor,verified_raw_artifacts=artifacts,changed_motion_sequence_cases=changed,remaining_derived_failures=dict(failures(original['cases'])),cases=original['cases'],qualification='pending',limits='Historical raw evidence interpreted with named adapter byte hashes. No new engine execution, changed source label or present-candidate qualification. Unrelated cases remain verbatim.')
    output.mkdir(parents=True,exist_ok=False)
    (output/'recollection.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    print(json.dumps(dict(bundle=str(bundle),source=context['tested_source'],cases=len(original['cases']),motion_sequence_cases=len(seen),remaining_failures=result['remaining_derived_failures'],output_sha256=sha(output/'recollection.json'))))

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--bundle',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();audit(a.bundle,a.output)
