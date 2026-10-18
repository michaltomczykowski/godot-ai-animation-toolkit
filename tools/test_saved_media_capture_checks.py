import copy,json,tempfile,unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import subprocess
from saved_media_capture_checks import framing,validate_report,OPERATIONS
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
  manifest['cases'].append({'operation':op,'scene_sha256':'a'*64}if kind=='graph'else{'operation':op,'kind':'saved_static_pair'if op=='pose_apply'else'clip','scene':{'sha256':'a'*64},**({'before':{'sha256':'d'*64}}if op=='pose_apply'else{})})
  for take in (1,2):
   trace=[]
   for tick in range(duration*60+1):
    s={'time_s':tick/60,'movie_frame':tick<duration*60,'framing':geometry(kind),'ownership':True,'position':[(100*(tick/60-.5) if tick/60<=1.1 else 60+200*(tick/60-1.1)) if 30<tick<90 and op in {'state_machine','blend_space','blend_tree','locomotion'} else 0,-30 if 30<tick<90 and op=='one_shot_layer' else 0],'rotation_rad':.1 if 30<tick<90 and op=='additive_lean' else 0}
    if kind=='rig':s.update(finite=True,writers=0 if op=='pose_apply'else 1,expected_writers=0 if op=='pose_apply'else 1,native_update_requested=True,fresh_global_pose_error=0,skinned_meshes=0,position_error=0,rotation_error=0,scale_error=0,phase_s=tick/60,channels=0 if op=='pose_apply'else 1,motion=.1)
    trace.append(s)
   runs.append({'operation':op,'take':take,'fps':60,'passed':True,'failures':[],'scene_sha256':'a'*64,'before_sha256':'d'*64 if op=='pose_apply'else'','saved_pair_difference':.1,'trace':trace})
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
 def test_serial_wrapper_failed_native_capture_preserves_receipt_and_never_encodes(self):
  with tempfile.TemporaryDirectory()as directory:
   root=Path(directory);project=root/'project';project.mkdir();(project/'project.godot').write_text('[application]\nconfig/name="offline"\n');manifest=root/'manifest.json';manifest.write_text(json.dumps({'cases':[{'operation':x,'scene':str(root/'saved.tscn'),'scene_sha256':'a'*64}for x in sorted(OPERATIONS['graph'])]}));args=SimpleNamespace(output=root/'output',project=project,godot=Path('fake-godot'),ffmpeg=Path('fake-ffmpeg'),ffprobe=Path('fake-ffprobe'));commands=[]
   def runner(cmd,**kwargs):commands.append(cmd);return subprocess.CompletedProcess(cmd,1)
   with patch('saved_scene_media_capture.verify_scenes'),patch('saved_scene_media_capture.tools',return_value={}),patch('saved_scene_media_capture.preflight',return_value={}):
    with self.assertRaises(ValueError):capture(args,'graph',manifest,root/'fake-native.json',runner)
   receipt=json.loads((args.output/'graph/receipt.json').read_text());self.assertEqual(receipt['status'],'failed_preserved');self.assertEqual(len(commands),1);self.assertNotIn('fake-ffmpeg',str(commands));self.assertFalse((project/'override.cfg').exists());self.assertTrue((args.output/'graph/startup.json').is_file())
if __name__=='__main__':unittest.main()
