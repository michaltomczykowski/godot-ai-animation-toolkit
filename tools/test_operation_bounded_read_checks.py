import copy
import hashlib
import json
import math
import unittest
import operation_bounded_read_checks as checks

class BoundedReadTests(unittest.TestCase):
 def fixture(self,key):
  op=key.split('.')[-1];scene=checks.INSPECT_SCENE if key.startswith('animation_inspect.') else 'res://repair_rig_audit/20261018_123456/'+('poses' if op=='pose_list' else 'pose_apply')+'.tscn'
  row={'operation':key,'scene':scene,'open':{'opened':True},'request':{'directory':'res://animation_toolkit/repair_audit/rig_poses_20261018_123456'} if op=='pose_list' else {}}
  row['request']=checks.fixed_request(row);request=row['request']
  if op=='rig_profile':result={'skeleton_path':checks.SKELETON,'kind':'3d','bone_count':56,'saved':'','roles':dict(checks.ROLES),'capabilities':{'walk_cycle':True},'missing':{'locomotion':[]}}
  elif op=='sample':result={'sample_count':8,'missing_bones':[],'length':1,'bones_truncated':False,'times':[i/7 for i in range(8)],'bones':{n:{'positions':[[0,i/10,0] for i in range(8)]} for n in ('B-foot.L','B-foot.R')}}
  elif op=='motion_audit':result={'passed':True,'failed_checks':0,'support':{'sample_count':120,'trace':[{} for _ in range(120)],'counts':{'l':60,'r':60,'both':0,'flight':0},'max_abs_hip_forward':0.1,'max_abs_hip_lateral':0.1}}
  elif op=='rig_get':
   bones=[{'name':n,'index':i,'parent':i-1,'rest_position':dict(x=0,y=0,z=0),'rest_scale':dict(x=1,y=1,z=1),'pose_position':dict(x=0,y=0,z=0),'pose_rotation':'(0, 0, 0, 1)'} for i,n in enumerate(checks.EXPECTED_BONES)]
   next(b for b in bones if b['name']=='B-upperArm.L')['pose_rotation']=f'(0, {math.sin(.3)}, 0, {math.cos(.3)})'
   result={'kind':'3d','bone_count':56,'skeleton_path':checks.RIG_SKELETON,'bones':bones}
  else:
   directory=request['directory'];result={'directory':directory,'exists':True,'pose_count':2,'poses':[{'name':n,'path':directory+'/'+n+'.json','bone_count':56,'source':checks.RIG_SKELETON} for n in ('arm','rest')]}
   files={}
   for name in ('arm','rest'):
    content={'format':'godot-ai-animation-pose','version':1,'rest_relative':True,'bones':dict.fromkeys(checks.EXPECTED_BONES,{})};text=json.dumps(content)
    files[name+'.json']={'raw_utf8':text,'content':content,'sha256':hashlib.sha256(text.encode()).hexdigest()}
   row.update(files_before=files,files_after=copy.deepcopy(files),files_before_execution_ns=4,files_after_execution_ns=6)
  row['result']=result
  if op!='pose_list':row.update(error_request=({'op':op,'player_path':checks.PLAYER,'animation_name':checks.CLIP,'skeleton_path':'/MotionWalk/Missing'} if key.startswith('animation_inspect.') else {'op':op,'skeleton_path':'/DefinitelyMissingSkeleton'}),typed_error={'error':'NODE_NOT_FOUND: Missing'})
  event={'validator':'bounded_read_v1','operation':key,'driver':checks.SOURCES[key],'row':row,'checks':checks.derive(row),'execution_ns':10}
  deps=checks.DEPENDENCIES+('tools/'+event['driver'],)+(('test_project/repair_motion_fixture.tscn','test_project/tools/repair_motion_playback.gd') if key.startswith('animation_inspect.') else ('test_project/repair_rig_fixture.tscn','tools/fixture_copy.py'))
  context={'dependencies':dict.fromkeys(deps,{})}
  def public(operation,request,response,at):return {'id':str(at),'operation':operation,'driver':event['driver'],'public_tool':'custom_'+operation.split('.')[0],'route':'public_godot_ai','scene':scene,'params':request,'response':response,'execution_ns':at}
  calls=[public(key,request,result,5)]
  if op!='pose_list':calls.append(public(key,row['error_request'],row['typed_error'],7))
  if key.startswith('animation_inspect.'):
   probe={'op':'describe','player_path':checks.PLAYER,'animation_name':checks.CLIP};row.update(before={'clips':[{'name':checks.CLIP}]},after={'clips':[{'name':checks.CLIP}]})
   calls.extend([public('animation_inspect.describe',probe,row['before'],2),public('animation_inspect.describe',probe,row['after'],8)])
  elif op=='pose_list':
   row['save_requests']=[{'op':'pose_save','skeleton_path':checks.RIG_SKELETON,'pose_dir':request['directory'],'name':n} for n in ('rest','arm')];row['save_results']=[{'saved':True},{'saved':True}]
   calls.extend(public('animation_rig.pose_save',req,response,at) for req,response,at in zip(row['save_requests'],row['save_results'],[2,3]))
  else:
   pose={'format':'godot-ai-animation-pose','version':1,'rest_relative':True,'bones':{'B-upperArm.L':{'rotation':dict(kind='quaternion',x=0,y=math.sin(.3),z=0,w=math.cos(.3)),'position':dict(kind='vector3',x=0,y=0,z=0),'scale':dict(kind='vector3',x=1,y=1,z=1)}}}
   row.update(producer_request={'op':'pose_apply','skeleton_path':checks.RIG_SKELETON,'pose':pose},producer_response={'applied':True})
   calls.append(public('animation_rig.pose_apply',row['producer_request'],row['producer_response'],3))
  opens=[{'id':'open','public_tool':'scene_open','request':{'path':scene},'response':row['open'],'execution_ns':1}]
  return event,context,calls,opens
 def test_literal_names_match_authored_public_fbx(self):
  import re
  from pathlib import Path
  raw=(Path(__file__).resolve().parents[1]/checks.MODEL).read_bytes()
  names={x.decode() for x in re.findall(rb'(B-[A-Za-z0-9_.-]+)\x00\x01Model',raw)}
  self.assertEqual(names,set(checks.EXPECTED_BONES));self.assertEqual(len(names),56)
 def test_five_rows_pending_stays_pending(self):
  for key in checks.SOURCES:
   with self.subTest(key=key):
    args=self.fixture(key);proof=checks.verify_event(*args)
    self.assertEqual(proof['checks']['source_unchanged'],'pending');self.assertEqual(proof['checks']['reported_errors'],'pending')
    self.assertEqual(proof['checks']['valid_effect'],'pending' if key.endswith(('sample','motion_audit')) else 'pass')
 def test_corrupted_response_each(self):
  for key in checks.SOURCES:
   args=self.fixture(key);row=args[0]['row'];row['result']={}
   with self.subTest(key=key):self.assertEqual(checks.derive(row)['valid_effect'],'fail')
 def test_exact_missing_node_code(self):
  for key in checks.SOURCES:
   if key.endswith('pose_list'):continue
   args=self.fixture(key);args[0]['row']['typed_error']={'error':'OTHER_UPPER: not same code'}
   self.assertEqual(checks.derive(args[0]['row'])['typed_errors'],'fail')
 def test_wrong_actual_call_missing_call_and_dependency(self):
  for mutation in ('response','missing','dependency'):
   args=list(self.fixture('animation_inspect.rig_profile'))
   if mutation=='response':args[2][0]['response']={'other':True}
   if mutation=='missing':args[2]=args[2][1:]
   if mutation=='dependency':args[1]['dependencies'].pop(checks.MODEL)
   with self.subTest(mutation=mutation),self.assertRaises(ValueError):checks.verify_event(*args)
 def test_wrong_scene_and_driver_and_claim(self):
  for field,value in [('scene','res://wrong.tscn'),('driver','fake.py'),('checks',{'valid_effect':'pass'})]:
   args=self.fixture('animation_inspect.sample')
   if field=='scene':args[0]['row'][field]=value
   else:args[0][field]=value
   with self.assertRaises(ValueError):checks.verify_event(*args)
 def test_wrong_profile_role(self):
  args=self.fixture('animation_inspect.rig_profile');args[0]['row']['result']['roles']['hips']='B-head'
  self.assertEqual(checks.derive(args[0]['row'])['valid_effect'],'fail')
 def test_nonfinite_and_missing_sample(self):
  args=self.fixture('animation_inspect.sample');args[0]['row']['result']['bones']['B-foot.L']['positions'][0][1]=float('inf')
  self.assertEqual(checks.derive(args[0]['row'])['valid_effect'],'fail')
 def test_audit_counts_not_suite_pass(self):
  args=self.fixture('animation_inspect.motion_audit');args[0]['row']['result']['support']['counts']['l']=59
  self.assertEqual(checks.derive(args[0]['row'])['valid_effect'],'fail')
 def test_rig_wrong_names_and_arm_angle(self):
  for field in ('name','pose_rotation'):
   args=self.fixture('animation_rig.rig_get');bone=next(b for b in args[0]['row']['result']['bones'] if b['name']=='B-upperArm.L');bone[field]='wrong' if field=='name' else '(0,0,0,1)'
   self.assertEqual(checks.derive(args[0]['row'])['valid_effect'],'fail')
 def test_pose_bytes_and_wrong_file_and_content(self):
  for mutation in ('hash','after','content'):
   args=self.fixture('animation_rig.pose_list');row=args[0]['row']
   if mutation=='hash':row['files_before']['arm.json']['sha256']='a'*64
   if mutation=='after':row['files_after']={}
   if mutation=='content':row['files_before']['arm.json']['content']['bones']={}
   self.assertEqual(checks.derive(row)['valid_effect'],'fail')
 def test_missing_producer_or_wrong_time(self):
  for key in ('animation_rig.pose_list','animation_rig.rig_get'):
   args=list(self.fixture(key));args[2]=[e for e in args[2] if e['operation']==key]
   with self.assertRaises(ValueError):checks.verify_event(*args)
  args=self.fixture('animation_rig.pose_list');args[0]['row']['files_before_execution_ns']=6
  with self.assertRaises(ValueError):checks.verify_event(*args)
if __name__=='__main__':unittest.main()
