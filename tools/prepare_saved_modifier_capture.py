"""Prepare five immutable r006 modifier scenes; no Godot process or generation."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
IDS=tuple('local_'+op+'_dummy' for op in ('ik_setup','look_at_setup','twist_setup','spring_setup','retarget_setup'))
NAME='Toolkit Saved Modifier Preflight'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def script_uid(path):
    sidecar=Path(str(path)+".uid")
    return sidecar if path.suffix==".gd" and sidecar.is_file() else None
def git(repo,*args):return subprocess.check_output(['git','-C',str(repo),*args],text=True).strip()
def admit_native(row,report):
    matches=[r for r in report['rows'] if r.get('id')==row['id'] and r.get('state')=='redo' and r.get('native') is False]
    if len(matches)!=3 or {r.get('fps') for r in matches}!={30,60,120}:raise ValueError('missing actual native redo rows')
    for r in matches:
        if r.get('case_failures')!=[] or r.get('case_engine_errors')!=[] or r.get('op')!=row['op'] or r.get('params')!=row['params'] or r.get('scene')!=row['states']['redo']:raise ValueError('native/public case mismatch')
    return matches

def prepare(repo,bundle,out):
    if out.exists():raise ValueError('preserve earlier preparation')
    context_path=bundle/'operation-context.json';native_path=bundle/'modifier-native.json'
    context=json.loads(context_path.read_text());native=json.loads(native_path.read_text())
    if context['tested_source']!='c5c248356c33b1277373a8d033e78b0243fc592c' or native.get('failures')!=[] or native.get('engine_errors')!=[]:raise ValueError('expected exact r006 source/native receipt')
    bridge={}
    for rel,d in context['dependencies'].items():
        if rel.startswith('addons/godot_ai_animation/'):
            p=repo/rel
            if git(repo,'hash-object','--path',rel,str(p))!=d['git_blob']:raise ValueError('production dependency changed: '+rel)
            bridge[rel]={'git_blob':d['git_blob'],'original_checkout_sha256':d['sha256'],'capture_checkout_sha256':sha(p)}
    manifests=list((bundle/'appdata/Godot/app_userdata').glob('*/rig_modifier_history.json'))
    if len(manifests)!=1 or sha(manifests[0])!=native['manifest_sha256']:raise ValueError('source saved manifest identity missing')
    src_app=manifests[0].parent;source=json.loads(manifests[0].read_text())
    cases=[]
    for key in IDS:
        rows=[r for r in source['cases'] if r['id']==key]
        if len(rows)!=1:raise ValueError('missing selected public case: '+key)
        row=rows[0];proof=admit_native(row,native);scene=src_app/row['states']['redo'].removeprefix('user://')
        if sha(scene)!=proof[0]['scene_sha256'] or any(r['scene_sha256']!=proof[0]['scene_sha256'] for r in proof):raise ValueError('saved scene differs from actual native receipt')
        if row['params'].get('active') is not False:raise ValueError('saved activation contract changed')
        cases.append((row,scene,proof))
    project=out/'project';app=out/'appdata/Godot/app_userdata'/NAME
    project.mkdir(parents=True);app.mkdir(parents=True)
    receipts={}
    def copy_resource(virtual,src,dst):
        if virtual in receipts:return
        dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
        receipts[virtual]={'path':virtual,'sha256':sha(src),'copied_sha256':sha(dst),'original':str(src)}
        uid=script_uid(src)
        if uid is not None:copy_resource(virtual+'.uid',uid,Path(str(dst)+'.uid'))
        if src.suffix not in ('.tscn','.tres'):return
        for path in re.findall(r'\[ext_resource[^\n]*path="([^"]+)"',src.read_text(encoding='utf-8')):
            if path.startswith('user://'):
                rel=Path(path.removeprefix('user://'));origin=src_app/rel;target=app/rel
            elif path.startswith('res://'):
                rel=Path(path.removeprefix('res://'));origin=repo/rel if path.startswith('res://addons/') else repo/'test_project'/rel;target=project/rel
            else:raise ValueError('unbound external resource '+path)
            if '..' in rel.parts or not origin.is_file():raise ValueError('unresolved saved resource '+path)
            copy_resource(path,origin,target)
    selected=[]
    for row,scene,proof in cases:
        target='res://scenes/'+row['id']+'.tscn';desired=project/'scenes'/(row['id']+'.tscn');copy_resource(target,scene,desired)
        item=dict(row);item['scene']={'path':target,'sha256':sha(desired)}
        item['native_reused_scope']='saved settings and native history; unchanged spring config effect requires fresh preflight'
        item['original_native_rows']=proof;selected.append(item)
    for helper in ('check_saved_modifier_capture.gd','render_saved_modifier_capture.gd','saved_media_framing.gd'):
        copy_resource('res://tools/'+helper,repo/'test_project/tools'/helper,project/'tools'/helper)
    dependencies=[{k:v for k,v in r.items() if k in ('path','sha256')} for r in receipts.values()]
    (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="'+NAME+'"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/stretch/mode="viewport"\nwindow/stretch/aspect="keep"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    result={'kind':'saved_modifier_capture_manifest','source_public':context['tested_source'],'capture_source':git(repo,'rev-parse','HEAD'),'source_context_sha256':sha(context_path),'source_manifest_sha256':sha(manifests[0]),'native828_sha256':sha(native_path),'engine':context['engine'],'core_commit':context['core_commit'],'bridge':bridge,'cases':selected,'files':receipts,'capture_dependencies':dependencies,'activation':{'saved_active':False,'runtime_active':[False,True],'runtime_influence':1.0},'limitations':'No fresh generation; native828 spring effect used changed force/collider. New preflight keeps unchanged settings and must pass before renderer work.'}
    (project/'modifier-manifest.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
    (out/'preparation.json').write_text(json.dumps({'manifest_sha256':sha(project/'modifier-manifest.json'),'project':str(project),'APPDATA':str(out/'appdata'),'scene_count':5,'production_blob_count':len(bridge),'files':receipts,'engine_pending':True},indent=2),encoding='utf-8')
    return result
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',type=Path,required=True);p.add_argument('--bundle',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args();r=prepare(a.repo.resolve(),a.bundle.resolve(),a.output.resolve());print(json.dumps({'cases':len(r['cases']),'production_blobs':len(r['bridge']),'state':'prepared_native_pending'}))
