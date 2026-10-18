"""Serial graph/rig saved-bundle capture; reuse existing startup/decode utilities."""
import argparse,json,re,subprocess,sys
from pathlib import Path
from saved_effect_media_queue import durable,decode_progress,sha
from movie_capture_startup import run_capture
from ci_rendered_preview import validate_editor_log
from saved_media_capture_checks import validate_report,require
ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def scenes(manifest,kind):
 for row in manifest['cases']:
  if kind=='graph':yield Path(row['scene']),row['scene_sha256']
  else:
   yield Path(row['scene']['path']),row['scene']['sha256']
   if row.get('before'):yield Path(row['before']['path']),row['before']['sha256']
def verify_scenes(manifest,kind):
 for path,digest in scenes(manifest,kind):
  require(sha(path)==digest,'saved scene changed: '+str(path))
  if kind=='rig':require('type="MeshInstance3D"'not in path.read_text(encoding='utf-8-sig'),'mesh/skin body requires a separate capture contract')
def engine_banner(text):
 lines=[line for line in text.splitlines()if line.startswith('Godot Engine v')]
 require(bool(lines)and re.match(r'^Godot Engine v4\.7\.2\.stable',lines[0])is not None,'actual engine startup is not Godot4.7.2stable')
 return lines[0]
def tools(kind):
 paths=['tools/saved_scene_media_capture.py','tools/saved_media_capture_checks.py','tools/movie_capture_startup.py','tools/saved_effect_media_queue.py','tools/ci_rendered_preview.py','test_project/tools/saved_media_framing.gd','test_project/tools/render_saved_'+kind+'_effects.gd','test_project/tools/saved_'+kind+'_media_native.gd']
 if kind=='rig':paths.append('test_project/tools/saved_graph_media_native.gd')
 return {p:sha(ROOT/p)for p in paths}
def preflight(path,manifest,manifest_hash,kind,dependencies):
 r=read(path);require(r.get('passed')is True and not r.get('failures')and not r.get('engine_errors')and r.get('mode')=='native','native positive preflight failed')
 require(r.get('manifest_sha256')==manifest_hash,'native preflight used another manifest')
 for key,rel in [('renderer_sha256','test_project/tools/render_saved_'+kind+'_effects.gd'),('native_helper_sha256','test_project/tools/saved_'+kind+'_media_native.gd'),('framing_helper_sha256','test_project/tools/saved_media_framing.gd')]:require(r.get(key)==dependencies[rel],'native preflight checker source differs: '+key)
 expected={(x['operation'],t,fps)for x in manifest['cases']for t in (1,2)for fps in (30,60,120)};runs=r.get('runs',[])
 require(len(runs)==len(expected)and {(x.get('operation'),x.get('take'),x.get('fps'))for x in runs}==expected and all(x.get('passed')is True and x.get('failures')==[]for x in runs),'native preflight matrix incomplete')
 log=path.with_suffix('.log');require(log.is_file(),'complete native positive log required');text=log.read_text(encoding='utf-8',errors='replace');validate_editor_log(text);engine_banner(text)
 return {'report':str(path),'sha256':sha(path),'log':str(log),'log_sha256':sha(log)}
def capture(args,kind,manifest_path,native_path,runner=subprocess.run):
 manifest_path=manifest_path.resolve();manifest=read(manifest_path);digest=sha(manifest_path);verify_scenes(manifest,kind);dependencies=tools(kind);proof=preflight(native_path,manifest,digest,kind,dependencies)
 folder=args.output.resolve()/kind;folder.mkdir(parents=True,exist_ok=False);receipt=folder/'receipt.json';frames=folder/'frames';frames.mkdir();report_path=folder/'native-observations.json';log=folder/'capture.log';seconds=len(manifest['cases'])*2*(2 if kind=='graph'else 4);expected=60*seconds
 state={'kind':kind,'status':'prepared','manifest':str(manifest_path),'manifest_sha256':digest,'producer_dependencies':dependencies,'native_preflight':proof,'historical_scenes':[{'path':str(p),'sha256':s}for p,s in scenes(manifest,kind)],'expected_frames':expected,'visual_assessment':'pending','qualification':'pending'}
 def stage(value):state['status']=value;durable(receipt,state)
 try:
  stage('before_native_capture')
  command=[str(args.godot),'--path',str(args.project.resolve()),'--rendering-method','gl_compatibility','--rendering-driver','opengl3','--fixed-fps','60','--write-movie',str(frames/'frame.png'),'--script','res://tools/render_saved_'+kind+'_effects.gd','--',str(manifest_path),str(report_path)]
  state['capture_command']=command;stage('capturing')
  with log.open('x',encoding='utf-8')as stream:
   def launch(cmd,check=False):return runner(cmd,check=check,stdout=stream,stderr=subprocess.STDOUT)
   startup=run_capture(args.project,1920,1080,folder/'startup.json',command,launch)
  require(startup['passed'],'startup/capture failed');text=log.read_text(encoding='utf-8',errors='replace');validate_editor_log(text);state['actual_engine_banner']=engine_banner(text);r=read(report_path);state['report_proof']=validate_report(manifest,r,digest,kind)
  for key,rel in [('renderer_sha256','test_project/tools/render_saved_'+kind+'_effects.gd'),('native_helper_sha256','test_project/tools/saved_'+kind+'_media_native.gd'),('framing_helper_sha256','test_project/tools/saved_media_framing.gd')]:require(r.get(key)==dependencies[rel],'actual renderer/helper source changed')
  require(sha(manifest_path)==digest and dependencies==tools(kind),'manifest/tool changed during capture');verify_scenes(manifest,kind);stage('validating_pngs')
  paths=sorted(frames.glob('frame????????.png'));require([p.name for p in paths]==[f'frame{i:08d}.png'for i in range(expected)],'incomplete/extra actual PNG sequence')
  from PIL import Image
  hashes=[]
  for p in paths:
   with Image.open(p)as im:require(im.format=='PNG'and im.size==(1920,1080),'cropped/nonPNG frame');im.load()
   hashes.append({'path':str(p),'sha256':sha(p)})
  state['frames']=hashes;state['native_report_sha256']=sha(report_path);state['startup_sha256']=sha(folder/'startup.json');state['capture_log_sha256']=sha(log);video=folder/'saved-comparison.mp4';stage('encoding')
  command=[str(args.ffmpeg),'-hide_banner','-loglevel','error','-n','-framerate','60','-i',str(frames/'frame%08d.png'),'-an','-frames:v',str(expected),'-c:v','libx264','-threads','2','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
  state['encode_command']=command;stage('encoding');done=runner(command,check=True,capture_output=True,text=True);(folder/'encode.log').write_text(done.stdout+done.stderr);require(not done.stderr.strip(),'encoder emitted errors')
  command=[str(args.ffmpeg),'-hide_banner','-loglevel','error','-xerror','-err_detect','explode','-i',str(video),'-map','0','-f','null','-','-progress','pipe:1'];state['decode_command']=command;stage('independent_full_decode');done=runner(command,check=True,capture_output=True,text=True);(folder/'decode.log').write_text(done.stdout+done.stderr);require(not done.stderr.strip(),'independent decoder emitted errors');state['full_decode']=decode_progress(done.stdout,{'fps':60,'seconds':seconds})
  done=runner([str(args.ffprobe),'-v','error','-show_streams','-of','json',str(video)],check=True,capture_output=True,text=True);streams=json.loads(done.stdout)['streams'];require(len(streams)==1 and streams[0].get('codec_type')=='video'and streams[0].get('width')==1920 and streams[0].get('height')==1080 and streams[0].get('avg_frame_rate')=='60/1','encoded stream differs from admitted frames');state['streams']=streams;state['video_sha256']=sha(video);state['decode_log_sha256']=sha(folder/'decode.log');verify_scenes(manifest,kind);stage('complete_media_visual_review_pending');return state
 except Exception as exc:
  state['error']=str(exc);stage('failed_preserved');raise

def main():
 p=argparse.ArgumentParser(description=__doc__)
 for field in ('project','godot','ffmpeg','ffprobe','output'):p.add_argument('--'+field,type=Path,required=True)
 for kind in ('graph','rig'):
  p.add_argument('--'+kind+'-manifest',type=Path);p.add_argument('--'+kind+'-native-report',type=Path)
 a=p.parse_args();pairs=[(k,getattr(a,k+'_manifest'),getattr(a,k+'_native_report'))for k in ('graph','rig')if getattr(a,k+'_manifest')];p.error('select at least one manifest')if not pairs else None
 for kind,manifest,native in pairs:
  if native is None:p.error('--'+kind+'-native-report is required')
  capture(a,kind,manifest,native)
 return 0
if __name__=='__main__':raise SystemExit(main())
