"""Actual rendered editor preview proof. Run under Xvfb; never --headless.

Owns its backend/editor and records exact public calls through the operation
collector. Rendering success is established from decoded PNG pixels, not logs.
"""
from __future__ import annotations

import argparse
import asyncio
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import time

from ci_mcp_route import port_open
from preview_native_debug import launch_command, cleanup_debugger_group
from preview_postmortem import Postmortem
from preview_renderer_profile import LINUX, PROFILES, validate_environment, validate_renderer_identity


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def validate_images(paths, directory):
    from PIL import Image, ImageChops
    directory = Path(directory).resolve()
    if len(paths) != 4 or len(set(paths)) != 4:
        raise ValueError("preview must report four distinct PNG paths")
    images, rows = [], []
    for path in paths:
        path = Path(path).resolve()
        if not path.is_relative_to(directory) or path.suffix != '.png':
            raise ValueError("PNG escaped the isolated output directory")
        with Image.open(path) as source:
            if source.format != 'PNG' or source.size != (320, 240):
                raise ValueError("wrong PNG format/dimensions")
            image = source.convert('RGB')
        if max(hi-lo for lo, hi in image.getextrema()) < 12:
            raise ValueError("uniform/blank preview image")
        images.append(image)
        rows.append({'path':path.name,'sha256':digest(path),'size':list(image.size),'rgb_extrema':image.getextrema(), 'unique_colors':len(image.getcolors(320*240) or [])})
    for index in range(len(images)):
        for previous in range(index):
            if ImageChops.difference(images[previous], images[index]).getbbox() is None:
                raise ValueError("preview times produced identical images")
    return rows


def require_success(value):
    if not isinstance(value, dict) or value.get('error'):
        raise ValueError('public call failed: '+str(value))
    return value


def require_error(value, code):
    error = value.get('error', '')
    actual = error.get('code', '') if isinstance(error, dict) else str(error).split(':',1)[0]
    if actual != code:
        raise ValueError('expected typed '+code+', got '+str(value))


def validate_editor_log(text):
    text = re.sub(r'\x1b\[[0-9;]*m', '', text)
    if re.search(r'(?m)^\s*(?:SCRIPT )?ERROR:', text) or re.search(
            r'double free or corruption|malloc\(\):|free\(\): invalid pointer|Program (?:received|terminated with) signal SIG(?:ABRT|SEGV|BUS)',text):
        raise ValueError('engine/script error in complete editor log')


def scene_ready(state, hierarchy, scene, required=()):
    paths={node.get('path') for node in hierarchy.get('nodes',[])}
    return (not state.get('error') and not hierarchy.get('error')
        and state.get('current_scene')==scene and set(required)<=paths)


async def wait_scene(call, scene, required=(), timeout=60, pause=asyncio.sleep):
    deadline=time.monotonic()+timeout
    stable=0
    while time.monotonic()<deadline:
        state=await call('editor_state',{})
        hierarchy=await call('scene_get_hierarchy',{'depth':8,'limit':100})
        stable=stable+1 if scene_ready(state,hierarchy,scene,required) else 0
        if stable>=3: return {'state':state,'hierarchy':hierarchy,'stable_reads':stable}
        await pause(.5)
    raise TimeoutError('edited scene did not become stable before mutation: '+scene)


async def exercise(args, report):
    from fastmcp import Client
    from fastmcp.client.transports import StdioTransport
    from fastmcp.exceptions import ToolError
    from mcp_presets_audit import payload
    from operation_case_collector import record_public_call
    from fixture_copy import copy_scene
    transport = StdioTransport(sys.executable, ['-m','godot_ai','attach',
        '--port',str(args.port),'--ws-port',str(args.ws_port)],
        cwd=str(args.core_root), keep_alive=False)
    async with Client(transport, timeout=90) as client:
        async def call(name, params):
            try:
                result = payload(await client.call_tool(name, params))
            except ToolError as exc:
                result = {'error':str(exc)}
            case_id = record_public_call(name, params, result)
            report['calls'].append({'public_case_id':case_id,'tool':name,'params':params,'response':result})
            return result
        deadline = time.monotonic()+90
        while True:
            sessions = (await call('session_manage',{'op':'list'})).get('sessions',[])
            if len(sessions) == 1: break
            if time.monotonic() > deadline: raise TimeoutError('one editor session did not become ready')
            await asyncio.sleep(1)
        require_success(await call('session_activate',{'session_id':sessions[0]['session_id']}))
        # Startup scene restoration can finish after the MCP session connects.
        # Wait for the explicitly launched scene before navigating elsewhere.
        report['startup_ready']=await wait_scene(call,'res://main.tscn')
        scene = args.project/'repair_rendered_preview.tscn'
        copy_scene(args.project/'repair_rig_fixture.tscn', scene)
        require_success(await call('scene_open',{'path':'res://repair_rendered_preview.tscn'}))
        player='/RepairRigFixture/AnimationPlayer'
        skeleton='/RepairRigFixture/Dummy/Skeleton3D'
        deadline = time.monotonic()+60
        while True:
            tools = {tool.name for tool in await client.list_tools()}
            if 'custom_animation_motion' in tools and 'custom_animation_inspect' in tools: break
            if time.monotonic() > deadline: raise TimeoutError('toolkit registry did not become ready')
            await asyncio.sleep(1)
        report['fixture_ready']=await wait_scene(call,'res://repair_rendered_preview.tscn',
            (player,skeleton))
        require_success(await call('custom_animation_motion',{'op':'walk_cycle',
            'player_path':player,'skeleton_path':skeleton,'animation_name':'rendered_walk',
            'duration':1.0,'root_motion':False}))
        inspect={'player_path':player,'animation_name':'rendered_walk'}
        baseline=require_success(await call('custom_animation_inspect',{'op':'timeline',**inspect}))
        require_success(await call('scene_save',{}))
        baseline_scene=scene.read_bytes()
        (args.output/'before-scene.tscn').write_bytes(baseline_scene)
        (args.output/'before-timeline.json').write_text(json.dumps(baseline,sort_keys=True),encoding='utf-8')
        request={'op':'preview',**inspect,'skeleton_path':skeleton,
            'character_path':'/RepairRigFixture/Dummy','times':[0.05,0.23,0.47,0.71],
            'width':320,'height':240,'output_dir':'res://rendered_preview_pngs',
            'basename':'walk','overwrite':False}
        output=args.project/'rendered_preview_pngs'
        if output.exists(): raise ValueError('fresh PNG output directory required')
        async def checkpoint(label):
            timeline=require_success(await call('custom_animation_inspect',{'op':'timeline',**inspect}))
            case_id=report['calls'][-1]['public_case_id']
            require_success(await call('scene_save',{}))
            scene_path=args.output/(label+'-scene.tscn')
            timeline_path=args.output/(label+'-timeline.json')
            scene_path.write_bytes(scene.read_bytes())
            timeline_path.write_text(json.dumps(timeline,sort_keys=True),encoding='utf-8')
            return {'timeline_public_case_id':case_id,
                'scene_save_public_case_id':report['calls'][-1]['public_case_id'],
                'scene':{'path':scene_path.name,'sha256':digest(scene_path)},
                'timeline':{'path':timeline_path.name,'sha256':digest(timeline_path)}}
        checkpoints={}
        report['checkpoints']=checkpoints
        checkpoints['before_dry']=await checkpoint('before-dry')
        require_error(await call('custom_animation_inspect',{**request,'dry_run':True}),'INVALID_PARAMS')
        if output.exists(): raise ValueError('dry_run created output files')
        checkpoints['after_dry']=await checkpoint('after-dry')
        require_error(await call('custom_animation_inspect',{**request,'animation_name':'absent'}),'INVALID_PARAMS')
        checkpoints['before_preview']=await checkpoint('before-preview')
        result=require_success(await call('custom_animation_inspect',request))
        report['public_case_id']=report['calls'][-1]['public_case_id']
        report['raw_response']=result
        checkpoints['after_preview']=await checkpoint('after-preview')
        expected=['res://rendered_preview_pngs/walk_%02d.png'%i for i in range(4)]
        if result.get('paths') != expected or result.get('times') != request['times']:
            raise ValueError('preview returned wrong paths/times: '+str(result))
        paths=[args.project/path.removeprefix('res://') for path in result['paths']]
        report['images']=validate_images(paths,output)
        before={path.name:digest(path) for path in output.iterdir()}
        require_error(await call('custom_animation_inspect',request),'INVALID_PARAMS')
        checkpoints['after_overwrite_refusal']=await checkpoint('after-overwrite-refusal')
        if before != {path.name:digest(path) for path in output.iterdir()}:
            raise ValueError('overwrite refusal changed files')
        after=require_success(await call('custom_animation_inspect',{'op':'timeline',**inspect}))
        require_success(await call('scene_save',{}))
        if after != baseline or scene.read_bytes() != baseline_scene:
            raise ValueError('preview/refusals changed saved live scene poses or clip')
        if any(point['scene']['sha256'] != digest(args.output/'before-scene.tscn')
               or point['timeline']['sha256'] != digest(args.output/'before-timeline.json')
               for point in checkpoints.values()):
            raise ValueError('individual preview/refusal checkpoint changed source scene/timeline')
        (args.output/'after-timeline.json').write_text(json.dumps(after,sort_keys=True),encoding='utf-8')
        report['restoration']={'before_scene':{'path':'before-scene.tscn','sha256':digest(args.output/'before-scene.tscn')},
            'after_scene':{'path':'restored-scene.tscn','sha256':digest(scene)},
            'before_timeline':{'path':'before-timeline.json','sha256':digest(args.output/'before-timeline.json')},
            'after_timeline':{'path':'after-timeline.json','sha256':digest(args.output/'after-timeline.json')}}
        for path in paths: shutil.copy2(path,args.output/path.name)
        shutil.copy2(scene,args.output/'restored-scene.tscn')


def run(args):
    from operation_case_collector import prepare
    args.project=args.project.resolve()
    args.core_root=args.core_root.resolve()
    args.output=args.output.resolve()
    args.output.mkdir(parents=True,exist_ok=False)
    context=args.output/'context.json'
    report={'schema_version':1,'operation':'animation_inspect.preview','calls':[],'images':[],'passed':False,'editor_command':[],
        'display':os.environ.get('DISPLAY'),'renderer':'gl_compatibility',
        'renderer_profile':args.renderer_profile}
    owned=[]
    debug_process=None
    postmortem=None
    editor=None
    try:
        validate_environment(args.renderer_profile,sys.platform,os.environ.get('DISPLAY'))
        debugger=getattr(args,'native_debugger','none')
        # Validate before spawning anything. Godot/version/context stay unchanged.
        launch_command([args.godot],debugger)
        report['native_debugger']={'mode':debugger}
        report['context']=prepare(Path(__file__).resolve().parents[1],args.core_root,args.godot,context)
        report['context_sha256']=digest(context)
        if report['context']['platform'] != ('linux' if args.renderer_profile==LINUX else 'windows'):
            raise ValueError('renderer profile/recorded context platform mismatch')
        os.environ['TOOLKIT_OPERATION_CONTEXT']=str(context)
        os.environ['TOOLKIT_OPERATION_TRACE_DIR']=str(args.output/'traces')
        if port_open(args.port) or port_open(args.ws_port): raise ValueError('backend ports already occupied')
        env=os.environ.copy()
        env.pop('ANIMATION_TOOLKIT_CI',None)
        env.pop('GODOT_AI_ALLOW_HEADLESS',None)
        env.update(GODOT_AI_DISABLE_TELEMETRY='true',GODOT_AI_VENV_PYTHON=sys.executable)
        env['PYTHONPATH']=os.pathsep.join(filter(None,[str(args.core_root/'src'),env.get('PYTHONPATH','')]))
        with (args.output/'backend.log').open('wb') as backend_log, (args.output/'editor.log').open('wb') as editor_log:
            backend=subprocess.Popen([sys.executable,'-m','godot_ai','--transport','streamable-http',
                '--port',str(args.port),'--ws-port',str(args.ws_port)],cwd=args.core_root,env=env,
                stdout=backend_log,stderr=subprocess.STDOUT)
            owned.append(backend)
            deadline=time.monotonic()+45
            while not (port_open(args.port) and port_open(args.ws_port)):
                if backend.poll() is not None or time.monotonic()>deadline: raise RuntimeError('backend startup failed')
                time.sleep(.25)
            command=[args.godot,'--editor','--path',str(args.project),'--rendering-method','gl_compatibility',
                '--rendering-driver','opengl3','--audio-driver','Dummy','res://main.tscn']
            report['editor_command']=command
            actual_command=launch_command(command,debugger)
            report['editor_launch_command']=actual_command
            if debugger=='postmortem':
                postmortem=Postmortem(args.godot,args.output)
                report['native_debugger']=postmortem.report
            editor=subprocess.Popen(actual_command,env=env,stdout=editor_log,stderr=subprocess.STDOUT,
                **(postmortem.launch_kwargs() if postmortem else {}),
                **({'start_new_session':True} if debugger=='gdb' else {}))
            owned.append(editor)
            if postmortem:postmortem.bind(editor)
            if debugger=='gdb':
                debug_process=editor
                report['native_debugger'].update(pid=editor.pid,private_process_group=True)
            asyncio.run(exercise(args,report))
            startup=(args.output/'editor.log').read_text(encoding='utf-8',errors='replace')
            report['renderer_identity']=validate_renderer_identity(
                args.renderer_profile,report['context']['platform'],startup)
            report['passed']=True
    except Exception as exc:
        report['error']=str(exc)
        if hasattr(exc,'postmortem_report'):report['native_debugger']=exc.postmortem_report
    finally:
        if postmortem and editor is not None:
            try:
                postmortem.collect(editor,failed=bool(report.get("error")))
                if postmortem.report.get("editor_returncode_before_cleanup") not in (None,0):report["passed"]=False
            except Exception as exc:
                report["passed"]=False
                report.setdefault("secondary_errors",[]).append("postmortem collection failed: "+str(exc))
        for process in reversed(owned):
            if process is debug_process:
                try:
                    cleanup=cleanup_debugger_group(process)
                    report['native_debugger']['cleanup']=cleanup
                    if cleanup.get('pre_cleanup_returncode') not in (None,0):
                        report['passed']=False
                        report.setdefault('secondary_errors',[]).append('native debugger exited abnormally before owned cleanup')
                except (OSError,subprocess.TimeoutExpired) as exc:
                    report['passed']=False
                    report.setdefault('secondary_errors',[]).append('owned debugger cleanup failed: '+str(exc))
                continue
            try:
                if process.poll() is None:
                    process.terminate()
                    try: process.wait(timeout=10)
                    except subprocess.TimeoutExpired: process.kill(); process.wait(timeout=5)
            except (OSError,subprocess.TimeoutExpired) as exc:
                report['passed']=False
                report.setdefault('secondary_errors',[]).append('owned process cleanup failed: '+str(exc))
        if postmortem:
            try:
                report["native_debugger"]=postmortem.close()
                if postmortem.report.get('cleanup_errors'):report['passed']=False
            except Exception as exc:
                report["passed"]=False
                report.setdefault("secondary_errors",[]).append("postmortem owned cleanup failed: "+str(exc))
        # Preserve partial images on failure too; they are diagnostic artifacts,
        # never inferred successful frames.
        image_dir=args.project/'rendered_preview_pngs'
        if image_dir.is_dir():
            for path in image_dir.glob('*.png'):
                shutil.copy2(path,args.output/path.name)
        report['logs']=[{'path':name,'sha256':digest(args.output/name)} for name in ['editor.log','backend.log'] if (args.output/name).is_file()]
        if (args.output/'editor.log').is_file():
            try:
                complete_log=(args.output/'editor.log').read_text(encoding='utf-8',errors='replace')
                validate_editor_log(complete_log)
                if report.get('context'):
                    report['renderer_identity']=validate_renderer_identity(
                        args.renderer_profile,report['context']['platform'],complete_log)
            except ValueError as exc:
                report['passed']=False
                if report.get('error'):
                    report.setdefault('secondary_errors',[]).append(str(exc))
                else:
                    report['error']=str(exc)
        (args.output/'rendered-preview.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('RENDERED_PREVIEW='+json.dumps({'passed':report['passed'],'error':report.get('error')}))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-debugger',choices=('none','gdb','postmortem'),default=os.environ.get('TOOLKIT_PREVIEW_NATIVE_DEBUGGER','none'))
    parser.add_argument('--renderer-profile',choices=PROFILES,default=LINUX)
    parser.add_argument('--core-root',type=Path,required=True)
    parser.add_argument('--project',type=Path,default=Path('test_project'))
    parser.add_argument('--output',type=Path,default=Path('rendered-preview-artifacts'))
    parser.add_argument('--godot',default='godot')
    parser.add_argument('--port',type=int,default=8000)
    parser.add_argument('--ws-port',type=int,default=9500)
    raise SystemExit(run(parser.parse_args()))
