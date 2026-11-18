import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from operation_pose_blend_refusal_checks import derive,verify_event,directory_bytes,observe_missing_pose,DEPENDENCIES
import test_operation_fx_intention_checks as fx_tests
from operation_fx_intention_checks import verify_event as fx_verify


def pose_fixture():
 directory='res://animation_toolkit/repair_audit/rig_poses_20261024_123456';scene='res://repair_rig_audit/20261024_123456/poses.tscn'
 pose={'format':'godot-ai-animation-pose','version':1,'rest_relative':True,'source':'fixture','bones':{'actual-bone':{'rotation':{'kind':'quaternion','x':0,'y':0,'z':0,'w':1}}}}
 raw=json.dumps(pose).encode();file={'type':'file','bytes_hex':raw.hex(),'sha256':hashlib.sha256(raw).hexdigest()}
 snapshot={'exists':True,'entries':{name:copy.deepcopy(file) for name in ('rest.json','arm.json','half.json')}}
 producer={'op':'pose_blend','pose_dir':directory,'from':'rest','to':'arm','factor':.5,'name':'half'}
 request={**producer,'from':'definitely_missing','overwrite':True}
 made={'saved_path':directory+'/half.json','factor':.5,'undoable':False,'pose':pose}
 refused={'error':'INVALID_PARAMS: Pose file not found: '+directory+'/definitely_missing.json'}
 row={'operation':'animation_rig.pose_blend','scene':scene,'directory':directory,'request':request,'result':refused,'producer_request':producer,'producer_response':made,'before':snapshot,'after':copy.deepcopy(snapshot),'before_execution_ns':20,'after_execution_ns':40}
 event={'operation':row['operation'],'driver':'mcp_rig_pose_crud.py','validator':'pose_blend_refusal_v1','route':'public_godot_ai','row':row,'checks':derive(row),'execution_ns':50,'context_sha256':'a'*64,'run_id':'fixture-run'}
 context={'run_id':'fixture-run','dependencies':dict.fromkeys(DEPENDENCIES,{})}
 def call(identity,request,response,execution):return {'id':identity,'operation':row['operation'],'public_tool':'custom_animation_rig','request':request,'params':request,'response':response,'driver':'mcp_rig_pose_crud.py','route':'public_godot_ai','scene':scene,'execution_ns':execution,'run_id':'fixture-run','context_sha256':'a'*64}
 calls=[call('producer',producer,made,10),call('refusal',request,refused,30)]
 opens=[{'id':'open','public_tool':'scene_open','request':{'path':scene},'response':{'opened':True},'execution_ns':1,'run_id':'fixture-run','context_sha256':'a'*64}]
 return row,event,context,calls,opens

class SpriteFramesChannel(unittest.TestCase):
 def test_actual_resource_channel_four_layouts_with_no_animation_track_claim(self):
  for mode in ('new','overwrite','missing_library','instanced'):
   row,c,e,b,s=fx_tests.FxIntentionTests().fixture('sprite_frames',mode)
   row['generated']['clips']=copy.deepcopy(row['before']['clips'])
   row['generated']['frames']={'generated':{'fps':12,'loop':True,'frames':[]}}
   row['after_probe']=copy.deepcopy(row['generated']);row['redone']=copy.deepcopy(row['generated']);row['persist_redo']['snapshot']=copy.deepcopy(row['generated'])
   self.assertEqual(fx_verify(e,c,b,s)['checks']['track_paths_types'],'pass')
   self.assertNotIn('generated',row['generated']['clips'])
 def test_resource_types_regions_path_and_source_corruptions_reject(self):
  for kind in ('resource','cell','region','texture','path','source'):
   row,c,e,b,s=fx_tests.FxIntentionTests().fixture('sprite_frames')
   if kind=='resource':row['intention']['resource_class']='Texture2D'
   elif kind=='cell':row['intention']['cells'][0]['class']='ImageTexture'
   elif kind=='region':row['intention']['cells'][1]['region'][0]=0
   elif kind=='texture':row['intention']['cells'][0]['atlas']='wrong.png'
   elif kind=='path':row['request']['sprite_path']='/Main/OtherSprite'
   else:row['input_files_after']['res://tests/fixtures/sheet.png']='f'*64
   if kind=='path':
    with self.assertRaises(ValueError):fx_verify(e,c,b,s)
   else:self.assertEqual(fx_verify(e,c,b,s)['checks']['track_paths_types'],'fail')

class PoseBlendRefusal(unittest.TestCase):
 def test_exact_actual_typed_refusal_binds_existing_output_and_calls(self):
  row,e,c,calls,opens=pose_fixture();proof=verify_event(e,c,calls,opens)
  self.assertEqual(proof['checks'],{'typed_errors':'pass'});self.assertEqual(proof['public_case_ids'],['producer','refusal'])
  self.assertNotIn('valid_effect',proof['checks'])
 def test_wrong_unknown_or_generic_error_never_passes(self):
  for error in ['UNKNOWN: missing','INVALID_PARAMS: other','TRANSPORT_OUTCOME_UNKNOWN: disconnected',{'code':'INVALID_PARAMS','message':'wrong file'}]:
   row,*_=pose_fixture();row['result']={'error':error};self.assertEqual(derive(row)['typed_errors'],'fail')
 def test_changed_existing_output_or_extra_directory_entry_rejects(self):
  row,*_=pose_fixture();raw=b'changed';row['after']['entries']['half.json'].update(bytes_hex=raw.hex(),sha256=hashlib.sha256(raw).hexdigest())
  self.assertEqual(derive(row)['typed_errors'],'fail')
  row,*_=pose_fixture();row['after']['entries']['surprise']={'type':'directory'}
  with self.assertRaises(ValueError):derive(row)
 def test_bad_file_hash_request_or_producer_rejects(self):
  row,*_=pose_fixture();row['before']['entries']['half.json']['sha256']='f'*64
  with self.assertRaises(ValueError):derive(row)
  row,*_=pose_fixture();row['request']['from']='rest'
  with self.assertRaises(ValueError):derive(row)
  row,*_=pose_fixture();row['producer_response']['pose']={}
  self.assertEqual(derive(row)['typed_errors'],'fail')
 def test_source_dependency_timing_context_and_call_binding(self):
  for field,value in [('driver','other.py'),('operation','animation_rig.pose_save'),('run_id','other')]:
   row,e,c,calls,opens=pose_fixture();e[field]=value
   with self.assertRaises(ValueError):verify_event(e,c,calls,opens)
  row,e,c,calls,opens=pose_fixture();c['dependencies'].pop(DEPENDENCIES[0])
  with self.assertRaises(ValueError):verify_event(e,c,calls,opens)
  for index,field,value in [(1,'response',{'error':'UNKNOWN'}),(1,'params',{}),(0,'execution_ns',25),(1,'execution_ns',45),(1,'context_sha256','f'*64)]:
   row,e,c,calls,opens=pose_fixture();calls[index][field]=value
   with self.assertRaises(ValueError):verify_event(e,c,calls,opens)
  row,e,c,calls,opens=pose_fixture()
  with self.assertRaises(ValueError):verify_event(e,c,calls+calls,opens)
  with self.assertRaises(ValueError):verify_event(e,c,calls,[])

class RefusalObserver(unittest.IsolatedAsyncioTestCase):
 async def test_one_existing_refusal_only_no_valid_write_and_real_directory_bytes(self):
  row,e,c,calls,opens=pose_fixture()
  with tempfile.TemporaryDirectory() as folder:
   directory=Path(folder)
   for name,item in row['before']['entries'].items():(directory/name).write_bytes(bytes.fromhex(item['bytes_hex']))
   before=directory_bytes(directory);actual_calls=[]
   async def call(client,tool,request):actual_calls.append((tool,request));return row['result']
   base={k:v for k,v in row['producer_request'].items() if k!='name'}
   with patch('operation_case_collector.record_snapshot_result') as emit:
    result=await observe_missing_pose(object(),call,row['scene'],row['directory'],directory,base,row['producer_response'])
   self.assertEqual(result,row['result']);self.assertEqual(actual_calls,[('custom_animation_rig',row['request'])])
   self.assertEqual(directory_bytes(directory),before);self.assertEqual(emit.call_count,1)
   observed=emit.call_args.args[1];self.assertEqual(derive(observed),{'typed_errors':'pass'})


class CollectorRefusalGlue(unittest.TestCase):
 def test_public_refusal_snapshot_closes_only_typed_channel(self):
  import operation_case_collector as collector
  import test_operation_case_collector as collector_tests
  case=collector_tests.Collector();case.setUp()
  try:
   row,_,_,_,_=pose_fixture();context=json.loads(case.context.read_text())
   for rel in DEPENDENCIES:
    file=case.root/rel;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('fixture-only source')
    context['dependencies'][rel]={'sha256':collector.sha(file),'git_blob':'blob'}
   case.context.write_text(json.dumps(context))
   with patch.object(collector.sys,'argv',['mcp_rig_pose_crud.py']),patch.object(collector.time,'perf_counter_ns',side_effect=iter(range(100,10000,100))):
    collector.record_public_call('scene_open',{'path':row['scene']},{'opened':True})
    made=collector.record_public_call('custom_animation_rig',row['producer_request'],row['producer_response'])
    row['before_execution_ns']=collector.time.perf_counter_ns()
    refused=collector.record_public_call('custom_animation_rig',row['request'],row['result'])
    row['after_execution_ns']=collector.time.perf_counter_ns()
    emitted=collector.record_snapshot_result('pose_blend_refusal_v1',row)
   actual=case.collect()['cases'][-1]
   self.assertEqual(actual['id'],emitted);self.assertEqual(actual['checks'],{'typed_errors':'pass'})
   self.assertEqual(actual['public_case_ids'],[made,refused])
  finally:case.doCleanups()

if __name__=='__main__':unittest.main()
