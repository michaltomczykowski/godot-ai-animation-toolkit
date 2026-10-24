"""Exact same-call source/error evidence for three copied-scene reads."""
import math,re
from operation_setup_history_checks import equal
from operation_snapshot_checks import successful,error_code
from operation_bounded_read_checks import EXPECTED_BONES,MODEL

BASE=('tools/operation_remaining_read_checks.py','tools/remaining_read_witness.py','tools/mcp_presets_audit.py','tools/fixture_copy.py','test_project/tests/remaining_read_observation.gd','test_project/tests/test_remaining_read_witness.gd','test_project/tests/inspect_read_snapshot.gd','test_project/tests/operation_history_trace.gd','tools/operation_setup_history_checks.py')
DRIVERS={'animation_rig.rig_get':'mcp_rig_pose_apply_audit.py','animation_rig.pose_list':'mcp_rig_pose_crud.py','animation_graph.graph_get':'mcp_graph_audit.py'}
GRAPH_BASE={'op':'state_machine','player_path':'/RepairGraphFixture/AnimationPlayer','states':[{'name':'idle','animation':'idle'},{'name':'walk','animation':'walk'}],'transitions':[{'from':'idle','to':'walk','xfade':.1}]}
POSE_TYPED_REASON='Typed pose_list proof is the actual selected directory=[] guard returning INVALID_PARAMS before DirAccess. Missing directories remain successful empty-list requests; default/legacy String behavior is unchanged.'
def require(ok,msg):
 if not ok:raise ValueError(msg)
def digest(v,n=64):return isinstance(v,str)and re.fullmatch('[0-9a-f]{'+str(n)+'}',v)is not None
def numeric(v):return type(v)in(int,float)and math.isfinite(v)
def fixed(key,stage,scene):
 if key=='animation_graph.graph_get':
  require(re.fullmatch(r'res://repair_graph_audit/[0-9]{8}_[0-9]{6}/graph_get\.tscn',scene)is not None,'unknown graph read scene')
  return {'op':'graph_get','tree_path':'/RepairGraphFixture/AnimationTree'if stage=='valid'else'/DefinitelyMissingAnimationTree'}
 require(re.fullmatch(r'res://repair_rig_audit/[0-9]{8}_[0-9]{6}/'+('poses'if key.endswith('pose_list')else'pose_apply')+r'\.tscn',scene)is not None,'unknown rig read scene')
 if key=='animation_rig.rig_get':return {'op':'rig_get','skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D'if stage=='valid'else'/DefinitelyMissingSkeleton'}
 require(key=='animation_rig.pose_list','unknown remaining rig read')
 if stage=='refusal':return {'op':'pose_list','directory':[]}
 stamp=scene.rsplit('/',2)[1];return {'op':'pose_list','directory':'res://animation_toolkit/repair_audit/rig_poses_'+stamp}

def snapshot_complete(snapshot,marker,context):
 if not isinstance(snapshot,dict)or snapshot.get('scene')!=marker['scene']or snapshot.get('unsupported')!=[]or type(snapshot.get('history'))is not int or type(snapshot.get('global_history'))is not int:return False
 nodes=snapshot.get('nodes',{});resources=snapshot.get('resources',{});files=snapshot.get('files',{})
 if not isinstance(nodes,dict)or not isinstance(resources,dict)or not isinstance(files,dict)or not digest(files.get(marker['scene']))or not all(digest(v)for v in files.values()):return False
 graph=marker['operation']=='animation_graph.graph_get'
 required={'.':'Node2D','Character':'Node2D','OtherCharacter':'Node2D','AnimationPlayer':'AnimationPlayer','AnimationTree':'AnimationTree'}if graph else{'.':'Node3D','Dummy':'Node3D','Dummy/Skeleton3D':'Skeleton3D','AnimationPlayer':'AnimationPlayer'}
 if any(nodes.get(path,{}).get('class')!=kind for path,kind in required.items()):return False
 for path,node in nodes.items():
  if type(node.get('id'))is not int or not isinstance(node.get('properties'),dict)or not isinstance(node.get('children'),list)or not isinstance(node.get('class'),str)or not node.get('class'):return False
  expected_name=('RepairGraphFixture'if graph else'RepairRigFixture')if path=='.'else path.rsplit('/',1)[-1]
  if node.get('name')!=expected_name:return False
  if any((name if path=='.'else path+'/'+name)not in nodes for name in node['children']):return False
 if marker['operation']=='animation_rig.pose_list':
  directory=fixed(marker['operation'],'valid',marker['scene'])['directory']
  if not all(digest(files.get(directory+'/'+name+'.json'))for name in ('rest','arm')):return False
 player=nodes['AnimationPlayer']
 if not {'playback','libraries','clips'}.issubset(player)or not isinstance(player['playback'],dict)or not isinstance(player['libraries'],dict)or not isinstance(player['clips'],dict):return False
 if not {'assigned','current','playing','queue','speed','playing_speed','position'}.issubset(player['playback'])or type(player['playback']['playing'])is not bool:return False
 if graph:
  ref=nodes['AnimationTree']['properties'].get('tree_root',{}).get('resource_id')
  if resources.get(ref,{}).get('class')!='AnimationNodeStateMachine':return False
 if not graph:
  bones=nodes['Dummy/Skeleton3D'].get('bones',[])
  if len(bones)!=56 or {b.get('name')for b in bones}!=set(EXPECTED_BONES)or any(not {'name','parent','rest','position','rotation','scale','enabled'}.issubset(b)or type(b['parent'])is not int or type(b['enabled'])is not bool for b in bones):return False
  if files.get('res://models/human_dummy/HumanCharacterDummy_F.fbx')!=context['dependencies'][MODEL]['sha256']:return False
 def refs(v):
  if isinstance(v,dict):
   if set(v)=={'resource_id'}:return v['resource_id']in resources
   if 'unsupported'in v:return False
   if 'bytes_sha256'in v:return set(v)=={'type','bytes_sha256'}and digest(v['bytes_sha256'])
   return all(refs(x)for x in v.values())
  if isinstance(v,list):return all(refs(x)for x in v)
  if type(v)is float:return math.isfinite(v)
  return v is None or isinstance(v,(str,bool,int))
 return all(isinstance(r.get('class'),str)and isinstance(r.get('properties'),dict)and isinstance(r.get('path'),str)for r in resources.values())and refs(nodes)and refs(resources)

def source_status(row,context):
 if not equal(row.get('before'),row.get('after')):return 'fail'
 fixture='res://repair_graph_fixture.tscn'if row['marker']['operation']=='animation_graph.graph_get'else'res://repair_rig_fixture.tscn'
 expected=context['dependencies']['test_project/'+fixture.removeprefix('res://')]['sha256']
 if row.get('fixture_path')!=fixture or row.get('fixture_sha256')!=expected:return 'fail'
 return 'pass'if row.get('snapshot_schema')=='stored_graph_v1'and snapshot_complete(row.get('before'),row['marker'],context)else'pending'

def graph_valid(native,result):
 if not isinstance(native,dict)or not successful(result)or native.get('tree_class')!='AnimationTree'or native.get('root_class')!='AnimationNodeStateMachine'or native.get('tree_path')!='AnimationTree'or native.get('player_path')!='AnimationPlayer'or native.get('player_resolved')is not True or native.get('active')is not False:return False
 states=native.get('states',[]);implicit=native.get('implicit_states',[]);edges=native.get('transitions',[])
 if len(states)!=2 or {s.get('name')for s in states}!={'idle','walk'}or sorted(implicit)!=['End','Start']or any(s.get('class')!='AnimationNodeAnimation'or s.get('animation')!=s.get('name')for s in states):return False
 if len(edges)!=2 or {(e.get('from'),e.get('to'))for e in edges}!={('Start','idle'),('idle','walk')}:return False
 for e in edges:
  xfade=0. if e['from']=='Start'else .1
  if e.get('class')!='AnimationNodeStateMachineTransition'or not numeric(e.get('xfade'))or abs(e['xfade']-xfade)>1e-6 or type(e.get('advance_mode'))is not int or e['advance_mode']!=2 or type(e.get('switch_mode'))is not int or e['switch_mode']!=0 or e.get('condition')!=''or e.get('expression')!=''or type(e.get('priority'))is not int or e['priority']!=1 or e.get('reset')is not True:return False
 if result.get('tree_path')!='/RepairGraphFixture/AnimationTree'or result.get('anim_player')!=native.get('anim_player')or result.get('anim_player_resolved')is not True or result.get('active')is not False or not isinstance(result.get('animations'),list)or sorted(result['animations'])!=['idle','walk']:return False
 root=result.get('root',{});actual=root.get('states',[]);links=root.get('transitions',[])
 if root.get('type')!='state_machine'or root.get('state_count')!=2 or root.get('transition_count')!=2 or len(actual)!=2 or {s.get('name')for s in actual}!={'idle','walk'}or any(s.get('node')!={'type':'animation','animation':s.get('name')}for s in actual):return False
 if len(links)!=2 or {(e.get('from'),e.get('to'))for e in links}!={('Start','idle'),('idle','walk')}:return False
 for e in links:
  if not numeric(e.get('xfade_time'))or abs(e['xfade_time']-(0. if e['from']=='Start'else .1))>1e-6 or e.get('advance_mode')!='auto'or e.get('switch_mode')!='immediate'or e.get('condition')!=''or e.get('advance_expression')!=''or type(e.get('priority'))is not int or e['priority']!=1 or e.get('reset')is not True:return False
 return True

def verify_pair(event,context,events,public,begins,support):
 key=event.get('operation');driver=DRIVERS.get(key);row=event.get('row',{});marker=row.get('marker',{});scene=marker.get('scene','')
 require(driver is not None and row.get('phase')=='end'and marker.get('stage')=='valid','only a completed known positive read can derive checks')
 fixture='test_project/repair_graph_fixture.tscn'if key=='animation_graph.graph_get'else'test_project/repair_rig_fixture.tscn'
 deps=BASE+('tools/'+driver,fixture,'addons/godot_ai_animation/utils/error_codes.gd')+(('addons/godot_ai_animation/handlers/graph.gd','addons/godot_ai_animation/spec/graph_builders.gd')if key=='animation_graph.graph_get'else(MODEL,'addons/godot_ai_animation/handlers/rig.gd'))
 for path in deps:
  d=context.get('dependencies',{}).get(path,{});require(digest(d.get('sha256'))and digest(d.get('git_blob'),40),'unbound remaining read dependency: '+path)
 stages=('valid','refusal');rows=[];calls=[];ids=[];valid_helper_id=None;valid_start=None
 def helper(e,test,stage):
  r=e.get('row',{});m=r.get('marker',{});wanted=fixed(key,stage,scene)
  require(e.get('validator')=='remaining_read_witness_v1'and e.get('driver')=='test_remaining_read_witness.gd'and e.get('route')=='public_test_run_inner_dispatch'and e.get('run_id')==context.get('run_id')and bool(context.get('run_id'))and e.get('operation')==key,'foreign remaining read helper source')
  require(set(m)=={'token','context_sha256','run_id','operation','request','scene','stage'}and digest(m['token'],32)and m['context_sha256']==e.get('context_sha256')and e.get('context_sha256')==event.get('context_sha256')and m['run_id']==context['run_id']and m['operation']==key and m['scene']==scene and m['stage']==stage and equal(m['request'],wanted)and r.get('op')==key.split('.')[-1]and r.get('mode')=='remaining_read','remaining read marker request/context differs')
  a=[v for v in begins if v.get('id')==e.get('test_run_begin_id')];b=[v for v in support if v.get('public_tool')=='test_run'and v.get('test_run_begin_id')==e.get('test_run_begin_id')]
  require(len(a)==len(b)==1,'missing/ambiguous remaining read public helper span')
  start,end=a[0],b[0];request={'suite':'remaining_read_witness','test_name':test,'verbose':True}
  require(start.get('request')==end.get('request')==request and start.get('scene')==end.get('scene')==scene and start.get('driver')==end.get('driver')==driver and start['execution_ns']<end['execution_ns']and start['time_ns']<=e['time_ns']<=end['time_ns'],'remaining read helper public source/scene/order differs')
  results=[x for x in end.get('response',{}).get('results',[])if x.get('suite')=='remaining_read_witness'and x.get('test')==test]
  require(len(results)==1 and results[0].get('passed')is True and not results[0].get('skipped',False)and type(results[0].get('assertion_count'))is int and results[0]['assertion_count']>0,'remaining read helper did not execute')
  return start,end
 for stage in stages:
  completed=[e for e in events if e.get('validator')=='remaining_read_witness_v1'and e.get('operation')==key and e.get('row',{}).get('phase')=='end'and e['row'].get('marker',{}).get('scene')==scene and e['row']['marker'].get('stage')==stage]
  require(len(completed)==1,'missing/duplicate remaining read stage')
  end=completed[0];m=end['row']['marker'];started=[e for e in events if e.get('validator')=='remaining_read_witness_v1'and e.get('row',{}).get('phase')=='begin'and e['row'].get('marker',{}).get('token')==m['token']]
  require(len(started)==1,'missing/duplicate remaining read begin token')
  start=started[0];a,b=helper(start,'test_begin',stage);c,d=helper(end,'test_end',stage)
  require(equal(start['row']['marker'],m)and equal(end['row'].get('begin_marker'),m),'remaining read activation mutated')
  tool='custom_animation_graph'if key=='animation_graph.graph_get'else'custom_animation_rig'
  originals=[p for p in public if p.get('operation')==key and p.get('driver')==driver and p.get('public_tool')==tool and p.get('route')=='public_godot_ai'and p.get('scene')==scene and equal(p.get('params'),m['request'])and b['execution_ns']<p.get('execution_ns',0)<c['execution_ns']]
  require(len(originals)==1,'witness must bracket exactly one original public read')
  # No extra operator or mutating operation may hide between witnesses.
  interlopers=[p for p in public if p.get('scene')==scene and b['execution_ns']<p.get('execution_ns',0)<c['execution_ns']and p['id']!=originals[0]['id']]
  require(not interlopers,'another operation inside remaining read span')
  rows.append(end['row']);calls.append(originals[0]);ids += [start['id'],end['id'],b['id'],d['id'],originals[0]['id']]
  if stage=='valid':require(end['id']==event['id'],'positive event identity differs');valid_helper_id=d['id'];valid_start=a['execution_ns']
 require(calls[0]['execution_ns']<calls[1]['execution_ns'],'remaining read refusal precedes positive')
 okay=successful(calls[0].get('response'))and(len(calls)==1 or error_code(calls[1].get('response'))==('INVALID_PARAMS'if key=='animation_rig.pose_list'else'NODE_NOT_FOUND'))
 statuses=[source_status(r,context)for r in rows];source='fail'if 'fail'in statuses else'pass'if set(statuses)=={'pass'}else'pending'
 errors=all(type(r.get('errors_before'))is int and r['errors_before']==0 and type(r.get('errors_after'))is int and r['errors_after']==0 and r.get('errors')==[]for r in rows)
 checks={'source_unchanged':source if okay else'fail','reported_errors':'pass'if okay and errors else'fail'}
 checks['typed_errors']='pass'if okay else'fail'
 if key=='animation_graph.graph_get':
  producers=[p for p in public if p.get('operation')=='animation_graph.state_machine'and p.get('driver')==driver and p.get('public_tool')=='custom_animation_graph'and p.get('route')=='public_godot_ai'and p.get('scene')==scene and equal(p.get('params'),GRAPH_BASE)and successful(p.get('response'))and p['execution_ns']<valid_start]
  require(len(producers)==1,'fixed graph read lacks exact authored producer')
  ids.append(producers[0]['id']);native=rows[0].get('graph_before',{});checks['valid_effect']='pass'if okay and equal(native,rows[0].get('graph_after'))and graph_valid(native,calls[0]['response'])else'fail'
 return {'checks':checks,'public_case_ids':ids,'public_test_run_case_id':valid_helper_id,'limits':'Exact copied-scene original read/refusal live stored nodes/resources/bones/readable Player/history/files plus synchronous logger only. Unsupported state stays pending. Graph effect is fixed authored idle/walk native topology/binding, not arbitrary graphs or other returned parameters. No playback/visual proof. '+(POSE_TYPED_REASON if key=='animation_rig.pose_list'else'')}
