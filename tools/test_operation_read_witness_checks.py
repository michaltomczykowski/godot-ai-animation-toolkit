import copy
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import AsyncMock,patch
import operation_read_witness_checks as w
import inspect_read_witness as wrapper
import test_inspect_numeric_reference as numeric


def snapshot(scene,context):
 three=scene.endswith('repair_motion_fixture.tscn');player='WalkAnim' if three else 'AnimationPlayer'
 names=['.','Dummy','Dummy/Skeleton3D',player,'Floor','Cam','Sun','Ui','Ui/Title'] if three else ['.','Character','OtherCharacter',player]
 nodes={p:dict(id=i+1,name=p.split('/')[-1],**{'class':'Node3D' if three else 'Node2D'},properties={'stored':True},children=[]) for i,p in enumerate(names)}
 for p in names[1:]:nodes[p.rsplit('/',1)[0] if '/' in p else '.']['children'].append(p.split('/')[-1])
 clipnames=['repair_probe_walk','repair_probe_walk_24','repair_probe_run','repair_probe_run_24','walk'] if three else ['walk','run','idle','jump','lean']
 resources={str(i+1):{'class':'Animation','path':'','properties':{'length':{'type':'float','bytes_sha256':'a'*64},'loop_mode':1,'tracks/0/type':0}} for i in range(5)}
 resources['6']={'class':'AnimationLibrary','path':'','properties':{'_data':{'dictionary':[]}}}
 nodes[player].update(playback={'current':'','assigned':'','playing':False,'position':None},libraries={'':{'resource_id':'6'}},clips={n:{'resource_id':str(i+1)} for i,n in enumerate(clipnames)})
 if three:
  from operation_bounded_read_checks import EXPECTED_BONES
  nodes['Dummy/Skeleton3D']['bones']=[dict(name=n,parent=-1,rest={'type':'Transform3D','bytes_sha256':'a'*64},position={'type':'Vector3','bytes_sha256':'b'*64},rotation={'type':'Quaternion','bytes_sha256':'c'*64},scale={'type':'Vector3','bytes_sha256':'d'*64},enabled=True) for n in EXPECTED_BONES]
 files={scene:'a'*64}
 if three:files['res://models/human_dummy/HumanCharacterDummy_F.fbx']='a'*64
 return dict(scene=scene,nodes=nodes,resources=resources,files=files,unsupported=[],history=5,global_history=2)


def fixture(op='describe'):
 key='animation_inspect.'+op;driver,scene,request=w.fixed(key,'valid')
 paths=w.BASE_DEPS+('tools/'+driver,'test_project/'+scene.removeprefix('res://'),'test_project/models/human_dummy/HumanCharacterDummy_F.fbx','test_project/tools/repair_motion_playback.gd','tools/operation_bounded_read_checks.py')
 ctx={'run_id':'run','dependencies':{p:dict(sha256='a'*64,git_blob='b'*40) for p in paths}}
 events=[];public=[];begins=[];support=[]
 for j,stage in enumerate(('valid','refusal')):
  offset=j*10;wall=j*100;token=str(j+1)*32
  marker=dict(token=token,context_sha256='c'*64,run_id='run',operation=key,request=w.fixed(key,stage)[2],scene=scene,stage=stage)
  for phase,test,at,time in [('begin','test_begin',1,15),('end','test_end',5,35)]:
   begin_id=stage+'-'+phase;req={'suite':w.SUITE,'test_name':test,'verbose':True}
   begins.append(dict(id=begin_id,driver=driver,scene=scene,request=req,execution_ns=offset+at-1,time_ns=wall+time-5))
   support.append(dict(id=begin_id+'-done',test_run_begin_id=begin_id,public_tool='test_run',driver=driver,scene=scene,request=req,execution_ns=offset+at+1,time_ns=wall+time+5,response={'results':[dict(suite=w.SUITE,test=test,passed=True,assertion_count=2)]}))
   row=dict(op=op,marker=copy.deepcopy(marker),phase=phase)
   if phase=='end':
    state=snapshot(scene,ctx);row.update(before=state,after=copy.deepcopy(state),begin_marker=copy.deepcopy(marker),errors=[],errors_before=0,errors_after=0,snapshot_schema='stored_graph_v1')
    if stage=='valid' and op in ('sample','motion_audit'):
     row.update(reference=numeric.reference(op),after_reference=copy.deepcopy(state),reference_errors=[])
   events.append(dict(id=stage+'-'+phase+'-raw',validator='inspect_read_witness_v1',driver='test_inspect_read_witness.gd',route='public_test_run_inner_dispatch',operation=key,run_id='run',context_sha256='c'*64,test_run_begin_id=begin_id,time_ns=wall+time,row=row))
  if stage=='valid':result=numeric.sample_result(numeric.reference('sample')) if op=='sample' else numeric.audit_result(numeric.reference()) if op=='motion_audit' else {'ok':True}
  else:
   from operation_inspect_checks import ERROR_CODES
   result={'error':ERROR_CODES.get(op,'NODE_NOT_FOUND')+': expected'}
  public.append(dict(id=stage+'-operator',operation=key,driver=driver,public_tool='custom_animation_inspect',route='public_godot_ai',scene=scene,params=marker['request'],response=result,execution_ns=offset+3))
 return events[1],ctx,events,public,begins,support

class ReadWitnessTests(unittest.TestCase):
 def test_all_eleven_fixed_positive_refusal_pairs(self):
  for op in ('describe','timeline','audit','compare','stats','motion_report','dry_run','help','rig_profile','sample','motion_audit'):
   with self.subTest(op=op):self.assertEqual(set(w.verify_pair(*fixture(op))['checks'].values()),{'pass'})
 def test_source_clip_pose_player_history_file_changes_fail(self):
  for field in ('clip','pose','player','history','file','node','resource'):
   args=fixture('sample');row=args[0]['row'];state=row['after']
   if field=='clip':state['nodes']['WalkAnim']['clips'].pop('walk')
   elif field=='pose':state['nodes']['Dummy/Skeleton3D']['bones'][0]['rotation']['bytes_sha256']='e'*64
   elif field=='player':state['nodes']['WalkAnim']['playback']['playing']=True
   elif field=='history':state['history']+=1
   elif field=='file':state['files']['res://repair_motion_fixture.tscn']='e'*64
   elif field=='node':state['nodes']['Floor']['properties']['stored']=False
   else:state['resources']['1']['properties']['tracks/0/type']=2
   with self.subTest(field=field):self.assertEqual(w.verify_pair(*args)['checks']['source_unchanged'],'fail')
 def test_unreadable_state_stays_pending_and_refusal_also_required(self):
  args=fixture();args[0]['row']['before']['unsupported']=['unreadable_Player'];args[0]['row']['after']['unsupported']=['unreadable_Player']
  self.assertEqual(w.verify_pair(*args)['checks']['source_unchanged'],'pending')
  args=fixture();args[2][-1]['row']['after']['history']=99
  self.assertEqual(w.verify_pair(*args)['checks']['source_unchanged'],'fail')
 def test_incomplete_resource_capture_never_promoted(self):
  args=fixture()
  for field in ('before','after'):args[0]['row'][field]['resources']['1']['properties']={}
  self.assertEqual(w.verify_pair(*args)['checks']['source_unchanged'],'pending')
 def test_actual_logger_and_wrong_refusal_code_fail(self):
  args=fixture();args[2][-1]['row'].update(errors_after=1,errors=[{'message':'engine error'}])
  self.assertEqual(w.verify_pair(*args)['checks']['reported_errors'],'fail')
  args=fixture();args[3][-1]['response']['error']='SOME_UPPER: not actual code'
  self.assertEqual(set(w.verify_pair(*args)['checks'].values()),{'fail'})
 def test_missing_wrong_or_duplicate_actual_call(self):
  for fault in ('missing','duplicate','wrong'):
   args=list(fixture())
   if fault=='missing':args[3]=args[3][1:]
   elif fault=='duplicate':args[3].append(copy.deepcopy(args[3][0]))
   else:args[3][0]['params']={'op':'stats'}
   with self.subTest(fault=fault),self.assertRaises(ValueError):w.verify_pair(*args)
 def test_wrong_source_context_span_and_token(self):
  for fault in ('source','dependency','span','token','context','scene'):
   args=fixture()
   if fault=='source':args[0]['driver']='wrong.gd'
   elif fault=='dependency':args[1]['dependencies'].pop(w.BASE_DEPS[0])
   elif fault=='span':args[5][0]['response']['results'][0]['passed']=False
   elif fault=='token':args[0]['row']['marker']['token']='f'*32
   elif fault=='context':args[0]['row']['marker']['context_sha256']='f'*64
   else:args[4][0]['scene']='res://other.tscn'
   with self.subTest(fault=fault),self.assertRaises(ValueError):w.verify_pair(*args)
 def test_missing_reference_stays_pending_corrupt_reference_fails(self):
  args=fixture('sample');args[0]['row'].pop('reference')
  self.assertEqual(w.verify_pair(*args)['checks']['valid_effect'],'pending')
  for field in ('value','clock','sha','pollution'):
   args=fixture('sample');row=args[0]['row']
   if field=='value':args[3][0]['response']['bones']['B-foot.L']['positions'][0][1]=.5
   elif field=='clock':row['reference']['frames'][1]['position']=0.
   elif field=='sha':row['reference']['scene_sha256']='e'*64
   else:row['after_reference']['history']=6
   self.assertEqual(w.verify_pair(*args)['checks']['valid_effect'],'fail')

class DriverWrapperTests(unittest.IsolatedAsyncioTestCase):
 async def test_original_operator_invoked_once_with_exact_request_and_cleanup(self):
  with TemporaryDirectory() as d:
   context=Path(d)/'ctx.json';context.write_text(json.dumps({'run_id':'run'}))
   begin={'results':[dict(suite=wrapper.SUITE,test='test_begin',passed=True,assertion_count=1)]};end={'results':[dict(suite=wrapper.SUITE,test='test_end',passed=True,assertion_count=2)]}
   request={'op':'sample','samples':8};operator={'error':'NODE_NOT_FOUND: expected'}
   with patch.dict('os.environ',{'TOOLKIT_OPERATION_CONTEXT':str(context),'TOOLKIT_OPERATION_TRACE_DIR':d}),patch.object(wrapper,'call',new=AsyncMock(side_effect=[begin,operator,end])) as call:
    result,token=await wrapper.witnessed_call(object(),request,'res://fixture.tscn','refusal')
    self.assertEqual(result,operator);self.assertEqual(len(token),32);self.assertEqual(call.await_count,3);self.assertEqual(call.call_args_list[1].args[1:],('custom_animation_inspect',request));self.assertFalse((Path(d)/'active-inspect-read.json').exists())
 async def test_begin_failure_does_not_retry_or_invoke_operator(self):
  with TemporaryDirectory() as d:
   context=Path(d)/'ctx.json';context.write_text(json.dumps({'run_id':'run'}))
   with patch.dict('os.environ',{'TOOLKIT_OPERATION_CONTEXT':str(context),'TOOLKIT_OPERATION_TRACE_DIR':d}),patch.object(wrapper,'call',new=AsyncMock(return_value={'results':[]})) as call:
    with self.assertRaises(RuntimeError):await wrapper.witnessed_call(object(),{'op':'stats'},'res://fixture.tscn','valid')
    self.assertEqual(call.await_count,2);self.assertTrue(all(x.args[1]=="test_run" for x in call.call_args_list));self.assertFalse((Path(d)/'active-inspect-read.json').exists())
if __name__=='__main__':unittest.main()
