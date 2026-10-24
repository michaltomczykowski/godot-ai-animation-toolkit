"""Require both released-core rendered receipts from this workflow's exact source."""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import subprocess

CORES={'4.2.1':'bfc264200584ea5823f18356acb164781f57796d',
       '4.3.0':'b82b5c519b1b17228f70d8effce1626f391bd1dd'}


def source_blobs(repo, source):
    output=subprocess.check_output(['git','ls-tree','-rz',source,'--',
        'addons/godot_ai_animation','tools','test_project/tests','test_project/tools'],cwd=repo)
    blobs={}
    for row in output.split(b'\0'):
        if not row: continue
        meta,path=row.split(b'\t',1)
        rel=path.decode()
        if rel.endswith('.uid') or Path(rel).suffix not in ('.gd','.py','.json','.tscn','.tres','.cfg','.godot'): continue
        mode,kind,blob=meta.decode().split()
        if kind != 'blob' or mode=='120000': raise ValueError('nonregular dependency '+rel)
        blobs[rel]=blob
    return blobs


def verify_identity(context, source, core, blobs):
    if (context.get('tested_source') != source or context.get('platform') != 'linux'
            or context.get('core_version') != core or context.get('core_commit') != CORES[core]
            or context.get('core_qualification') != 'released'
            or not str(context.get('engine','')).startswith('4.7.2.')):
        raise ValueError('rendered receipt source/platform/core/engine mismatch')
    actual={path:identity.get('git_blob') for path,identity in context.get('dependencies',{}).items()}
    if not blobs or actual != blobs:
        raise ValueError('rendered receipt dependency set/blobs differ from exact source')


def check(repo, source, receipts):
    from operation_preview_adapter import verify_preview_bundle
    source=subprocess.check_output(['git','rev-parse','--verify',source+'^{commit}'],cwd=repo,text=True).strip()
    blobs=source_blobs(repo,source)
    expected={'rendered-preview-linux-core-'+core for core in CORES}
    actual={path.name for path in receipts.iterdir()}
    if actual != expected: raise ValueError('missing/extra rendered matrix artifact directories')
    rows=[]
    for core in CORES:
        folder=receipts/('rendered-preview-linux-core-'+core)
        verified=verify_preview_bundle(folder)
        verify_identity(verified['context'],source,core,blobs)
        proof=verified['proof']
        if not proof.get('public_case_id') or any(proof.get('checks',{}).get(name) != 'pass'
                for name in ('file_effect','source_unchanged')):
            raise ValueError('strict rendered proof lacks actual file effect/source restoration')
        rows.append({'core_version':core,'core_commit':CORES[core],
            'public_case_id':proof['public_case_id'],'checks':proof['checks']})
    return {'tested_source':source,'platform':'linux','matrix':rows}


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--source',required=True)
    p.add_argument('--receipts',type=Path,required=True)
    p.add_argument('--repo',type=Path,default=Path('.'))
    args=p.parse_args()
    print('RENDERED_PREVIEW_MATRIX='+json.dumps(check(args.repo,args.source,args.receipts),sort_keys=True))
