import copy
import json
import math
import unittest
import operation_rig_clip_native_checks as c
import operation_rig_scene_history_checks as h
import test_operation_rig_scene_history_checks as history_tests


def native_case(op,layout='local',kind='3d',state='redo'):
 label=f'{layout}_{kind}_{op}_{state}'
 row={'label':label,'layout':layout,'kind':kind,'op':op,'state':state,'scene':'user://rig_clip_history_'+label+'.tscn','sha256':'a'*64,'observations':[],'clocks':[],'tracks':[],'failures':[]}
 if state=='redo' and kind=='3d':
  rows,times=c.contract(op)
  row['observations']=[{'phase':'authored','at':t,'metric':m,'bone':b,'actual':{'pose':copy.deepcopy(v),'rest':copy.deepcopy(v)} if m=='ankle_rest_distance' else copy.deepcopy(v)} for m,b,t,v in rows]
  row['clocks']=[{'phase':'authored','requested':t,'position':t,'assigned':'generated','speed':1.,'process':2} for t in times]
  row['tracks']=[{'path':'Skeleton:'+b,'bone':b,'type':ty,'target_class':'Skeleton3D','target_relative_to_skeleton':'.','bone_index':0} for b,ty in sorted(c.REQUIRED[op])]
  row['clip']={'length':1.,'loop':0,'track_count':len(row['tracks']),'root':'../../Character','root_resolves':True}
 return row


def fixture(op='pose_to_clip',layout='local'):
 row=history_tests.fixture(op,mode=layout)
 context={'run_id':'run','engine_command':'godot472','dependencies':{p:dict(sha256='a'*64,git_blob='b'*40) for p in set(h.DEPENDENCIES+c.DEPENDENCIES)}}
 origin=dict(id='origin',row=row,validator='rig_scene_history_v1',driver='test_rig_clip_history.gd',route='public_test_run_inner_dispatch',operation='animation_rig.'+op,run_id='run',test_run_begin_id='begin',time_ns=20)
 req=dict(suite='rig_clip_history',verbose=True)
 start=dict(id='begin',request=req,scene=row['scene'],execution_ns=1,time_ns=10)
 end=dict(id='end',test_run_begin_id='begin',public_tool='test_run',request=req,scene=row['scene'],execution_ns=2,time_ns=30,response={'results':[dict(suite='rig_clip_history',test=row['test'],passed=True,assertion_count=500)]})
 cases=[native_case(n,layout,state=stage) for n in c.WRITERS for stage in ('undo','redo')]+[native_case('pose_to_clip',layout,'2d',stage) for stage in ('undo','redo')]
 report=dict(layout=layout,saved_states=18,cases=cases,failures=[],engine_errors=[])
 event=dict(id='native',operation='animation_rig.'+op,scene=f'user://rig_clip_history_{layout}_3d_{op}_redo.tscn',driver='mcp_rig_clip_history.py',route='native_godot',run_id='run',command=['godot472','--headless','--path','project','--script','res://tools/check_rig_clip_history.gd','--',layout],returncode=0,stdout='RIG_CLIP_HISTORY_RUNTIME='+json.dumps(report),stderr='',execution_ns=3)
 return event,context,[origin],[start],[end]

class RigClipNativeTests(unittest.TestCase):
 def test_all_eight_five_layouts(self):
  for op in c.WRITERS:
   for layout in c.LAYOUTS:
    with self.subTest(op=op,layout=layout):self.assertEqual(set(c.verify_native(*fixture(op,layout))['checks'].values()),{'pass'})
 def test_each_inert_and_nonfinite_value_fails(self):
  for op in c.WRITERS:
   for bad in ([0,0,0,1],[float('nan'),0,0],None):
    row=native_case(op);selected=row['observations'][-1];selected['actual']=bad
    with self.subTest(op=op,bad=bad):self.assertEqual(c.derive(row)['valid_effect'],'fail')
 def test_well_typed_inert_original_pose_fails_each_operation(self):
  for op in c.WRITERS:
   row=native_case(op)
   for sample in row['observations']:
    metric=sample['metric'];bone=sample['bone']
    if metric=='rotation':
     value=c.axis(2,math.pi) if bone=='thigh_L' else c.axis(2,-math.pi/2 if bone=='arm_L' else math.pi/2) if bone.startswith('arm_') else c.axis(0,.22) if op=='bake_pose_sequence' else [0,0,0,1]
    elif metric=='position':value=[.02,1.13,0] if op=='bake_pose_sequence' else [0,1.1,0]
    elif metric=='scale':value=[1,1,1] if bone=='eye' else [1.1,.9,1.05]
    elif metric=='direction':value=[0,1,0]
    else:continue
    sample['actual']=value
   with self.subTest(op=op):self.assertEqual(c.derive(row)['valid_effect'],'fail')
 def test_wrong_paths_types_and_targets(self):
  for op in c.WRITERS:
   for field,value in [('path','Other:hips'),('type',0),('target_relative_to_skeleton','../Other'),('bone_index',-1)]:
    row=native_case(op);row['tracks'][0][field]=value
    with self.subTest(op=op,field=field):self.assertEqual(c.derive(row)['track_paths_types'],'fail')
 def test_clock_cannot_be_batch_pass(self):
  for field,value in [('position',99),('speed',.8),('process',1),('assigned','source/input')]:
   row=native_case('pose_to_clip');row['clocks'][0][field]=value
   self.assertEqual(c.derive(row)['valid_effect'],'fail')
  row=native_case('pose_to_clip');row['observations']=[]
  self.assertEqual(c.derive(row)['valid_effect'],'fail')
 def test_original_threshold_boundaries(self):
  row=native_case('punch');row['observations'][0]['actual']=[math.sqrt(1-.95**2),0,.95]
  self.assertEqual(c.derive(row)['valid_effect'],'fail')
  row=native_case('squat');row['observations'][1]['actual']['pose'][1]=.003
  self.assertEqual(c.derive(row)['valid_effect'],'fail')
 def test_wrong_source_dependency_engine_command_scene(self):
  for fault in ('driver','engine','command','scene','dependency','run'):
   args=fixture();e,ctx=args[:2]
   if fault=='driver':e['driver']='other.py'
   elif fault=='engine':e['command'][0]='otherGodot'
   elif fault=='command':e['command'][-1]='not_layout'
   elif fault=='scene':e['scene']='user://other.tscn'
   elif fault=='run':e['run_id']='other'
   else:ctx['dependencies'].pop(c.DEPENDENCIES[0])
   with self.subTest(fault=fault),self.assertRaises(ValueError):c.verify_native(*args)
 def test_missing_ambiguous_or_wrong_hash_origin(self):
  for fault in ('missing','duplicate','hash'):
   args=list(fixture())
   if fault=='missing':args[2]=[]
   elif fault=='duplicate':args[2]+=copy.deepcopy(args[2])
   else:args[2][0]['row']['persist_redo']['sha256']='b'*64
   with self.assertRaises(ValueError):c.verify_native(*args)
 def test_raw_case_not_total_eighteen(self):
  args=fixture();e=args[0];report=json.loads(e['stdout'].split('=',1)[1]);report.pop('cases');e['stdout']='RIG_CLIP_HISTORY_RUNTIME='+json.dumps(report)
  with self.assertRaises(ValueError):c.verify_native(*args)
 def test_actual_public_failure_not_masked(self):
  args=fixture();args[4][0]['response']['results'][0]['passed']=False
  self.assertEqual(set(c.verify_native(*args)['checks'].values()),{'fail'})
 def test_native_failure_and_engine_error_retained(self):
  for fault in ('returncode','stderr'):
   args=fixture();args[0][fault]=1 if fault=='returncode' else 'ERROR: engine'
   self.assertEqual(set(c.verify_native(*args)['checks'].values()),{'fail'})
 def test_origin_wrong_request_or_native_before_span(self):
  args=fixture();args[2][0]['row']['request']['duration']=2
  with self.assertRaises(ValueError):c.verify_native(*args)
  args=fixture();args[0]['execution_ns']=1
  with self.assertRaises(ValueError):c.verify_native(*args)
if __name__=='__main__':unittest.main()
