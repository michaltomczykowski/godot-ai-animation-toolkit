"""One existing public pose_blend missing-input refusal and exact file atomicity."""
import hashlib
import json
import re
import time
from pathlib import Path
from operation_snapshot_checks import equivalent, successful

DEPENDENCIES=('tools/operation_pose_blend_refusal_checks.py','tools/mcp_rig_pose_crud.py',
 'tools/mcp_presets_audit.py','tools/fixture_copy.py','test_project/repair_rig_fixture.tscn',
 'addons/godot_ai_animation/handlers/rig.gd','addons/godot_ai_animation/spec/pose_math.gd')


def directory_bytes(directory):
 directory=Path(directory)
 if not directory.is_dir():return {'exists':False,'entries':{}}
 entries={}
 for path in sorted(directory.rglob('*')):
  if path.is_symlink():raise ValueError('pose refusal directory must not contain links')
  name=path.relative_to(directory).as_posix()
  if path.is_dir():entries[name]={'type':'directory'}
  else:
   raw=path.read_bytes();entries[name]={'type':'file','bytes_hex':raw.hex(),'sha256':hashlib.sha256(raw).hexdigest()}
 return {'exists':True,'entries':entries}


async def observe_missing_pose(client,call,scene,pose_dir,disk_dir,blend_base,producer_response):
 # Reuses the driver's existing refusal exactly once. No successful call is retried.
 from operation_case_collector import record_snapshot_result
 request={**blend_base,'from':'definitely_missing','name':'half','overwrite':True}
 before=directory_bytes(disk_dir);before_ns=time.perf_counter_ns()
 result=await call(client,'custom_animation_rig',request)
 after=directory_bytes(disk_dir);after_ns=time.perf_counter_ns()
 record_snapshot_result('pose_blend_refusal_v1',{'operation':'animation_rig.pose_blend',
  'scene':scene,'request':request,'result':result,'directory':pose_dir,
  'before':before,'after':after,'before_execution_ns':before_ns,'after_execution_ns':after_ns,
  'producer_request':{**blend_base,'name':'half'},'producer_response':producer_response})
 return result


def fixed_request(row):
 directory=row.get('directory','')
 if not re.fullmatch(r'res://animation_toolkit/repair_audit/rig_poses_[0-9]{8}_[0-9]{6}',directory):raise ValueError('pose refusal directory not source-bound')
 return {'op':'pose_blend','pose_dir':directory,'from':'definitely_missing','to':'arm','factor':.5,'name':'half','overwrite':True}


def file_contents(snapshot):
 if not isinstance(snapshot,dict) or snapshot.get('exists') is not True or set(snapshot.get('entries',{}))!={'rest.json','arm.json','half.json'}:raise ValueError('pose refusal must observe complete existing three-file directory')
 result={}
 for name,item in snapshot['entries'].items():
  if item.get('type')!='file' or set(item)!={'type','bytes_hex','sha256'}:raise ValueError('pose refusal contains unexpected directory entry type')
  try:raw=bytes.fromhex(item['bytes_hex'])
  except (ValueError,TypeError):raise ValueError('pose refusal malformed file bytes')
  if hashlib.sha256(raw).hexdigest()!=item.get('sha256'):raise ValueError('pose refusal file hash differs from bytes')
  result[name]=raw
 return result


def derive(row):
 if row.get('operation')!='animation_rig.pose_blend' or row.get('request')!=fixed_request(row):raise ValueError('pose refusal operation/request differs from source contract')
 before=file_contents(row.get('before'));after=file_contents(row.get('after'))
 directory=row['directory'];error=row.get('result',{}).get('error')
 expected_message='Pose file not found: '+directory+'/definitely_missing.json'
 typed=(error==('INVALID_PARAMS: '+expected_message) if isinstance(error,str)
        else isinstance(error,dict) and error.get('code')=='INVALID_PARAMS' and error.get('message')==expected_message)
 producer=row.get('producer_response',{})
 try:half=json.loads(before['half.json'].decode('utf-8'))
 except (ValueError,UnicodeError):half=None
 prior=(successful(producer) and producer.get('saved_path')==directory+'/half.json'
  and producer.get('factor')==.5 and producer.get('undoable') is False and isinstance(half,dict)
  and half.get('format')=='godot-ai-animation-pose' and type(half.get('version')) is int and half['version']==1 and half.get('rest_relative') is True
  and isinstance(half.get('bones'),dict) and bool(half['bones']) and equivalent(half,producer.get('pose')))
 return {'typed_errors':'pass' if typed and before==after and prior else 'fail'}


def verify_event(event,context,public_events,scene_events):
 row=event.get('row',{})
 if event.get('validator')!='pose_blend_refusal_v1' or event.get('operation')!='animation_rig.pose_blend' or event.get('driver')!='mcp_rig_pose_crud.py' or event.get('route')!='public_godot_ai':raise ValueError('pose refusal source/case identity differs')
 if any(p not in context.get('dependencies',{}) for p in DEPENDENCIES):raise ValueError('pose refusal dependencies missing')
 if not isinstance(event.get('context_sha256'),str) or not re.fullmatch('[0-9a-f]{64}',event['context_sha256']) or not event.get('run_id') or event['run_id']!=context.get('run_id'):raise ValueError('pose refusal context identity absent')
 scene=row.get('scene','')
 if not re.fullmatch(r'res://repair_rig_audit/[0-9]{8}_[0-9]{6}/poses\.tscn',scene):raise ValueError('pose refusal scene differs from source driver')
 request=fixed_request(row)
 producer={k:v for k,v in request.items() if k not in ('overwrite',)};producer['from']='rest'
 if row.get('producer_request')!=producer:raise ValueError('pose refusal prior producer request differs')
 def bound(e):return e.get('run_id')==event['run_id'] and e.get('context_sha256')==event['context_sha256']
 def matches(req,response):
  return [e for e in public_events if bound(e) and e.get('operation')=='animation_rig.pose_blend' and e.get('public_tool')=='custom_animation_rig'
   and e.get('driver')=='mcp_rig_pose_crud.py' and e.get('route')=='public_godot_ai' and e.get('scene')==scene
   and e.get('request')==req and e.get('params')==req and equivalent(e.get('response'),response)]
 bad=matches(request,row.get('result'));made=matches(producer,row.get('producer_response'))
 if len(bad)!=1 or len(made)!=1:raise ValueError('pose refusal lacks unique actual producer/refusal calls')
 if not (made[0]['execution_ns']<row.get('before_execution_ns',0)<bad[0]['execution_ns']<row.get('after_execution_ns',0)<event.get('execution_ns',0)):raise ValueError('pose refusal bytes do not bracket actual completed call')
 opens=[e for e in scene_events if bound(e) and e.get('public_tool')=='scene_open' and e.get('request',{}).get('path')==scene and successful(e.get('response')) and e.get('execution_ns',0)<made[0]['execution_ns']]
 if not opens:raise ValueError('pose refusal lacks actual preceding scene open')
 checks=derive(row)
 if event.get('checks')!=checks:raise ValueError('pose refusal declared checks differ')
 return {'checks':checks,'public_case_ids':[made[0]['id'],bad[0]['id']],'dry_case_ids':[],
  'failures':[] if checks['typed_errors']=='pass' else ['missing-input refusal or output/directory atomicity failed'],
  'limits':'One actual pose_blend missing-file refusal with existing output and complete isolated-directory bytes unchanged. No scene/history, valid-effect, playback or invocation approval inferred.'}
