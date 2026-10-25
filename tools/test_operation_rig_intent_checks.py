"""Pure numeric and binding corruptions, not actual Godot execution proof."""
from copy import deepcopy
import importlib.util,math,sys,types,unittest
from pathlib import Path
import operation_rig_intent_checks as intent
import operation_rig_scene_history_checks as history
from test_operation_rig_scene_history_checks import fixture


def numeric_row(op='pose_apply',mode='local',variant=None):
 r=fixture(op,mode=mode,variant=variant)
 before=r['before']['snapshot'];node=before['children']['Skeleton']
 node['bones']=[dict(name=name,parent=-1,rest=intent.transform(a,(1,1,1),(i+1,2,0)),pose=intent.transform(p,(1.2,.8,1.1),(i+1.1,2.2,0)),enabled=i!=2,meta={'authored':'keep'})for i,(name,a,p)in enumerate(zip(('arm_L','arm_R','untouched'),(.2,-.1,.35),(.5,-.4,.7)))]
 generated=deepcopy(before)
 if op=='pose_apply':generated['children']['Skeleton']['bones'][0]['pose']=intent.transform(.8,(1.6,.6,1.3),(1.4,1.7,0))
 else:
  bone=dict(name='tool',parent=0 if r['variant']=='append'else-1,rest=intent.transform(math.pi/6,(1.4,.8,1.2),(.5,1,0),True),pose=intent.transform(.3,(1,1,1),(.5,1,0)),enabled=True,meta={})
  if r['variant']=='append':generated['children']['Skeleton']['bones'].append(bone)
  else:generated['children']['Generated']={'type':'Skeleton3D','children':{},'bones':[bone]}
 for stage in ('dry','refusal','undo'):r[stage]['state']['snapshot']=deepcopy(before)
 for stage in ('write','redo'):r[stage]['state']['snapshot']=deepcopy(generated)
 r['persist_undo']['snapshot']=deepcopy(before);r['persist_redo']['snapshot']=deepcopy(generated)
 if mode!='local':r.update(peer_before=deepcopy(before),peer_after=deepcopy(before),pristine=deepcopy(before))
 return r


def integrated():
 # Apply only the committed minimal patch in memory. No shared source mutation.
 text=Path(history.__file__).read_text();lines=Path('docs/patches/rig-two-intent-history-adapter.patch').read_text().splitlines()
 hunks=[];old=[];new=[]
 for line in lines:
  if line.startswith(('---','+++')):continue
  if line.startswith('@@'):
   if old:hunks.append(('\n'.join(old)+'\n','\n'.join(new)+'\n'))
   old=[];new=[]
  elif line.startswith(' '):old.append(line[1:]);new.append(line[1:])
  elif line.startswith('-'):old.append(line[1:])
  elif line.startswith('+'):new.append(line[1:])
 if old:hunks.append(('\n'.join(old)+'\n','\n'.join(new)+'\n'))
 for a,b in hunks:
  if text.count(a)!=1:raise ValueError('integration patch no longer exact')
  text=text.replace(a,b)
 module=types.ModuleType('integrated_rig_history');exec(compile(text,history.__file__,'exec'),module.__dict__);return module


def bound(row):
 module=integrated();req={'suite':row['suite'],'test_name':row['test'],'verbose':True}
 context={'run_id':'run','dependencies':{p:{'sha256':'a'*64,'git_blob':'b'*40}for p in module.DEPENDENCIES}}
 event={'validator':'rig_scene_history_v1','driver':'test_'+row['suite']+'.gd','route':'public_test_run_inner_dispatch','operation':'animation_rig.'+row['op'],'run_id':'run','test_run_begin_id':'begin','time_ns':15,'row':row}
 begin={'id':'begin','request':req,'execution_ns':10,'time_ns':10,'scene':row['scene']}
 end={'id':'end','public_tool':'test_run','test_run_begin_id':'begin','request':deepcopy(req),'execution_ns':20,'time_ns':20,'scene':row['scene'],'response':{'results':[{'suite':row['suite'],'test':row['test'],'passed':True,'assertion_count':42}]}}
 return module,event,context,[begin],[end]


class Controls(unittest.TestCase):
 def test_nine_supported_exact_cases(self):
  for mode in ('local','locked','editable'):
   for op,variant in [('pose_apply','apply'),('rig_chain','create'),('rig_chain','append')]:
    row=numeric_row(op,mode,variant);self.assertEqual(intent.effect(row),'pass')
    m,*args=bound(row);self.assertEqual(set(m.verify_event(*args)['checks'].values()),{'pass'})
 def test_pose_wrong_request_inert_rotation_offset_scale_and_other_bones(self):
  for fault in ('request','inert','rotation','offset','scale','rest','otherbone','enabled'):
   r=numeric_row();bone=r['write']['state']['snapshot']['children']['Skeleton']['bones'][0]
   if fault=='request':r['request']['pose']['bones']['arm_L']['rotation']['z']=0
   elif fault=='inert':bone['pose']=deepcopy(r['before']['snapshot']['children']['Skeleton']['bones'][0]['pose'])
   elif fault=='rotation':bone['pose']['basis']=intent.transform(.6,(1.6,.6,1.3),(0,0,0))['basis']
   elif fault=='offset':bone['pose']['origin']['x']=.4
   elif fault=='scale':bone['pose']['basis']['z']['z']=1
   elif fault=='rest':bone['rest']['origin']['y']=99
   elif fault=='otherbone':r['write']['state']['snapshot']['children']['Skeleton']['bones'][1]['pose']['origin']['x']=99
   else:bone['enabled']=False
   if fault=='request':
    with self.assertRaises(ValueError):intent.effect(r)
   else:self.assertEqual(intent.effect(r),'fail',fault)
 def test_chain_exact_rest_parent_and_preserved_source(self):
  for fault in ('parent','name','position','matrix','scalingorder','missing','extra','peer'):
   r=numeric_row('rig_chain',variant='append');bones=r['write']['state']['snapshot']['children']['Skeleton']['bones'];bone=bones[-1]
   if fault=='parent':bone['parent']=1
   elif fault=='name':bone['name']='other'
   elif fault=='position':bone['rest']['origin']['y']=.5
   elif fault=='matrix':bone['rest']['basis']['y']['x']=0
   elif fault=='scalingorder':bone['rest']=intent.transform(math.pi/6,(1.4,.8,1.2),(.5,1,0),False)
   elif fault=='missing':bones.pop()
   elif fault=='extra':bones.append(deepcopy(bone))
   else:bones[0]['rest']['origin']['x']=9
   self.assertEqual(intent.effect(r),'fail',fault)
 def test_saved_and_redo_intent_checked_independently(self):
  for stage in ('redo','persist_redo'):
   r=numeric_row();snap=r[stage]['snapshot']if stage=='persist_redo'else r[stage]['state']['snapshot'];snap['children']['Skeleton']['bones'][0]['pose']['origin']['y']=2
   self.assertEqual(intent.effect(r),'fail')
 def test_scope_pending_not_generic_duplication(self):
  for op,kind,variant in [('pose_apply','2d','apply'),('pose_apply','3d','mirror'),('rig_chain','3d','subtree'),('rig_chain','2d','create')]:self.assertEqual(intent.effect(fixture(op,kind=kind,variant=variant)),'pending')
  r=numeric_row();r['write']['response']={'data':{'anything':'response content ignored'}};self.assertEqual(intent.effect(r),'pass')
 def test_public_source_case_order_and_original_gates_cannot_be_bypassed(self):
  for fault in ('source','operation','request','scene','span','skip','history','errors'):
   m,e,c,b,s=bound(numeric_row())
   if fault=='source':c['dependencies'].pop('tools/operation_rig_intent_checks.py')
   elif fault=='operation':e['operation']='animation_rig.rig_chain'
   elif fault=='request':e['row']['request']['blend']=.5
   elif fault=='scene':s[0]['scene']='res://wrong.tscn'
   elif fault=='span':e['time_ns']=25
   elif fault=='skip':s[0]['response']['results'][0]['skipped']=True
   elif fault=='history':e['row']['write']['state']['version']=9
   else:e['row']['errors_after']=1;e['row']['errors']=['error']
   if fault in ('skip','history','errors'):self.assertEqual(m.verify_event(e,c,b,s)['checks']['valid_effect'],'fail')
   else:
    with self.assertRaises(ValueError,msg=fault):m.verify_event(e,c,b,s)
 def test_nonfinite_and_boolean_numbers_rejected(self):
  for value in (True,float('nan'),float('inf')):
   r=numeric_row();r['write']['state']['snapshot']['children']['Skeleton']['bones'][0]['pose']['origin']['x']=value;self.assertEqual(intent.effect(r),'fail')
if __name__=='__main__':unittest.main()
