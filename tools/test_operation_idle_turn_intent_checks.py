"""Synthetic physical records and deliberate corruptions; never engine proof."""
import copy,hashlib,json,math,unittest
import operation_idle_turn_intent_checks as s


def report(op):
 if op in ('jump','strafe_cycle'):
  from test_operation_jump_strafe_intent_checks import physical_report
  return physical_report(op)
 runs=[]
 for fps in (30,60,120):
  for mode in ('player','tree'):
   duration=.3 if op=='idle_cycle'else 1.;frames=round(duration*fps)+1
   r={'id':'dummy','fps':fps,'mixer'if op=='idle_cycle'else'mode':mode,'frames':frames,'leg_length_m':1.,'nonfinite':0,'failures':[],'thresholds_pass':True,'trace':[{'time'if op=='idle_cycle'else't':i/fps}for i in range(frames)]}
   if op=='idle_cycle':
    r.update(active_mixers=1,active_root_position_track=False,path_errors=[],generation_clamp_metadata_known=True,generation_reach_clamped=False,max_actor_distance_m=0.,max_extracted_root_delta_m=0.,crossed_loop_seams=3,period_s=.1,duration_s=.3,max_pose_step_m=.001,max_rotation_step_rad=.002,max_reference_position_error_m=0.,max_reference_rotation_error_rad=0.,max_interior_step_m=.001,max_interior_rotation_step_rad=.002,max_seam_step_m=.001,max_seam_rotation_step_rad=.002,seam_velocity_probe={'bones':[{'fastest_interior_rotation_step_rad':.001,'position_step_jump_m':.001,'rotation_step_jump_rad':.001}]},feet={side:dict(max_standing_slide_m=.001,max_rest_ankle_target_penetration_m=0.,max_standing_height_error_m=0.,knee_pole_flips=0,expected_standing_frames=frames,observed_contact_band_frames=frames)for side in('l','r')})
   else:
    r.update(source_world_up=[0.,1.,0.],source_world_forward=[0.,0.,1.],rest_left_offset=[-1.,0.,0.],settled_headings={x:[0.,0.,-1.]for x in('hips','chest','head')},heading_error_rad=0.,pivot_checks=[dict(stage=1,sample_time=.5,heading_error_rad=0.)],max_motion_m=.1,max_pose_step_m=.01,max_angle_step_rad=.1,extracted_root_distance_m=0.,extracted_root_angle_rad=0.,actor_distance_m=0.,actor_angle_rad=0.,feet={side:dict(stance_slide_m=.001,penetration_m=0.,max_declared_contact_height_m=0.,stance_rotation_rad=0.,knee_flips=0,contact_frames=10,endpoint_position_error_m=0.,endpoint_heading_error_rad=0.)for side in('l','r')})
    for item in r['trace']:item['hip_heading']=s.rotate([0.,0.,1.],[0.,1.,0.],math.pi*item['t'])
   runs.append(r)
 return {'runs':runs,'engine_errors':[],'passed':True}


def bound(op):
 request=s.fixed_request(op);scene='res://repair_'+('idle'if op=='idle_cycle'else'turn')+'_quality/'+('a'*32)+'/responsive_extracted_dummy.tscn';sha='c'*64
 case={'id':'dummy','scene':scene,'params':request,'passed':True,'player':'AnimationPlayer','skeleton':'Dummy/Skeleton3D','fixture_sha256':'a'*64,'scene_sha256':sha,'roles':s.ROLES,'write':{'saved':'actual public output'},'save':{'saved':True},'reopen':{'reloaded_from_disk':True}}
 route={'source_head':'d'*40,'operation':op,'passed':True,'profile':'responsive','phase':'candidate','root_mode':'extracted','invocation_kind':'ordinary call','case_selection':'dummy','cases':[case]}
 raw=json.dumps(route).encode();native=report(op);native.update(source_head='d'*40,case_selection='dummy',route_sha256=hashlib.sha256(raw).hexdigest(),checker_sha256='a'*64,native_helper_sha256='a'*64,input_identity_helper_sha256='a'*64,base_checker_sha256='a'*64)
 for run in native['runs']:run['input_identity']={'schema':'motion_physical_input_v1','complete':True,'id':'dummy','scene':scene,'request':request,'fixture_sha256':'a'*64,'roles':case['roles'],'expected_scene_sha256':sha,'scene_before_sha256':sha,'scene_after_sha256':sha,'rest_sha256':'f'*64,'bone_count':50,'player':'AnimationPlayer','skeleton':'Dummy/Skeleton3D','player_class':'AnimationPlayer','skeleton_class':'Skeleton3D','clip_present':True,'animation_name':request['animation_name']}
 native_raw=json.dumps(native).encode();row={'operation':'animation_motion.'+op,'scene':scene,'native_case_id':'native','project_root':'/project','route_path':'/route.json','report_path':'/native.json','route_bytes_hex':raw.hex(),'route_sha256':hashlib.sha256(raw).hexdigest(),'report_bytes_hex':native_raw.hex(),'report_sha256':hashlib.sha256(native_raw).hexdigest()}
 command=['godot','--headless','--path','/project','--script','res://tools/'+s.SCRIPTS[op],'--','/route.json','/native.json']+(['candidate']if op=='idle_cycle'else[])+['case_id=dummy'];row['command']=command
 e={'kind':'operation_snapshot_assertions','route':'public_godot_ai','run_id':'run','validator':'idle_turn_physical_v1','driver':'check_selected_motion_intent.py','operation':row['operation'],'execution_ns':50,'row':row}
 c={'run_id':'run','tested_source':'d'*40,'engine_command':'godot','dependencies':{p:{'sha256':'a'*64,'git_blob':'b'*40}for p in s.DEPS+s.EXTRA_DEPS.get(op,())+('test_project/tools/'+s.SCRIPTS[op],)}}
 public=[{'id':'made','operation':row['operation'],'scene':scene,'params':request,'response':case['write'],'driver':'mcp_run_quality_review.py','route':'public_godot_ai','execution_ns':10}]
 natives=[{'id':'native','driver':'check_selected_motion_intent.py','operation':row['operation'],'scene':scene,'command':command,'returncode':0,'stdout':s.PREFIXES[op]+json.dumps({'runs':6,'passed':True,'engine_errors':[]}),'stderr':'','execution_ns':40}]
 support=[{'id':'save','public_tool':'scene_save','scene':scene,'response':case['save'],'driver':'mcp_run_quality_review.py','execution_ns':20},{'id':'open','public_tool':'scene_open','request':{'path':scene,'force_reload':True},'response':case['reopen'],'driver':'mcp_run_quality_review.py','execution_ns':30}]
 for v in [e]+public+natives+support:v['context_sha256']='e'*64;v['run_id']='run'
 return e,c,public,natives,support


class Controls(unittest.TestCase):
 def test_native_clock_field_is_operation_specific(self):
  for op in ('idle_cycle','turn_cycle'):
   r=report(op);clock='time'if op=='idle_cycle'else't';foreign='t'if op=='idle_cycle'else'time'
   r['runs'][0]['trace'][0][foreign]=r['runs'][0]['trace'][0].pop(clock)
   with self.subTest(op=op),self.assertRaisesRegex(ValueError,'trace clock'):s.numeric(op,r)
 def test_two_exact_six_clock_contracts_and_bound_public_sources(self):
  for op in ('idle_cycle','turn_cycle'):
   self.assertEqual(s.numeric(op,report(op)),{'valid_effect':'pass'});self.assertEqual(s.verify_event(*bound(op))['checks'],{'valid_effect':'pass'})
 def test_inert_bad_heading_sign_and_float_bool_errors_cannot_hide_under_passed(self):
  for op,fault in [('idle_cycle','inert'),('idle_cycle','actor'),('idle_cycle','seam'),('idle_cycle','foot'),('idle_cycle','bool'),('turn_cycle','heading'),('turn_cycle','sign'),('turn_cycle','foot'),('turn_cycle','actor'),('turn_cycle','nan')]:
   r=report(op);x=r['runs'][0]
   if fault=='inert':x['max_pose_step_m']=x['max_rotation_step_rad']=0.
   elif fault=='actor':x['max_actor_distance_m'if op=='idle_cycle'else'actor_distance_m']=.1
   elif fault=='seam':x['seam_velocity_probe']['bones'][0]['position_step_jump_m']=.006
   elif fault=='foot':x['feet']['l']['max_standing_slide_m'if op=='idle_cycle'else'endpoint_position_error_m']=.1
   elif fault=='bool':x['max_extracted_root_delta_m']=False
   elif fault=='heading':x['settled_headings']['chest']=[1.,0.,0.]
   elif fault=='sign':x['trace'][round(.5*x['fps'])]['hip_heading']=[-1.,0.,0.]
   else:x['max_motion_m']=float('nan')
   self.assertEqual(s.numeric(op,r),{'valid_effect':'fail'},(op,fault))
 def test_missing_duplicate_clocks_trace_pivot_and_nonfinite_vectors(self):
  for fault in ('clock','duplicate','trace','pivot','vector'):
   r=report('turn_cycle')
   if fault=='clock':r['runs'][0]['fps']=29
   elif fault=='duplicate':r['runs'][0]=copy.deepcopy(r['runs'][1])
   elif fault=='trace':r['runs'][0]['trace'][0]['t']=1.
   elif fault=='pivot':r['runs'][0]['pivot_checks']=[]
   else:r['runs'][0]['source_world_up'][0]=float('nan')
   with self.assertRaises(ValueError,msg=fault):s.numeric('turn_cycle',r)
 def test_exact_context_source_request_file_and_public_call_bindings(self):
  for fault in ('source','dependency','routebytes','nativebytes','request','call','command','save','reopen','order','mutation'):
   e,c,p,n,support=copy.deepcopy(bound('turn_cycle'))
   if fault=='source':c['tested_source']='e'*40
   elif fault=='dependency':c['dependencies'].pop(s.DEPS[0])
   elif fault=='routebytes':e['row']['route_sha256']='0'*64
   elif fault=='nativebytes':e['row']['report_bytes_hex']='00'
   elif fault=='request':p[0]['params']=dict(p[0]['params'],direction='right')
   elif fault=='call':p[0]['driver']='wrong.py'
   elif fault=='command':n[0]['command']=n[0]['command'][:-1]
   elif fault=='save':support.pop(0)
   elif fault=='reopen':support[1]['response']={'reloaded_from_disk':False}
   elif fault=='order':support[1]['execution_ns']=5
   else:p.append(dict(p[0],id='other',operation='animation_edit.reverse',execution_ns=35))
   with self.assertRaises(ValueError,msg=fault):s.verify_event(e,c,p,n,support)
 def test_identity_corruption_even_with_rehashed_native_report(self):
  for key,value in [('scene_before_sha256','0'*64),('skeleton','Other'),('request',{}),('clip_present',False),('rest_sha256',''),('complete',False)]:
   args=bound('idle_cycle');row=args[0]['row'];native=json.loads(bytes.fromhex(row['report_bytes_hex']));native['runs'][0]['input_identity'][key]=value;raw=json.dumps(native).encode();row.update(report_bytes_hex=raw.hex(),report_sha256=hashlib.sha256(raw).hexdigest())
   with self.assertRaises(ValueError,msg=key):s.verify_event(*args)
if __name__=='__main__':unittest.main()
