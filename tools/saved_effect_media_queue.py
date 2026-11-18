"""Serial private saved-effect capture/encode queue; never qualifies visual review.

Existing captures require --reuse INDEX=DIR and are independently revalidated.
Failed/partial output is preserved and blocks the queue; select a fresh output
root for a retry. A durable checkpoint precedes every subprocess stage.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
from fractions import Fraction
from check_saved_effects import check, capture_failures
from ci_rendered_preview import validate_editor_log
from movie_capture_startup import run_capture, override_bytes
from review_receipts import write_json as durable

ROOT=Path(__file__).resolve().parents[1]

def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def read(path): return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def verify_inputs(plan,project,repo=ROOT):
    if plan.get('kind')!='saved_effect_render_plan' or not plan.get('cases'): raise ValueError('invalid immutable plan')
    for rel,expected in plan['tool_sha256'].items():
        if sha(repo/rel)!=expected: raise ValueError('plan tool changed: '+rel)
    for case in plan['cases']:
        for scene in case['scenes'].values():
            if sha(scene['path'])!=scene['sha256']: raise ValueError('saved scene changed')
        for rel,expected in case['dependencies'].items():
            if not rel.startswith('res://') or '..' in Path(rel[6:]).parts: raise ValueError('unsafe resource path')
            if sha(project/rel[6:])!=expected: raise ValueError('saved dependency changed: '+rel)

def validate_capture(case,folder,plan_sha,checker=check):
    from PIL import Image
    report=read(folder/'native-observations.json')
    startup=read(folder/'startup.json')
    if (startup.get('passed') is not True or startup.get('cleanup')!='owned_override_removed'
        or startup.get('returncode')!=0 or startup.get('viewport')!=[1400,800]
        or startup.get('override_sha256')!=hashlib.sha256(override_bytes(1400,800)).hexdigest()
        or not startup.get('project_sha256_before') or startup.get('project_sha256_before')!=startup.get('project_sha256_after')):
        raise ValueError('capture startup receipt missing/failed')
    if report.get('plan_sha256')!=plan_sha: raise ValueError('capture came from another immutable plan')
    native=checker(case,report)
    failures=native['failures']+capture_failures(report,folder,case['fps']*case['seconds'])
    if failures: raise ValueError('native capture failed: '+str(failures[:5]))
    primary=folder/'capture.log' if (folder/'capture.log').is_file() else folder/'renderer.log'
    if not primary.is_file() or not primary.stat().st_size: raise ValueError('complete capture log is required')
    logs=[primary]+([folder/'errors.log'] if (folder/'errors.log').is_file() else [])
    for path in logs: validate_editor_log(path.read_text(encoding='utf-8',errors='replace'))
    paths=sorted(folder.glob('frame????????.png'))
    expected=[f'frame{i:08d}.png' for i in range(case['fps']*case['seconds'])]
    if [p.name for p in paths]!=expected: raise ValueError('missing/duplicate capture sequence')
    frames=[]
    for path in paths:
        with Image.open(path) as image:
            if image.format!='PNG' or image.size!=(1400,800): raise ValueError('cropped/invalid actual PNG')
            image.load()
        frames.append({'path':str(path.resolve()),'sha256':sha(path)})
    if case.get('audio_output_required') and not (folder/'frame.wav').is_file(): raise ValueError('actual captured WAV missing')
    return {'native_report_sha256':sha(folder/'native-observations.json'),'startup_sha256':sha(folder/'startup.json'),
        'native_check':native,
        'logs':[{'path':str(p.resolve()),'sha256':sha(p)} for p in logs],'frames':frames,
        'wav_sha256':sha(folder/'frame.wav') if case.get('audio_output_required') else None}

def decode_progress(text,case):
    frames=re.findall(r'^frame=(\d+)$',text,re.M)
    times=re.findall(r'^out_time_us=(\d+)$',text,re.M)
    if not frames or not times or int(frames[-1])!=case['fps']*case['seconds'] or abs(int(times[-1])/1e6-case['seconds'])>1/case['fps']+.001:
        raise ValueError('independent full video decode is incomplete')
    return {'frames':int(frames[-1]),'duration_s':int(times[-1])/1e6}

def media_metadata(value,case):
    streams=value.get('streams',[])
    videos=[s for s in streams if s.get('codec_type')=='video']
    audios=[s for s in streams if s.get('codec_type')=='audio']
    if len(videos)!=1 or [videos[0].get('width'),videos[0].get('height')]!=[1400,800] or Fraction(videos[0].get('avg_frame_rate','0'))!=case['fps']:
        raise ValueError('encoded video dimensions/FPS differ from capture')
    if bool(audios)!=bool(case.get('audio_output_required')): raise ValueError('encoded audio stream ownership mismatch')

def preserved_prefix(previous, plan, plan_sha):
    """Revalidate an immutable complete prefix of a failed, inactive queue."""
    checkpoint_path=previous/'queue.json'
    if (previous/'queue.lock').exists():
        raise ValueError('Previous capture queue is still locked')
    checkpoint=read(checkpoint_path)
    if (checkpoint.get('status')!='failed_preserved' or checkpoint.get('plan_sha256')!=plan_sha
            or checkpoint.get('first_plan_case',0)!=0):
        raise ValueError('Expected an inactive failed queue for the same full plan')
    rows=checkpoint['cases']
    if not 0 < len(rows) < len(plan['cases']):
        raise ValueError('Expected a nonempty incomplete captured prefix')
    for i,closed in enumerate(rows):
        folder=previous/f'case{i:02d}'
        path=folder/'media-receipt.json'
        case=plan['cases'][i]
        if (closed['index']!=i or closed['case_id']!=case['id']
                or Path(closed['receipt']).resolve()!=path.resolve() or sha(path)!=closed['sha256']):
            raise ValueError('Previous complete receipt differs from its checkpoint')
        receipt=read(path)
        if (receipt['plan_sha256']!=plan_sha or receipt['case_id']!=case['id']
                or receipt['operation']!=case['operation']
                or receipt['full_decode']['frames']!=case['fps']*case['seconds']
                or abs(receipt['full_decode']['duration_s']-case['seconds'])>1/case['fps']+.001
                or sha(folder/'native-comparison.mp4')!=receipt['video_sha256']):
            raise ValueError('Previous complete media differs from the bound case')
        media_metadata(receipt,case)
        if validate_capture(case,Path(receipt['capture_folder']),plan_sha)!=receipt['capture_identity']:
            raise ValueError('Previous complete capture changed')
    return {'checkpoint':str(checkpoint_path), 'sha256':sha(checkpoint_path), 'cases':rows}


def run(args,runner=subprocess.run):
    plan_path=args.plan.resolve();project=args.project.resolve();output=args.output.resolve()
    plan=read(plan_path);plan_sha=sha(plan_path)
    verify_inputs(plan,project)
    reused={int(item.split('=',1)[0]):Path(item.split('=',1)[1]).resolve() for item in args.reuse}
    previous=getattr(args,'resume_from',None)
    if previous and output.exists():
        raise ValueError('Resume requires a fresh output directory')
    prefix=preserved_prefix(previous.resolve(),plan,plan_sha) if previous else None
    first=len(prefix['cases']) if prefix else 0
    if any(i < first or i >= len(plan['cases']) for i in reused):
        raise ValueError('Reuse index is outside the work range')
    output.mkdir(parents=True,exist_ok=True)
    lock=output/'queue.lock'
    with lock.open('x') as stream: stream.write(str(os.getpid()))
    state={'schema_version':1,'plan':str(plan_path),'plan_sha256':plan_sha,'status':'starting','cases':[],
        'first_plan_case':first,'preserved_prefix':prefix,
        'visual_review':'pending','audio_output_review':'pending','qualification':'pending'}
    producers={name:sha(Path(__file__).with_name(name)) for name in
        ('saved_effect_media_queue.py','check_saved_effects.py','movie_capture_startup.py')}
    state['producer_dependencies']=producers
    checkpoint=output/'queue.json'
    def stage(name,index):
        state.update(status=name,current_case=index);durable(checkpoint,state)
    try:
        durable(checkpoint,state)
        for index,case in enumerate(plan['cases'][first:],first):
            verify_inputs(plan,project)
            if sha(plan_path)!=plan_sha: raise ValueError('immutable plan changed during queue')
            folder=output/f'case{index:02d}'
            receipt_path=folder/'media-receipt.json'
            if folder.exists():
                if not receipt_path.is_file(): raise ValueError('partial output preserved; use fresh retry output: '+str(folder))
                receipt=read(receipt_path)
                capture=Path(receipt['capture_folder'])
                identity=validate_capture(case,capture,plan_sha)
                if receipt.get('producer_dependencies')!=producers or receipt.get('plan_sha256')!=plan_sha or receipt.get('case_id')!=case['id'] or receipt.get('capture_identity')!=identity or sha(folder/'native-comparison.mp4')!=receipt.get('video_sha256'):
                    raise ValueError('completed media reuse identity changed')
            else:
                folder.mkdir()
                capture=reused.get(index,folder/'capture')
                if index not in reused:
                    capture.mkdir()
                    command=[args.godot,'--path',str(project),'--rendering-method','gl_compatibility','--rendering-driver','opengl3',
                        '--fixed-fps',str(case['fps']),'--write-movie',str(capture/'frame.png'),
                        '--script','res://tools/render_saved_effects.gd','--',str(plan_path),str(index),str(capture/'native-observations.json')]
                    stage('capturing',index)
                    state['current_command']=command;durable(checkpoint,state)
                    with (capture/'capture.log').open('w',encoding='utf-8') as log:
                        def launch(command,check): return runner(command,check=check,stdout=log,stderr=subprocess.STDOUT)
                        startup=run_capture(project,1400,800,capture/'startup.json',command,launch)
                    if not startup['passed']: raise ValueError('capture subprocess failed')
                stage('validating_capture',index)
                identity=validate_capture(case,capture,plan_sha)
                video=folder/'native-comparison.mp4'
                command=[args.ffmpeg,'-hide_banner','-loglevel','error','-n','-framerate',str(case['fps']),'-i',str(capture/'frame%08d.png')]
                if case.get('audio_output_required'): command+=['-i',str(capture/'frame.wav'),'-map','0:v:0','-map','1:a:0','-c:a','aac']
                else: command+=['-an']
                command+=['-frames:v',str(case['fps']*case['seconds']),'-c:v','libx264','-threads','2','-crf','18','-pix_fmt','yuv420p','-movflags','+faststart',str(video)]
                stage('encoding',index)
                state['current_command']=command;durable(checkpoint,state)
                encoded=runner(command,check=True,capture_output=True,text=True)
                (folder/'encode.log').write_text(encoded.stdout+encoded.stderr,encoding='utf-8')
                receipt={'schema_version':1,'plan_sha256':plan_sha,'case_id':case['id'],'operation':case['operation'],
                    'producer_dependencies':producers,
                    'capture_folder':str(capture),'capture_identity':identity,'encode_command':command,
                    'video_sha256':sha(video),'visual_review':'pending','audio_output_review':'pending' if case.get('audio_output_required') else 'not_applicable'}
            stage('independent_full_decode',index)
            video=folder/'native-comparison.mp4'
            decode=[args.ffmpeg,'-hide_banner','-loglevel','error','-xerror','-err_detect','explode','-i',str(video),'-map','0','-f','null','-','-progress','pipe:1']
            state['current_command']=decode;durable(checkpoint,state)
            completed=runner(decode,check=True,capture_output=True,text=True)
            (folder/'decode.log').write_text(completed.stdout+completed.stderr,encoding='utf-8')
            if completed.stderr.strip(): raise ValueError('full decoder emitted errors')
            receipt['full_decode']=decode_progress(completed.stdout,case)
            metadata=runner([args.ffprobe,'-v','error','-show_streams','-of','json',str(video)],check=True,capture_output=True,text=True)
            info=json.loads(metadata.stdout);media_metadata(info,case)
            receipt['streams']=info['streams'];receipt['decode_command']=decode
            durable(receipt_path,receipt)
            state['cases'].append({'index':index,'case_id':case['id'],'receipt':str(receipt_path),'sha256':sha(receipt_path)})
            stage('case_complete',index)
        state['status']='complete_media_pending_review';durable(checkpoint,state)
        return 0
    except Exception as exc:
        if isinstance(exc,subprocess.CalledProcessError):
            state['subprocess_output']={'stdout':exc.stdout,'stderr':exc.stderr,'returncode':exc.returncode,'command':exc.cmd}
        state.update(status='failed_preserved',error=str(exc));durable(checkpoint,state)
        return 1
    finally:
        lock.unlink()

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan',type=Path,required=True);p.add_argument('--project',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--godot',required=True)
    p.add_argument('--ffmpeg',required=True);p.add_argument('--ffprobe',required=True)
    p.add_argument('--reuse',action='append',default=[],metavar='INDEX=DIR')
    p.add_argument('--resume-from',type=Path,help='Validate an inactive failed queue and write remaining cases to a fresh output')
    raise SystemExit(run(p.parse_args()))
