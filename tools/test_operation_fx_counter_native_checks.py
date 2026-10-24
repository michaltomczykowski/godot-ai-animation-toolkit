import copy
import json
import unittest
from operation_fx_intention_checks import verify_event,derive
from operation_fx_counter_native_checks import CHECKER,DRIVER,ADAPTER,is_event
import test_operation_fx_intention_checks as fx_tests


def fixture(mode='new'):
 row,context,event,begins,support=fx_tests.FxIntentionTests().fixture('counter',mode)
 event.update(context_sha256='c'*64,run_id='actual-run')
 context['engine_command']='actual-godot'
 context['dependencies'].update({p:{'sha256':'d'*64} for p in (CHECKER,DRIVER,ADAPTER)})
 scene=row['persist_redo']['path']
 obs={'schema':'fx_counter_native_v1','scene_sha256':row['persist_redo']['sha256'],'checker_sha256':'d'*64,'clip':'generated','player_path':'AnimationPlayer','assigned_animation':'generated','method_callback_immediate':True,'manual_clock':True,'advance_seconds':.50001,'editor_hint':False,'inside_tree':True,'target_path':'ScoreLabel','target_class':'Label','text':'50','method_track_type':5,'method_track_enabled':True,'method_track_path':'ScoreLabel','method_track_key_count':31}
 result={'op':'counter','scene':scene,'failures':[],'checks':[{'method_target':'ScoreLabel','text':'50'}],'counter_observation':obs}
 command=['actual-godot','--headless','--path','C:/ci/test_project','--script','res://tools/check_fx_runtime.gd','--',scene,'counter','generated','FxHistory']
 native={'id':'actual-native:1','kind':'native_saved_output','route':'native_godot','driver':'mcp_fx_history.py','operation':'animation_fx.counter','scene':scene,'command':command,'returncode':0,'stdout':'FX_RUNTIME='+json.dumps(result),'stderr':'','context_sha256':'c'*64,'run_id':'actual-run','execution_ns':20,'time_ns':20}
 support.append(native)
 return row,context,event,begins,support,result

class CounterNativeTests(unittest.TestCase):
 def test_four_existing_layouts_promote_only_actual_native50(self):
  for mode in ('new','overwrite','missing_library','instanced'):
   row,c,e,b,s,result=fixture(mode);proof=verify_event(e,c,b,s)
   with self.subTest(mode=mode):
    self.assertEqual(set(proof['checks'].values()),{'pass'})
    self.assertEqual(proof['counter_native']['native_case_id'],'actual-native:1')
    self.assertNotIn('mcp_invocation',proof['checks'])
 def test_old_zero_without_native_is_pending_never_pass(self):
  row,c,e,b,s,_=fixture();proof=verify_event(e,c,b,s[:-1])
  self.assertEqual(proof['checks']['valid_effect'],'pending');self.assertEqual(proof['checks']['playback'],'pending')
  self.assertIn('editor_hint',proof['counter_native']['reason'])
 def test_unexpected_editor_values_never_promoted_by_native(self):
  for value in ['50','1','',0,None,{'text':'0'}]:
   row,c,e,b,s,_=fixture();row['intention']['samples'][0]['actual']=value
   with self.subTest(value=value):self.assertEqual(verify_event(e,c,b,s)['checks']['valid_effect'],'fail')
  row,c,e,b,s,_=fixture();row['intention']=None
  self.assertEqual(derive(row)['valid_effect'],'fail')
 def test_native_observation_mutations_fail(self):
  changes={'scene_sha256':'e'*64,'checker_sha256':'e'*64,'clip':'other','player_path':'OtherPlayer','assigned_animation':'other','method_callback_immediate':False,'manual_clock':False,'advance_seconds':.5,'editor_hint':True,'inside_tree':False,'target_path':'OtherLabel','target_class':'Node','text':'0','method_track_type':0,'method_track_enabled':False,'method_track_path':'OtherLabel','method_track_key_count':11}
  for field,value in changes.items():
   row,c,e,b,s,r=fixture();r['counter_observation'][field]=value;s[-1]['stdout']='FX_RUNTIME='+json.dumps(r)
   with self.subTest(field=field):self.assertEqual(verify_event(e,c,b,s)['checks']['valid_effect'],'fail')
 def test_scene_other_driver_and_external_counter_cannot_be_borrowed(self):
  for field,value in [('driver','mcp_fx_audit.py'),('scene','user://fx_history_counter_overwrite_redo.tscn')]:
   row,c,e,b,s,_=fixture();s[-1][field]=value
   with self.subTest(field=field):self.assertEqual(verify_event(e,c,b,s)['checks']['valid_effect'],'pending')
 def test_native_failure_and_engine_error_remain_failures(self):
  for key,value in [('returncode',1),('stderr','ERROR: actual engine failure')]:
   row,c,e,b,s,_=fixture();s[-1][key]=value
   with self.subTest(key=key):self.assertEqual(verify_event(e,c,b,s)['checks']['playback'],'fail')
 def test_context_route_chronology_command_and_dependency_refused(self):
  for key,value in [('context_sha256','f'*64),('run_id','other'),('route','public_godot_ai'),('execution_ns',1),('time_ns',1),('command',['wrong-godot'])]:
   row,c,e,b,s,_=fixture();s[-1][key]=value
   with self.subTest(key=key),self.assertRaises(ValueError):verify_event(e,c,b,s)
  row,c,e,b,s,_=fixture();c['dependencies'].pop(CHECKER)
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
 def test_duplicate_native_and_missing_or_ambiguous_report_refused(self):
  row,c,e,b,s,_=fixture();s.append(copy.deepcopy(s[-1]))
  with self.assertRaises(ValueError):verify_event(e,c,b,s)
  for stdout in ['','FX_RUNTIME={}\nFX_RUNTIME={}']:
   row,c,e,b,s,_=fixture();s[-1]['stdout']=stdout
   with self.assertRaises(ValueError):verify_event(e,c,b,s)
 def test_original_history_and_source_invariants_still_required(self):
  for field,value in [('after_dry',{}),('source_sha256_after','e'*64),('errors_after',3),('after_probe',{})]:
   mode='instanced' if field=='source_sha256_after' else 'new'
   row,c,e,b,s,_=fixture(mode);row[field]=value
   with self.subTest(field=field):self.assertEqual(verify_event(e,c,b,s)['checks']['valid_effect'],'fail')
 def test_native_selector_is_narrow(self):
  row,c,e,b,s,_=fixture();self.assertTrue(is_event(s[-1]))
  for key,value in [('operation','animation_fx.shake'),('driver','mcp_fx_audit.py'),('scene','res://counter.tscn')]:
   event=dict(s[-1]);event[key]=value;self.assertFalse(is_event(event))


class ExistingWrapperControls(unittest.IsolatedAsyncioTestCase):
 async def test_existing64_processes_emit_only_four_counter_events(self):
  import argparse
  import contextlib
  import io
  from pathlib import Path
  import subprocess
  from unittest.mock import patch
  import mcp_fx_history as wrapper
  class Client:
   def __init__(self,*args,**kwargs):pass
   async def __aenter__(self):return self
   async def __aexit__(self,*args):pass
   async def call_tool(self,*args):return {}
  result={'failed':0,'passed':5,'total':5,'results':[{'test':name,'passed':True,'assertion_count':1} for name in wrapper.EXPECTED]}
  async def call(client,name,params):return result if name=='test_run' else {}
  commands=[]
  def native(command,**kwargs):
   commands.append(command)
   self.assertEqual(kwargs['timeout'],20)
   return subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps({'failures':[]}),'')
  args=argparse.Namespace(core_root=Path('.'),port=8000,ws_port=9500,session_hint='fixture',godot='actual-godot',project_root=Path('test_project'))
  with patch.object(wrapper,'Client',Client),patch.object(wrapper,'StdioTransport',return_value=None),patch.object(wrapper,'call',side_effect=call),patch.object(wrapper.subprocess,'run',side_effect=native),patch.object(wrapper,'record_native_result') as emit,contextlib.redirect_stdout(io.StringIO()):
   self.assertEqual(await wrapper.run(args),0)
  self.assertEqual(len(commands),64);self.assertEqual(emit.call_count,4)
  self.assertEqual({call.args[1] for call in emit.call_args_list},{f'user://fx_history_counter_{mode}_redo.tscn' for mode in ('new','overwrite','missing_library','instanced')})
  for call in emit.call_args_list:
   self.assertEqual(call.args[0],'animation_fx.counter');self.assertIn(call.args[2],commands)
   self.assertEqual(call.args[2][-3:],['counter','generated','FxHistory'])

class CollectorCounterJoin(unittest.TestCase):
 def test_inner_row_joins_native_without_external_invocation_or_generic_orphan(self):
  import tempfile
  from pathlib import Path
  from unittest.mock import patch
  import operation_case_collector as collector
  import test_operation_case_collector as collector_tests
  case=collector_tests.Collector();case.setUp()
  try:
   row,_,event,_,support,_=fixture()
   context=json.loads(case.context.read_text())
   from operation_fx_intention_checks import DEPENDENCIES
   paths=set(DEPENDENCIES)|{CHECKER,DRIVER,ADAPTER,'test_project/tests/operation_history_trace.gd','tools/mcp_presets_audit.py','tools/operation_history_checks.py'}
   for rel in paths:
    p=case.root/rel;p.parent.mkdir(parents=True,exist_ok=True);p.write_text('fixture-only source')
    context['dependencies'][rel]={'sha256':collector.sha(p),'git_blob':'blob'}
   case.context.write_text(json.dumps(context))
   for path in row['input_files_before']:row['input_files_before'][path]=context['dependencies']['test_project/'+path.removeprefix('res://')]['sha256']
   row['input_files_after']=dict(row['input_files_before'])
   clock=patch.object(collector.time,'time_ns',side_effect=iter(range(100,10000,100)))
   clock.start();case.addCleanup(clock.stop)
   collector.record_public_call('scene_open',{'path':'res://main.tscn'},{'opened':True})
   with collector.public_test_run_span('test_run',{'suite':'fx_route_history','verbose':True}):
    collector._emit('editor_history_assertions',{'operation':'animation_fx.counter','driver':'test_fx_route_history.gd','validator':'fx_intention_history_v1','route':'public_test_run_inner_dispatch','test_run_begin_id':collector._active_test_run['begin_id'],'row':row})
    collector.record_public_call('test_run',{'suite':'fx_route_history','verbose':True},support[0]['response'])
   command=support[-1]['command'];command[0]=context['engine_command'];command[3]=str(case.root/'test_project')
   native=json.loads(support[-1]['stdout'].split('=',1)[1]);native['counter_observation']['checker_sha256']=context['dependencies'][CHECKER]['sha256']
   import subprocess
   with patch.object(collector.sys,'argv',['mcp_fx_history.py']):
    emitted=collector.record_native_result('animation_fx.counter',row['persist_redo']['path'],command,subprocess.CompletedProcess(command,0,'FX_RUNTIME='+json.dumps(native),''))
   result=case.collect()
   self.assertEqual(result['successful_public_operations'],[])
   self.assertEqual(len(result['cases']),1)
   self.assertEqual(result['cases'][0]['checks']['valid_effect'],'pass')
   self.assertEqual(result['cases'][0]['checks']['playback'],'pass')
   self.assertEqual(result['cases'][0]['counter_native']['native_case_id'],emitted)
   self.assertNotIn('mcp_invocation',result['cases'][0]['checks'])
  finally:case.doCleanups()

if __name__=='__main__':unittest.main()
