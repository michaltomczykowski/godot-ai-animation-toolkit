"""Strict source-bound setup-only native transaction observations; no motion oracle."""
from copy import deepcopy
import math,re,json

PHASES=('before','after_dry','after_write','before_undo','undone','redone','persisted')
DEPS=('tools/operation_setup_source_checks.py','addons/godot_ai_animation/handlers/motion.gd','addons/godot_ai_animation/runtime/setup_grounding.gd','test_project/models/human_dummy/HumanCharacterDummy_F.fbx','tools/operation_setup_history_checks.py','tools/setup_history_witness.py','tools/mcp_motion_setup_secondary.py','tools/mcp_presets_audit.py','tools/fixture_copy.py','test_project/repair_rig_fixture.tscn','test_project/tests/test_animation_motion.gd','test_project/tests/setup_history_observation.gd','test_project/tests/inspect_read_snapshot.gd','test_project/tests/operation_history_trace.gd')
LIMITS='Exact setup-only native stored observations before secondary_motion. Original dry/history/saved-reload/target path and value-type binding preserved. No requested-effect, playback or visual promotion.'

def require(ok,message):
 if not ok:raise ValueError(message)
def digest(v,n=64):return isinstance(v,str)and re.fullmatch('[0-9a-f]{'+str(n)+'}',v)is not None
def success(v):return isinstance(v,dict)and bool(v)and not v.get('error')
def finite(value):
 if isinstance(value,bool)or value is None or isinstance(value,str):return True
 if type(value)in(int,float):return math.isfinite(value)
 if isinstance(value,list):return all(finite(x)for x in value)
 if isinstance(value,dict):return all(finite(x)for x in value.values())
 return False

def equal(a,b):
 if isinstance(a,bool)or isinstance(b,bool):return type(a)is type(b)and a==b
 if type(a)in(int,float)and type(b)in(int,float):return math.isfinite(a)and math.isfinite(b)and a==b
 if isinstance(a,dict)and isinstance(b,dict):return a.keys()==b.keys()and all(equal(a[k],b[k])for k in a)
 if isinstance(a,list)and isinstance(b,list):return len(a)==len(b)and all(equal(x,y)for x,y in zip(a,b))
 return type(a)is type(b)and a==b

def numeric(v):return type(v)in(int,float)and math.isfinite(v)
def key_value(key,expected):
 value=key.get('value');fields=('x','y','z','w')if expected=='Quaternion'else('x','y','z')
 return key.get('value_type')==expected and isinstance(value,dict)and value.get('type')==expected and all(numeric(value.get(k))for k in fields)and numeric(key.get('time'))and numeric(key.get('transition'))

def semantic(state):
 """Ignore re-instantiation IDs, keeping resource aliasing and stored properties."""
 resources=state['resources'];seen={}
 def canon(value):
  if isinstance(value,list):return [canon(x)for x in value]
  if not isinstance(value,dict):return value
  if set(value)=={'dictionary'}:
   entries=value['dictionary'];return {'dictionary':[canon(pair)for pair in sorted(entries,key=lambda pair:json.dumps(pair[0],sort_keys=True))]}
  if set(value)=={'resource_id'}:
   key=value['resource_id'];require(key in resources,'dangling stored resource reference')
   if key in seen:return {'ref':seen[key]}
   label=len(seen);seen[key]=label;r=resources[key];path=r.get('path','')
   return {'resource':label,'class':r['class'],'path':''if '::'in path else path,'properties':canon(r['properties'])}
  return {k:canon(v)for k,v in sorted(value.items())if k!='id'}
 return canon(state['nodes'])

def complete(row):
 state=row.get('stored',{});request=row['marker']['request'];root=request['player_path'].strip('/').split('/')[0]
 player=request['player_path'].removeprefix('/'+root+'/');skeleton=request['skeleton_path'].removeprefix('/'+root+'/');nodes=state.get('nodes',{});resources=state.get('resources',{})
 if not (state.get('scene')==row['marker']['scene']and state.get('unsupported')==[]and type(state.get('history'))is int and type(state.get('global_history'))is int and isinstance(nodes,dict)and bool(nodes)and isinstance(resources,dict)and finite(state)and row.get('player_class')=='AnimationPlayer'and row.get('player_path')==player and row.get('player_root')=='..'and isinstance(row.get('clips'),dict)):return False
 if nodes.get(player,{}).get('class')!='AnimationPlayer'or nodes.get(skeleton,{}).get('class')!='Skeleton3D':return False
 bones=nodes[skeleton].get('bones')
 if not isinstance(bones,list)or not bones or any(not {'name','parent','rest','position','rotation','scale','enabled'}.issubset(b)or not isinstance(b['name'],str)or type(b['parent'])is not int or type(b['enabled'])is not bool for b in bones):return False
 for path,node in nodes.items():
  if type(node.get('id'))is not int or not isinstance(node.get('class'),str)or not isinstance(node.get('properties'),dict)or not isinstance(node.get('children'),list):return False
  if any((child if path=='.'else path+'/'+child)not in nodes for child in node['children']):return False
 if any(not isinstance(r.get('class'),str)or not isinstance(r.get('properties'),dict)or not isinstance(r.get('path'),str)for r in resources.values()):return False
 files=state.get('files',{})
 return isinstance(files,dict)and all(digest(v)for v in files.values())and digest(row.get('scene_sha256'))and files.get(state['scene'])==row['scene_sha256']

def tracks_valid(row):
 request=row['marker']['request'];root=request['player_path'].strip('/').split('/')[0];skeleton=request['skeleton_path'].removeprefix('/'+root+'/')
 names=['idle','walk','run']+(['jump']if request.get('include_jump',True)else[])+(['turn_left']if request.get('include_turn',False)else[])
 clips=row['clips']
 for name in names:
  clip=clips.get(name,{})
  if type(clip.get('loop_mode'))is not int or clip['loop_mode']not in(0,1,2)or type(clip.get('length'))not in(int,float)or not math.isfinite(clip['length'])or clip['length']<=0 or not clip.get('tracks'):return False
  bones=0
  for track in clip['tracks']:
   keys=track.get('keys',[]);kind=track.get('type');target=track.get('node_class');prop=track.get('property')
   if track.get('path')!=str(track.get('node_path'))+':'+str(prop):return False
   if type(kind)is not int or type(track.get('interpolation'))is not int or track['interpolation']not in(0,1,2)or track.get('enabled')is not True or not track.get('node_path')or not keys or not finite(keys):return False
   if target=='Skeleton3D':
    bone_records=row['stored']['nodes'][skeleton]['bones']
    if track['node_path']!=skeleton or type(track.get('bone_index'))is not int or not 0<=track['bone_index']<len(bone_records)or track.get('bone_name')!=prop or bone_records[track['bone_index']]['name']!=prop or not prop:return False
    expected={1:'Vector3',2:'Quaternion',3:'Vector3'}.get(kind)
    if expected is None or any(not key_value(k,expected)for k in keys):return False
    bones+=1
   elif target=='Node3D':
    # Only the explicit carrier position binding is admitted here.
    if kind!=1 or prop!='position'or track.get('property_type')!='Vector3'or any(not key_value(k,'Vector3')for k in keys):return False
    if not skeleton.startswith(track['node_path']+'/'):return False
   else:return False
  if bones==0:return False
 return True

def derive(rows):
 require(set(rows)==set(PHASES),'missing/extra setup native phases')
 clean=all(complete(r)for r in rows.values());s={k:r['stored']for k,r in rows.items()}
 before=s['before'];written=s['after_write'];undone=s['undone'];redone=s['redone']
 dry=clean and equal(before,s['after_dry'])and equal(rows['before']['clips'],rows['after_dry']['clips'])
 history=(clean and equal(written,s['before_undo'])and equal(before,undone)and equal(written,redone) and written['history']==before['history']+1 and written['global_history']==before['global_history']and written['nodes']!=before['nodes'])
 saved=clean and equal(semantic(written),semantic(s['persisted']))
 paths=clean and tracks_valid(rows['after_write'])and tracks_valid(rows['persisted'])
 return {'dry_run':'pass'if dry else'fail','undo_redo':'pass'if history else'fail','save_reopen':'pass'if saved else'fail','track_paths_types':'pass'if paths else'fail'}

def fixed(request):
 wanted={'op':'character_setup','player_path':'/RepairRigFixture/AnimationPlayer','skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D','duration':1.0,'run_duration':.7,'idle_duration':2.0,'speed':.7,'run_speed':1.4,'root_motion':True,'include_jump':True,'include_turn':True,'active':False,'samples':30}
 return equal(request,wanted)or equal(request,{k:v for k,v in wanted.items()if k!='speed'})

def verify_event(event,context,events,public,begins,support):
 for path in DEPS:
  d=context.get('dependencies',{}).get(path,{})
  require(digest(d.get('sha256'))and digest(d.get('git_blob'),40),'unbound setup observer dependency: '+path)
 marker=event.get('row',{}).get('marker',{});token=marker.get('token')
 require(digest(token,32)and fixed(marker.get('request',{})),'setup token/request mismatch')
 require(marker.get('context_sha256')==event.get('context_sha256')and marker.get('run_id')==context.get('run_id')and bool(context.get('run_id'))and marker.get('operation')=='animation_motion.character_setup','setup marker context mismatch')
 scene=marker.get('scene','');require(re.fullmatch(r'res://repair_motion_audit/[0-9]{8}_[0-9]{6}/setup_secondary\.tscn',scene)is not None,'unknown setup checkpoint scene')
 candidates=[e for e in events if e.get('validator')=='setup_history_v1'and e.get('row',{}).get('marker',{}).get('token')==token]
 require(len(candidates)in(len(PHASES),len(PHASES)+2),'duplicate/missing setup observation')
 rows={};spans={};ids=[]
 for item in candidates:
  row=item.get('row',{});phase=row.get('phase');m=row.get('marker',{})
  require(row.get('mode')=='setup_checkpoint'and phase in PHASES+('before_refusal','after_refusal') and phase not in rows and {k:v for k,v in m.items()if k!='phase'}=={k:v for k,v in marker.items()if k!='phase'},'setup marker changed')
  require(item.get('operation')=='animation_motion.character_setup'and item.get('driver')=='test_animation_motion.gd'and item.get('route')=='public_test_run_inner_dispatch'and item.get('run_id')==context['run_id']and item.get('context_sha256')==event.get('context_sha256'),'setup observation source/context mismatch')
  test='test_public_setup_bundle_undo_redo'if phase in ('before_undo','undone','redone')else'test_public_setup_evidence_snapshot'
  starts=[b for b in begins if b.get('id')==item.get('test_run_begin_id')];ends=[b for b in support if b.get('public_tool')=='test_run'and b.get('test_run_begin_id')==item.get('test_run_begin_id')]
  require(len(starts)==len(ends)==1,'setup observation lacks exact public helper span')
  start,end=starts[0],ends[0];wanted={'suite':'animation_motion','test_name':test,'verbose':True}
  require(start.get('request')==end.get('request')==wanted and start.get('scene')==end.get('scene')==scene and start.get('driver')==end.get('driver')=='mcp_motion_setup_secondary.py'and start['execution_ns']<end['execution_ns']and start['time_ns']<=item['time_ns']<=end['time_ns'],'setup helper request/order/scene mismatch')
  outcomes=[r for r in end.get('response',{}).get('results',[])if r.get('suite')=='animation_motion'and r.get('test')==test]
  require(len(outcomes)==1 and outcomes[0].get('passed')is True and not outcomes[0].get('skipped',False)and type(outcomes[0].get('assertion_count'))is int and outcomes[0]['assertion_count']>0,'setup helper did not execute')
  rows[phase]=row;spans[phase]=(start,end);ids.append(item['id'])
 require(event.get('id')==next(e['id']for e in candidates if e['row']['phase']=='persisted'),'only completed setup checkpoint may derive checks')
 def calls(params):return [p for p in public if p.get('operation')=='animation_motion.character_setup'and p.get('driver')=='mcp_motion_setup_secondary.py'and p.get('scene')==scene and p.get('params')==params and p.get('route')=='public_godot_ai'and success(p.get('response'))]
 dry=calls(dict(marker['request'],dry_run=True));write=calls(marker['request']);require(len(dry)==len(write)==1,'setup requires exact original dry/write calls')
 dry,write=dry[0],write[0]
 require(spans['before'][1]['execution_ns']<dry['execution_ns']<spans['after_dry'][0]['execution_ns']and spans['after_dry'][1]['execution_ns']<write['execution_ns']<spans['after_write'][0]['execution_ns']and spans['after_write'][1]['execution_ns']<spans['before_undo'][0]['execution_ns'],'setup public calls/observations out of order')
 require(spans['before_undo'][0]['id']==spans['undone'][0]['id']==spans['redone'][0]['id'],'setup history observations come from different calls')
 history=[e for e in candidates if e['row']['phase']in('before_undo','undone','redone')];require([e['row']['phase']for e in sorted(history,key=lambda e:e['time_ns'])]==['before_undo','undone','redone'],'native Undo/Redo observation order differs')
 saves=[s for s in support if s.get('public_tool')=='scene_save'and s.get('scene')==scene and s.get('driver')=='mcp_motion_setup_secondary.py'and success(s.get('response'))and spans['redone'][1]['execution_ns']<s['execution_ns']<spans['persisted'][0]['execution_ns']]
 opens=[s for s in support if s.get('public_tool')=='scene_open'and s.get('request')=={'path':scene,'force_reload':True}and s.get('driver')=='mcp_motion_setup_secondary.py'and success(s.get('response'))and spans['redone'][1]['execution_ns']<s['execution_ns']<spans['persisted'][0]['execution_ns']]
 require(len(saves)==len(opens)==1 and saves[0]['execution_ns']<opens[0]['execution_ns'],'setup-only save/forced reopen not bound')
 require(digest(rows['persisted'].get('scene_sha256')),'saved setup scene hash missing')
 other=[p for p in public if p.get('scene')==scene and write['execution_ns']<p.get('execution_ns',0)<spans['persisted'][1]['execution_ns']and p.get('operation')not in {'animation_motion.character_setup'}]
 require(not other,'another operation contaminated setup-only checkpoint')
 require(set(PHASES)<=set(rows),'missing original setup phase')
 checks=derive({p:rows[p]for p in PHASES})
 from operation_setup_source_checks import verify_extra,LIMITS as SOURCE_LIMITS
 extra,extra_ids=verify_extra(rows,spans,public,context);checks.update(extra)
 return {'checks':checks,'public_test_run_case_id':spans['redone'][1]['id'],'public_case_ids':[dry['id'],write['id']]+extra_ids+ids+[saves[0]['id'],opens[0]['id']],'limits':LIMITS+' '+SOURCE_LIMITS}
