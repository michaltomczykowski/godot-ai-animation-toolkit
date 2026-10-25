"""Prepare/run exactly two preserved motion representatives. No generation."""
import argparse,hashlib,json,math,subprocess,re
from pathlib import Path
from movie_capture_startup import run_capture
from ci_rendered_preview import validate_editor_log
from compose_character_quality import compose

SELECTED={'right-strafe':'strafe/candidate-r001/right/responsive','stationary-jump':'jump/candidate-r002/stationary/responsive-in-place'}
TOOLS=['render_character_quality.gd','render_strafe_quality.gd','render_jump_quality.gd','character_quality_native.gd','motion_capture_guard.gd','check_motion_capture_admission.gd','check_strafe_quality.gd','check_jump_quality.gd','check_run_quality.gd']
def sha(p):
    h=hashlib.sha256()
    with Path(p).open('rb') as f:
        while b:=f.read(1024*1024):h.update(b)
    return h.hexdigest()
def put(path,value):
    with Path(path).open('x',encoding='utf-8') as f:json.dump(value,f,indent=2)
def prepare(repo,project,evidence,output):
    output.mkdir(parents=True,exist_ok=False)
    head=subprocess.check_output(['git','-C',str(repo),'rev-parse','HEAD'],text=True).strip()
    manifest={'kind':'two_saved_motion_representatives','capture_source':head,'project':str(project.resolve()),'cases':{}}
    files=[dict(path=str((project/'tools'/name).resolve()),sha256=sha(repo/'test_project/tools'/name)) for name in TOOLS]
    files += [dict(path=str((repo/'tools'/name).resolve()),sha256=sha(repo/'tools'/name)) for name in ('prepare_motion_representatives.py','compose_character_quality.py','movie_capture_startup.py','ci_rendered_preview.py')]
    for f in files:
        if sha(f['path'])!=f['sha256']:raise ValueError('Project tool differs from capture source')
    for key,relative in SELECTED.items():
        source=evidence/relative;route_path=source/'route.json';route=json.loads(route_path.read_text())
        if route.get('passed') is not True or [r['id'] for r in route['cases']]!=['dummy','xbot','short','zup_tall']:raise ValueError('Exact public four-rig route required')
        for row in route['cases']:
            if sha(project/row['scene'].removeprefix('res://'))!=row['scene_sha256']:raise ValueError('Preserved scene changed')
            if row['params']['op']!=('strafe_cycle' if key=='right-strafe' else 'jump') or row['params']['root_motion'] is not (key=='right-strafe'):raise ValueError('Wrong ownership/operation')
            if key=='right-strafe' and row['params'].get('direction')!='right':raise ValueError('Wrong strafe direction')
            if key=='stationary-jump' and float(row['params'].get('distance',0))!=0:raise ValueError('Wrong jump distance')
        natives=[]
        for path in source.glob('native-check*.json'):
            report=json.loads(path.read_text())
            if report.get('passed') is True and report.get('engine_errors')==[] and report.get('failures')==[] and report.get('route_sha256')==sha(route_path) and len(report.get('runs',[]))==24:natives.append(dict(path=str(path),sha256=sha(path)))
        if not natives:raise ValueError('Original24-play native admission missing')
        folder=output/key;folder.mkdir();copied=folder/'route.json';copied.write_bytes(route_path.read_bytes())
        bound=list(files)
        seen={f['path'] for f in bound}
        def dependency(path):
            path=path.resolve()
            if str(path) in seen:return
            if not path.is_file():raise ValueError('Saved dependency missing: '+str(path))
            seen.add(str(path));bound.append(dict(path=str(path),sha256=sha(path)))
            if path.suffix in ('.tscn','.tres','.import'):
                for virtual in re.findall(r'res://[^"\s]+',path.read_text(encoding='utf-8')):
                    dependency(project/virtual.removeprefix('res://'))
            elif path.suffix in ('.fbx','.glb','.gltf') and Path(str(path)+'.import').is_file():dependency(Path(str(path)+'.import'))
        for row in route['cases']:dependency(project/row['scene'].removeprefix('res://'))
        def tree(source):
            text=subprocess.check_output(['git','-C',str(repo),'ls-tree','-r',source,'--','addons/godot_ai_animation'],text=True)
            return {line.split('\t',1)[1]:line.split()[2] for line in text.splitlines() if not line.endswith('.uid')}
        old_tree=tree(route['source_head']);new_tree=tree(head)
        bridge={path:dict(original_git_blob=blob,capture_git_blob=new_tree.get(path),exact=blob==new_tree.get(path)) for path,blob in old_tree.items()}
        binding=dict(producer_blob_bridge=bridge,route_sha256=sha(copied),original_route=str(route_path),producer_source=route['source_head'],capture_source=head,files=bound,original_native=natives,scope='Original immutable saved output; operation-specific producer bridge in motion-representative-media-plan.md; no regeneration or current-producer relabel')
        put(folder/'capture-binding.json',binding);manifest['cases'][key]=dict(route=str(copied.resolve()),binding=str((folder/'capture-binding.json').resolve()),renderer='render_strafe_quality.gd' if key=='right-strafe' else 'render_jump_quality.gd')
    put(output/'preparation.json',manifest);return manifest

def validate_render(report,binding_sha,probe,jump,frames):
    if report.get('errors')!=[] or report.get('guarded') is not True or report.get('frames')!=1440 or report.get('fps')!=60 or report.get('size')!=[1920,1080] or report.get('capture_binding_sha256')!=binding_sha or report.get('probe') is not probe:raise ValueError('Invalid native capture header')
    trace=report.get('trace',[])
    if len(trace)!=2880:raise ValueError('Missing per-frame view witnesses')
    rigs=['dummy','xbot','short','zup_tall']
    for i,row in enumerate(trace):
        frame=i//2;local=frame%360
        if (row.get('frame'),row.get('rig'),row.get('view'),row.get('take'))!=(frame,rigs[frame//360],i%2,local//180+1 if jump else 1):raise ValueError('Wrong native frame/rig/view/take')
        if row.get('fits') is not True or row.get('skin_fresh') is not True or row.get('depth_clipped')!=0 or type(row.get('points')) is not int or row['points']<=0 or type(row.get('skin_before')) is not int or type(row.get('skin_after')) is not int or row['skin_after']<=row['skin_before']:raise ValueError('Stale/clipped native output')
        for field in ('actor_world','root_delta_owner_parent'):
            vector=row.get(field,[])
            if len(vector)!=3 or not all(type(x) in (int,float) and math.isfinite(x) for x in vector):raise ValueError('Missing finite native transform witness')
        poses=row.get('poses_world',{})
        if set(poses)!={'hips','head','hand_l','hand_r','foot_l','foot_r'} or any(len(v)!=3 or not all(type(x) in (int,float) and math.isfinite(x) for x in v) for v in poses.values()):raise ValueError('Missing finite native pose witness')
        if jump and local==180:
            first=trace[(frame-180)*2+i%2]
            if row['actor_world']!=first['actor_world'] or row['poses_world']!=first['poses_world']:raise ValueError('Fresh second take does not reset native pose/origin')
        bounds=row.get('bounds',[])
        if len(bounds)!=4 or not all(type(x) in (int,float) and math.isfinite(x) for x in bounds) or not(8<=bounds[0]<=bounds[2]<=944 and 8<=bounds[1]<=bounds[3]<=892):raise ValueError('Geometry outside panel')
        expected=(local%180 if jump else local)/60
        if type(row.get('native_time')) not in (int,float) or abs(row['native_time']-expected)>1e-10:raise ValueError('Wrong native clock')
    expected=[i for i in range(1440) if not probe or i%(180 if jump else 360) in ([0,90,179] if jump else [0,120,240,359])]
    images=sorted(frames.glob('*.png'))
    if [p.name for p in images]!=[f'{i:06d}.png' for i in expected] or report.get('png_frames')!=len(expected):raise ValueError('PNG schedule/count mismatch')
    from PIL import Image
    return [dict(name=p.name,sha256=sha(p)) for p in images if _png(p,Image)]
def _png(path,Image):
    with Image.open(path) as image:
        if image.size!=(1920,1080):raise ValueError('Wrong actual PNG dimensions')
        image.verify()
    return True

def execute(a):
    prepared=json.loads(a.preparation.read_text());item=prepared['cases'][a.case];project=Path(prepared['project']);binding=json.loads(Path(item['binding']).read_text())
    for f in binding['files']:
        if sha(f['path'])!=f['sha256']:raise ValueError('Frozen input changed: '+f['path'])
    if sha(item['route'])!=binding['route_sha256']:raise ValueError('Frozen route changed')
    a.output.mkdir(parents=True,exist_ok=False)
    state=dict(kind='two_saved_motion_execution',case=a.case,phase=a.phase,preparation_sha256=sha(a.preparation),binding_sha256=sha(item['binding']),recorder_sha256=sha(__file__),commands=[],visual_approval=False)
    try:
        def launch(command,name,startup=False):
            with (a.output/(name+'.log')).open('x') as log:
                def runner(cmd,**kw):return subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,**kw)
                state['commands'].append(command)
                if startup:
                    result=run_capture(project,1920,1080,a.output/(name+'-startup.json'),command,runner)
                    if result.get('passed') is not True:raise ValueError('Capture startup/process failed')
                elif runner(command,check=False).returncode:raise ValueError('Native process failed')
            text=(a.output/(name+'.log')).read_text(encoding='utf-8',errors='replace')
            if 'Godot Engine v4.7.2.' not in text:raise ValueError('Actual engine startup is not4.7.2')
            validate_editor_log(text)
            state.setdefault('logs',[]).append(dict(path=str(a.output/(name+'.log')),sha256=sha(a.output/(name+'.log'))))
        base=[str(a.godot),'--path',str(project)]
        if a.phase=='native':
            for control in ('','foreign_tree','active_modifier','wrong_root_track'):
                report=a.output/('admission-'+(control or 'positive')+'.json')
                launch(base[:1]+['--headless']+base[1:]+['--script','res://tools/check_motion_capture_admission.gd','--',item['route'],str(report),control],'admission-'+(control or 'positive'))
                if json.loads(report.read_text()).get('passed') is not True:raise ValueError('Admission control failed')
            script='check_strafe_quality.gd' if a.case=='right-strafe' else 'check_jump_quality.gd';report=a.output/'native.json'
            launch(base[:1]+['--headless']+base[1:]+['--script','res://tools/'+script,'--',item['route'],str(report)],'physical')
            data=json.loads(report.read_text())
            if data.get('passed') is not True or data.get('engine_errors')!=[] or data.get('failures')!=[] or data.get('route_sha256')!=binding['route_sha256'] or len(data.get('runs',[]))!=24:raise ValueError('Fresh physical preflight failed')
        else:
            if a.native is None:raise ValueError('Exact fresh native receipt required')
            native=json.loads((a.native/'execution.json').read_text())
            if native.get('passed') is not True or native.get('phase')!='native' or native.get('case')!=a.case or native.get('binding_sha256')!=state['binding_sha256']:raise ValueError('Wrong fresh native receipt')
            state['native_execution_sha256']=sha(a.native/'execution.json')
            if a.phase=='capture':
                if a.probe is None:raise ValueError('Successful framing probe receipt required before full capture')
                probe=json.loads((a.probe/'execution.json').read_text())
                if probe.get('passed') is not True or probe.get('phase')!='probe' or probe.get('case')!=a.case or probe.get('binding_sha256')!=state['binding_sha256']:raise ValueError('Wrong framing probe receipt')
                state['probe_execution_sha256']=sha(a.probe/'execution.json')
            frames=a.output/(a.mode+'_frames');phase='probe' if a.phase=='probe' else 'full'
            launch(base+['--rendering-method','gl_compatibility','--script','res://tools/'+item['renderer'],'--',item['route'],str(frames),a.mode,item['binding'],phase],'render',True)
            report=json.loads((frames/'render.json').read_text())
            route=json.loads(Path(item['route']).read_text())
            if report.get('operation')!=route['operation'] or report.get('source_head')!=route['source_head'] or report.get('mode')!=a.mode or [(r.get('id'),r.get('scene'),r.get('scene_sha256')) for r in report.get('cases',[])]!=[(r['id'],r['scene'],r['scene_sha256']) for r in route['cases']]:raise ValueError('Render output does not bind exact producer/scene/mode')
            state['pngs']=validate_render(report,state['binding_sha256'],a.phase=='probe',a.case=='stationary-jump',frames)
            if a.phase=='capture':
                if a.ffmpeg is None:raise ValueError('ffmpeg required')
                state['media']=compose(a.output,a.mode,a.ffmpeg)
        state['passed']=True
    except Exception as error:
        state.update(passed=False,error=str(error));raise
    finally:put(a.output/'execution.json',state)

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='action',required=True)
    prep=sub.add_parser('prepare')
    for key in ('repo','project','evidence','output'):prep.add_argument('--'+key,type=Path,required=True)
    run=sub.add_parser('run');run.add_argument('--preparation',type=Path,required=True);run.add_argument('--case',choices=SELECTED,required=True);run.add_argument('--phase',choices=('native','probe','capture'),required=True);run.add_argument('--godot',type=Path,required=True);run.add_argument('--output',type=Path,required=True);run.add_argument('--mode',choices=('clean','diagnostic'),default='clean');run.add_argument('--native',type=Path);run.add_argument('--probe',type=Path);run.add_argument('--ffmpeg',type=Path)
    a=p.parse_args()
    if a.action=='prepare':prepare(a.repo.resolve(),a.project.resolve(),a.evidence.resolve(),a.output.resolve())
    else:execute(a)
