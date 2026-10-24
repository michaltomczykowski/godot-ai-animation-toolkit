import copy,json,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import subprocess
from saved_media_capture_checks import framing,validate_report,OPERATIONS,sha,clock,scene_clock
from saved_scene_media_capture import preflight,helper_bindings
FIXTURE=tempfile.TemporaryDirectory()
SCENE=Path(FIXTURE.name)/"rig.tscn"
SCENE.write_text('[gd_scene format=3]\n[sub_resource type="Animation" id="A"]\nloop_mode = 1\n[sub_resource type="AnimationLibrary" id="L"]\n_data = {&"generated": SubResource("A")}\n[node name="Main" type="Node2D"]\n[node name="Anim" type="AnimationPlayer" parent="."]\n')
from saved_scene_media_capture import capture

def geometry(kind):
 points=[[100,200],[120,200],[120,240],[100,240],[110,220],[115,220]]
 if kind=='rig':points+= [[105,210],[110,210],[115,210]]
 r={'points':points,'point_count':len(points),'body_rect':[24,100,1872,760],'bounds':[100,200,20,40],'behind_or_clipped_depth':0,'visible':True,'finite':True,'fits':True}
 if kind=='rig':r.update(bone_count=1,skin_scope='unskinned_joint_spheres_and_axis_rods_only')
 return r

def report(kind):
 duration=2 if kind=='graph'else 4;manifest={'cases':[]};runs=[]
 for op in sorted(OPERATIONS[kind]):
  manifest['cases'].append({'operation':op,'scene_sha256':'a'*64}if kind=='graph'else{'operation':op,'kind':'saved_static_pair'if op=='pose_apply'else'clip','scene':{'path':str(SCENE),'sha256':sha(SCENE)},'animation':'generated','player':'Anim',**({'before':{'sha256':'d'*64}}if op=='pose_apply'else{})})
  for take in (1,2):
   trace=[]
   for tick in range(duration*60+1):
    s={'time_s':tick/60,'movie_frame':tick<duration*60,'framing':geometry(kind),'ownership':True,'position':[(100*(tick/60-.5) if tick/60<=1.1 else 60+200*(tick/60-1.1)) if 30<tick<90 and op in {'state_machine','blend_space','blend_tree','locomotion'} else 0,-30 if 30<tick<90 and op=='one_shot_layer' else 0],'rotation_rad':.1 if 30<tick<90 and op=='additive_lean' else 0}
    if kind=='rig':s.update(finite=True,writers=0 if op=='pose_apply'else 1,expected_writers=0 if op=='pose_apply'else 1,native_update_requested=True,fresh_global_pose_error=0,skinned_meshes=0,position_error=0,rotation_error=0,scale_error=0,phase_s=0 if op=='pose_apply'else (tick/60)%1,assigned_animation=''if op=='pose_apply'else'generated',clip_length=0 if op=='pose_apply'else 1.,clip_loop_mode=0 if op=='pose_apply'else 1,playing=op!='pose_apply',channels=0 if op=='pose_apply'else 1,motion=.1)
    trace.append(s)
   runs.append({'operation':op,'take':take,'fps':60,'passed':True,'failures':[],'scene_sha256':sha(SCENE)if kind=='rig'else'a'*64,'before_sha256':'d'*64 if op=='pose_apply'else'','saved_pair_difference':.1,'trace':trace})
 r={'manifest_sha256':'b'*64,'passed':True,'failures':[],'engine_errors':[],'mode':'render','startup_admission':{'width':1920,'height':1080,'stretch':'viewport'},'viewport_sizes':{'logical':[1920,1080],'texture':[1920,1080]},'runs':runs};r['frames'if kind=='graph'else'intended_frames']=len(runs)*duration*60
 return manifest,r
class Controls(unittest.TestCase):
 def test_both_actual_report_shapes_and_explicit_end_boundaries(self):
  for kind in ('graph','rig'):
   m,r=report(kind);v=validate_report(m,r,'b'*64,kind);self.assertEqual(v['movie_frames'],1680 if kind=='graph'else 4320)
 def test_true_flag_cannot_hide_cropping_behind_header_or_tiny_geometry(self):
  for mutation in ('crop','header','behind','hidden','bounds','tiny'):
   g=geometry('graph')
   if mutation=='crop':g['points'][0][0]=1921
   if mutation=='header':g['points'][0][1]=70
   if mutation=='behind':g['behind_or_clipped_depth']=1
   if mutation=='hidden':g['visible']=False
   if mutation=='bounds':g['bounds'][0]=90
   if mutation=='tiny':g['points']=[[100,200]]*6;g['bounds']=[100,200,0,0]
   with self.assertRaises(ValueError,msg=mutation):framing(g,'graph')
 def test_source_clock_ownership_duplicate_and_movie_boundary_corruption(self):
  m,original=report('graph')
  for mutation in ('native','viewport','source','ownership','duplicate','boundary','time'):
   r=copy.deepcopy(original)
   if mutation=='native':r['mode']='native'
   if mutation=='viewport':r['viewport_sizes']['texture']=[1152,648]
   if mutation=='source':r['runs'][0]['scene_sha256']='c'*64
   if mutation=='ownership':r['runs'][0]['trace'][3]['ownership']=False
   if mutation=='duplicate':r['runs'][1]=copy.deepcopy(r['runs'][0])
   if mutation=='boundary':r['runs'][0]['trace'][-1]['movie_frame']=True
   if mutation=='time':r['runs'][0]['trace'][8]['time_s']=.8
   with self.assertRaises(ValueError,msg=mutation):validate_report(m,r,'b'*64,'graph')
 def test_skin_stale_native_global_and_authored_channel_refusals(self):
  m,r=report('rig')
  for key,value in [('skinned_meshes',1),('native_update_requested',False),('fresh_global_pose_error',.00002),('rotation_error',.00002)]:
   old=r['runs'][0]['trace'][0][key];r['runs'][0]['trace'][0][key]=value
   with self.assertRaises(ValueError,msg=key):validate_report(m,r,'b'*64,'rig')
   r['runs'][0]['trace'][0][key]=old
 def test_rig_clock_stuck_lag_skip_and_changed_clip_fail(self):
  m,original=report('rig')
  for fault in ('stuck','lag','skip','clip','length','loop'):
   r=copy.deepcopy(original);run=next(x for x in r['runs']if x['operation']=='walk_cycle')
   if fault=='stuck':
    for sample in run['trace']:sample['phase_s']=.25
   else:
    sample=run['trace'][20]
    if fault=='lag':sample['phase_s']-=1/60
    if fault=='skip':sample['phase_s']+=1/60
    if fault=='clip':sample['assigned_animation']='unrelated'
    if fault=='length':sample['clip_length']=2.
    if fault=='loop':sample['clip_loop_mode']=0
   with self.assertRaises(ValueError,msg=fault):validate_report(m,r,'b'*64,'rig')
 def test_clock_finite_end_linear_wrap_and_pingpong_conventions(self):
  for loop in (0,1,2):
   for tick in range(241):
    t=tick/60;phase=min(t,1)if loop==0 else t%1 if loop==1 else t%2 if t%2<=1 else 2-t%2
    clock({'phase_s':phase,'assigned_animation':'generated','clip_length':1.,'clip_loop_mode':loop,'playing':loop!=0 or t<=1},{'animation':'generated','length':1.,'loop_mode':loop},tick,60)
 def test_clock_metadata_comes_from_exact_saved_scene_bytes(self):
  with tempfile.TemporaryDirectory()as d:
   p=Path(d)/'scene.tscn';p.write_text('[gd_scene format=3]\n[sub_resource type="Animation" id="A"]\nlength = 2.5\nloop_mode = 2\n[sub_resource type="AnimationLibrary" id="L"]\n_data = {&"generated": SubResource("A")}\n[node name="Main" type="Node2D"]\n[node name="Anim" type="AnimationPlayer" parent="."]\n')
   row={'scene':{'path':str(p),'sha256':sha(p)},'animation':'generated','player':'Anim'}
   self.assertEqual(scene_clock(row),{'animation':'generated','length':2.5,'loop_mode':2,'speed_scale':1.})
   p.write_text(p.read_text().replace('2.5','3.5'))
   with self.assertRaises(ValueError):scene_clock(row)
   row['scene']['sha256']=sha(p);row['animation']='unrelated'
   with self.assertRaises(ValueError):scene_clock(row)
 def test_actual_saved_speed_and_retained_finite_endpoint(self):
  with tempfile.TemporaryDirectory()as d:
   p=Path(d)/'scene.tscn';p.write_text('[gd_scene format=3]\n[sub_resource type="Animation" id="A"]\n[sub_resource type="AnimationLibrary" id="L"]\n_data = {&"generated": SubResource("A")}\n[node name="Main" type="Node2D"]\n[node name="Player" type="AnimationPlayer" parent="."]\nspeed_scale = 0.8\n[node name="Peer" type="AnimationPlayer" parent="."]\nspeed_scale = 2.0\n')
   row={'scene':{'path':str(p),'sha256':sha(p)},'animation':'generated','player':'Player'};s=scene_clock(row)
   self.assertEqual(s['speed_scale'],.800000011920929)
   for tick,phase,playing in ((1,.0133333335320155,True),(75,1.,False),(239,1.,False)):
    sample={'phase_s':phase,'assigned_animation':'generated','clip_length':1.,'clip_loop_mode':0,'playing':playing}
    clock(sample,s,tick,60)
    for wrong in (0.,.25,phase+1/60):
     if wrong==phase:continue
     with self.assertRaises(ValueError):clock(dict(sample,phase_s=wrong),s,tick,60)
   for player in ('Missing','Peer'):
    wrong=dict(row,player=player)
    if player=='Missing':
     with self.assertRaises(ValueError):scene_clock(wrong)
    else:self.assertEqual(scene_clock(wrong)['speed_scale'],2.)
 def test_raster_edge_cannot_pass(self):
  for kind in ('graph','rig'):
   g=geometry(kind);g['points'][0]=[24,100]
   with self.assertRaises(ValueError):framing(g,kind)
 def test_preflight_requires_explicit_empty_error_lists_and_actual_clip_helper(self):
  dependencies={rel:'a'*64 for _,rel in helper_bindings('rig')};base={'passed':True,'failures':[],'engine_errors':[],'mode':'native','manifest_sha256':'b'*64,'runs':[]}
  base.update({key:'a'*64 for key,_ in helper_bindings('rig')})
  with tempfile.TemporaryDirectory()as d:
   p=Path(d)/'positive.json';p.with_suffix('.log').write_text('Godot Engine v4.7.2.stable.official\n')
   for fault in ('missing_failures','null_failures','missing_errors','null_errors','missing_clip_helper','changed_clip_helper'):
    r=copy.deepcopy(base)
    if fault=='missing_failures':del r['failures']
    if fault=='null_failures':r['failures']=None
    if fault=='missing_errors':del r['engine_errors']
    if fault=='null_errors':r['engine_errors']=None
    if fault=='missing_clip_helper':del r['clip_helper_sha256']
    if fault=='changed_clip_helper':r['clip_helper_sha256']='c'*64
    p.write_text(json.dumps(r))
    with self.assertRaises(ValueError,msg=fault):preflight(p,{'cases':[]},'b'*64,'rig',dependencies)
   p.write_text(json.dumps(base));preflight(p,{'cases':[]},'b'*64,'rig',dependencies)
 def test_serial_wrapper_failed_native_capture_preserves_receipt_and_never_encodes(self):
  with tempfile.TemporaryDirectory()as directory:
   root=Path(directory);project=root/'project';project.mkdir();(project/'project.godot').write_text('[application]\nconfig/name="offline"\n');manifest=root/'manifest.json';manifest.write_text(json.dumps({'cases':[{'operation':x,'scene':str(root/'saved.tscn'),'scene_sha256':'a'*64}for x in sorted(OPERATIONS['graph'])]}));args=SimpleNamespace(output=root/'output',project=project,godot=Path('fake-godot'),ffmpeg=Path('fake-ffmpeg'),ffprobe=Path('fake-ffprobe'));commands=[]
   def runner(cmd,**kwargs):commands.append(cmd);return subprocess.CompletedProcess(cmd,1)
   with patch('saved_scene_media_capture.verify_scenes'),patch('saved_scene_media_capture.tools',return_value={}),patch('saved_scene_media_capture.preflight',return_value={}):
    with self.assertRaises(ValueError):capture(args,'graph',manifest,root/'fake-native.json',runner)
   receipt=json.loads((args.output/'graph/receipt.json').read_text());self.assertEqual(receipt['status'],'failed_preserved');self.assertEqual(len(commands),1);self.assertNotIn('fake-ffmpeg',str(commands));self.assertFalse((project/'override.cfg').exists());self.assertTrue((args.output/'graph/startup.json').is_file())
if __name__=='__main__':unittest.main()
