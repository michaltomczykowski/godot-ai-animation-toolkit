"""Five narrowly bound public read responses; unobserved semantics stay pending."""
from __future__ import annotations
import hashlib
import json
import math
import re
from operation_snapshot_checks import equivalent, successful, error_code

# Independent names: 56 literal Model strings in the committed public FBX.
EXPECTED_BONES=('B-chest', 'B-foot.L', 'B-foot.R', 'B-forearm.L', 'B-forearm.R', 'B-hand.L', 'B-hand.R', 'B-handProp.L', 'B-handProp.R', 'B-head', 'B-hips', 'B-indexFinger01.L', 'B-indexFinger01.R', 'B-indexFinger02.L', 'B-indexFinger02.R', 'B-indexFinger03.L', 'B-indexFinger03.R', 'B-jaw', 'B-middleFinger01.L', 'B-middleFinger01.R', 'B-middleFinger02.L', 'B-middleFinger02.R', 'B-middleFinger03.L', 'B-middleFinger03.R', 'B-neck', 'B-pinky01.L', 'B-pinky01.R', 'B-pinky02.L', 'B-pinky02.R', 'B-pinky03.L', 'B-pinky03.R', 'B-ringFinger01.L', 'B-ringFinger01.R', 'B-ringFinger02.L', 'B-ringFinger02.R', 'B-ringFinger03.L', 'B-ringFinger03.R', 'B-root', 'B-shin.L', 'B-shin.R', 'B-shoulder.L', 'B-shoulder.R', 'B-spine', 'B-spineProxy', 'B-thigh.L', 'B-thigh.R', 'B-thumb01.L', 'B-thumb01.R', 'B-thumb02.L', 'B-thumb02.R', 'B-thumb03.L', 'B-thumb03.R', 'B-toe.L', 'B-toe.R', 'B-upperArm.L', 'B-upperArm.R')
MODEL='test_project/models/human_dummy/HumanCharacterDummy_F.fbx'
DEPENDENCIES=('tools/operation_bounded_read_checks.py','tools/mcp_presets_audit.py',
 'addons/godot_ai_animation/handlers/inspect.gd','addons/godot_ai_animation/handlers/rig.gd',
 'addons/godot_ai_animation/spec/pose_math.gd','addons/godot_ai_animation/spec/rig_analysis.gd',MODEL)
INSPECT_SCENE='res://repair_motion_fixture.tscn'
PLAYER='/MotionWalk/WalkAnim'
SKELETON='/MotionWalk/Dummy/Skeleton3D'
CLIP='repair_probe_walk'
RIG_SKELETON='/RepairRigFixture/Dummy/Skeleton3D'
ROLES={'hips':'B-hips','foot_l':'B-foot.L','foot_r':'B-foot.R','thigh_l':'B-thigh.L','thigh_r':'B-thigh.R'}
SOURCES={'animation_inspect.rig_profile':'mcp_inspect_3d.py','animation_inspect.sample':'mcp_inspect_3d.py',
 'animation_inspect.motion_audit':'mcp_inspect_3d.py','animation_rig.pose_list':'mcp_rig_pose_crud.py',
 'animation_rig.rig_get':'mcp_rig_pose_apply_audit.py'}


def number(v):return type(v) in (float,int) and math.isfinite(v)
def near(v,w):return number(v) and abs(v-w)<1e-5

def quaternion(value):
 if not isinstance(value,str) or not re.fullmatch(r'\(\s*[-+0-9.eE]+,\s*[-+0-9.eE]+,\s*[-+0-9.eE]+,\s*[-+0-9.eE]+\s*\)',value):return None
 try:values=[float(x) for x in value.strip('()').split(',')]
 except ValueError:return None
 return values if all(number(x) for x in values) else None


def fixed_request(row):
 key=row.get('operation');request=row.get('request',{});op=key.split('.')[-1] if key in SOURCES else ''
 base={'player_path':PLAYER,'skeleton_path':SKELETON,'animation_name':CLIP}
 if key=='animation_inspect.rig_profile':return {'op':op,'skeleton_path':SKELETON,'save':False}
 if key=='animation_inspect.sample':return {'op':op,**base,'samples':8,'bones':['B-foot.L','B-foot.R']}
 if key=='animation_inspect.motion_audit':return {'op':op,**base,'samples':120}
 if key=='animation_rig.rig_get':return {'op':op,'skeleton_path':RIG_SKELETON}
 if key=='animation_rig.pose_list':
  directory=request.get('directory','')
  if not re.fullmatch(r'res://animation_toolkit/repair_audit/rig_poses_[0-9]{8}_[0-9]{6}',directory):raise ValueError('unbound pose directory')
  return {'op':op,'directory':directory}
 raise ValueError('unknown bounded read operation')


def structural_sample(result):
 bones=result.get('bones',{})
 return (successful(result) and result.get('sample_count')==8 and result.get('missing_bones')==[]
  and near(result.get('length'),1) and result.get('bones_truncated') is False and set(bones)=={'B-foot.L','B-foot.R'}
  and len(result.get('times',[]))==8 and all(near(v,i/7) for i,v in enumerate(result['times']))
  and all(len(b.get('positions',[]))==8 and all(isinstance(v,list) and len(v)==3 and all(number(x) for x in v) for v in b['positions']) for b in bones.values()))


def structural_audit(result):
 support=result.get('support',{});trace=support.get('trace',[]);counts=support.get('counts',{})
 return (successful(result) and result.get('passed') is True and result.get('failed_checks')==0
  and support.get('sample_count')==120 and len(trace)==120
  and all(type(counts.get(k)) is int and counts[k]>=0 for k in ('l','r','both','flight'))
  and sum(counts[k] for k in ('l','r','both','flight'))==120 and counts['l']+counts['r']>0
  and all(number(support.get(k)) for k in ('max_abs_hip_forward','max_abs_hip_lateral')))


def pose_files_valid(row):
 files=row.get('files_before',{});directory=row['request']['directory'];result=row['result']
 if set(files)!={'rest.json','arm.json'} or not equivalent(files,row.get('files_after')):return False
 for name,data in files.items():
  text=data.get('raw_utf8')
  if not isinstance(text,str) or hashlib.sha256(text.encode()).hexdigest()!=data.get('sha256'):return False
  try:content=json.loads(text)
  except ValueError:return False
  if not equivalent(content,data.get('content')) or content.get('format')!='godot-ai-animation-pose' or type(content.get('version')) is not int or content.get('version')!=1 or content.get('rest_relative') is not True or set(content.get('bones',{}))!=set(EXPECTED_BONES):return False
 poses=result.get('poses',[])
 return (successful(result) and result.get('directory')==directory and result.get('exists') is True and result.get('pose_count')==2
  and poses==[{'name':name,'path':directory+'/'+name+'.json','bone_count':56,'source':RIG_SKELETON} for name in ('arm','rest')])


def rig_get_valid(result):
 if not successful(result) or result.get('bone_count')!=56 or result.get('kind')!='3d' or result.get('skeleton_path')!=RIG_SKELETON:return False
 bones=result.get('bones',[])
 if not isinstance(bones,list) or len(bones)!=56 or not all(isinstance(b,dict) and type(b.get('index')) is int for b in bones) or {b.get('name') for b in bones}!=set(EXPECTED_BONES) or sorted(b.get('index',-2) for b in bones)!=list(range(56)):return False
 for b in bones:
  parent=b.get('parent');index=b.get('index')
  if type(parent) is not int or parent>=index or parent< -1:return False
  for field in ('rest_position','rest_scale','pose_position'):
   if set(b.get(field,{}))!={'x','y','z'} or not all(number(x) for x in b[field].values()):return False
  if quaternion(b.get('pose_rotation')) is None:return False
 arm=next(b for b in bones if b['name']=='B-upperArm.L');q=quaternion(arm['pose_rotation'])
 expected=(0,math.sin(.3),0,math.cos(.3))
 return all(near(v,w) for v,w in zip(q,expected)) and all(near(v,0) for v in arm['pose_position'].values())


def derive(row):
 key=row.get('operation')
 if row.get('request')!=fixed_request(row):raise ValueError('bounded read request mismatch')
 result=row.get('result',{})
 if key=='animation_inspect.rig_profile':
  valid=(successful(result) and result.get('kind')=='3d' and result.get('bone_count')==56
   and result.get('skeleton_path')==SKELETON and result.get('saved')==''
   and all(result.get('roles',{}).get(k)==v for k,v in ROLES.items())
   and result.get('capabilities',{}).get('walk_cycle') is True and result.get('missing',{}).get('locomotion')==[])
 elif key=='animation_inspect.sample':valid=structural_sample(result)
 elif key=='animation_inspect.motion_audit':valid=structural_audit(result)
 elif key=='animation_rig.pose_list':valid=pose_files_valid(row)
 else:valid=rig_get_valid(result)
 # Schema/counters and passed flags cannot establish independent FK/contact correctness.
 effect='pending' if valid and key in {'animation_inspect.sample','animation_inspect.motion_audit'} else ('pass' if valid else 'fail')
 code='pending' if key=='animation_rig.pose_list' else ('pass' if error_code(row.get('typed_error'))=='NODE_NOT_FOUND' else 'fail')
 return {'valid_effect':effect,'typed_errors':code,'source_unchanged':'pending','reported_errors':'pending'}


def verify_event(event,context,public_events,scene_events):
 row=event.get('row',{});key=row.get('operation');source=SOURCES.get(key)
 deps=DEPENDENCIES+('tools/'+str(source),)+(('test_project/repair_motion_fixture.tscn','test_project/tools/repair_motion_playback.gd') if key and key.startswith('animation_inspect.') else ('test_project/repair_rig_fixture.tscn','tools/fixture_copy.py'))
 if event.get('validator')!='bounded_read_v1' or event.get('driver')!=source or any(p not in context.get('dependencies',{}) for p in deps):raise ValueError('bounded read source/dependency mismatch')
 if event.get('operation')!=key or row.get('request')!=fixed_request(row):raise ValueError('bounded read operation/request mismatch')
 scene=row.get('scene','')
 if (scene!=INSPECT_SCENE if key.startswith('animation_inspect.') else re.fullmatch(r'res://repair_rig_audit/[0-9]{8}_[0-9]{6}/'+('poses' if key.endswith('pose_list') else 'pose_apply')+r'\.tscn',scene) is None):raise ValueError('bounded read scene mismatch')
 def matches(operation,params,response):
  return [e for e in public_events if e.get('operation')==operation and e.get('driver')==source and e.get('scene')==scene and e.get('public_tool')=='custom_'+operation.split('.')[0] and e.get('route')=='public_godot_ai' and equivalent(e.get('params'),params) and equivalent(e.get('response'),response) and e['execution_ns']<event['execution_ns']]
 reads=matches(key,row['request'],row.get('result'))
 if not reads:raise ValueError('bounded read lacks exact actual response/call')
 read=min(reads,key=lambda e:e['execution_ns']);ids=[read['id']]
 opened=[e for e in scene_events if e.get('public_tool')=='scene_open' and e.get('request',{}).get('path')==scene and equivalent(e.get('response'),row.get('open')) and successful(e.get('response')) and e['execution_ns']<read['execution_ns']]
 if not opened:raise ValueError('bounded read lacks actual scene open')
 ids.append(max(opened,key=lambda e:e['execution_ns'])['id'])
 if key!='animation_rig.pose_list':
  bad=({'op':key.split('.')[-1],'player_path':PLAYER,'animation_name':CLIP,'skeleton_path':'/MotionWalk/Missing'} if key.startswith('animation_inspect.') else {'op':'rig_get','skeleton_path':'/DefinitelyMissingSkeleton'})
  if row.get('error_request')!=bad:raise ValueError('bounded read refusal request mismatch')
  refusals=matches(key,bad,row.get('typed_error'))
  if not refusals or min(e['execution_ns'] for e in refusals)<=read['execution_ns']:raise ValueError('bounded read lacks ordered exact refusal')
  ids.append(min(refusals,key=lambda e:e['execution_ns'])['id'])
 if key.startswith('animation_inspect.'):
  probe={'op':'describe','player_path':PLAYER,'animation_name':CLIP}
  before=matches('animation_inspect.describe',probe,row.get('before'))
  after=matches('animation_inspect.describe',probe,row.get('after'))
  if not before or not after or min(x['execution_ns'] for x in before)>=read['execution_ns'] or max(x['execution_ns'] for x in after)<=max(x['execution_ns'] for x in refusals):raise ValueError('bounded read missing actual before/after describe observations')
  ids.extend([min(before,key=lambda e:e['execution_ns'])['id'],max(after,key=lambda e:e['execution_ns'])['id']])
 if key=='animation_rig.pose_list':
  if not row.get('files_before_execution_ns',0)<read['execution_ns']<row.get('files_after_execution_ns',0)<event['execution_ns']:raise ValueError('pose directory observations do not bracket actual read')
  saves=row.get('save_requests',[]);responses=row.get('save_results',[])
  expected=[{'op':'pose_save','skeleton_path':RIG_SKELETON,'pose_dir':row['request']['directory'],'name':n} for n in ('rest','arm')]
  if saves!=expected or len(responses)!=2:raise ValueError('pose_list lacks expected authored pose producers')
  for req,response in zip(saves,responses):
   producers=matches('animation_rig.pose_save',req,response)
   if not successful(response) or not producers or max(e['execution_ns'] for e in producers)>=read['execution_ns']:raise ValueError('pose_list producer not bound')
   ids.append(max(producers,key=lambda e:e['execution_ns'])['id'])
 if key=='animation_rig.rig_get':
  from mcp_rig_pose_apply_audit import SKELETON as skeleton
  req=row.get('producer_request',{});pose=req.get('pose',{})
  expected_pose={'format':'godot-ai-animation-pose','version':1,'rest_relative':True,'bones':{'B-upperArm.L':{'rotation':{'kind':'quaternion','x':0,'y':math.sin(.3),'z':0,'w':math.cos(.3)},'position':{'kind':'vector3','x':0,'y':0,'z':0},'scale':{'kind':'vector3','x':1,'y':1,'z':1}}}}
  if not equivalent(req,{'op':'pose_apply','skeleton_path':skeleton,'pose':expected_pose}):raise ValueError('rig_get producer request mismatch')
  producers=matches('animation_rig.pose_apply',req,row.get('producer_response'))
  if not successful(row.get('producer_response')) or not producers or max(e['execution_ns'] for e in producers)>=read['execution_ns']:raise ValueError('rig_get lacks prior actual pose_apply')
  ids.append(max(producers,key=lambda e:e['execution_ns'])['id'])
 checks=derive(row)
 if checks!=event.get('checks'):raise ValueError('bounded read declared checks mismatch')
 return {'checks':checks,'public_case_ids':ids,'dry_case_ids':[],'failures':[],
  'limits':'Fixed authored public dummy/requests only. source_unchanged and reported_errors pending: describe equality/disk bytes do not prove live scene or full engine log invariance. Sample/motion_audit valid_effect pending independent FK/contact reference. pose_list typed_errors pending: missing directory is successful empty-list contract. No preview/playback/visual approval.'}
