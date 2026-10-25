"""Root-owned manual PNG capture/encode/decode; never generate animation assets."""
import argparse,json,os,subprocess
from pathlib import Path
from check_saved_modifier_capture import validate
from saved_effect_media_queue import durable,decode_progress,sha
from ci_rendered_preview import validate_editor_log

def capture(a,runner=subprocess.run):
    a.output.mkdir(parents=True,exist_ok=False)
    frames=a.output/'frames';report_path=a.output/'render.json'
    manifest=json.loads(a.manifest.read_text());reference=json.loads(a.native.read_text())
    validate(reference,manifest,sha(a.manifest))
    state={'kind':'saved_modifier_manual_capture','state':'starting','manifest_sha256':sha(a.manifest),'native_sha256':sha(a.native),'recorder_sha256':sha(Path(__file__)),'visual_approval':False}
    def stage(name):state['state']=name;durable(a.output/'recording.json',state)
    try:
        command=[str(a.godot),'--path',str(a.project.resolve()),'--rendering-method','gl_compatibility','--rendering-driver','opengl3','--script','res://tools/render_saved_modifier_capture.gd','--',str(a.manifest.resolve()),str(report_path.resolve()),'render',str(a.native.resolve()),str(frames.resolve())]
        state['command']=command;stage('capturing_exact_native_frames')
        env=dict(os.environ,APPDATA=str(a.appdata.resolve()))
        # Keep engine output durable even if this parent is interrupted mid-capture.
        with (a.output/'engine.log').open('x',encoding='utf-8') as engine_log:
            done=runner(command,env=env,stdout=engine_log,stderr=subprocess.STDOUT,text=True,check=False,timeout=900)
        engine_output=(a.output/'engine.log').read_text(encoding='utf-8')
        state['engine_exit']=done.returncode;state['engine_log_sha256']=sha(a.output/'engine.log')
        if done.returncode:raise ValueError('native renderer nonzero exit')
        validate_editor_log(engine_output)
        report=json.loads(report_path.read_text());validate(report,manifest,sha(a.manifest),frames,reference,sha(a.native))
        state['report_sha256']=sha(report_path);stage('all2400_pngs_admitted')
        video=a.output/'saved-five-modifiers.mp4'
        command=[str(a.ffmpeg),'-hide_banner','-loglevel','error','-n','-framerate','60','-i',str(frames/'%06d.png'),'-an','-frames:v','2400','-c:v','libx264','-threads','2','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
        state['encode_command']=command;runner(command,check=True,capture_output=True,text=True,timeout=300)
        command=[str(a.ffmpeg),'-hide_banner','-loglevel','error','-xerror','-err_detect','explode','-i',str(video),'-map','0','-f','null','-','-progress','pipe:1']
        state['decode_command']=command;stage('independent_full_decode')
        done=runner(command,check=True,capture_output=True,text=True,timeout=180);(a.output/'decode.log').write_text(done.stdout+done.stderr)
        if done.stderr.strip():raise ValueError('independent decoder errors')
        state['full_decode']=decode_progress(done.stdout,{'fps':60,'seconds':40})
        probe=runner([str(a.ffprobe),'-v','error','-show_streams','-of','json',str(video)],check=True,capture_output=True,text=True,timeout=30)
        streams=json.loads(probe.stdout)['streams']
        if len(streams)!=1 or streams[0].get('width')!=1920 or streams[0].get('height')!=1080 or streams[0].get('avg_frame_rate')!='60/1':raise ValueError('encoded stream dimensions/rate')
        state['video_sha256']=sha(video);state['decode_sha256']=sha(a.output/'decode.log');state['streams']=streams
        stage('complete_technical_media_visual_review_pending');return state
    except BaseException as exc:
        state['error']=repr(exc);stage('failed_preserved');raise
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    for name in ('project','appdata','manifest','native','godot','ffmpeg','ffprobe','output'):p.add_argument('--'+name,type=Path,required=True)
    capture(p.parse_args())
