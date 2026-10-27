"""Root-operated three-play setup replay; preparation is offline and exclusive.

Only `run` launches processes. It imports the copied original FBX in a fresh
minimal project, then invokes the unchanged existing native setup checker.
"""
import argparse
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

import audit_setup_intent_bridge as audit

FILES = ('test_project/tools/check_setup_tree_quality.gd',
         'addons/godot_ai_animation/runtime/setup_grounding.gd',
         'addons/godot_ai_animation/spec/motion_space.gd',
         'test_project/models/human_dummy/HumanCharacterDummy_F.fbx')


def write(path, value):
    with path.open('x',encoding='utf-8') as stream:json.dump(value,stream,indent=2)


def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))


def project_path(rel):return rel.removeprefix('test_project/')


def hashes(project, paths):return {p:audit.sha((project/p).read_bytes()) for p in paths}


def cache_hashes(project):
    result = {p.relative_to(project).as_posix():audit.sha(p.read_bytes()) for p in (project/'.godot/imported').rglob('*') if p.is_file()}
    audit.need(any(p.endswith('.scn') for p in result), 'fresh FBX import produced no PackedScene cache')
    for p in ('models/human_dummy/HumanCharacterDummy_F.fbx.import','.godot/uid_cache.bin'):
        if (project/p).is_file():result[p]=audit.sha((project/p).read_bytes())
    return result


def prepare(args):
    audit.need(not args.output.exists(),'preserve prior setup replay directory')
    bridge = audit.audit(args)
    b = audit.read_evidence(args.setup_root,args.project_root)
    args.output.mkdir(parents=True,exist_ok=False); project=args.output/'project';project.mkdir()
    inputs={}
    for rel in FILES:
        source=args.repo/rel;target=project/project_path(rel);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
        inputs[target.relative_to(project).as_posix()]=audit.sha(target.read_bytes())
        uid=source.with_name(source.name+'.uid')
        if uid.is_file():
            target_uid=target.with_name(target.name+'.uid');shutil.copyfile(uid,target_uid);inputs[target_uid.relative_to(project).as_posix()]=audit.sha(target_uid.read_bytes())
    model_import='models/human_dummy/HumanCharacterDummy_F.fbx.import'
    shutil.copyfile(args.project_root/model_import,project/model_import)
    import_text=(project/model_import).read_text(encoding='utf-8-sig')
    audit.need('import_script/path=""' in import_text and 'fbx/importer=0' in import_text,'unreviewed custom model import recipe')
    # Retain original import settings, never copy any imported resource/cache.
    scene=project/audit.SCENE.removeprefix('res://');scene.parent.mkdir(parents=True);shutil.copyfile(args.project_root/audit.SCENE.removeprefix('res://'),scene)
    inputs[scene.relative_to(project).as_posix()]=audit.SCENE_SHA
    (project/'project.godot').write_text('config_version=5\n\n[application]\nconfig/name="Scoped setup intent replay"\n\n[rendering]\nrenderer/rendering_method="gl_compatibility"\n',encoding='utf-8')
    inputs['project.godot']=audit.sha((project/'project.godot').read_bytes())
    row=copy.deepcopy(b['routes'][0]['cases'][0]);row['quality_specs']=[audit.SPEC.copy()]
    manifest=dict(source_head=audit.PUBLIC_SOURCES[0],candidate_source=bridge['candidate_source'],original_route_reusers=list(audit.PUBLIC_SOURCES[1:]),historical_native_executor_source=audit.NATIVE_SOURCE,cases=[row])
    write(args.output/'manifest.json',manifest);write(args.output/'historical-bridge.json',bridge)
    receipt=dict(kind='scoped_setup_replay_preparation',candidate_source=bridge['candidate_source'],repo=str(args.repo.resolve()),core_root=str(args.core_root.resolve()),setup_root=str(args.setup_root.resolve()),original_project_root=str(args.project_root.resolve()),original_public_source=audit.PUBLIC_SOURCES[0],original_scene=audit.SCENE,manifest_sha256=audit.sha((args.output/'manifest.json').read_bytes()),immutable_project_inputs=inputs,import_recipe_before_sha256=audit.sha((project/model_import).read_bytes()),cache_copied=False,expected_native_plays=3,runner_sha256=audit.sha(Path(__file__).read_bytes()),auditor_sha256=audit.sha(Path(audit.__file__).read_bytes()))
    receipt['historical_bridge_sha256']=audit.sha((args.output/'historical-bridge.json').read_bytes())
    write(args.output/'preparation.json',receipt)
    return receipt


def process(command, directory, label, timeout, env):
    started=time.perf_counter_ns();record=dict(command=command,timeout_s=timeout,started_execution_ns=started,state='starting')
    with (directory/(label+'.log')).open('xb') as stream:
        proc=subprocess.Popen(command,stdin=subprocess.DEVNULL,stdout=stream,stderr=subprocess.STDOUT,env=env,creationflags=subprocess.CREATE_NO_WINDOW if os.name=='nt' else 0)
        record.update(pid=proc.pid,state='running');write(directory/(label+'.started.json'),record)
        try:
            proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            proc.terminate()
            try:proc.wait(timeout=10)
            except subprocess.TimeoutExpired:proc.kill();proc.wait(timeout=10)
            record.update(state='timed_out_unknown_no_retry',returncode=proc.returncode,finished_execution_ns=time.perf_counter_ns())
            write(directory/(label+'.completed.json'),record)
            raise RuntimeError(label+' timed out; original attempt preserved, no retry')
    record.update(state='complete',returncode=proc.returncode,finished_execution_ns=time.perf_counter_ns(),log_sha256=audit.sha((directory/(label+'.log')).read_bytes()))
    write(directory/(label+'.completed.json'),record)
    audit.need(proc.returncode==0,label+' subprocess failed; original outputs preserved')
    return record


def run(args):
    directory=args.prepared.resolve();prep=read(directory/'preparation.json');project=directory/'project'
    audit.need(not (directory/'execution.json').exists() and not (directory/'version.started.json').exists(),'preserve prior engine attempt; no retry')
    audit.need(prep.get('kind')=='scoped_setup_replay_preparation' and prep.get('cache_copied') is False and prep.get('expected_native_plays')==3,'foreign replay preparation')
    audit.need(prep['runner_sha256']==audit.sha(Path(__file__).read_bytes()) and prep['auditor_sha256']==audit.sha(Path(audit.__file__).read_bytes()),'replay runner/auditor changed after preparation')
    audit.need(not (project/'.godot').exists(),'fresh project already has an import cache')
    audit.need(hashes(project,prep['immutable_project_inputs'])==prep['immutable_project_inputs'],'prepared replay input bytes changed')
    audit.need(audit.sha((project/'models/human_dummy/HumanCharacterDummy_F.fbx.import').read_bytes())==prep['import_recipe_before_sha256'],'prepared model import recipe changed')
    audit.need(audit.sha((directory/'manifest.json').read_bytes())==prep['manifest_sha256'],'prepared replay manifest changed')
    audit.need(audit.sha((directory/'historical-bridge.json').read_bytes())==prep['historical_bridge_sha256'],'prepared historical bridge changed')
    source=subprocess.check_output(['git','rev-parse','HEAD'],cwd=prep['repo'],text=True).strip()
    audit.need(source==prep['candidate_source'],'candidate source changed after preparation')
    manifest=read(directory/'manifest.json');row=audit.one(manifest.get('cases',[]),'one saved dummy replay required')
    audit.need(manifest.get('source_head')==audit.PUBLIC_SOURCES[0] and manifest.get('candidate_source')==source and row.get('scene')==audit.SCENE and row.get('scene_sha256')==audit.SCENE_SHA and audit.same(row.get('request'),audit.REQUEST) and audit.same(row.get('quality_specs'),[audit.SPEC]),'replay request/scene/spec changed')
    env=os.environ.copy();env['APPDATA']=str(directory/'appdata');env['PYTHONUTF8']='1'
    for key in ('ANIMATION_TOOLKIT_CI','GODOT_AI_ALLOW_HEADLESS'):env.pop(key,None)
    state=dict(kind='scoped_setup_three_play_execution',candidate_source=source,original_public_source=audit.PUBLIC_SOURCES[0],historical_native_executor_source=audit.NATIVE_SOURCE,engine=str(args.godot),engine_sha256=audit.sha(args.godot.read_bytes()),preparation_sha256=audit.sha((directory/'preparation.json').read_bytes()),manifest_sha256=prep['manifest_sha256'],state='running',processes=[])
    def save():
        # Atomic replacement only for this exclusively created current attempt.
        temporary=directory/'execution.tmp';temporary.write_text(json.dumps(state,indent=2),encoding='utf-8');temporary.replace(directory/'execution.json')
    try:
        save();state['processes'].append(process([str(args.godot),'--version'],directory,'version',15,env));save()
        version=(directory/'version.log').read_text(encoding='utf-8-sig').strip();audit.need(version=='4.7.2.stable.official.ed1daf0bf','exact official engine required')
        state['processes'].append(process([str(args.godot),'--headless','--editor','--path',str(project),'--import','--quit'],directory,'import',180,env));save()
        audit.need('ERROR:' not in (directory/'import.log').read_text(encoding='utf-8-sig'),'fresh model import emitted errors')
        audit.need(hashes(project,prep['immutable_project_inputs'])==prep['immutable_project_inputs'],'fresh import changed source/scene/model/checker bytes')
        before=cache_hashes(project);state['fresh_import_cache_before_native']=before;save()
        command=[str(args.godot),'--headless','--path',str(project),'--script','res://tools/check_setup_tree_quality.gd','--',str(directory/'manifest.json'),str(directory/'native.json')]
        state['processes'].append(process(command,directory,'native',90,env));save()
        audit.need(cache_hashes(project)==before and hashes(project,prep['immutable_project_inputs'])==prep['immutable_project_inputs'],'native replay changed imported cache/model/scene/source bytes')
        audit.need(subprocess.check_output(['git','rev-parse','HEAD'],cwd=prep['repo'],text=True).strip()==source,'candidate source changed during replay')
        native=read(directory/'native.json');log=(directory/'native.log').read_text(encoding='utf-8-sig')
        audit.need(native.get('source_head')==audit.PUBLIC_SOURCES[0] and native.get('manifest_sha256')==prep['manifest_sha256'] and native.get('checker_sha256')==prep['immutable_project_inputs']['tools/check_setup_tree_quality.gd'],'fresh native source/manifest/checker identity differs')
        audit.need(native.get('passed') is True and native.get('engine_errors')==[] and native.get('failures')==[] and len(native.get('runs',[]))==3 and 'ERROR:' not in log,'fresh three-play native failure')
        summary=[json.loads(line.split('=',1)[1]) for line in log.splitlines() if line.startswith('SETUP_TREE_QUALITY=')]
        audit.need(summary==[dict(engine_errors=[],failures=[],passed=True,runs=3)],'fresh native exact completion absent')
        bridge=read(directory/'historical-bridge.json');numeric=audit.verify_numeric(native['runs'],[-1.35006184791564e-5,0.,1.])
        state.update(state='complete',native_sha256=audit.sha((directory/'native.json').read_bytes()),inputs_after_native=hashes(project,prep['immutable_project_inputs']),fresh_import_cache_after_native=cache_hashes(project));save()
        bridge.update(checks={'valid_effect':'pass'},candidate_execution='fresh exact-source three-FPS saved-scene replay; original public generation retained',fresh_native_executor_source=source,fresh_native_observations=numeric,fresh_replay_execution_sha256=audit.sha((directory/'execution.json').read_bytes()),missing_joins=[],historical_rig_limit_retained='Historical r009 FBX/cache/rest hashes remain unavailable. Fresh replay independently binds current copied FBX, fresh official import cache and saved scene before/after playback; original reports are unchanged.')
        bridge['fresh_artifacts']={name:dict(path=str(directory/name),sha256=audit.sha((directory/name).read_bytes()))for name in ('preparation.json','manifest.json','execution.json','native.json','version.log','import.log','native.log','version.started.json','version.completed.json','import.started.json','import.completed.json','native.started.json','native.completed.json')}
        write(directory/'setup-intent-proof.json',bridge)
        return bridge
    except Exception as exc:
        state.update(state='failed',error=str(exc));save();raise


def main():
    p=argparse.ArgumentParser(description=__doc__);sub=p.add_subparsers(dest='mode',required=True)
    stage=sub.add_parser('prepare')
    for name in ('repo','core-root','setup-root','project-root','output'):stage.add_argument('--'+name,type=Path,required=True)
    play=sub.add_parser('run');play.add_argument('--prepared',type=Path,required=True);play.add_argument('--godot',type=Path,required=True)
    args=p.parse_args();result=prepare(args) if args.mode=='prepare' else run(args)
    print(json.dumps({'state':'prepared' if args.mode=='prepare' else 'complete','candidate_source':result['candidate_source'],'checks':result.get('checks',{'valid_effect':'pending'})}))
    return 0


if __name__=='__main__':raise SystemExit(main())
