"""Two fixed transition requests against separately accepted saved references."""
import hashlib,json,math
from operation_idle_turn_intent_checks import need,number,vec,dot,same,ROLES,decode

SCRIPT='check_start_stop_quality.gd'
REFERENCES={
 'walk':('res://repair_walk_quality/95f43a6eb93e42eaa73440b6411d239a/responsive_extracted_dummy.tscn','769c02c337510d5503cec7ec9a963bb0bed2a8559e97d15d510327cb19b4ed9f'),
 'idle':('res://repair_idle_quality/12f39e415f3b4ee19128d7b7737e0eba/responsive_extracted_dummy.tscn','8b8b79fcc805f79d91f50f1ff1aae2021634391b0e95c51bfda3efb7ee2db304')}
DEPS=('tools/operation_transition_intent_checks.py','tools/check_selected_transition_intent.py','tools/mcp_run_quality_review.py','test_project/tools/'+SCRIPT,'test_project/tools/character_quality_native.gd','test_project/tools/motion_physical_input_identity.gd','addons/godot_ai_animation/handlers/motion.gd','addons/godot_ai_animation/spec/motion_transitions.gd','test_project/repair_rig_fixture.tscn','test_project/models/human_dummy/HumanCharacterDummy_F.fbx')
LIMITS='One ordinary Responsive dummy extracted request per transition, six clocks; accepted walk/idle byte identities, endpoint/continuation/contact/hold and independent half-steady-speed travel. No other parameters or visual approval.'

def request(op):
 need(op in ('walk_start','walk_stop'),'foreign transition')
 return dict(op=op,player_path='/RepairRigFixture/AnimationPlayer',skeleton_path='/RepairRigFixture/Dummy/Skeleton3D',animation_name='quality_'+op,root_motion=True)

def numeric(op,report):
 request(op);runs=report.get('runs',[])
 need(len(runs)==6 and {(r.get('id'),r.get('fps'),r.get('mixer'))for r in runs}=={('dummy',f,m)for f in (30,60,120)for m in ('player','tree')},'six distinct transition clocks required')
 okay=report.get('passed')is True and report.get('engine_errors')==[] and report.get('failures')==[]
 for r in runs:
  leg=r.get('leg_length_m');need(number(leg)and leg>0,'missing transition rig scale')
  t=r.get('trace');need(type(r.get('frames'))is int and r['frames']>2 and isinstance(t,list)and len(t)==r['frames'],'missing transition trace')
  need(all(number(v.get('time'))and abs(v['time']-i/r['fps'])<1e-5 and vec(v.get('root'))for i,v in enumerate(t)),'wrong transition trace clock/root')
  duration=r.get('action_duration_s');period=r.get('accepted_walk_period_s');cycle=r.get('accepted_walk_cycle_world');actual=r.get('actual_world_travel');forward=r.get('source_world_forward')
  need(number(duration)and abs(duration-1.)<1e-6 and number(period)and period>0 and all(vec(v)for v in (cycle,actual,forward))and abs(dot(forward,forward)-1)<1e-5,'missing independent accepted walk travel')
  expected=[v*.5*duration/period for v in cycle]
  distance=lambda a,b:math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))
  okay=okay and dot(cycle,forward)>.001 and distance(actual,expected)<=.0001 and distance([t[-1]['root'][i]-t[0]['root'][i]for i in range(3)],actual)<=.0001
  okay=okay and all(dot([b['root'][i]-a['root'][i]for i in range(3)],forward)>=-.000001 for a,b in zip(t,t[1:]))
  for kind in ('walk','idle'):
   join=r.get('gait_join'if kind=='walk'else'idle_join',{})
   need((join.get('reference_scene'),join.get('reference_scene_sha256'))==REFERENCES[kind]and join.get('reference_phase')==0.,'accepted reference/phase differs')
   for key,bound in [('endpoint_position_error_m',.001*leg),('endpoint_rotation_error_rad',.001),('max_continuation_position_step_error_m',.005),('max_continuation_rotation_step_error_rad',.75*r.get('max_rotation_step_rad',0)+.002)]:
    value=join.get(key);okay=okay and number(value)and 0<=value<=bound
  identity=r.get('accepted_walk_identity',{})
  need(identity.get('complete')is True and identity.get('scene')==REFERENCES['walk'][0]and identity.get('scene_before_sha256')==identity.get('scene_after_sha256')==REFERENCES['walk'][1],'accepted walk loaded bytes differ')
  okay=okay and r.get('nonfinite')==0 and type(r.get('nonfinite'))is int and r.get('failures')==[] and r.get('thresholds_pass')is True and r.get('active_mixers')==1 and r.get('generation_clamp_metadata_known')is True and r.get('generation_reach_clamped')is False
  for key,bound in [('root_hold_error_m',.00001),('backward_root_step_m',.000001),('max_reference_position_error_m',.001*leg),('max_reference_rotation_error_rad',.0001),('hold_position_error_m',.001*leg),('hold_rotation_error_rad',.001)]:
   value=r.get(key);okay=okay and number(value)and 0<=value<=bound
  feet=r.get('feet');need(isinstance(feet,dict)and set(feet)=={'l','r'},'missing bilateral transition feet')
  for foot in feet.values():
   for key,bound in [('max_declared_contact_slide_m',min(.02*leg,.03)),('max_declared_contact_height_m',.01*leg),('max_rest_ankle_plane_penetration_m',.01*leg)]:
    value=foot.get(key);okay=okay and number(value)and 0<=value<=bound
   okay=okay and type(foot.get('knee_pole_flips'))is int and foot['knee_pole_flips']==0 and type(foot.get('declared_contact_frames'))is int and foot['declared_contact_frames']>0
 return {'valid_effect':'pass'if okay else'fail'}

def verify_event(event,context,public,natives,support):
 row=event['row'];op=row.get('operation','').removeprefix('animation_motion.');expected=request(op)
 need(event.get('driver')=='check_selected_transition_intent.py'and event.get('validator')=='transition_physical_v1'and event.get('run_id')==context.get('run_id'),'foreign transition event')
 for dep in DEPS:need(isinstance(context.get('dependencies',{}).get(dep,{}).get('sha256'),str),'unbound transition dependency '+dep)
 route=decode(row.get('route_bytes_hex'),row.get('route_sha256'),'transition route');report=decode(row.get('report_bytes_hex'),row.get('report_sha256'),'transition native')
 need(route.get('source_head')==report.get('source_head')==context.get('tested_source')and route.get('operation')==op and route.get('passed')is True and route.get('case_selection')=='dummy'and route.get('phase')=='candidate'and route.get('profile')=='responsive'and route.get('root_mode')=='extracted'and route.get('invocation_kind')=='ordinary call','transition scope/source differs')
 need(len(route.get('cases',[]))==1,'one selected transition required');case=route['cases'][0];scene=case.get('scene')
 need(case.get('id')=='dummy'and same(case.get('params'),expected)and case.get('roles')==ROLES and case.get('passed')is True and row.get('scene')==scene,'transition request/rig differs')
 for field,dep in [('checker_sha256','test_project/tools/'+SCRIPT),('native_helper_sha256','test_project/tools/character_quality_native.gd'),('input_identity_helper_sha256','test_project/tools/motion_physical_input_identity.gd')]:need(report.get(field)==context['dependencies'][dep]['sha256'],'transition native source differs')
 need(report.get('route_sha256')==row['route_sha256']and report.get('case_selection')=='dummy','transition route selector differs')
 for kind in ('walk','idle'):
  ref=row.get('reference_routes',{}).get(kind,{})
  manifest=decode(ref.get('bytes_hex'),ref.get('sha256'),'accepted '+kind+' route')
  need(report.get(kind+'_route_sha256')==ref['sha256']and manifest.get('source_head')=='9188ffa22e756213ae48e88d359b5918c0b2c384'and manifest.get('passed')is True and manifest.get('operation')==kind+'_cycle','accepted reference producer differs')
  selected=[v for v in manifest.get('cases',[])if v.get('id')=='dummy']
  need(len(selected)==1 and (selected[0].get('scene'),selected[0].get('scene_sha256'))==REFERENCES[kind],'accepted reference row differs')
 for run in report.get('runs',[]):
  w=run.get('input_identity',{})
  need(w.get('complete')is True and w.get('scene')==scene and w.get('roles')==ROLES and same(w.get('request'),expected)and w.get('scene_before_sha256')==w.get('scene_after_sha256')==case.get('scene_sha256')and w.get('fixture_sha256')==case.get('fixture_sha256')==context['dependencies']['test_project/repair_rig_fixture.tscn']['sha256']and w.get('player_class')=='AnimationPlayer'and w.get('skeleton_class')=='Skeleton3D'and type(w.get('bone_count'))is int and w['bone_count']>0 and isinstance(w.get('rest_sha256'),str),'transition loaded bytes/request differs')
 need(len({r['input_identity']['rest_sha256']for r in report.get('runs',[])})==1,'transition rest differs across clocks')
 made=[p for p in public if p.get('operation')==row['operation']and p.get('scene')==scene and same(p.get('params'),expected)and p.get('response')==case.get('write')and p.get('driver')=='mcp_run_quality_review.py'];need(len(made)==1,'unique public transition write absent');made=made[0]
 native=[n for n in natives if n.get('id')==row.get('native_case_id')];need(len(native)==1,'actual transition native event absent');native=native[0]
 command=[context['engine_command'],'--headless','--path',row['project_root'],'--script','res://tools/'+SCRIPT,'--',row['route_path'],row['route_path'],row['walk_route_path'],row['idle_route_path'],row['report_path'],'case_id=dummy']
 need(native.get('driver')=='check_selected_transition_intent.py'and native.get('command')==row.get('command')==command and native.get('returncode')==0 and 'ERROR:'not in native.get('stdout','')+native.get('stderr',''),'transition native command/result differs')
 summaries=[json.loads(v.split('=',1)[1])for v in native.get('stdout','').splitlines()if v.startswith('START_STOP_QUALITY_CHECK=')]
 need(len(summaries)==1 and summaries[0].get('runs')==6 and summaries[0].get('passed')is True and summaries[0].get('engine_errors')==[],'transition native summary missing')
 saves=[s for s in support if s.get('public_tool')=='scene_save'and s.get('scene')==scene and s.get('response')==case.get('save')and made['execution_ns']<s['execution_ns']<native['execution_ns']]
 opens=[s for s in support if s.get('public_tool')=='scene_open'and s.get('request')=={'path':scene,'force_reload':True}and s.get('response')==case.get('reopen')and made['execution_ns']<s['execution_ns']<native['execution_ns']]
 need(len(saves)==len(opens)==1 and saves[0]['execution_ns']<opens[0]['execution_ns']and opens[0]['response'].get('reloaded_from_disk')is True and native['execution_ns']<event['execution_ns'],'transition save/reload/native order differs')
 return {'checks':numeric(op,report),'public_case_ids':[made['id'],saves[0]['id'],opens[0]['id'],native['id']],'limits':LIMITS}
