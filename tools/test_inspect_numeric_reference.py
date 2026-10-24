import copy
import math
import unittest
import inspect_numeric_reference as n

def reference(op='motion_audit',travel=.03):
 count=8 if op=='sample' else 120
 frames=[]
 for i in range(count):
  t=i/(count-1);z=n.f(travel*t)
  points={}
  for bone in n.BONES:
   side=-.1 if bone.endswith('.R') else .1 if bone.endswith('.L') else 0.
   y=.5 if 'shin' in bone else 0. if 'foot' in bone or 'toe' in bone else 1.
   points[bone]=[n.f(side),y,z]
  frames.append({'at':t,'position':t,'assigned':'repair_probe_walk','speed':1.,'process':2,'points':points})
 return {'scene':'res://repair_motion_fixture.tscn','scene_sha256':'a'*64,'clip':'repair_probe_walk','kind':'fresh_saved_scene_native_Player','samples':count,'eligible':True,'root_track_before':'Dummy:position','root_track_played':'Dummy:position' if op=='sample' else '', 'up':[0,1,0],'forward':[0,0,1],'lateral':[1,0,0],'legs':{'l':1.,'r':1.},'rest_feet':{'l':[n.f(.1),0,0],'r':[n.f(-.1),0,0]},'frames':frames}

def sample_result(ref):
 result=dict(length=1,sample_count=8,times=[i/7 for i in range(8)],contact_threshold=.02,missing_bones=[],bones_truncated=False,undoable=False,bones={},feet={})
 zs=[0.,.0043,.0086,.0129,.0171,.0214,.0257,.03]
 for side,x in [('l',.1),('r',-.1)]:
  bone='B-foot.'+side.upper();result['bones'][bone]={'positions':[[x,0,z] for z in zs]}
  result['feet'][side]={'bone':bone,'heights':[0.]*8,'min_height':0.,'height_range':0.,'contacts':[{'start':0.,'end':1.}]}
 return result

def audit_result(ref):
 times=[i/119 for i in range(120)];hips=[[0,1,round(ref['frames'][i]['points']['B-hips'][2],4)] for i in range(120)]
 result=dict(length=1,loop_mode='linear',sample_count=120,contact_threshold=.005,motion_kind='gait',in_place=True,body_travel=.03,undoable=False,hips=dict(samples=120,height_range=0.,body_travel=.03,body_path=.03,mean_speed=.03,trace=hips),feet={},support=dict(sample_count=120,counts=dict(l=0,r=0,both=120,flight=0),trace=[dict(time=round(t,4),state='both',hip_forward=0.,hip_lateral=0.) for t in times],max_abs_hip_forward=0.,max_abs_hip_lateral=0.),checks=[],passed=True,failed_checks=0)
 for side,x in [('l',.1),('r',-.1)]:
  foot=dict(bone='B-foot.'+side.upper(),ground=0.,worst_slide=.03,mean_slide=.03,path=.03,contact_time=1.,contact_fraction=1.,windows=[dict(start=0.,end=1.,slide=.03,path=.03)],max_penetration=0.,penetration_time=0.,penetration_budget=.01,trace=[[x,0,round(ref['frames'][i]['points']['B-foot.'+side.upper()][2],4)] for i in range(120)],pose_range=dict(min_knee_angle_degrees=180.,min_knee_angle_time=0.,max_extension_ratio=1.,max_extension_time=0.),knee_pole=dict(flips=0,max_angle_degrees=0.,worst_time=0.,valid_samples=0))
  result['feet'][side]=foot
 result['checks']=[dict(check='hip_bob',passed=True,value=0.,budget=.12)]
 for side in ('l','r'):result['checks'] += [dict(check='foot_slide.'+side,passed=True,value=.03,budget=.05),dict(check='ground_penetration.'+side,passed=True,value=0.,budget=.01),dict(check='knee_pole_flip.'+side,passed=True,value=0,budget=0)]
 return result

class NumericReferenceTests(unittest.TestCase):
 def test_closed_form_sample_and_audit(self):
  s=reference('sample');a=reference()
  self.assertTrue(n.sample_effect(sample_result(s),s));self.assertTrue(n.audit_effect(audit_result(a),a))
 def test_sample_wrong_coordinate_time_window_and_count(self):
  for field in ('coordinate','time','window','count'):
   ref=reference('sample');out=sample_result(ref)
   if field=='coordinate':out['bones']['B-foot.L']['positions'][2][0]=99
   elif field=='time':out['times'][2]=.2
   elif field=='window':out['feet']['l']['contacts'][0]['end']=.5
   else:out['sample_count']=7
   with self.subTest(field=field):self.assertFalse(n.sample_effect(out,ref))
 def test_audit_each_numeric_group_corruption(self):
  for field in ('hip','foot','support','grade','threshold','knee','pole'):
   ref=reference();out=audit_result(ref)
   if field=='hip':out['hips']['body_travel']=.031
   elif field=='foot':out['feet']['l']['worst_slide']=.031
   elif field=='support':out['support']['counts']['both']=119
   elif field=='grade':out['checks'][0]['passed']=False
   elif field=='threshold':out['checks'][1]['budget']=1.
   elif field=='knee':out['feet']['l']['pose_range']['max_extension_ratio']=.98
   else:out['feet']['l']['knee_pole']['flips']=1
   with self.subTest(field=field):self.assertFalse(n.audit_effect(out,ref))
 def test_inert_nonfinite_wrong_native_clock_and_source(self):
  for op in ('sample','motion_audit'):
   for field in ('inert','nonfinite','clock','source','root','speed'):
    ref=reference(op)
    if field=='inert':
     for row in ref['frames']:row['points']=copy.deepcopy(ref['frames'][0]['points'])
    elif field=='nonfinite':ref['frames'][0]['points']['B-foot.L'][0]=math.inf
    elif field=='clock':ref['frames'][1]['position']=0.
    elif field=='source':ref['scene']='res://other.tscn'
    elif field=='root':ref['root_track_played']='wrong'
    else:ref['frames'][0]['speed']=.8
    with self.subTest(op=op,field=field):self.assertFalse(n.reference_valid(ref,op))
 def test_rounding_does_not_relax_slide_budget(self):
  ref=reference(travel=.0500001);out=audit_result(ref)
  out.update(in_place=False,body_travel=.05)
  out['hips'].update(body_travel=.05,body_path=.05,mean_speed=.05)
  for side in ('l','r'):
   out['feet'][side].update(worst_slide=.05,mean_slide=.05,path=.05,windows=[dict(start=0.,end=1.,slide=.05,path=.05)])
  for check in out['checks']:
   if check['check'].startswith('foot_slide.'):check['value']=.05
  self.assertFalse(n.audit_effect(out,ref))
 def test_nonunit_axes_are_not_accepted(self):
  ref=reference();ref['forward']=[0,0,2]
  self.assertFalse(n.reference_valid(ref,'motion_audit'))
if __name__=='__main__':unittest.main()
