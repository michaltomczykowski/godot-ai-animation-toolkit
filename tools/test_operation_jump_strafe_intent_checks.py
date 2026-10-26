"""Offline synthetic corruptions plus preserved real raw-shape controls.

These records are parser/oracle controls, never new native qualification.
"""
import copy
import hashlib
import json
import math
from pathlib import Path
import unittest

import operation_idle_turn_intent_checks as s
from mcp_run_quality_review import metric_inputs


def physical_report(op):
 runs=[]
 for fps in (30,60,120):
  for mode in ('player','tree'):
   frames=math.ceil(1.25*fps)+1 if op=='jump'else 6*fps+1
   r=dict(id='dummy',fps=fps,mixer=mode,frames=frames,leg_length_m=1.,nonfinite=0,failures=[],thresholds_pass=True,source_world_up=[0.,1.,0.],source_world_forward=[0.,0.,1.])
   trace=[]
   for i in range(frames):
    time=i/fps
    if op=='jump':
     flight=2*math.sqrt(.4/9.81);at=time-.22;h=max(0.,math.sqrt(.4*9.81)*at-.5*9.81*at*at)if 0<=at<=flight else 0.
     contact=time<=.22+1e-6 or time>=.22+flight-1e-6
     trace.append(dict(time=time,root=[0.,0.,0.],hip=[0.,1.+h,0.],hip_height_m=h,feet={side:dict(p=[x,h,0.],height=h,declared_contact=contact)for side,x in (('l',.1),('r',-.1))}))
    else:
     phase=time%1;x=max(0.,min(1.,(phase-.12)/.76));along=.1*(math.floor(time)+x*x*(3-2*x))
     trace.append(dict(time=time,root=[along,0.,0.],feet={side:dict(p=[along+x,0.,0.],height_from_rest_ankle_plane=0.,declared_contact=True)for side,x in (('l',.1),('r',-.1))}))
   r['trace']=trace
   if op=='jump':
    peak=max(trace,key=lambda x:x['hip_height_m']);air=[x['time']for x in trace if x['feet']['l']['height']>.01]
    r.update(clip_length_s=1.,hip_position_key_times_s=[i/120 for i in range(121)],loop_mode=0,generation_reach_evaluated=True,generation_reach_clamped=False,takeoff_marker_s=.22,landing_marker_s=.22+flight,observed_flight_frames=len(air),first_observed_air_s=air[0],last_observed_air_s=air[-1],apex_height_m=peak['hip_height_m'],apex_time_s=peak['time'],root_error_m=0.,grounded_root_delta_m=0.,unexpected_extraction_m=0.,final_pose_position_error_m=0.,final_pose_rotation_error_rad=0.,max_motion_m=.2,max_pose_step_m=.1/fps,max_bone_angular_speed_rad_s=1.,feet={side:dict(slide_m=0.,penetration_m=0.,contact_height_m=0.,knee_flips=0,maximum_lift_m=.2,contact_frames=sum(x['feet'][side]['declared_contact']for x in trace))for side in ('l','r')})
   else:
    r.update(period_s=1.,loop_mode=1,root_mode='extracted',source_world_left=[1.,0.,0.],rest_left_foot_world=[.1,0.,0.],rest_right_foot_world=[-.1,0.,0.],root_distance_m=.6,active_mixers=1,path_errors=[],marker_errors=[],generation_reach_clamped=False,root_error_m=0.,root_cycle_contract_error_m=0.,forward_drift_m=0.,max_in_place_root_delta_m=0.,max_in_place_clip_translation_m=0.,max_reference_position_error_m=0.,max_reference_rotation_error_rad=0.,crossed_loop_seams=6,max_pose_step_m=.1/fps,minimum_signed_lateral_foot_gap_m=.2,feet={side:dict(max_declared_stance_slide_m=0.,max_rest_ankle_plane_penetration_m=0.,max_declared_contact_height_m=0.,knee_pole_flips=0,contact_windows=7,declared_contact_frames=frames,observed_contact_band_frames=frames)for side in ('l','r')},arms={side:dict(max_upper_up_dot=-.95,min_elbow_deg=12.,max_elbow_deg=15.,wrist_excursion_rad=.03)for side in ('l','r')})
   runs.append(r)
 return dict(runs=runs,engine_errors=[],passed=True)


def bound(op):
 from test_operation_idle_turn_intent_checks import bound as existing_bound
 return existing_bound(op)


def rehash(row,key,data):
 raw=json.dumps(data).encode();row[key+'_bytes_hex']=raw.hex();row[key+'_sha256']=hashlib.sha256(raw).hexdigest()


ARCHIVE=Path('E:/GodotAI-toolkit-release-2.0.0/20261014')
PRESERVED={
 'jump':('jump/candidate-r002/stationary/responsive','native-check-6b34bb6ac178899f.json','3a17e396fa5326ef06fdc4ee0dabaccf1d6b53014d00cd77d718b09c6428e884','6580354a006afa1c99f2f3136ccff552a36f07efc905f5bf38ebd954dd657ff0'),
 'strafe_cycle':('strafe/candidate-r001/left/responsive','native-check-1bd18cfe5e5be1ff.json','2fe9a8177b81f1d139b6e07ac7e3c1fbbaa873fcecb7f4099b72aa1387db7b63','e8385d81a3708a89e32297116b4ecfeff3e52cd24241c8e1ed94da00d46c82a3')}


class Controls(unittest.TestCase):
 def test_fixed_requests_six_clocks_and_exact_public_join(self):
  for op in ('jump','strafe_cycle'):
   with self.subTest(op=op):
    self.assertEqual(s.numeric(op,physical_report(op)),{'valid_effect':'pass'})
    self.assertEqual(s.verify_event(*bound(op))['checks'],{'valid_effect':'pass'})

 def test_native_expected_metadata_is_never_the_intent_or_tolerance_oracle(self):
  for op in ('jump','strafe_cycle'):
   r=physical_report(op)
   for x in r['runs']:
    x.update(expected_apex_height_m=100.,expected_apex_time_s=-100.,expected_root_distance_m=-99.,height_tolerance_m=0.,timing_tolerance_s=0.,flight_tolerance_s=0.)
   self.assertEqual(s.numeric(op,r),{'valid_effect':'pass'})

 def test_preserved_real_native_clock_and_ankle_shapes_are_hash_bound_controls_only(self):
  for op,(folder,native_name,route_hash,native_hash)in PRESERVED.items():
   directory=ARCHIVE/folder
   if not (directory/native_name).is_file():self.skipTest('private preserved raw reports unavailable')
   route_raw=(directory/'route.json').read_bytes();native_raw=(directory/native_name).read_bytes()
   self.assertEqual(hashlib.sha256(route_raw).hexdigest(),route_hash)
   self.assertEqual(hashlib.sha256(native_raw).hexdigest(),native_hash)
   route,native=json.loads(route_raw),json.loads(native_raw)
   self.assertEqual(route['source_head'],native['source_head']);self.assertEqual(native['route_sha256'],route_hash)
   case=next(x for x in route['cases']if x['id']=='dummy')
   self.assertNotEqual(case['params'],s.fixed_request(op))
   runs=[x for x in native['runs']if x['id']=='dummy'];self.assertEqual(len(runs),6)
   for x in runs:
    self.assertEqual(x['frames'],len(x['trace']))
    self.assertTrue(all(abs(sample['time']-i/x['fps'])<1e-5 for i,sample in enumerate(x['trace'])))
    s.raw_feet(x,[0.,1.,0.],'height'if op=='jump'else'height_from_rest_ankle_plane')
   corrupt=copy.deepcopy(runs[0]);corrupt['trace'][0]['feet'].pop('l')
   with self.assertRaises(ValueError):s.raw_feet(corrupt,[0.,1.,0.],'height'if op=='jump'else'height_from_rest_ankle_plane')
   # These historical default-height/default-speed requests lack the new
   # selected identity/hip/frame observations. They cannot qualify this scope.
   with self.assertRaises(ValueError):s.numeric(op,dict(native,runs=runs))

 def test_explicit_metrics_preserve_omitted_defaults_and_reject_foreign_or_nonphysical_inputs(self):
  for op in s.SCRIPTS:self.assertEqual(metric_inputs(op),{})
  self.assertEqual(metric_inputs('jump',height=.2),{'height':.2})
  self.assertEqual(metric_inputs('strafe_cycle',speed=.1),{'speed':.1})
  for op,kwargs in [('idle_cycle',{'height':.2}),('jump',{'speed':.1}),('strafe_cycle',{'height':.2})]+[('jump',{'height':x})for x in (False,0.,-1.,float('nan'),float('inf'))]:
   with self.subTest(op=op,kwargs=kwargs),self.assertRaises(ValueError):metric_inputs(op,**kwargs)

 def test_jump_tiny_hop_delayed_apex_and_wrong_flight_cannot_use_output_expectations(self):
  for fault in ('tiny_hop','delay','flight','no_air','inert','contact','recovery','clamp','marker'):
   r=physical_report('jump');x=r['runs'][0]
   if fault in ('tiny_hop','delay'):
    for sample in x['trace']:
     if fault=='tiny_hop':sample['hip'][1]=1+sample['hip_height_m']*.05
     else:
      at=sample['time']-.42;sample['hip'][1]=1+max(0.,math.sqrt(.4*9.81)*at-.5*9.81*at*at)
     sample['hip_height_m']=sample['hip'][1]-1
    peak=max(x['trace'],key=lambda a:a['hip_height_m']);x.update(apex_height_m=peak['hip_height_m'],apex_time_s=peak['time'],expected_apex_height_m=peak['hip_height_m'],expected_apex_time_s=peak['time'],height_tolerance_m=100,timing_tolerance_s=100)
   elif fault in ('flight','no_air'):
    for sample in x['trace']:
     if fault=='no_air'or sample['time']>.4:
      for f in sample['feet'].values():f['height']=0.;f['p'][1]=0.
    air=[p['time']for p in x['trace']if p['feet']['l']['height']>.01];x.update(observed_flight_frames=len(air),first_observed_air_s=air[0]if air else-1,last_observed_air_s=air[-1]if air else-1,flight_tolerance_s=100)
   elif fault=='inert':x['max_motion_m']=0.
   elif fault=='contact':x['feet']['l']['slide_m']=.1
   elif fault=='recovery':x['final_pose_position_error_m']=.1
   elif fault=='clamp':x['generation_reach_clamped']=True
   else:x['landing_marker_s']+=.1
   with self.subTest(fault=fault):self.assertEqual(s.numeric('jump',r),{'valid_effect':'fail'})

 def test_strafe_sign_double_travel_teleport_reverse_intermediate_and_foreign_frame(self):
  for fault in ('sign','double','inert','teleport','reverse','drift','foot','arms','frame'):
   r=physical_report('strafe_cycle');x=r['runs'][0]
   if fault in ('sign','double','inert','teleport','reverse','drift'):
    for i,sample in enumerate(x['trace']):
     if fault=='sign':sample['root'][0]*=-1
     elif fault=='double':sample['root'][0]*=2
     elif fault=='inert':sample['root'][0]=0.
     elif fault=='teleport':sample['root'][0]=.1*math.floor(sample['time'])
     elif fault=='reverse'and i==10:sample['root'][0]-=.02
     elif fault=='drift':sample['root'][2]=.1*sample['time']
    x['root_distance_m']=s.length(x['trace'][-1]['root']);x['expected_root_distance_m']=x['root_distance_m'];x['root_cycle_contract_error_m']=0.
   elif fault=='foot':x['feet']['r']['knee_pole_flips']=1
   elif fault=='arms':x['arms']['l']['wrist_excursion_rad']=0.
   else:x['source_world_left']=[-1.,0.,0.]
   with self.subTest(fault=fault):
    if fault=='frame':
     with self.assertRaises(ValueError):s.numeric('strafe_cycle',r)
    else:self.assertEqual(s.numeric('strafe_cycle',r),{'valid_effect':'fail'})

 def test_missing_clocks_feet_hip_and_authoring_times_fail_closed(self):
  for op,fault in [(op,f)for op in ('jump','strafe_cycle')for f in ('clock','feet','duplicate')]+[('jump','hip'),('jump','keys')]:
   r=physical_report(op);x=r['runs'][0]
   if fault=='clock':x['trace'][0].pop('time')
   elif fault=='feet':x['trace'][0]['feet'].pop('r')
   elif fault=='duplicate':r['runs'][0]=copy.deepcopy(r['runs'][1])
   elif fault=='hip':x['trace'][0].pop('hip')
   else:x['hip_position_key_times_s']=[0.,.5,1.]
   with self.subTest(op=op,fault=fault),self.assertRaises(ValueError):s.numeric(op,r)

 def test_wrong_request_metrics_and_rehashed_scene_bytes_never_qualify(self):
  for op in ('jump','strafe_cycle'):
   for fault in ('public_metric','route_metric','native_metric','scene','base','control'):
    args=bound(op);e,c,p,n,_=args;row=e['row'];field='height'if op=='jump'else'speed'
    if fault=='public_metric':p[0]['params']=dict(p[0]['params'],**{field:.9})
    elif fault=='route_metric':
     route=json.loads(bytes.fromhex(row['route_bytes_hex']));route['cases'][0]['params'][field]=.9;rehash(row,'route',route)
    else:
     report=json.loads(bytes.fromhex(row['report_bytes_hex']))
     if fault=='native_metric':report['runs'][0]['input_identity']['request'][field]=.9
     elif fault=='scene':report['runs'][0]['input_identity']['scene_after_sha256']='0'*64
     elif fault=='base':
      if op!='jump':continue
      report['base_checker_sha256']='0'*64
     else:report['control']='inert'
     rehash(row,'report',report)
    with self.subTest(op=op,fault=fault),self.assertRaises(ValueError):s.verify_event(*args)


if __name__=='__main__':unittest.main()
