"""Run saved rig native proof and deliberate negative controls without rendering."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    for field in ('manifest','project-root','godot','output'): p.add_argument('--'+field,type=Path,required=True)
    p.add_argument('--checker',type=Path,default=Path(__file__).resolve().parents[1]/'test_project/tools/render_saved_rig_effects.gd')
    a=p.parse_args()
    a.output.mkdir(parents=True,exist_ok=False)
    manifest=json.loads(a.manifest.read_text(encoding='utf-8-sig'))
    summary={'passed':False,'manifest_sha256':sha(a.manifest),'controls':[]}
    for control in ('positive','inert','competing_player','wrong_scene_hash'):
        route=a.manifest
        if control=='wrong_scene_hash':
            corrupt=json.loads(json.dumps(manifest));corrupt['cases'][0]['scene']['sha256']='0'*64
            route=a.output/'wrong_scene_hash-manifest.json'
            route.write_text(json.dumps(corrupt,indent=2))
        target=a.output/(control+'.json')
        command=[str(a.godot),'--headless','--path',str(a.project_root),'--script',str(a.checker.resolve()),'--',str(route.resolve()),str(target.resolve()),'native']
        if control in ('inert','competing_player'):command.append(control)
        with target.with_suffix('.log').open('x',encoding='utf-8') as log:
            result=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=120)
        report=json.loads(target.read_text()) if target.exists() else {}
        runs=report.get('runs',[])
        identities={(r.get('operation'),r.get('take'),r.get('fps'))for r in runs}
        expected={(r['operation'],take,fps)for r in manifest['cases']for take in (1,2)for fps in (30,60,120)}
        if control=='wrong_scene_hash': expected={key for key in expected if key[0]!=manifest['cases'][0]['operation']}
        valid=(len(runs)==len(expected) and identities==expected and not report.get('engine_errors'))
        if control=='positive':valid=valid and result.returncode==0 and report.get('passed') is True and all(r['passed'] for r in runs)
        elif control=='inert':valid=valid and result.returncode==1 and report.get('passed') is False and all(not r['passed'] if r['operation']!='pose_apply' else r['passed'] for r in runs)
        elif control=='competing_player':valid=valid and result.returncode==1 and report.get('passed') is False and all('Nonfinite or competing writer' in r['failures'] for r in runs)
        else:valid=valid and result.returncode==1 and report.get('passed') is False and sum('Saved scene hash mismatch' in f for f in report.get('failures',[]))==6 and all(r['passed'] for r in runs)
        summary['controls'].append({'control':control,'passed':valid,'runs':len(runs),'failed_runs':sum(not r['passed'] for r in runs),'report_sha256':sha(target) if target.exists() else None})
        (a.output/'summary.json').write_text(json.dumps(summary,indent=2))
        print(json.dumps(summary['controls'][-1]),flush=True)
    summary['scenes_unchanged']=all(sha(Path(row['scene']['path']))==row['scene']['sha256'] and (not row.get('before') or sha(Path(row['before']['path']))==row['before']['sha256'])for row in manifest['cases'])
    summary['passed']=summary['scenes_unchanged'] and all(row['passed']for row in summary['controls'])
    (a.output/'summary.json').write_text(json.dumps(summary,indent=2))
    return int(not summary['passed'])

if __name__=='__main__':raise SystemExit(main())
