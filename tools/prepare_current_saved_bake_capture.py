"""Stage exact fresh public bake8 resources; no engine or parity approval."""
import argparse,json,re,shutil,subprocess
from pathlib import Path
from prepare_saved_bake_capture import IDS,NAME,user_relative,sha,read
SOURCE='26a35eb2dc7106cdd951b4771f9ec8c3971861bc'
DRIVER='mcp_rig_bake_restoration.py'
def admit(bundle):
 c=read(bundle/'operation-context.json');r=read(bundle/'bake-restoration.json');e=read(bundle/'execution.json');n=r.get('runtime',{})
 if c.get('tested_source')!=SOURCE or e.get('source')!=SOURCE or e.get('stage')!='complete':raise ValueError('current complete source required')
 if r.get('passed') is not True or n.get('failures')!=[] or n.get('engine_errors')!=[] or [n.get(k)for k in ('cases','saved_states','played_states')]!=[201,603,402]:raise ValueError('complete actual native201 required')
 drivers=[v for v in e.get('drivers',[])if v.get('driver')==DRIVER]
 if len(drivers)!=1 or drivers[0].get('returncode')!=0:raise ValueError('executed bake driver missing')
 calls=[]
 for f in sorted((bundle/'public-calls').glob('*.jsonl')):
  for line in f.read_text().splitlines():
   v=json.loads(line)
   if v.get('driver')==DRIVER:
    if v.get('context_sha256')!=sha(bundle/'operation-context.json') or v.get('run_id')!=c['run_id'] or v.get('route')!='public_godot_ai':raise ValueError('public context mismatch')
    calls.append(v)
 witnesses={}
 if len(r.get('suites',{}))!=6:raise ValueError('six original suites required')
 for name,result in r['suites'].items():
  found=[v for v in calls if v.get('kind')=='public_support_call'and v.get('public_tool')=='test_run'and v.get('request')=={'suite':name,'verbose':True}and v.get('response')==result]
  if len(found)!=1 or result.get('failed')!=0 or result.get('skipped')!=0:raise ValueError('original public suite witness missing')
  witnesses[name]=found[0]['id']
 manifest=Path(n['manifest_path']).resolve()
 if not manifest.is_relative_to(bundle.resolve()) or not manifest.is_file():raise ValueError('manifest escaped current bundle')
 rows=read(manifest)['cases'];selected=[]
 for key in IDS:
  found=[v for v in rows if v.get('id')==key]
  if len(found)!=1:raise ValueError('missing/duplicate selected case')
  row=found[0]
  if row.get('params',{}).get('op')!='bake_pose_sequence'or row['params'].get('fps')!=60 or set(row.get('states',{}))!={'do','undo','redo'}:raise ValueError('selected request/state changed')
  for virtual in [row['source'],*row['states'].values()]:
   f=(manifest.parent/user_relative(virtual)).resolve()
   if not f.is_relative_to(manifest.parent)or not f.is_file():raise ValueError('scene missing/escaped')
  selected.append(row)
 return c,r,manifest,selected,witnesses

def prepare(repo,bundle,out):
 if out.exists():raise ValueError('preserve earlier preparation')
 c,r,m,rows,witnesses=admit(bundle)
 external='addons/godot_ai_animation/utils/retarget_pose_restore.gd'
 blob=subprocess.check_output(['git','-C',str(repo),'rev-parse',SOURCE+':'+external],text=True).strip()
 if c['dependencies'].get(external,{}).get('git_blob')!=blob:raise ValueError('producer helper dependency missing')
 project=out/'project';app=out/'appdata/Godot/app_userdata'/NAME;project.mkdir(parents=True);app.mkdir(parents=True);files={}
 for row in rows:
  for virtual in [row['source'],*row['states'].values()]:
   rel=user_relative(virtual);src=m.parent/rel;dst=app/rel;dst.parent.mkdir(parents=True,exist_ok=True)
   refs=re.findall(r'\[ext_resource[^\n]*path="([^"]+)"',src.read_text())
   if set(refs)-{'res://'+external}:raise ValueError('unexpected scene dependency')
   shutil.copyfile(src,dst);files[virtual]={'original':str(src),'sha256':sha(src),'copied_sha256':sha(dst)}
 helpers=['test_project/tools/'+name for name in ('check_saved_bake_capture.gd','check_rig_bake_restoration.gd','modifier_native_reference.gd')]
 for rel in [external,*helpers]:
  virtual='res://'+rel.removeprefix('test_project/');dst=project/virtual[6:];dst.parent.mkdir(parents=True,exist_ok=True)
  dst.write_bytes(subprocess.check_output(['git','-C',str(repo),'show',SOURCE+':'+rel])if rel==external else(repo/rel).read_bytes());files[virtual]={'sha256':sha(dst),'origin':SOURCE if rel==external else str(repo/rel)}
  sidecar=Path(str(repo/rel)+'.uid')
  if sidecar.is_file():shutil.copyfile(sidecar,Path(str(dst)+'.uid'))
 (project/'project.godot').write_text('config_version=5\n[application]\nconfig/name="'+NAME+'"\n[display]\nwindow/size/viewport_width=1920\nwindow/size/viewport_height=1080\nwindow/stretch/mode="viewport"\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n')
 receipts={str(f.relative_to(bundle)):sha(f)for f in [bundle/'operation-context.json',bundle/'bake-restoration.json',bundle/'execution.json',m,*sorted((bundle/'public-calls').glob('*.jsonl'))]}
 result={'kind':'saved_current_bake_eight_manifest','state':'current_public_inputs_staged_native_capture_pending','source_public':SOURCE,'capture_source':subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip(),'context':c,'source_receipts':receipts,'public_suite_witnesses':witnesses,'cases':rows,'files':files,'runtime_receipt':r['runtime'],'scope':'Exact current saved inputs; suite witness is not new per-case parity/schedule admission. No media qualification.'}
 (project/'bake-manifest.json').write_text(json.dumps(result,indent=2));(out/'preparation.json').write_text(json.dumps({'state':result['state'],'manifest_sha256':sha(project/'bake-manifest.json'),'project':str(project),'APPDATA':str(out/'appdata')},indent=2));return result
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--repo',required=True,type=Path);p.add_argument('--bundle',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args();r=prepare(a.repo.resolve(),a.bundle.resolve(),a.output.resolve());print(json.dumps({'state':r['state'],'cases':len(r['cases'])}))
