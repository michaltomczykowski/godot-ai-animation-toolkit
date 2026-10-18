"""Strict admission of actual saved graph/rig rendered bundle reports."""
import hashlib,json,math
from pathlib import Path
BODY=[24,100,1872,760]
OPERATIONS={'graph':{'state_machine','blend_space','blend_tree','wire','locomotion','one_shot_layer','additive_lean'},'rig':{'pose_to_clip','walk_cycle','idle_breathing','blink','jumping_jack','squat','punch','bake_pose_sequence','pose_apply'}}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def require(ok,message):
 if not ok:raise ValueError(message)
def finite(v):return type(v)in(int,float)and math.isfinite(v)
def framing(value,kind):
 points=value.get('points',[]);minimum=6 if kind=='graph'else 9
 require(value.get('body_rect')==BODY and len(points)==value.get('point_count')and len(points)>=minimum,'missing exact projected geometry/body')
 if kind=='graph':require(len(points)==6,'unexpected saved graph display polygon')
 require(all(isinstance(p,list)and len(p)==2 and all(finite(x)for x in p)for p in points),'nonfinite projected vertices')
 require(value.get('visible')is True and value.get('finite')is True and value.get('behind_or_clipped_depth')==0,'invisible/behind/depth clipped geometry')
 require(all(24<=x<=1896 and 100<=y<=860 for x,y in points),'projected geometry crosses body/header/caption')
 xs,ys=zip(*points);bounds=[min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]
 require(bounds[2]>=2 and bounds[3]>=2,'subpixel/unreadable projected geometry')
 require(len(value.get('bounds',[]))==4 and all(finite(x)and abs(x-y)<1e-4 for x,y in zip(value['bounds'],bounds)),'reported bounds differ from actual projected vertices')
 if kind=='rig':require(value.get('bone_count',0)>0 and len(points)==9*value['bone_count']and value.get('skin_scope')=='unskinned_joint_spheres_and_axis_rods_only','unsupported rig body representation')
 return bounds

def validate_report(manifest,report,manifest_sha,kind):
 count=7 if kind=='graph'else 9;duration=2 if kind=='graph'else 4
 require(len(manifest['cases'])==count and {r['operation']for r in manifest['cases']}==OPERATIONS[kind]and report.get('manifest_sha256')==manifest_sha,'manifest identity/count differs')
 require(report.get('passed')is True and report.get('failures')==[] and report.get('engine_errors')==[],'saved/native runtime report failed')
 require(report.get('mode')=='render','headless/native/missing mode cannot qualify rendered capture')
 admission=report.get('startup_admission',{});require(admission.get('width')==1920 and admission.get('height')==1080 and admission.get('stretch')=='viewport','prestartup MovieMaker viewport not admitted')
 sizes=report.get('viewport_sizes',{});require(sizes.get('logical')==[1920,1080]and sizes.get('texture')==[1920,1080],'logical/texture size differs')
 runs=report.get('runs',[]);ops={x['operation']for x in manifest['cases']};expected={(op,take,60)for op in ops for take in (1,2)}
 require(len(runs)==count*2 and {(r.get('operation'),r.get('take'),r.get('fps'))for r in runs}==expected,'missing/duplicate rendered case/take identity')
 movie_frames=0
 for run in runs:
  require(run.get('passed')is True and run.get('failures')==[],'failed per-case native run')
  row=next(x for x in manifest['cases']if x['operation']==run['operation']);trace=run.get('trace',[])
  if kind=='rig':require(row.get('kind')==('saved_static_pair'if row['operation']=='pose_apply'else'clip'),'unsupported rig scene/clock kind')
  require(len(trace)==duration*60+1,'incomplete native rendered trace including end boundary')
  for tick,sample in enumerate(trace):
   require(abs(sample.get('time_s',-1)-tick/60)<1e-7,'native schedule time differs')
   require(sample.get('movie_frame')is (tick<duration*60),'movie/end-boundary frame distinction missing')
   framing(sample.get('framing',{}),kind)
   if sample['movie_frame']:movie_frames+=1
   if kind=='graph':
    require(sample.get('ownership')is True,'graph writer ownership differs')
    require(len(sample.get('position',[]))==2 and all(finite(x)for x in sample['position'])and finite(sample.get('rotation_rad')),'nonfinite actual graph target')
   else:
    require(sample.get('finite')is True and sample.get('writers')==sample.get('expected_writers'),'rig finite/native writer ownership differs')
    require(sample.get('native_update_requested')is True and finite(sample.get('fresh_global_pose_error'))and sample['fresh_global_pose_error']<1e-5,'native global bone transform not fresh')
    require(sample.get('skinned_meshes')==0,'skin playback not admitted by unskinned capture')
    require(all(finite(sample.get(k))and sample[k]<=1e-5 for k in ('position_error','rotation_error','scale_error')),'native authored channel mismatch')
    expected_writers=1 if row.get('kind')=='clip'else 0
    require(sample['expected_writers']==expected_writers and finite(sample.get('phase_s'))and sample['phase_s']>=0,'saved rig clip/static clock contract differs')
    require(sample.get('channels',0)>0 if expected_writers else sample.get('channels')==0,'saved rig channel admission differs')
  if kind=='graph':require(run.get('scene_sha256')==row['scene_sha256'],'graph scene identity differs')
  else:require(run.get('scene_sha256')==row['scene']['sha256']and run.get('before_sha256','')==(row.get('before',{}).get('sha256','')),'rig scene pair identity differs')
  if kind=='graph':
   op=run['operation'];effect=trace[60];baseline=trace[0]
   if op in {'state_machine','blend_space','blend_tree','locomotion'}:require(max(s['position'][0]for s in trace if .5<s['time_s']<=1)>=20,'saved graph walk control ineffective')
   if op=='one_shot_layer':require(effect['position'][1]<=-20,'saved OneShot control ineffective')
   if op=='additive_lean':require(effect['rotation_rad']>=.05,'saved additive control ineffective')
   if op=='wire':require(all(max(abs(a-b)for a,b in zip(s['position'],baseline['position']))<=.01 and abs(s['rotation_rad']-baseline['rotation_rad'])<=.01 for s in trace),'saved wire idle binding moved')
   if op in {'blend_space','locomotion'}:
    velocities=[(s['time_s'],(s['position'][0]-trace[i-1]['position'][0])*60)for i,s in enumerate(trace)if i>0]
    walk=max(v for t,v in velocities if .6<t<1)
    run_speed=max(v for t,v in velocities if 1.1+1.5/60<t<=1.2)
    require(abs(walk-100)<.01 and abs(run_speed-200)<.01,'native saved walk/run control speed differs')
   if op!='state_machine':require(max(abs(a-b)for a,b in zip(trace[-1]['position'],baseline['position']))<=.01 and abs(trace[-1]['rotation_rad']-baseline['rotation_rad'])<=.01,'saved graph neutral reset failed')
  elif row.get('kind')=='clip':require(max(s.get('motion',0)for s in trace)>=.001,'inert saved rig clip')
  else:require(finite(run.get('saved_pair_difference'))and run['saved_pair_difference']>=.001,'unchanged saved pose pair')
 require(movie_frames==count*2*duration*60,'movie frame admission count differs')
 require(report.get('frames'if kind=='graph'else'intended_frames')==movie_frames,'renderer movie-frame total differs')
 return {'kind':kind,'runs':len(runs),'movie_frames':movie_frames,'native_boundary_samples':len(runs),'visual_assessment':'pending','skin_scope':'not_applicable_unskinned_display_geometry_only'}
