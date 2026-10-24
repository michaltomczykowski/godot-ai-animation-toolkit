"""Recompute eight authored synthetic rig-clip intentions from actual native values."""
import json
import math
import re
from operation_rig_scene_history_checks import WRITERS, verify_event as verify_origin, digest

LAYOUTS={'local','overwrite','missing_library','instanced','editable'}
DEPENDENCIES=('tools/operation_rig_clip_native_checks.py','tools/mcp_rig_clip_history.py',
 'test_project/tools/check_rig_clip_history.gd','tools/operation_rig_scene_history_checks.py')
BONES={'hips','spine','chest','head','eye'}|{n+'_'+s for s in ('L','R') for n in ('thigh','shin','foot','arm','forearm','hand')}
REQUIRED={
 'pose_to_clip':{('arm_L',2)},'walk_cycle':{('thigh_L',2),('hips',1)},
 'idle_breathing':{('chest',2),('head',2),('hips',1)},'blink':{('eye',3)},
 'jumping_jack':{('arm_L',2),('arm_R',2),('hips',1)},'squat':{('hips',1)},
 'punch':{('arm_L',2),('arm_R',2),('hips',1)},'bake_pose_sequence':{('hips',1),('hips',2),('hips',3)}}

def num(v):return type(v) in (float,int) and math.isfinite(v)
def approx(a,b):return num(a) and abs(a-b)<max(1e-5,abs(a)*1e-5)
def vec(a,b):return isinstance(a,list) and len(a)==len(b) and all(approx(x,y) for x,y in zip(a,b))
def axis(axis,angle):
 q=[0.,0.,0.,math.cos(angle/2)];q[axis]=math.sin(angle/2);return q

def multiply(a,b):
 x,y,z,w=a;u,v,r,s=b
 return [w*u+x*s+y*r-z*v,w*v-x*r+y*s+z*u,w*r+x*v-y*u+z*s,w*s-x*u-y*v-z*r]

def rotation(actual,expected):
 if not isinstance(actual,list) or len(actual)!=4 or not all(num(v) for v in actual):return False
 norm=sum(v*v for v in actual)
 if abs(norm-1)>1e-5:return False
 dot=abs(sum(a*b for a,b in zip(actual,expected)))
 return 2*math.acos(min(1.,max(-1.,dot)))<.002


def contract(op):
 rows=[];times=[]
 def at(t):times.append(t)
 def add(metric,bone,t,value):rows.append((metric,bone,t,value))
 if op=='pose_to_clip':
  for t in (0.,.25,.5,.75,1.):at(t);add('rotation','arm_L',t,axis(2,-math.pi/2+.6*t))
 elif op=='walk_cycle':
  for t in (0.,.25,.5,.75,1.):
   at(t);angle=math.radians(25*(1-4*t if t<=.5 else 4*t-3))
   add('rotation','thigh_L',t,multiply(axis(2,math.pi),axis(0,angle)))
   add('position','hips',t,[0,1.1+(.05 if t in (.25,.75) else 0),0])
 elif op=='idle_breathing':
  at(.35);add('rotation','chest',.35,axis(0,math.radians(1.6)));add('rotation','head',.35,axis(0,math.radians(-1)))
  at(.5);add('position','hips',.5,[0,1.11,0])
 elif op=='blink':
  for t,y in ((0.,1),(.2,.55),(.4,.1),(.55,.1),(1.,1)):at(t);add('scale','eye',t,[1,y,1])
 elif op=='jumping_jack':
  at(.5);add('rotation','arm_L',.5,axis(2,math.radians(-10)));add('rotation','arm_R',.5,axis(2,math.radians(10)));add('position','hips',.5,[0,1.14,0])
 elif op=='squat':
  for t in (.35,.5,.65):
   at(t);add('position','hips',t,[0,.9,0])
   for side,x in (('L',.2),('R',-.2)):add('ankle_rest_distance','foot_'+side,t,[x,0,0])
 elif op=='punch':
  for t,side in ((.175,'L'),(.675,'R')):at(t);add('direction','arm_'+side,t,[0,0,1]);add('position','hips',t,[0,1.05,0])
 elif op=='bake_pose_sequence':
  for t in (0.,.125,.25,.375,.5,.75,1.):
   at(t);add('rotation','hips',t,axis(0,.1+.6*t));add('position','hips',t,[.02,1.13,0]);add('scale','hips',t,[1.1,.9,1.05])
 else:raise ValueError('not an authored rig clip writer')
 return rows,times


def derive(case):
 op=case['op'];wanted,times=contract(op)
 clip=case.get('clip',{});tracks=case.get('tracks',[])
 paths=(approx(clip.get('length'),1) and type(clip.get('loop')) is int and clip['loop']==0 and clip.get('root')=='../../Character' and clip.get('root_resolves') is True
  and type(clip.get('track_count')) is int and clip['track_count']>0 and clip['track_count']==len(tracks))
 pairs=set()
 for track in tracks:
  bone=track.get('bone');kind=track.get('type');pairs.add((bone,kind))
  paths=paths and bone in BONES and type(kind) is int and kind in {1,2,3} and track.get('path')=='Skeleton:'+str(bone) and track.get('target_class')=='Skeleton3D' and track.get('target_relative_to_skeleton')=='.' and type(track.get('bone_index')) is int and track['bone_index']>=0
 paths=paths and REQUIRED[op].issubset(pairs)
 rows=[r for r in case.get('observations',[]) if r.get('phase')=='authored']
 effects=len(rows)==len(wanted)
 for row,(metric,bone,time,expected) in zip(rows,wanted):
  effects=effects and row.get('metric')==metric and row.get('bone')==bone and approx(row.get('at'),time)
  actual=row.get('actual')
  if metric=='rotation':okay=rotation(actual,expected)
  elif metric=='direction':okay=isinstance(actual,list) and len(actual)==3 and all(num(v) for v in actual) and abs(sum(v*v for v in actual)-1)<1e-5 and actual[2]>.95
  elif metric=='ankle_rest_distance':
   okay=isinstance(actual,dict) and vec(actual.get('rest'),expected) and isinstance(actual.get('pose'),list) and len(actual['pose'])==3 and all(num(v) for v in actual['pose'])
   okay=okay and math.dist(actual['pose'],actual['rest'])<.003
  else:okay=vec(actual,expected)
  effects=effects and okay
 clocks=[c for c in case.get('clocks',[]) if c.get('phase')=='authored']
 clock=(len(clocks)==len(times) and all(approx(c.get('requested'),t) and approx(c.get('position'),t) and c.get('assigned')=='generated' and num(c.get('speed')) and c['speed']==1 and type(c.get('process')) is int and c['process']==2 for c,t in zip(clocks,times)))
 return {'valid_effect':'pass' if effects and clock else 'fail','track_paths_types':'pass' if paths else 'fail','playback':'pass' if effects and paths and clock else 'fail'}


def is_event(event):return 'res://tools/check_rig_clip_history.gd' in event.get('command',[])


def verify_native(event,context,origins,begins,support):
 op=event.get('operation','').removeprefix('animation_rig.');cmd=event.get('command',[])
 if event.get('run_id')!=context.get('run_id') or op not in WRITERS or event.get('driver')!='mcp_rig_clip_history.py' or event.get('route')!='native_godot' or not cmd or cmd[0]!=context.get('engine_command'):raise ValueError('rig clip native source/operation/engine mismatch')
 for path in DEPENDENCIES:
  v=context.get('dependencies',{}).get(path,{})
  if not digest(v.get('sha256')) or not re.fullmatch('[0-9a-f]{40}',str(v.get('git_blob',''))):raise ValueError('rig clip native missing committed source dependency')
 try:script=cmd[cmd.index('--script')+1];args=cmd[cmd.index('--')+1:]
 except (ValueError,IndexError):raise ValueError('rig clip native missing exact command')
 if len(cmd)!=8 or cmd[1:3]!=['--headless','--path'] or not isinstance(cmd[3],str) or not cmd[3] or cmd[4:7]!=['--script','res://tools/check_rig_clip_history.gd','--'] or script!='res://tools/check_rig_clip_history.gd' or len(args)!=1 or args[0] not in LAYOUTS or '--headless' not in cmd:raise ValueError('rig clip native command/layout mismatch')
 layout=args[0];scene=f'user://rig_clip_history_{layout}_3d_{op}_redo.tscn'
 if event.get('scene')!=scene:raise ValueError('rig clip native saved scene mismatch')
 marker='RIG_CLIP_HISTORY_RUNTIME=';payloads=[l[len(marker):] for l in event.get('stdout','').splitlines() if l.startswith(marker)]
 if len(payloads)!=1:raise ValueError('rig clip native missing/ambiguous raw report')
 report=json.loads(payloads[0]);cases=report.get('cases',[])
 labels={f'{layout}_3d_{name}_{stage}' for name in WRITERS for stage in ('undo','redo')}|{f'{layout}_2d_pose_to_clip_{stage}' for stage in ('undo','redo')}
 if report.get('layout')!=layout or len(cases)!=18 or {c.get('label') for c in cases}!=labels:raise ValueError('rig clip native report lacks exact case identities')
 selected=[c for c in cases if c.get('op')==op and c.get('kind')=='3d' and c.get('state')=='redo' and c.get('scene')==scene and c.get('layout')==layout]
 if len(selected)!=1:raise ValueError('rig clip native case missing/ambiguous')
 case=selected[0]
 if case.get('label')!=f'{layout}_3d_{op}_redo':raise ValueError('rig clip selected label differs from operation identity')
 matches=[e for e in origins if e.get('validator')=='rig_scene_history_v1' and e.get('operation')==event['operation'] and e.get('row',{}).get('kind')=='3d' and e['row'].get('mode')==layout and e['row'].get('persist_redo',{}).get('path')==scene and e['row']['persist_redo'].get('sha256')==case.get('sha256')]
 if len(matches)!=1 or not digest(case.get('sha256')):raise ValueError('rig clip native lacks unique exact saved SHA/public inner producer')
 origin=matches[0];proof=verify_origin(origin,context,begins,support)
 end=next(s for s in support if s.get('id')==proof['public_test_run_case_id'])
 if not end.get('execution_ns',0)<event.get('execution_ns',0):raise ValueError('rig clip native ran before real public test completion')
 checks=derive(case)
 raw=event.get('stdout','')+'\n'+event.get('stderr','')
 if event.get('returncode')!=0 or report.get('saved_states')!=18 or report.get('failures')!=[] or report.get('engine_errors')!=[] or case.get('failures')!=[] or 'ERROR:' in raw or any(v!='pass' for v in proof['checks'].values()):checks={k:'fail' for k in checks}
 return {'checks':checks,'public_test_run_case_id':proof['public_test_run_case_id'],'public_origin_id':origin['id'],'failures':[] if all(v=='pass' for v in checks.values()) else ['actual authored rig clip native/source contract failed'],
 'limits':'Exact fixed synthetic unskinned3D rig clip case at original manual-clock times/thresholds, joined by saved-scene SHA to actual public inner producer. Independent authored quaternion/vector/direction/rest-ankle expectations; no generated-key expected values. This native proof adds no physical grounding, skinning, visual, history, broad source or editor-error approval.'}
