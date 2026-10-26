"""Independent toy accepted walk plus transitions and deliberate bad intent."""
import copy,unittest
from operation_transition_intent_checks import numeric,REFERENCES

def fixture():
 runs=[]
 for fps in (30,60,120):
  for mode in ('player','tree'):
   frames=round(1.6*fps)+1
   joins={key:dict(reference_scene=REFERENCES[kind][0],reference_scene_sha256=REFERENCES[kind][1],reference_phase=0.,endpoint_position_error_m=0.,endpoint_rotation_error_rad=0.,max_continuation_position_step_error_m=0.,max_continuation_rotation_step_error_rad=0.)for key,kind in [('gait_join','walk'),('idle_join','idle')]}
   r=dict(id='dummy',fps=fps,mixer=mode,frames=frames,leg_length_m=1.,action_duration_s=1.,accepted_walk_period_s=1.,accepted_walk_cycle_world=[0.,0.,.8],actual_world_travel=[0.,0.,.4],source_world_forward=[0.,0.,1.],trace=[dict(time=i/fps,root=[0.,0.,.4*min(i/fps,1.)])for i in range(frames)],accepted_walk_identity=dict(complete=True,scene=REFERENCES['walk'][0],scene_before_sha256=REFERENCES['walk'][1],scene_after_sha256=REFERENCES['walk'][1]),nonfinite=0,failures=[],thresholds_pass=True,active_mixers=1,generation_clamp_metadata_known=True,generation_reach_clamped=False,max_rotation_step_rad=.1,root_hold_error_m=0.,backward_root_step_m=0.,max_reference_position_error_m=0.,max_reference_rotation_error_rad=0.,hold_position_error_m=0.,hold_rotation_error_rad=0.,feet={s:dict(max_declared_contact_slide_m=.001,max_declared_contact_height_m=.001,max_rest_ankle_plane_penetration_m=.001,knee_pole_flips=0,declared_contact_frames=10)for s in ('l','r')},**joins)
   runs.append(r)
 return dict(passed=True,engine_errors=[],failures=[],runs=runs)

class Controls(unittest.TestCase):
 def test_both_symmetric_transfers_use_accepted_walk_distance(self):
  for op in ('walk_start','walk_stop'):self.assertEqual(numeric(op,fixture()),{'valid_effect':'pass'})
 def test_wrong_distance_direction_contact_and_metadata_cannot_hide_in_passed(self):
  for fault in ('distance','reverse','trace_endpoint','backward','contact','knee','inert','clamp','bool'):
   report=fixture();r=report['runs'][0]
   if fault=='distance':r['actual_world_travel'][2]=.8
   elif fault=='reverse':r['actual_world_travel'][2]=-.4
   elif fault=='trace_endpoint':r['trace'][-1]['root'][2]=.8
   elif fault=='backward':r['trace'][5]['root'][2]=-.01
   elif fault=='contact':r['feet']['l']['max_declared_contact_slide_m']=.03
   elif fault=='knee':r['feet']['r']['knee_pole_flips']=1
   elif fault=='inert':r['actual_world_travel']=[0.,0.,0.]
   elif fault=='clamp':r['generation_reach_clamped']=True
   else:r['root_hold_error_m']=False
   with self.subTest(fault=fault):self.assertEqual(numeric('walk_start',report),{'valid_effect':'fail'})
 def test_reference_identity_phase_clock_and_missing_feet_refuse(self):
  for fault in ('reference','phase','clock','duplicate','feet','nan'):
   report=fixture();r=report['runs'][0]
   if fault=='reference':r['gait_join']['reference_scene_sha256']='0'*64
   elif fault=='phase':r['idle_join']['reference_phase']=.1
   elif fault=='clock':r['trace'][1]['time']=.123
   elif fault=='duplicate':report['runs'][0]=copy.deepcopy(report['runs'][1])
   elif fault=='feet':r['feet'].pop('l')
   else:r['accepted_walk_cycle_world'][0]=float('nan')
   with self.subTest(fault=fault),self.assertRaises(ValueError):numeric('walk_stop',report)

if __name__=='__main__':unittest.main()
