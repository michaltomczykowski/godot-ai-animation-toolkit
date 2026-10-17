"""Seven exact saved-rig native playback contracts, never intended/visual promotion."""
import json
import math
from pathlib import PurePosixPath

MODIFIERS={'ik_setup':('TwoBoneIK3D',{'kind':'two_bone','chain':['B-upperArm.L','B-forearm.L','B-hand.L'],'target_name':'AuditHandTarget'}),'spring_setup':('SpringBoneSimulator3D',{'springs':[{'root_bone':'B-forearm.L','end_bone':'B-hand.L','stiffness':.3,'drag':.2,'gravity':.1,'radius':.02}]}),'look_at_setup':('LookAtModifier3D',{'bone':'B-head','target_name':'AuditHeadTarget','forward_axis':'+z'}),'twist_setup':('BoneTwistDisperser3D',{'disperse':{'root_bone':'B-hips','end_bone':'B-chest','mode':'even'}})}
OPS={'animation_rig.'+x for x in ('pose_apply','rig_chain')}|{'animation_rig_modifiers.'+x for x in (*MODIFIERS,'retarget_setup')}

def number(v):return not isinstance(v,bool) and isinstance(v,(int,float)) and math.isfinite(v)

def contract(operation):
 op=operation.split('.')[1]
 if operation not in OPS:raise ValueError('not a seven-rig playback operation')
 if op in MODIFIERS:return 'check_rig_modifiers_runtime.gd','RIG_MODIFIER_RUNTIME=',True
 if op=='retarget_setup':return 'check_retarget_runtime.gd','RETARGET_RUNTIME=',False
 return 'check_rig_saved_structure_runtime.gd','RIG_SAVED_STRUCTURE=',True

def verify_native(event,context):
 name,marker,parameterized=contract(event['operation']);op=event['operation'].split('.')[1];cmd=event.get('command',[])
 if not cmd or cmd[0]!=context.get('engine_command'):raise ValueError('engine identity differs')
 try:script=cmd[cmd.index('--script')+1];args=cmd[cmd.index('--')+1:]
 except (ValueError,IndexError):raise ValueError('missing exact native command')
 if script!='res://tools/'+name or args!=[event['scene']]+([op]if parameterized else []):raise ValueError('native script/scene/op mismatch')
 for path in ('tools/operation_rig_native_checks.py','test_project/tools/'+name):
  if path not in context.get('dependencies',{}):raise ValueError('source-bound dependency missing: '+path)
 if PurePosixPath(event['scene']).name!=op+'.tscn':raise ValueError('unexpected audited saved scene name')
 raw=event.get('stdout','')+'\n'+event.get('stderr','');payloads=[x[len(marker):]for x in event.get('stdout','').splitlines()if x.startswith(marker)]
 okay=event.get('returncode')==0 and 'ERROR:'not in raw and len(payloads)==1
 if len(payloads)!=1:return {'playback':'fail'},['missing/ambiguous exact native result']
 r=json.loads(payloads[0])
 if not isinstance(r,dict) or r.get('scene')!=event['scene'] or r.get('op',op)!=op:raise ValueError('native report scene/op mismatch')
 okay=okay and r.get('failures')==[]
 if op in MODIFIERS:
  okay=okay and r.get('modifier_class')==MODIFIERS[op][0] and number(r.get('response')) and r['response']>=.001
  if op in {'ik_setup','look_at_setup'}:okay=okay and r.get('target_resolved') is True
 elif op=='retarget_setup':okay=okay and number(r.get('processed')) and r['processed']>0 and number(r.get('target_head_change')) and r['target_head_change']>=.1
 else:
  okay=okay and r.get('samples')==6 and number(r.get('worst_error')) and r['worst_error']<.001
  if op=='pose_apply':okay=okay and r.get('bone')=='B-upperArm.L' and r.get('expected_angle')==.6
  else:okay=okay and r.get('bone')=='repair_tool_tip' and r.get('parent')=='B-hand.R' and type(r.get('bone_index'))is int and type(r.get('parent_index'))is int and r['bone_index']>=0 and r['parent_index']>=0 and r['bone_index']!=r['parent_index'] and number(r.get('parent_response')) and r['parent_response']>.1
 return {'playback':'pass'if okay else 'fail'},[]if okay else ['actual source-specific saved rig native contract failed']

def origin_matches(event,call):
 op=event['operation'].split('.')[1];p=call.get('params',{})
 if op in MODIFIERS:return p.get('active')is False and p.get('skeleton_path')=='/RepairRigFixture/Dummy/Skeleton3D' and all(p.get(k)==v for k,v in MODIFIERS[op][1].items())
 if op=='retarget_setup':return all(p.get(k)==v for k,v in {'skeleton_path':'/RepairRetargetFixture/Source','target_path':'/RepairRetargetFixture/Target','profile':'auto','rotation':True,'active':False,'move_target':True}.items())
 if p.get('skeleton_path')!='/RepairRigFixture/Dummy/Skeleton3D':return False
 if op=='rig_chain':return p.get('bones')==[{'name':'repair_tool_tip','parent':'B-hand.R','position':[0,.05,0]}] and call.get('response',{}).get('bones')==['repair_tool_tip'] and call['response'].get('bones_created')==1 and call['response'].get('skeleton_path')==p['skeleton_path']
 pose=p.get('pose',{});bone=pose.get('bones',{}).get('B-upperArm.L',{});q=bone.get('rotation',{})
 return pose.get('rest_relative')is True and set(pose.get('bones',{}))=={'B-upperArm.L'} and all(number(q.get(k)) and abs(q[k]-v)<1e-8 for k,v in {'x':0,'y':math.sin(.3),'z':0,'w':math.cos(.3)}.items()) and bone.get('position')=={'kind':'vector3','x':0,'y':0,'z':0} and bone.get('scale')=={'kind':'vector3','x':1,'y':1,'z':1} and p.get('blend',1)==1 and p.get('mirror',False)is False
