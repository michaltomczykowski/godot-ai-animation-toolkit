"""Strict saved-modifier native/media receipts; no engine or visual approval."""
import argparse,json,math,struct,re
from pathlib import Path
from saved_media_capture_checks import sha,require,finite,BODY
OPS={'ik_setup','look_at_setup','twist_setup','spring_setup','retarget_setup'}
def digest(v):return isinstance(v,str) and re.fullmatch("[0-9a-f]{64}",v) is not None
def finite_tree(v):
    if type(v) in (int,float):return math.isfinite(v)
    if isinstance(v,dict):return all(finite_tree(x) for x in v.values())
    if isinstance(v,list):return all(finite_tree(x) for x in v)
    return True
SEMANTIC=('tick','time','native_elapsed_s','input_time_s','pose_sha256','source_input_pose_sha256','focus_poses','bounds_min','bounds_max','display_envelope','effect','finite')
def framing(value):
    points=value.get('points',[])
    require(value.get('body_rect')==BODY and value.get('point_count')==len(points)==8,'complete conservative world-box projection missing')
    require(value.get('visible') is True and value.get('finite') is True and value.get('behind_or_clipped_depth')==0,'nonfinite/behind/clipped display')
    require(all(isinstance(p,list) and len(p)==2 and all(finite(x) for x in p) and 25<=p[0]<=1895 and 101<=p[1]<=859 for p in points),'display leaves body/header guard')
    xs,ys=zip(*points);bounds=[min(xs),min(ys),max(xs)-min(xs),max(ys)-min(ys)]
    require(bounds[2]>=2 and bounds[3]>=2 and len(value.get('bounds',[]))==4 and all(abs(x-y)<1e-4 for x,y in zip(bounds,value['bounds'])),'incorrect/unreadable projection bounds')
def validate(report,manifest,manifest_sha,frames=None,reference=None,reference_sha=None):
    require(report.get('passed') is True and report.get('engine_errors')==[] and type(report.get('engine_errors')) is list and report.get('failures')==[] and type(report.get('failures')) is list and report.get('inert_control') is False,'failed/malformed native report')
    require(report.get('manifest_sha256')==manifest_sha and report.get('fps')==60,'manifest/FPS mismatch')
    deps={d['path']:d['sha256'] for d in manifest['capture_dependencies']}
    for field,path in (('renderer_sha256','res://tools/render_saved_modifier_capture.gd'),('shared_evaluator_sha256','res://tools/check_saved_modifier_capture.gd'),('framing_sha256','res://tools/saved_media_framing.gd')):require(digest(deps.get(path)) and report.get(field)==deps.get(path),'wrong actual script bytes')
    cases={r['id']:r for r in manifest['cases']};require(len(cases)==5 and {r['op'] for r in cases.values()}==OPS,'five exact operation identities')
    runs=report.get('runs',[]);require(len(runs)==20,'missing native4s cells')
    require([(r['id'],r['active'],r['take']) for r in runs]==[(i,a,t) for i in cases for t in (0,1) for a in (False,True)],'wrong/duplicate/reordered case/take/activation')
    render=report.get('mode')=='render';require(report.get('mode') in ('native','render'),'unknown report mode')
    if render:require(reference is not None and digest(reference_sha) and report.get('native_preflight_sha256')==reference_sha,'render requires exact native preflight receipt')
    require(report.get('accepted_frames')==(2400 if render else 0),'accepted frame total')
    movie=[]
    for run in runs:
        require(run.get('failures')==[] and run.get('op')==cases[run['id']]['op'] and run.get('scene_sha256')==cases[run['id']]['scene']['sha256'] and run.get('fps')==60 and run.get('frames')==240 and run.get('excluded_loading_process_frames')==2 and run.get('saved_active') is False and run.get('runtime_influence')==1.,'saved activation/source/warmup changed')
        require(len(run.get('trace',[]))==240 and digest(run.get('config_sha256')),'missing native frame/config observations')
        if run['active']:require(max(s.get('effect',0) for s in run['trace'])>.001,'inert active modifier')
        for tick,s in enumerate(run['trace']):
            require(s.get('tick')==tick and abs(s.get('native_elapsed_s',-1)-(tick+1)/60)<1e-14 and abs(s.get('input_time_s',-1)-tick/60)<1e-14,'native/input clock skipped or interpolated')
            require(digest(s.get('pose_sha256')) and digest(s.get('source_input_pose_sha256')) and isinstance(s.get('focus_poses'),dict) and bool(s['focus_poses']) and finite_tree(s['focus_poses']),'missing raw focused native pose/source signature')
            require(s.get('finite') is True and s.get('raw')-s.get('raw_before')==(1 if run['active'] else 0) and s.get('final')-s.get('final_before')==1 and s.get('skin')-s.get('skin_before')>=1,'stale final/raw/skin signal')
            require(len(s.get('active_writers',[]))==(2 if run['active'] else 1),'competing runtime writer')
            env=s.get('display_envelope',{});require(env.get('vertex_count',0)>0 and len(env.get('minimum',[]))==3 and len(env.get('maximum',[]))==3 and all(finite(x) for x in env['minimum']+env['maximum']) and all(x<=y for x,y in zip(env['minimum'],env['maximum'])),'missing complete native world envelope')
            if not run['active']:require(s.get('effect',1)<.001,'inactive baseline changed')
            if render and run['active']:
                movie.append(s);framing(s.get('framing',{}));require(s.get('png_dimensions')==[1920,1080] and s.get('raw_after_draw')==s['raw'] and s.get('final_after_draw')==s['final'] and s.get('skin_after_draw',-1)>=s['skin'],'draw-time mutation or PNG size')
        peer=next(r for r in runs if r['id']==run['id'] and r['active']==run['active'] and r['take']!=run['take'])
        require(peer['final_pose']==run['final_pose'] and peer['config_sha256']==run['config_sha256'],'fresh reset pose/config drift')
        if reference is not None:
            original=next(r for r in reference['runs'] if (r['id'],r['active'],r['take'])==(run['id'],run['active'],run['take']))
            require(run['config_sha256']==original['config_sha256'] and all({k:s[k] for k in SEMANTIC}=={k:o[k] for k in SEMANTIC} for s,o in zip(run['trace'],original['trace'])),'rendered native trajectory differs from qualified preflight')
    if render:
        require([s.get('movie_frame') for s in movie]==list(range(2400)),'movie frame identity/order')
        if frames is not None:
            paths=sorted(frames.glob('*.png'));require([p.name for p in paths]==[f'{i:06d}.png' for i in range(2400)],'missing/extra accepted PNGs')
            for p,s in zip(paths,movie):
                header=p.open('rb').read(24);require(header[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',header[16:24])==(1920,1080) and sha(p)==s['png_sha256'] and Path(s['png_path']).resolve()==p.resolve(),'actual frame bytes/dimensions/path mismatch')
    return {'passed':True,'runs':20,'native_samples':4800,'accepted_frames':len(movie),'visual_approval':False}
if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--manifest',type=Path,required=True);p.add_argument('--report',type=Path,required=True);p.add_argument('--frames',type=Path);p.add_argument('--reference',type=Path);a=p.parse_args();print(json.dumps(validate(json.loads(a.report.read_text()),json.loads(a.manifest.read_text()),sha(a.manifest),a.frames,json.loads(a.reference.read_text()) if a.reference else None,sha(a.reference) if a.reference else None)))
