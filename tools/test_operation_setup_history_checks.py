"""Synthetic control records only; actual Godot parse/public execution pending."""
import copy,hashlib,json,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
from types import SimpleNamespace
import asyncio
import operation_setup_history_checks as s
from setup_history_witness import SetupWitness

REQUEST={'op':'character_setup','player_path':'/RepairRigFixture/AnimationPlayer','skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D','duration':1.,'run_duration':.7,'idle_duration':2.,'speed':.7,'run_speed':1.4,'root_motion':True,'include_jump':True,'include_turn':True,'active':False,'samples':30}
SCENE='res://repair_motion_audit/20261024_123456/setup_secondary.tscn'
def fixture():
 marker={'token':'a'*32,'context_sha256':'b'*64,'run_id':'run','operation':'animation_motion.character_setup','scene':SCENE,'request':REQUEST,'phase':'after_write'}
 key={'time':0.,'transition':1.,'value_type':'Quaternion','value':{'type':'Quaternion','x':0.,'y':0.,'z':0.,'w':1.}}
 clip={'length':1.,'loop_mode':0,'tracks':[{'path':'Dummy/Skeleton3D:B-hips','type':2,'enabled':True,'interpolation':1,'node_class':'Skeleton3D','node_path':'Dummy/Skeleton3D','bone_index':0,'bone_name':'B-hips','property':'B-hips','property_type':'','keys':[key]}]}
 base={'scene':SCENE,'nodes':{'.':{'id':10,'name':'RepairRigFixture','class':'Node3D','properties':{},'children':['AnimationPlayer','Dummy']},'AnimationPlayer':{'id':11,'class':'AnimationPlayer','properties':{},'children':[]}},'resources':{},'files':{SCENE:'c'*64},'unsupported':[],'history':10,'global_history':2}
 base['nodes']['Dummy']={'id':15,'class':'Node3D','properties':{},'children':['Skeleton3D']};base['nodes']['Dummy/Skeleton3D']={'id':16,'class':'Skeleton3D','properties':{},'children':[],'bones':[{'name':'B-hips','parent':-1,'rest':{'type':'Transform3D','bytes_sha256':'d'*64},'position':{'type':'Vector3','bytes_sha256':'e'*64},'rotation':{'type':'Quaternion','bytes_sha256':'f'*64},'scale':{'type':'Vector3','bytes_sha256':'0'*64},'enabled':True}]}
 written=copy.deepcopy(base);written['history']=11;written['nodes']['AnimationTree']={'id':12,'class':'AnimationTree','properties':{'active':False,'tree_root':{'resource_id':'30'}},'children':[]};written['nodes']['.']['children'].append('AnimationTree');written['resources']={'30':{'class':'AnimationNodeBlendTree','path':SCENE+'::Tree','properties':{'nodes':{'resource_id':'31'}}},'31':{'class':'AnimationNodeAnimation','path':SCENE+'::Clip','properties':{'animation':'walk'}}}
 rows={}
 for phase in s.PHASES:
  after=phase not in ('before','after_dry','undone')
  rows[phase]={'mode':'setup_checkpoint','phase':phase,'marker':copy.deepcopy(marker),'stored':copy.deepcopy(written if after else base),'clips':{n:copy.deepcopy(clip)for n in ('idle','walk','run','jump','turn_left')}if after else{},'player_class':'AnimationPlayer','player_path':'AnimationPlayer','player_root':'..','scene_sha256':'c'*64}
 # Reload creates different native IDs while preserving stored graph aliases.
 saved=rows['persisted']['stored'];saved['nodes']['AnimationTree']['id']=99;saved['nodes']['AnimationTree']['properties']['tree_root']['resource_id']='90';saved['resources']['90']=saved['resources'].pop('30');saved['resources']['90']['properties']['nodes']['resource_id']='91';saved['resources']['91']=saved['resources'].pop('31')
 return rows

def bound():
 rows=fixture();events=[];begins=[];support=[]
 for index,phase in enumerate(s.PHASES):
  # All three history observations share one actual test invocation.
  sequence=4 if phase in ('before_undo','undone','redone')else {'before':0,'after_dry':1,'after_write':2,'persisted':5}[phase]
  starttime=10+sequence*10;test='test_public_setup_bundle_undo_redo'if sequence==4 else'test_public_setup_evidence_snapshot'
  row=rows[phase];row['marker']['phase']='after_write'if sequence==4 else phase
  e={'id':phase,'validator':'setup_history_v1','operation':'animation_motion.character_setup','driver':'test_animation_motion.gd','route':'public_test_run_inner_dispatch','run_id':'run','context_sha256':'b'*64,'test_run_begin_id':'begin'+str(sequence),'time_ns':starttime+1+(index-3 if sequence==4 else 0),'row':row}
  events.append(e)
  if not any(v['id']==e['test_run_begin_id']for v in begins):
   req={'suite':'animation_motion','test_name':test,'verbose':True};begins.append({'id':e['test_run_begin_id'],'request':req,'scene':SCENE,'driver':'mcp_motion_setup_secondary.py','execution_ns':starttime,'time_ns':starttime});support.append({'id':'end'+str(sequence),'public_tool':'test_run','test_run_begin_id':e['test_run_begin_id'],'request':req,'scene':SCENE,'driver':'mcp_motion_setup_secondary.py','execution_ns':starttime+5,'time_ns':starttime+5,'response':{'results':[{'suite':'animation_motion','test':test,'passed':True,'assertion_count':10}]}})
 public=[{'id':'dry','operation':'animation_motion.character_setup','driver':'mcp_motion_setup_secondary.py','route':'public_godot_ai','scene':SCENE,'params':dict(REQUEST,dry_run=True),'response':{'data':{'dry_run':True}},'execution_ns':18},{'id':'write','operation':'animation_motion.character_setup','driver':'mcp_motion_setup_secondary.py','route':'public_godot_ai','scene':SCENE,'params':REQUEST,'response':{'data':{'undoable':True}},'execution_ns':28}]
 support += [{'id':'save','public_tool':'scene_save','scene':SCENE,'driver':'mcp_motion_setup_secondary.py','request':{},'response':{'saved':True},'execution_ns':57},{'id':'open','public_tool':'scene_open','scene':SCENE,'driver':'mcp_motion_setup_secondary.py','request':{'path':SCENE,'force_reload':True},'response':{'opened':True},'execution_ns':58}]
 context={'run_id':'run','dependencies':{p:{'sha256':'a'*64,'git_blob':'a'*40}for p in s.DEPS}}
 return events[-1],context,events,public,begins,support

class Controls(unittest.TestCase):
 def test_complete_native_shapes_and_resource_id_reload(self):
  self.assertEqual(set(s.derive(fixture()).values()),{'pass'})
  self.assertEqual(set(s.verify_event(*bound())['checks'].values()),{'pass'})
 def test_case_local_mutations_not_hidden_by_suite_pass(self):
  for phase,key in [('after_dry','dry_run'),('undone','undo_redo'),('redone','undo_redo'),('persisted','save_reopen')]:
   rows=fixture();rows[phase]['stored']['nodes']['.']['properties']['foreign']=True
   self.assertEqual(s.derive(rows)[key],'fail',phase)
  rows=fixture();rows['after_write']['stored']['global_history']+=1
  self.assertEqual(s.derive(rows)['undo_redo'],'fail')
 def test_paths_bones_types_keys_and_nonfinite(self):
  for key,value in [('path','Missing:wrong'),('node_path','Other/Skeleton'),('node_class','Node2D'),('bone_index',-1),('bone_name','wrong'),('enabled',False),('type',0)]:
   rows=fixture();rows['persisted']['clips']['walk']['tracks'][0][key]=value
   self.assertEqual(s.derive(rows)['track_paths_types'],'fail',key)
  for key,value in [('time',False),('transition',float('nan')),('value_type','Vector3'),('value',{'type':'Quaternion','x':None,'y':0,'z':0,'w':1})]:
   rows=fixture();rows['persisted']['clips']['walk']['tracks'][0]['keys'][0][key]=value
   self.assertEqual(s.derive(rows)['track_paths_types'],'fail',key)
 def test_every_identity_and_secondary_contamination_blocks(self):
  for fault in ('missing','duplicate','source','context','request','scene','span','skip','secondary','save','reopen','order','phaseorder'):
   e,c,events,public,begins,support=copy.deepcopy(bound())
   if fault=='missing':events.pop(1)
   elif fault=='duplicate':events.append(copy.deepcopy(events[0]))
   elif fault=='source':c['dependencies'].pop(s.DEPS[0])
   elif fault=='context':events[0]['context_sha256']='c'*64
   elif fault=='request':public[1]['params']['samples']=31
   elif fault=='scene':public[1]['scene']='res://other.tscn'
   elif fault=='span':begins[0]['request']['test_name']='other'
   elif fault=='skip':support[0]['response']['results'][0]['skipped']=True
   elif fault=='secondary':public.append(dict(public[1],id='secondary',operation='animation_motion.secondary_motion',execution_ns=59))
   elif fault=='save':support[-2]['execution_ns']=61
   elif fault=='reopen':support[-1]['request']['force_reload']=False
   elif fault=='order':public[0]['execution_ns']=29
   elif fault=='phaseorder':events[3]['time_ns'],events[4]['time_ns']=events[4]['time_ns'],events[3]['time_ns']
   with self.assertRaises(ValueError,msg=fault):s.verify_event(e,c,events,public,begins,support)
 def test_snapshot_completeness_and_boolean_types(self):
  for fault in ('unsupported','history','class','nonfinite'):
   rows=fixture();r=rows['before']
   if fault=='unsupported':r['stored']['unsupported']=['unreadable']
   elif fault=='history':r['stored']['history']=True
   elif fault=='class':r['player_class']='Node'
   else:r['stored']['nodes']['.']['properties']['bad']=float('inf')
   self.assertTrue(all(v=='fail'for v in s.derive(rows).values()))
  rows=fixture();rows['persisted']['stored']['nodes']['AnimationTree']['properties']['active']=0
  self.assertEqual(s.derive(rows)['save_reopen'],'fail')
 def test_reload_alias_and_storage_changes_are_not_ignored(self):
  rows=fixture();state=rows['persisted']['stored']
  state['resources']['91']['properties']['animation']='run'
  self.assertEqual(s.derive(rows)['save_reopen'],'fail')
  rows=fixture();state=rows['persisted']['stored']
  state['resources']['90']['properties']['nodes']={'resource_id':'90'}
  self.assertEqual(s.derive(rows)['save_reopen'],'fail')
  rows=fixture();del rows['persisted']['stored']['nodes']['Dummy/Skeleton3D']['bones']
  self.assertTrue(all(v=='fail'for v in s.derive(rows).values()))
  rows=fixture();rows['persisted']['stored']['files'][SCENE]='0'*64
  self.assertTrue(all(v=='fail'for v in s.derive(rows).values()))
 def test_wrapper_never_dispatches_write_or_runs_secondary(self):
  async def run():
   with tempfile.TemporaryDirectory()as d:
    root=Path(d);ctx=root/'context.json';ctx.write_text(json.dumps({'run_id':'run'}));target=root/SCENE.removeprefix('res://');target.parent.mkdir(parents=True);target.write_text('[gd_scene format=3]\n[node name="RepairRigFixture" type="Node3D"]\n[node name="AnimationPlayer" type="AnimationPlayer" parent="."]\n');directory=root/'trace';directory.mkdir();calls=[]
    async def fake(client,name,request):
     calls.append((name,request))
     if name=='test_run':return {'results':[{'suite':request['suite'],'test':request['test_name'],'passed':True,'assertion_count':1}]}
     return {'saved':True}
    with patch.dict('os.environ',TOOLKIT_OPERATION_CONTEXT=str(ctx),TOOLKIT_OPERATION_TRACE_DIR=str(directory)),patch('setup_history_witness.call',fake):
     w=SetupWitness(None,SCENE,REQUEST,root);w.prepare(target)
     self.assertIn('PublicSetupBundleHistory',target.read_text());await w.snapshot('before');await w.snapshot('after_dry');await w.snapshot('after_write');result=await w.checkpoint()
     self.assertEqual(result['stage'],'before_secondary_motion');self.assertEqual(Path(result['scene_copy']).read_bytes(),target.read_bytes());self.assertFalse((directory/'active-setup-history.json').exists())
     self.assertTrue(all(name in ('test_run','scene_save','scene_open')for name,_ in calls));self.assertTrue(calls[-2][0]=='scene_open'and calls[-1][0]=='test_run')
  asyncio.run(run())
if __name__=='__main__':unittest.main()
