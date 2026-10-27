import copy,json,math,unittest
from operation_rig_native_checks import OPS,MODIFIERS,contract,verify_native,origin_matches

def fixture(operation):
 op=operation.split('.')[1];name,marker,parameterized=contract(operation);scene='res://repair_rig_audit/20261017/'+op+'.tscn'
 report={'scene':scene,'op':op,'failures':[]}
 if op in MODIFIERS:report.update(modifier_class=MODIFIERS[op][0],response=.01,target_resolved=op in {'ik_setup','look_at_setup'})
 elif op=='retarget_setup':report.update(processed=6,target_head_change=.6)
 else:report.update(samples=6,worst_error=0,bone='B-upperArm.L'if op=='pose_apply'else'repair_tool_tip',parent='B-hand.R',bone_index=80,parent_index=55,expected_angle=.6,parent_response=.4)
 event={'operation':operation,'scene':scene,'command':['godot','--headless','--path','project','--script','res://tools/'+name,'--',scene]+([op]if parameterized else []),'returncode':0,'stdout':marker+json.dumps(report),'stderr':''}
 context={'engine_command':'godot','dependencies':{'tools/operation_rig_native_checks.py':{},'test_project/tools/'+name:{}}}
 return event,context,report,marker

class Controls(unittest.TestCase):
 def test_all_seven_exact_native_shapes(self):
  for op in OPS:
   e,c,_,_=fixture(op);self.assertEqual(verify_native(e,c)[0],{'playback':'pass'})
 def test_failures_errors_threshold_and_wrong_class_are_retained(self):
  for op in OPS:
   e,c,r,m=fixture(op)
   for key,value in [('returncode',1),('stderr','ERROR: realenginefailure'),('stdout',e['stdout']+'\n'+e['stdout'])]:
    x=copy.deepcopy(e);x[key]=value;self.assertEqual(verify_native(x,c)[0]['playback'],'fail')
   r['failures']=['savedwiringwrong'];e['stdout']=m+json.dumps(r);self.assertEqual(verify_native(e,c)[0]['playback'],'fail')
  for op,field,value in [('ik_setup','modifier_class','LookAtModifier3D'),('look_at_setup','target_resolved',False),('spring_setup','response',.00099),('retarget_setup','target_head_change',.099),('pose_apply','worst_error',.001),('rig_chain','parent_response',.1),('rig_chain','bone_index',55)]:
   family='animation_rig'if op in {'pose_apply','rig_chain'}else'animation_rig_modifiers';e,c,r,m=fixture(family+'.'+op);r[field]=value;e['stdout']=m+json.dumps(r);self.assertEqual(verify_native(e,c)[0]['playback'],'fail',(op,field))
 def test_exact_engine_scene_operation_and_dependencies_required(self):
  for op in OPS:
   e,c,r,m=fixture(op)
   x=copy.deepcopy(e);x['command'][0]='othergodot'
   with self.assertRaises(ValueError):verify_native(x,c)
   x=copy.deepcopy(e);r['scene']='res://other.tscn';x['stdout']=m+json.dumps(r)
   with self.assertRaises(ValueError):verify_native(x,c)
   with self.assertRaises(ValueError):verify_native(e,{'engine_command':'godot','dependencies':{}})
 def test_origin_binds_exact_request_and_returned_chain_names(self):
  for op,(_,extras)in MODIFIERS.items():
   e,_,_,_=fixture('animation_rig_modifiers.'+op);p={'op':op,'skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D','active':False,**extras};self.assertTrue(origin_matches(e,{'params':p}));p['active']=True;self.assertFalse(origin_matches(e,{'params':p}))
  e,_,_,_=fixture('animation_rig.rig_chain');call={'params':{'bones':[{'name':'repair_tool_tip','parent':'B-hand.R','position':[0,.05,0]}],'skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D'},'response':{'bones':['repair_tool_tip'],'bones_created':1,'skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D'}};self.assertTrue(origin_matches(e,call));call['response']['bones']=['foreign'];self.assertFalse(origin_matches(e,call))
  e,_,_,_=fixture('animation_rig.pose_apply');p={'skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D','pose':{'rest_relative':True,'bones':{'B-upperArm.L':{'rotation':{'kind':'quaternion','x':0,'y':math.sin(.3),'z':0,'w':math.cos(.3)},'position':{'kind':'vector3','x':0,'y':0,'z':0},'scale':{'kind':'vector3','x':1,'y':1,'z':1}}}}};self.assertTrue(origin_matches(e,{'params':p}));p['pose']['bones']['B-upperArm.L']['rotation']['y']=0;self.assertFalse(origin_matches(e,{'params':p}))

if __name__=='__main__':unittest.main()
