"""Strict shared read source/error witnesses and independent saved-walk references."""
import re
from inspect_numeric_reference import sample_effect,audit_effect

SUITE='inspect_read_witness'
BASE_DEPS=('tools/operation_read_witness_checks.py','tools/inspect_read_witness.py','tools/inspect_numeric_reference.py',
 'test_project/tests/test_inspect_read_witness.gd','test_project/tests/inspect_read_snapshot.gd',
 'test_project/tests/inspect_native_reference.gd','test_project/tests/operation_history_trace.gd')

def digest(v):return isinstance(v,str) and re.fullmatch('[0-9a-f]{64}',v) is not None

def fixed(operation,stage):
 op=operation.removeprefix('animation_inspect.')
 from mcp_inspect_audit import CASES,ERROR_CASES,SCENE
 if op in CASES:return 'mcp_inspect_audit.py',SCENE,{'op':op,**(CASES if stage=='valid' else ERROR_CASES)[op]}
 from mcp_inspect_3d import SCENE,PLAYER,SKELETON,CLIP
 if op not in {'rig_profile','sample','motion_audit'}:raise ValueError('unknown read witness operation')
 if stage=='refusal':request={'op':op,'player_path':PLAYER,'skeleton_path':'/MotionWalk/Missing','animation_name':CLIP}
 elif op=='rig_profile':request={'op':op,'skeleton_path':SKELETON,'save':False}
 else:request={'op':op,'player_path':PLAYER,'skeleton_path':SKELETON,'animation_name':CLIP,**({'samples':8,'bones':['B-foot.L','B-foot.R']} if op=='sample' else {'samples':120})}
 return 'mcp_inspect_3d.py',SCENE,request


def snapshot_complete(snapshot,scene,context):
 if not isinstance(snapshot,dict) or snapshot.get('scene')!=scene or snapshot.get('unsupported')!=[] or type(snapshot.get('history')) is not int or type(snapshot.get('global_history')) is not int:return False
 nodes=snapshot.get('nodes',{});resources=snapshot.get('resources',{});files=snapshot.get('files',{})
 if not isinstance(nodes,dict) or not isinstance(resources,dict) or not resources or not isinstance(files,dict) or not all(digest(v) for v in files.values()):return False
 expected={'walk','run','idle','jump','lean'} if scene=='res://repair_edit_fixture.tscn' else {'repair_probe_walk','repair_probe_walk_24','repair_probe_run','repair_probe_run_24','walk'}
 player='AnimationPlayer' if scene=='res://repair_edit_fixture.tscn' else 'WalkAnim'
 wanted={'.','Character','OtherCharacter',player} if player=='AnimationPlayer' else {'.','Dummy','Dummy/Skeleton3D',player,'Floor','Cam','Sun','Ui','Ui/Title'}
 if not wanted.issubset(nodes) or set(nodes[player].get('clips',{}))!=expected or 'playback' not in nodes[player] or not nodes[player].get('libraries'):return False
 for ref in nodes[player]['clips'].values():
  record=resources.get(ref.get('resource_id') if isinstance(ref,dict) else None,{})
  props=record.get('properties',{})
  if record.get('class')!='Animation' or not {'length','loop_mode'}.issubset(props) or not any(k.startswith('tracks/') for k in props):return False
 if player=='WalkAnim':
  bones=nodes['Dummy/Skeleton3D'].get('bones',[])
  from operation_bounded_read_checks import EXPECTED_BONES
  if len(bones)!=56 or {b.get('name') for b in bones}!=set(EXPECTED_BONES) or any(not {'name','parent','rest','position','rotation','scale','enabled'}.issubset(b) for b in bones):return False
 for path,node in nodes.items():
  if not isinstance(node,dict) or not {'id','name','class','properties','children'}.issubset(node) or type(node['id']) is not int or not isinstance(node['properties'],dict) or not isinstance(node['children'],list):return False
  if any((name if path=='.' else path+'/'+name) not in nodes for name in node['children']):return False
 for record in resources.values():
  if not isinstance(record,dict) or not isinstance(record.get('class'),str) or not isinstance(record.get('properties'),dict):return False
 def refs(value):
  if isinstance(value,dict):
   if set(value)=={'resource_id'}:return value['resource_id'] in resources
   if 'unsupported' in value:return False
   if 'bytes_sha256' in value and (set(value)!={'type','bytes_sha256'} or not digest(value['bytes_sha256'])):return False
   return all(refs(v) for v in value.values())
  if isinstance(value,list):return all(refs(v) for v in value)
  return True
 if not refs(nodes) or not refs(resources):return False
 input_paths=[scene]+(['res://models/human_dummy/HumanCharacterDummy_F.fbx'] if player=='WalkAnim' else [])
 return all(files.get(path)==context['dependencies'].get('test_project/'+path.removeprefix('res://'),{}).get('sha256') and digest(files.get(path)) for path in input_paths)


def source_status(row,scene,context):
 if row.get('before')!=row.get('after'):return 'fail'
 if row.get('after_reference',row.get('after'))!=row.get('after'):return 'fail'
 return 'pass' if row.get('snapshot_schema')=='stored_graph_v1' and snapshot_complete(row.get('before'),scene,context) else 'pending'


def verify_pair(event,context,events,public,begins,support):
 key=event.get('operation');row=event.get('row',{});marker=row.get('marker',{})
 if row.get('phase')!='end' or marker.get('stage')!='valid':raise ValueError('qualification requires a positive completed read witness')
 driver,scene,request=fixed(key,'valid')
 required=BASE_DEPS+('tools/'+driver,'test_project/'+scene.removeprefix('res://'))
 if driver=='mcp_inspect_3d.py':required+=('test_project/models/human_dummy/HumanCharacterDummy_F.fbx','test_project/tools/repair_motion_playback.gd','tools/operation_bounded_read_checks.py')
 for path in required:
  value=context.get('dependencies',{}).get(path,{})
  if not digest(value.get('sha256')) or not re.fullmatch('[0-9a-f]{40}',str(value.get('git_blob',''))):raise ValueError('read witness missing committed source dependency: '+path)
 def helper(e,test,stage):
  r=e.get('row',{});m=r.get('marker',{})
  if e.get('validator')!='inspect_read_witness_v1' or e.get('driver')!='test_inspect_read_witness.gd' or e.get('route')!='public_test_run_inner_dispatch' or e.get('operation')!=key or e.get('run_id')!=context.get('run_id') or not context.get('run_id'):raise ValueError('read helper source/run mismatch')
  if set(m)!={'token','context_sha256','run_id','operation','request','scene','stage'} or not re.fullmatch('[0-9a-f]{32}',str(m.get('token',''))) or m['context_sha256']!=e.get('context_sha256') or m['run_id']!=context['run_id'] or m['operation']!=key or m['scene']!=scene or m['stage']!=stage or m['request']!=fixed(key,stage)[2] or r.get('op')!=key.split('.')[-1]:raise ValueError('read marker differs from exact operation/request/context')
  starts=[x for x in begins if x.get('id')==e.get('test_run_begin_id')];ends=[x for x in support if x.get('public_tool')=='test_run' and x.get('test_run_begin_id')==e.get('test_run_begin_id')]
  if len(starts)!=1 or len(ends)!=1:raise ValueError('read helper lacks unique actual public span')
  start,end=starts[0],ends[0];expected={'suite':SUITE,'test_name':test,'verbose':True}
  if start.get('request')!=expected or end.get('request')!=expected or start.get('scene')!=scene or end.get('scene')!=scene or start.get('driver')!=driver or end.get('driver')!=driver or not start.get('execution_ns',0)<end.get('execution_ns',0) or not start.get('time_ns',0)<=e.get('time_ns',0)<=end.get('time_ns',0):raise ValueError('read helper public request/scene/order mismatch')
  results=[x for x in end.get('response',{}).get('results',[]) if x.get('suite')==SUITE and x.get('test')==test]
  if len(results)!=1 or results[0].get('passed') is not True or results[0].get('skipped',False) or type(results[0].get('assertion_count')) is not int or results[0]['assertion_count']<1:raise ValueError('read helper did not actually pass its selected test')
  return start,end
 paired=[];ids=[];calls=[]
 for stage in ('valid','refusal'):
  ends=[e for e in events if e.get('validator')=='inspect_read_witness_v1' and e.get('operation')==key and e.get('row',{}).get('phase')=='end' and e['row'].get('marker',{}).get('stage')==stage]
  if len(ends)!=1 or (stage=='valid' and ends[0]['id']!=event.get('id')):raise ValueError('read witness missing/ambiguous positive/refusal pair')
  end_event=ends[0];m=end_event['row']['marker']
  starts=[e for e in events if e.get('validator')=='inspect_read_witness_v1' and e.get('operation')==key and e.get('row',{}).get('phase')=='begin' and e['row'].get('marker',{}).get('token')==m['token']]
  if len(starts)!=1:raise ValueError('read witness missing/ambiguous matching begin')
  begin_event=starts[0];begin_span,begin_done=helper(begin_event,'test_begin',stage);end_span,end_done=helper(end_event,'test_end',stage)
  if end_event['row'].get('begin_marker')!=m or begin_event['row']['marker']!=m:raise ValueError('read marker changed during operation')
  actual=[e for e in public if e.get('operation')==key and e.get('driver')==driver and e.get('public_tool')=='custom_animation_inspect' and e.get('route')=='public_godot_ai' and e.get('scene')==scene and e.get('params')==m['request'] and begin_done['execution_ns']<e.get('execution_ns',0)<end_span['execution_ns']]
  if len(actual)!=1:raise ValueError('read witness does not bracket exactly one original actual call')
  ids.extend([begin_event['id'],end_event['id'],begin_done['id'],end_done['id'],actual[0]['id']]);paired.append(end_event['row']);calls.append(actual[0])
 valid,refusal=calls
 from operation_inspect_checks import ERROR_CODES
 expected_code=ERROR_CODES.get(key.split('.')[-1],'NODE_NOT_FOUND')
 from operation_snapshot_checks import error_code,successful
 successful_calls=successful(valid.get('response')) and error_code(refusal.get('response'))==expected_code
 statuses=[source_status(r,scene,context) for r in paired]
 source='fail' if 'fail' in statuses else 'pass' if statuses==['pass','pass'] else 'pending'
 errors=all(type(r.get('errors_before')) is int and r['errors_before']==0 and type(r.get('errors_after')) is int and r['errors_after']==0 and r.get('errors')==[] and r.get('reference_errors',[])==[] for r in paired)
 checks={'source_unchanged':source if successful_calls else 'fail','reported_errors':'pass' if successful_calls and errors else 'fail'}
 if key.split('.')[-1] in {'sample','motion_audit'}:
  ref=row.get('reference',{})
  if not ref or ref.get('failure') or ref.get('eligible') is not True:checks['valid_effect']='pending'
  else:
   expected_sha=context['dependencies']['test_project/repair_motion_fixture.tscn']['sha256']
   numeric=sample_effect if key.endswith('.sample') else audit_effect
   checks['valid_effect']='pass' if successful_calls and ref.get('scene_sha256')==expected_sha and row.get('reference_errors')==[] and row.get('after_reference')==row.get('after') and numeric(valid['response'],ref) else 'fail'
 return {'checks':checks,'public_case_ids':ids,'public_test_run_case_id':helper(event,'test_end','valid')[1]['id'],
  'limits':'One unchanged original external positive/refusal request pair. Source proof covers all observed scene nodes/stored Resource graph, bone/rest/Player-readable state, history and input/write-root file digests; unsupported state stays pending. Logger covers these exact call spans, not unrelated session errors. Numeric reference uses fresh committed scene/native Player in same editor and independent Python grading; no native-process, skin/visual or broader input qualification.'}
