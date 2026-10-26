"""Four fixed public dummy cases: saved-native physical intent, no output oracle."""
import hashlib,json,math,re

SCRIPTS={'idle_cycle':'check_idle_quality.gd','turn_cycle':'check_turn_quality.gd','jump':'check_jump_quality.gd','strafe_cycle':'check_strafe_quality.gd'}
PREFIXES={'idle_cycle':'IDLE_QUALITY_CHECK=','turn_cycle':'TURN_QUALITY_RESULT=','jump':'JUMP_QUALITY_CHECK=','strafe_cycle':'STRAFE_QUALITY_CHECK='}
EXTRA_DEPS={'jump':('test_project/tools/check_run_quality.gd','addons/godot_ai_animation/spec/motion_jump_plan.gd','addons/godot_ai_animation/spec/motion_space.gd','addons/godot_ai_animation/spec/motion_drivers.gd','addons/godot_ai_animation/registry/op_registry.gd'),'strafe_cycle':('addons/godot_ai_animation/spec/motion_space.gd','addons/godot_ai_animation/spec/motion_drivers.gd','addons/godot_ai_animation/registry/op_registry.gd')}
DEPS=('tools/operation_idle_turn_intent_checks.py','tools/check_selected_motion_intent.py','tools/mcp_run_quality_review.py','tools/mcp_character_quality_baseline.py','tools/mcp_presets_audit.py','tools/fixture_copy.py','test_project/repair_rig_fixture.tscn','test_project/models/human_dummy/HumanCharacterDummy_F.fbx','test_project/tools/motion_physical_input_identity.gd','test_project/tools/character_quality_native.gd','addons/godot_ai_animation/handlers/motion.gd','addons/godot_ai_animation/spec/motion_specs.gd','addons/godot_ai_animation/spec/rig_analysis.gd')
ROLES={'hips':'B-hips','spine':'B-spine','chest':'B-chest','head':'B-head',**{role+'_'+side:'B-'+name+'.'+side.upper()for role,name in [('arm','upperArm'),('forearm','forearm'),('hand','hand'),('shoulder','shoulder'),('thigh','thigh'),('shin','shin'),('foot','foot'),('toe','toe')]for side in('l','r')}}
LIMITS='One ordinary bundled-dummy saved request per operation, six Player/Tree clocks. Stationary/noninert idle, left180 two-stage turn, stationary height0.2m jump or left speed0.1m/s strafe only. Other rigs/styles/parameters, visual quality and source/history channels are not promoted.'

def need(ok,message):
 if not ok:raise ValueError(message)
def number(v):return type(v)in(int,float)and math.isfinite(v)
def digest(v):return isinstance(v,str)and re.fullmatch('[0-9a-f]{64}',v)is not None
def bounded(v,limit):return number(v)and 0<=v<=limit
def dot(a,b):return sum(x*y for x,y in zip(a,b))
def cross(a,b):return[a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def vec(v):return isinstance(v,list)and len(v)==3 and all(number(x)for x in v)
def angle(a,b):return math.atan2(math.sqrt(dot(cross(a,b),cross(a,b))),dot(a,b))
def rotate(v,up,radians):
 c,s=math.cos(radians),math.sin(radians);x=cross(up,v);return[v[i]*c+x[i]*s+up[i]*dot(up,v)*(1-c)for i in range(3)]
def same(a,b):
 if isinstance(a,bool)or isinstance(b,bool):return type(a)is type(b)and a==b
 if number(a)and number(b):return a==b
 if isinstance(a,dict)and isinstance(b,dict):return a.keys()==b.keys()and all(same(a[k],b[k])for k in a)
 if isinstance(a,list)and isinstance(b,list):return len(a)==len(b)and all(same(x,y)for x,y in zip(a,b))
 return type(a)is type(b)and a==b

def fixed_request(op):
 need(op in SCRIPTS,'unsupported physical intent operation')
 p={'op':op,'player_path':'/RepairRigFixture/AnimationPlayer','skeleton_path':'/RepairRigFixture/Dummy/Skeleton3D','animation_name':'quality_'+op.removesuffix('_cycle'),'root_motion':True}
 if op=='turn_cycle':p.update(direction='left',angle=180.,steps=2)
 if op=='jump':p.update(height=.2)
 if op=='strafe_cycle':p.update(direction='left',speed=.1)
 return p

def minus(a,b):return[x-y for x,y in zip(a,b)]

def length(v):return math.sqrt(dot(v,v))

def measured_frame(r):
 up,forward=r.get('source_world_up'),r.get('source_world_forward')
 need(all(vec(v)and abs(dot(v,v)-1)<1e-5 for v in(up,forward))and abs(dot(up,forward))<1e-5,'missing measured native world frame')
 return up,forward

def raw_feet(r,up,height_field):
 """Require actual bilateral positions and a common rest ankle plane."""
 plane=None
 for sample in r['trace']:
  feet=sample.get('feet');need(isinstance(feet,dict)and set(feet)=={'l','r'},'missing bilateral trace feet')
  need(vec(sample.get('root')),'missing played world root')
  for foot in feet.values():
   need(vec(foot.get('p'))and number(foot.get(height_field))and type(foot.get('declared_contact'))is bool,'missing played ankle observation')
   at=dot(foot['p'],up)-foot[height_field]
   if plane is None:plane=at
   need(abs(at-plane)<1e-5,'trace ankle plane differs')

def jump_numeric(r):
 """Height .2m, world gravity 9.81 and ordinary default timing from input.

 Saved hips keys supply the authoring clock. Public response and native
 expected_apex/tolerance fields never supply expected effect quantities.
 """
 leg,fps,trace=r['leg_length_m'],r['fps'],r['trace'];up,_=measured_frame(r)
 raw_feet(r,up,'height')
 height=fixed_request('jump')['height'];flight=2*math.sqrt(2*height/9.81)
 action=max(1.,flight/.55);takeoff=.22*action;landing=takeoff+flight;apex=takeoff+flight/2
 keys=r.get('hip_position_key_times_s')
 need(isinstance(keys,list)and len(keys)>2 and all(number(t)for t in keys)and abs(keys[0])<1e-6 and abs(keys[-1]-action)<1e-5,'missing saved jump authoring clock')
 gaps=[b-a for a,b in zip(keys,keys[1:])]
 need(all(0<gap<=1/60+1e-5 for gap in gaps),'unsupported sparse jump authoring clock')
 authored_dt=max(gaps);dt=1/fps
 timing_tolerance=2*dt+authored_dt
 height_tolerance=max(.002*leg,9.81*(dt+authored_dt)**2)
 flight_tolerance=timing_tolerance+.02*leg/math.sqrt(2*9.81*height)
 okay=number(r.get('clip_length_s'))and abs(r['clip_length_s']-action)<1e-5 and r['frames']==math.ceil((r['clip_length_s']+.25)*fps)+1
 okay=okay and type(r.get('loop_mode'))is int and r['loop_mode']==0 and r.get('generation_reach_evaluated')is True and r.get('generation_reach_clamped')is False
 okay=okay and all(number(r.get(k))and abs(r[k]-v)<1e-5 for k,v in(('takeoff_marker_s',takeoff),('landing_marker_s',landing)))
 need(all(vec(s.get('hip'))and number(s.get('hip_height_m'))for s in trace),'missing played hip observations')
 heights=[dot(minus(s['hip'],trace[0]['hip']),up)for s in trace]
 need(all(abs(h-s['hip_height_m'])<1e-5 for h,s in zip(heights,trace)),'played hip height/vector differs')
 peak=max(range(len(trace)),key=lambda i:heights[i]);observed_air=[]
 for sample,hip_height in zip(trace,heights):
  time=sample['time'];contact=time<=takeoff+1e-6 or time>=landing-1e-6
  okay=okay and all(f['declared_contact']==contact for f in sample['feet'].values())
  okay=okay and length(minus(sample['root'],trace[0]['root']))<=.0001
  if all(f['height']>.01*leg for f in sample['feet'].values()):observed_air.append(time)
  if takeoff<=time<=landing:
   at=time-takeoff;expected=math.sqrt(2*9.81*height)*at-.5*9.81*at*at
   okay=okay and abs(hip_height-expected)<=height_tolerance
 okay=okay and abs(heights[peak]-height)<=height_tolerance and abs(trace[peak]['time']-apex)<=timing_tolerance
 okay=okay and bool(observed_air)and len(observed_air)==r.get('observed_flight_frames')
 if observed_air:
  okay=okay and abs(observed_air[0]-takeoff)<=flight_tolerance and abs(observed_air[-1]-landing)<=flight_tolerance
  okay=okay and abs((observed_air[-1]-observed_air[0])-flight)<=2*flight_tolerance
  okay=okay and all(abs((b-a)-dt)<1e-5 for a,b in zip(observed_air,observed_air[1:]))
  okay=okay and all(number(r.get(k))and abs(r[k]-v)<1e-5 for k,v in(('first_observed_air_s',observed_air[0]),('last_observed_air_s',observed_air[-1])))
 okay=okay and all(number(r.get(k))and abs(r[k]-v)<1e-5 for k,v in(('apex_height_m',heights[peak]),('apex_time_s',trace[peak]['time'])))
 okay=okay and bounded(r.get('root_error_m'),.0001)and bounded(r.get('grounded_root_delta_m'),.000001)and bounded(r.get('unexpected_extraction_m'),.000001)
 okay=okay and bounded(r.get('final_pose_position_error_m'),min(.01*leg,.01))and bounded(r.get('final_pose_rotation_error_rad'),.01)
 okay=okay and number(r.get('max_motion_m'))and r['max_motion_m']>1e-6 and number(r.get('max_pose_step_m'))and 0<r['max_pose_step_m']*fps<=10*leg and bounded(r.get('max_bone_angular_speed_rad_s'),50)
 for side,foot in r['feet'].items():
  okay=okay and bounded(foot.get('slide_m'),min(.02*leg,.03))and bounded(foot.get('penetration_m'),.01*leg)and bounded(foot.get('contact_height_m'),.01*leg)and type(foot.get('knee_flips'))is int and foot['knee_flips']==0
  count=sum(sample['feet'][side]['declared_contact']for sample in trace)
  okay=okay and type(foot.get('contact_frames'))is int and foot['contact_frames']==count and count>0
  okay=okay and all(sample['feet'][side]['height']>=-.01*leg and (not sample['feet'][side]['declared_contact']or abs(sample['feet'][side]['height'])<=.01*leg)for sample in trace)
 return okay

def strafe_numeric(r):
 """Six seconds, ordinary one-second cycles, .1m/s anatomical left.

 The requested speed binds each cycle's signed world displacement. Continuous
 raw travel must be monotonic inside its speed envelope; native fractional
 phase interpolation and all existing physical predicates remain required.
 """
 leg,fps,trace=r['leg_length_m'],r['fps'],r['trace'];up,forward=measured_frame(r)
 raw_feet(r,up,'height_from_rest_ankle_plane')
 left=r.get('source_world_left');a,b=r.get('rest_left_foot_world'),r.get('rest_right_foot_world')
 need(vec(left)and abs(dot(left,left)-1)<1e-5 and vec(a)and vec(b),'missing anatomical strafe frame')
 offset=minus(a,b);offset=[v-up[i]*dot(offset,up)for i,v in enumerate(offset)];gap=length(offset)
 # Rest toes need not be exactly orthogonal to the bilateral ankle line.
 # Verify left against ankles and a nondegenerate anatomical forward frame;
 # keep the original measured forward/up travel-drift limits below.
 need(gap>1e-6 and length(minus(left,[v/gap for v in offset]))<1e-5 and abs(dot(cross(up,left),forward))>.99,'strafe anatomical left differs from measured feet')
 speed=fixed_request('strafe_cycle')['speed'];dt=1/fps;okay=r['frames']==6*fps+1
 okay=okay and number(r.get('period_s'))and abs(r['period_s']-1)<1e-5 and type(r.get('loop_mode'))is int and r['loop_mode']==1 and r.get('root_mode')=='extracted'
 signed=[]
 for i,sample in enumerate(trace):
  delta=minus(sample['root'],trace[0]['root']);along=dot(delta,left);signed.append(along)
  okay=okay and abs(dot(delta,forward))<=.0001 and abs(dot(delta,up))<=.0001
  if i%fps==0:okay=okay and abs(along-speed*sample['time'])<=.0001
  if i:okay=okay and -.000001<=along-signed[-2]<=2*speed*dt+.0001
 for second in range(6):
  section=signed[second*fps:(second+1)*fps+1]
  okay=okay and sum(b-a>1e-6 for a,b in zip(section,section[1:]))>=fps//2
 okay=okay and abs(signed[-1]-.6)<=.0001 and number(r.get('root_distance_m'))and abs(r['root_distance_m']-length(minus(trace[-1]['root'],trace[0]['root'])))<1e-5
 okay=okay and type(r.get('active_mixers'))is int and r['active_mixers']==1 and r.get('path_errors')==[] and r.get('marker_errors')==[] and r.get('generation_reach_clamped')is False
 okay=okay and all(bounded(r.get(k),.0001)for k in('root_error_m','root_cycle_contract_error_m','forward_drift_m'))
 okay=okay and bounded(r.get('max_in_place_root_delta_m'),.000001)and bounded(r.get('max_in_place_clip_translation_m'),.000001)
 okay=okay and bounded(r.get('max_reference_position_error_m'),.001*leg)and bounded(r.get('max_reference_rotation_error_rad'),.0001)
 okay=okay and type(r.get('crossed_loop_seams'))is int and r['crossed_loop_seams']==6 and number(r.get('max_pose_step_m'))and 1e-6<r['max_pose_step_m']<=6*leg/fps
 okay=okay and number(r.get('minimum_signed_lateral_foot_gap_m'))and r['minimum_signed_lateral_foot_gap_m']>0
 for sample in trace:okay=okay and dot(minus(sample['feet']['l']['p'],sample['feet']['r']['p']),left)>0
 for side,foot in r['feet'].items():
  okay=okay and bounded(foot.get('max_declared_stance_slide_m'),min(.02*leg,.03))and bounded(foot.get('max_rest_ankle_plane_penetration_m'),.01*leg)and bounded(foot.get('max_declared_contact_height_m'),.01*leg)and type(foot.get('knee_pole_flips'))is int and foot['knee_pole_flips']==0 and type(foot.get('contact_windows'))is int and foot['contact_windows']>=2
  declared=sum(s['feet'][side]['declared_contact']for s in trace)
  observed=sum(abs(s['feet'][side]['height_from_rest_ankle_plane'])<=.01*leg for s in trace)
  okay=okay and type(foot.get('declared_contact_frames'))is int and foot['declared_contact_frames']==declared and declared>0 and type(foot.get('observed_contact_band_frames'))is int and foot['observed_contact_band_frames']==observed and observed>0
  okay=okay and all(s['feet'][side]['height_from_rest_ankle_plane']>=-.01*leg and (not s['feet'][side]['declared_contact']or abs(s['feet'][side]['height_from_rest_ankle_plane'])<=.01*leg)for s in trace)
 arms=r.get('arms');need(isinstance(arms,dict)and set(arms)=={'l','r'},'missing ordinary strafe arms')
 for arm in arms.values():
  okay=okay and number(arm.get('max_upper_up_dot'))and -1<=arm['max_upper_up_dot']<-.8 and number(arm.get('min_elbow_deg'))and number(arm.get('max_elbow_deg'))and 0<=arm['min_elbow_deg']<arm['max_elbow_deg']<=180 and arm['max_elbow_deg']-arm['min_elbow_deg']>=1 and number(arm.get('wrist_excursion_rad'))and arm['wrist_excursion_rad']>=.005
 return okay

def numeric(op,report):
 need(op in SCRIPTS,'unsupported physical intent operation')
 runs=report.get('runs');need(isinstance(runs,list)and len(runs)==6,'six physical clocks required')
 keys={(r.get('id'),r.get('fps'),r.get('mode'if op=='turn_cycle'else'mixer'))for r in runs}
 need(keys=={('dummy',fps,mode)for fps in(30,60,120)for mode in('player','tree')},'missing/duplicate/foreign physical clock')
 okay=report.get('engine_errors')==[] and report.get('passed')is True
 for r in runs:
  leg=r.get('leg_length_m');need(number(leg)and leg>0,'missing physical rig scale')
  need(type(r['fps'])is int and type(r.get('frames'))is int and r['frames']>2,'invalid native clock type')
  trace=r.get('trace');need(isinstance(trace,list)and len(trace)==r['frames'],'missing native trace')
  clock='t'if op=='turn_cycle'else'time'
  need(all(number(x.get(clock))and abs(x[clock]-i/r['fps'])<1e-5 for i,x in enumerate(trace)),'native trace clock differs')
  okay=okay and r.get('nonfinite')==0 and type(r.get('nonfinite'))is int and r.get('failures')==[] and r.get('thresholds_pass')is True
  feet=r.get('feet');need(isinstance(feet,dict)and set(feet)=={'l','r'},'missing bilateral physical feet')
  if op=='jump':okay=jump_numeric(r)and okay
  elif op=='strafe_cycle':okay=strafe_numeric(r)and okay
  elif op=='idle_cycle':
   okay=okay and type(r.get('active_mixers'))is int and r['active_mixers']==1 and r.get('active_root_position_track')is False and r.get('path_errors')==[] and r.get('generation_clamp_metadata_known')is True and r.get('generation_reach_clamped')is False
   okay=okay and bounded(r.get('max_actor_distance_m'),.0001)and bounded(r.get('max_extracted_root_delta_m'),.0001)and type(r.get('crossed_loop_seams'))is int and r['crossed_loop_seams']>=2
   period=r.get('period_s');need(number(period)and period>0 and number(r.get('duration_s'))and abs(r['duration_s']-trace[-1]['time'])<1e-5,'missing actual idle period/duration')
   okay=okay and trace[-1]['time']>=2*period-1e-5 and r['crossed_loop_seams']==math.floor((trace[-1]['time']+1e-5)/period)
   step=r.get('max_pose_step_m');rotation=r.get('max_rotation_step_rad');need(number(step)and number(rotation),'missing noninert idle observation')
   okay=okay and step>=0 and rotation>=0 and(step>1e-6 or rotation>1e-6)
   a,b=r.get('max_interior_step_m'),r.get('max_interior_rotation_step_rad');need(number(a)and a>=0 and number(b)and b>=0,'missing interior seam observations')
   okay=okay and bounded(r.get('max_seam_step_m'),1.5*a+.001*leg)and bounded(r.get('max_seam_rotation_step_rad'),1.5*b+.002)
   okay=okay and bounded(r.get('max_reference_position_error_m'),.001*leg)and bounded(r.get('max_reference_rotation_error_rad'),.0001)
   interior=max((b['time']-a['time']for a,b in zip(trace,trace[1:])),default=0);okay=okay and abs(interior-1/r['fps'])<1e-5
   # Existing seam acceleration limits, recomputed from raw per-bone observations.
   probe=r.get('seam_velocity_probe',{});need(isinstance(probe.get('bones'),list)and probe['bones'],'missing independent seam probe')
   for bone in probe['bones']:
    fastest=bone.get('fastest_interior_rotation_step_rad');need(number(fastest)and fastest>=0,'missing seam interior angular speed')
    okay=okay and bounded(bone.get('position_step_jump_m'),.005)and bounded(bone.get('rotation_step_jump_rad'),.75*fastest+.002)
   for foot in feet.values():
    okay=okay and bounded(foot.get('max_standing_slide_m'),min(.02*leg,.03))and bounded(foot.get('max_rest_ankle_target_penetration_m'),.01*leg)and bounded(foot.get('max_standing_height_error_m'),.01*leg)and type(foot.get('knee_pole_flips'))is int and foot['knee_pole_flips']==0
    okay=okay and foot.get('expected_standing_frames')==r['frames']and type(foot.get('observed_contact_band_frames'))is int and 0<foot['observed_contact_band_frames']<=r['frames']
  else:
   up,forward,left=r.get('source_world_up'),r.get('source_world_forward'),r.get('rest_left_offset')
   need(all(vec(v)for v in(up,forward,left))and abs(dot(up,up)-1)<1e-5 and abs(dot(forward,forward)-1)<1e-5,'missing measured native turn frame')
   need(abs(dot(cross(up,left),forward))>1e-8,'degenerate anatomical turn frame')
   sign=1 if dot(cross(up,left),forward)>=0 else-1
   headings=r.get('settled_headings',{});need(set(headings)=={'hips','chest','head'}and all(vec(x)and abs(dot(x,x)-1)<1e-5 for x in headings.values()),'missing settled anatomical heading')
   target=rotate(forward,up,math.pi*sign);okay=okay and bounded(r.get('heading_error_rad'),.001)and all(angle(target,v)<=.001 for v in headings.values())
   pivots=r.get('pivot_checks');need(isinstance(pivots,list)and len(pivots)==1,'missing two-stage pivot')
   pivot=pivots[0];need(type(pivot.get('stage'))is int and pivot['stage']==1 and number(pivot.get('sample_time')),'wrong intermediate stage')
   sample=next((x for x in trace if abs(x['t']-pivot['sample_time'])<1e-6),None);need(sample is not None and vec(sample.get('hip_heading'))and abs(dot(sample['hip_heading'],sample['hip_heading'])-1)<1e-5,'missing played intermediate heading')
   okay=okay and bounded(pivot.get('heading_error_rad'),.001)and angle(rotate(forward,up,math.pi/2*sign),sample['hip_heading'])<=.001
   okay=okay and number(r.get('max_motion_m'))and r['max_motion_m']>=.001*leg and bounded(r.get('max_pose_step_m'),.25*leg)and bounded(r.get('max_angle_step_rad'),.75)
   okay=okay and all(bounded(r.get(k),.0001)for k in('extracted_root_distance_m','extracted_root_angle_rad','actor_distance_m','actor_angle_rad'))
   for foot in feet.values():
    okay=okay and bounded(foot.get('stance_slide_m'),min(.02*leg,.03))and bounded(foot.get('penetration_m'),.01*leg)and bounded(foot.get('max_declared_contact_height_m'),.01*leg)and bounded(foot.get('stance_rotation_rad'),math.pi/180)and type(foot.get('knee_flips'))is int and foot['knee_flips']==0 and type(foot.get('contact_frames'))is int and foot['contact_frames']>0
    okay=okay and bounded(foot.get('endpoint_position_error_m'),.001*leg)and bounded(foot.get('endpoint_heading_error_rad'),.001)
 return {'valid_effect':'pass'if okay else'fail'}

def decode(raw,sha,label):
 try:data=bytes.fromhex(raw)
 except(ValueError,TypeError):raise ValueError('invalid '+label+' bytes')
 need(hashlib.sha256(data).hexdigest()==sha,label+' hash differs');return json.loads(data.decode('utf-8-sig'))

def verify_event(event,context,public,natives,support):
 row=event['row'];op=row.get('operation','').removeprefix('animation_motion.');need(op in SCRIPTS,'foreign physical operation')
 for path in DEPS+EXTRA_DEPS.get(op,())+('test_project/tools/'+SCRIPTS[op],):
  d=context.get('dependencies',{}).get(path,{})
  need(digest(d.get('sha256'))and isinstance(d.get('git_blob'),str)and re.fullmatch('[0-9a-f]{40}',d['git_blob']),'unbound physical dependency '+path)
 need(event.get('driver')=='check_selected_motion_intent.py'and event.get('operation')==row['operation']and event.get('validator')=='idle_turn_physical_v1'and event.get('kind')=='operation_snapshot_assertions'and event.get('route')=='public_godot_ai'and event.get('run_id')==context.get('run_id'),'physical recorder source differs')
 route=decode(row.get('route_bytes_hex'),row.get('route_sha256'),'public route');report=decode(row.get('report_bytes_hex'),row.get('report_sha256'),'native report')
 need(route.get('source_head')==context.get('tested_source')==report.get('source_head'),'physical/public/context source differs')
 need(route.get('operation')==op and route.get('passed')is True and route.get('profile')=='responsive'and route.get('phase')=='candidate'and route.get('root_mode')=='extracted'and route.get('invocation_kind')=='ordinary call'and route.get('case_selection')=='dummy','unknown selected public scope')
 need(len(route.get('cases',[]))==1,'one selected public case required');case=route['cases'][0];request=fixed_request(op)
 need(case.get('id')=='dummy'and same(case.get('params'),request) and case.get('passed')is True and case.get('player')=='AnimationPlayer'and case.get('skeleton')=='Dummy/Skeleton3D'and case.get('roles')==ROLES,'public case intent differs')
 need(digest(event.get('context_sha256'))and all(v.get('context_sha256')==event['context_sha256']and v.get('run_id')==context['run_id']for v in public+natives+support),'foreign physical context/run')
 scene=case.get('scene');need(row.get('scene')==scene and digest(case.get('scene_sha256'))and case.get('fixture_sha256')==context['dependencies']['test_project/repair_rig_fixture.tscn']['sha256'],'scene/fixture identity differs')
 need(report.get('case_selection')=='dummy'and report.get('route_sha256')==row['route_sha256']and report.get('checker_sha256')==context['dependencies']['test_project/tools/'+SCRIPTS[op]]['sha256']and report.get('native_helper_sha256')==context['dependencies']['test_project/tools/character_quality_native.gd']['sha256']and report.get('input_identity_helper_sha256')==context['dependencies']['test_project/tools/motion_physical_input_identity.gd']['sha256'],'native input/checker source differs')
 if op=='jump':need(report.get('base_checker_sha256')==context['dependencies']['test_project/tools/check_run_quality.gd']['sha256'],'jump inherited checker source differs')
 need(report.get('control','')=='','corrupted native control cannot qualify ordinary intent')
 for run in report.get('runs',[]):
  w=run.get('input_identity',{})
  need(w.get('schema')=='motion_physical_input_v1'and w.get('complete')is True and w.get('id')=='dummy'and w.get('scene')==scene and same(w.get('request'),request) and w.get('fixture_sha256')==case['fixture_sha256']and w.get('roles')==case.get('roles'),'native input request/scene differs')
  need(w.get('expected_scene_sha256')==w.get('scene_before_sha256')==w.get('scene_after_sha256')==case['scene_sha256']and digest(w.get('rest_sha256'))and type(w.get('bone_count'))is int and w['bone_count']>0 and w.get('player')==case['player']and w.get('skeleton')==case['skeleton']and w.get('player_class')=='AnimationPlayer'and w.get('skeleton_class')=='Skeleton3D'and w.get('clip_present')is True and w.get('animation_name')==request['animation_name'],'native loaded bytes/rig/clip differs')
 need(len({r['input_identity']['rest_sha256']for r in report.get('runs',[])})==1 and len({r['input_identity']['bone_count']for r in report.get('runs',[])})==1,'physical rig differs across clocks')
 matches=[p for p in public if p.get('operation')==row['operation']and p.get('scene')==scene and same(p.get('params'),request) and p.get('response')==case.get('write')and p.get('driver')=='mcp_run_quality_review.py'and p.get('route')=='public_godot_ai'and not p.get('response',{}).get('error')]
 need(len(matches)==1 and bool(matches[0].get('response')),'missing unique actual public generation');made=matches[0]
 native=[n for n in natives if n.get('id')==row.get('native_case_id')];need(len(native)==1,'native subprocess event absent');native=native[0]
 command=native.get('command',[]);need(native.get('driver')=='check_selected_motion_intent.py'and native.get('operation')==row['operation']and native.get('scene')==scene and command==row.get('command')and command[0]==context.get('engine_command'),'native command/context differs')
 prefix=PREFIXES[op]
 summaries=[json.loads(line[len(prefix):])for line in native.get('stdout','').splitlines()if line.startswith(prefix)]
 need(len(summaries)==1 and summaries[0].get('runs')==6 and summaries[0].get('passed')is True and summaries[0].get('engine_errors')==[],'native summary lacks exact completed selected clocks')
 expected=['--headless','--path',row['project_root'],'--script','res://tools/'+SCRIPTS[op],'--',row['route_path'],row['report_path']]+(['candidate']if op=='idle_cycle'else[])+['case_id=dummy']
 need(command[1:]==expected and native.get('returncode')==0 and 'ERROR:'not in native.get('stdout','')+native.get('stderr',''),'native result/script/selector differs')
 saves=[s for s in support if s.get('public_tool')=='scene_save'and s.get('scene')==scene and s.get('response')==case.get('save')and s.get('driver')=='mcp_run_quality_review.py'and made['execution_ns']<s['execution_ns']<native['execution_ns']]
 opens=[s for s in support if s.get('public_tool')=='scene_open'and s.get('request')=={'path':scene,'force_reload':True}and s.get('response')==case.get('reopen')and s.get('driver')=='mcp_run_quality_review.py'and made['execution_ns']<s['execution_ns']<native['execution_ns']]
 need(len(saves)==len(opens)==1 and not saves[0].get('response',{}).get('error')and not opens[0].get('response',{}).get('error')and saves[0]['execution_ns']<opens[0]['execution_ns']and opens[0]['response'].get('reloaded_from_disk')is True,'missing actual save/forced disk reload')
 need(not any(p.get('scene')==scene and made['execution_ns']<p.get('execution_ns',0)<native['execution_ns']and p.get('id')!=made['id']and p.get('operation')not in {'animation_inspect.describe','animation_rig.pose_save'}and not p.get('response',{}).get('error')for p in public),'intervening public mutation')
 need(native['execution_ns']<event['execution_ns'],'report recorded before native completion')
 return {'checks':numeric(op,report),'public_case_ids':[made['id'],saves[0]['id'],opens[0]['id'],native['id']],'limits':LIMITS}
